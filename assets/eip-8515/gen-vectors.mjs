// Generate deterministic ERC-8515 test vectors (vectors.json).
// SPDX-License-Identifier: CC0-1.0

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ZERO_BYTES32,
  aggregate,
  bytesToHex,
  canonicalizeJson,
  deviceKey,
  domainSeparator,
  formatAccount,
  hexToBytes,
  keccak256,
  parseJson,
  privateKeyToAddress,
  reportProblem,
  signStatement,
  statementDigest,
  statementId,
  statementProblem,
  statementRoot,
  utf8ToBytes,
  verifyEnvelope,
} from './evidence.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const SERVICER_PK = '0x0000000000000000000000000000000000000000000000000000000000000001';
const LESSEE_PK = '0x0000000000000000000000000000000000000000000000000000000000000002';
const ATTESTER_PK = '0x0000000000000000000000000000000000000000000000000000000000000003';

const servicerAddress = privateKeyToAddress(SERVICER_PK);
const lesseeAddress = privateKeyToAddress(LESSEE_PK);
const attesterAddress = privateKeyToAddress(ATTESTER_PK);

const CHAIN_ID = 1;
const REGISTRY_ADDRESS = '0x1111111111111111111111111111111111111111';
const COLLATERAL_ID = '0x000000000000000000000000000000000000000000000000000000000000c011';
const PERIOD_START = 1735689600; // 2025-01-01T00:00:00Z
const PERIOD_END = 1735776000;   // 2025-01-02T00:00:00Z (86400s)

const registryAccount = formatAccount(CHAIN_ID, REGISTRY_ADDRESS);
const servicerAccount = formatAccount(CHAIN_ID, servicerAddress);
const lesseeAccount = formatAccount(CHAIN_ID, lesseeAddress);
const attesterAccount = formatAccount(CHAIN_ID, attesterAddress);

// 3 devices: two idType 0x01 (made-up DER-encoded EC P-256 SPKI), one idType 0x02 (UTF-8 serial)
const SPKI_PREFIX = '3059301306072a8648ce3d020106082a8648ce3d03010703420004';
const spki1Hex =
  '0x' +
  SPKI_PREFIX +
  '1111111111111111111111111111111111111111111111111111111111111111' +
  '2222222222222222222222222222222222222222222222222222222222222222';
const spki2Hex =
  '0x' +
  SPKI_PREFIX +
  '3333333333333333333333333333333333333333333333333333333333333333' +
  '4444444444444444444444444444444444444444444444444444444444444444';
const serial3Utf8 = 'SN-00142025-GPU03';
const serial3Hex = bytesToHex(utf8ToBytes(serial3Utf8));

const devices = [
  {
    label: 'gpu-1-h100-spki',
    pciVendorId: 0x10de,
    idType: 0x01,
    idBytesHex: spki1Hex,
    idBytesUtf8: null,
    deviceKey: deviceKey(0x10de, 0x01, hexToBytes(spki1Hex)),
  },
  {
    label: 'gpu-2-h100-spki',
    pciVendorId: 0x10de,
    idType: 0x01,
    idBytesHex: spki2Hex,
    idBytesUtf8: null,
    deviceKey: deviceKey(0x10de, 0x01, hexToBytes(spki2Hex)),
  },
  {
    label: 'gpu-3-serial',
    pciVendorId: 0x10de,
    idType: 0x02,
    idBytesHex: serial3Hex,
    idBytesUtf8: serial3Utf8,
    deviceKey: deviceKey(0x10de, 0x02, utf8ToBytes(serial3Utf8)),
  },
];

const pledgedDeviceKeys = devices.map((d) => d.deviceKey);

function baseStatement({
  device,
  pciDeviceId,
  location,
  observer,
  role,
  method,
  checksPassed,
  checksFailed,
  servedSeconds,
  missedSeconds,
  unknownSeconds,
  evidence,
}) {
  return {
    kind: 'ERC8515/statement/1',
    registry: registryAccount,
    servicer: servicerAccount,
    collateralId: COLLATERAL_ID,
    deviceKey: device,
    pciDeviceId,
    location,
    periodStart: String(PERIOD_START),
    periodEnd: String(PERIOD_END),
    observer,
    role,
    method,
    checksPassed: String(checksPassed),
    checksFailed: String(checksFailed),
    servedSeconds: String(servedSeconds),
    missedSeconds: String(missedSeconds),
    unknownSeconds: String(unknownSeconds),
    evidence,
  };
}

// 6 statements covering all 3 devices, all 4 methods, and deterministic selection tie-breaking
const rawStatementSpecs = [
  {
    label: 'gpu-1-hw-attestation',
    privKey: ATTESTER_PK,
    observerAddress: attesterAddress,
    statement: baseStatement({
      device: devices[0].deviceKey,
      pciDeviceId: '2330',
      location: 'US',
      observer: attesterAccount,
      role: 'third-party',
      method: 'hw-attestation',
      checksPassed: 24,
      checksFailed: 0,
      servedSeconds: 0,
      missedSeconds: 0,
      unknownSeconds: 86400,
      evidence: [
        {
          type: 'nvidia-spdm-attestation-bundle',
          uri: 'ipfs://bafybeigpu1attestationbundle0001',
          hash: keccak256('gpu-1-attestation-bundle-v1'),
        },
      ],
    }),
  },
  {
    label: 'gpu-1-lessee-workload-meter',
    privKey: LESSEE_PK,
    observerAddress: lesseeAddress,
    statement: baseStatement({
      device: devices[0].deviceKey,
      pciDeviceId: '2330',
      location: 'US',
      observer: lesseeAccount,
      role: 'lessee',
      method: 'workload-meter',
      checksPassed: 0,
      checksFailed: 0,
      servedSeconds: 72000,
      missedSeconds: 3600,
      unknownSeconds: 10800,
      evidence: [
        {
          type: 'slurm-usage-log',
          uri: 'ipfs://bafybeigpu1lesseemeter0001',
          hash: keccak256('gpu-1-lessee-meter-log-v1'),
        },
      ],
    }),
  },
  {
    label: 'gpu-1-servicer-workload-meter',
    privKey: SERVICER_PK,
    observerAddress: servicerAddress,
    statement: baseStatement({
      device: devices[0].deviceKey,
      pciDeviceId: '2330',
      location: 'US',
      observer: servicerAccount,
      role: 'servicer',
      method: 'workload-meter',
      checksPassed: 0,
      checksFailed: 0,
      servedSeconds: 73800,
      missedSeconds: 1800,
      unknownSeconds: 10800,
      evidence: [
        {
          type: 'servicer-billing-meter',
          uri: 'ipfs://bafybeigpu1servicermeter0001',
          hash: keccak256('gpu-1-servicer-meter-log-v1'),
        },
      ],
    }),
  },
  {
    label: 'gpu-2-hw-attestation',
    privKey: ATTESTER_PK,
    observerAddress: attesterAddress,
    statement: baseStatement({
      device: devices[1].deviceKey,
      pciDeviceId: '2330',
      location: 'US',
      observer: attesterAccount,
      role: 'third-party',
      method: 'hw-attestation',
      checksPassed: 12,
      checksFailed: 1,
      servedSeconds: 0,
      missedSeconds: 0,
      unknownSeconds: 86400,
      evidence: [
        {
          type: 'nvidia-spdm-attestation-bundle',
          uri: 'ipfs://bafybeigpu2attestationbundle0001',
          hash: keccak256('gpu-2-attestation-bundle-v1'),
        },
      ],
    }),
  },
  {
    label: 'gpu-2-bmc-telemetry',
    privKey: SERVICER_PK,
    observerAddress: servicerAddress,
    statement: baseStatement({
      device: devices[1].deviceKey,
      pciDeviceId: '2330',
      location: 'US',
      observer: servicerAccount,
      role: 'servicer',
      method: 'bmc-telemetry',
      checksPassed: 0,
      checksFailed: 0,
      servedSeconds: 0,
      missedSeconds: 0,
      unknownSeconds: 86400,
      evidence: [
        {
          type: 'redfish-telemetry-csv',
          uri: 'ipfs://bafybeigpu2bmctelemetry0001',
          hash: keccak256('gpu-2-bmc-telemetry-v1'),
        },
      ],
    }),
  },
  {
    label: 'gpu-3-site-inspection',
    privKey: SERVICER_PK,
    observerAddress: servicerAddress,
    statement: baseStatement({
      device: devices[2].deviceKey,
      pciDeviceId: '2330',
      location: 'DE',
      observer: servicerAccount,
      role: 'servicer',
      method: 'site-inspection',
      checksPassed: 0,
      checksFailed: 0,
      servedSeconds: 0,
      missedSeconds: 0,
      unknownSeconds: 86400,
      evidence: [],
    }),
  },
];

const statements = rawStatementSpecs.map((spec) => {
  const envelope = signStatement(spec.statement, spec.privKey);
  const id = statementId(spec.statement);
  const digest = statementDigest(CHAIN_ID, REGISTRY_ADDRESS, id);
  const verified = verifyEnvelope(envelope);
  if (!verified.ok) {
    throw new Error(`Failed self-verification for ${spec.label}: ${verified.problem}`);
  }
  return {
    label: spec.label,
    observerAddress: spec.observerAddress,
    statementId: id,
    digest,
    signature: envelope.signature,
    canonicalJson: canonicalizeJson(spec.statement),
    envelope,
  };
});

const envelopes = statements.map((s) => s.envelope);
const context = {
  chainId: CHAIN_ID,
  registryAddress: REGISTRY_ADDRESS,
  registry: registryAccount,
  servicerAddress,
  servicer: servicerAccount,
  collateralId: COLLATERAL_ID,
  periodStart: PERIOD_START,
  periodEnd: PERIOD_END,
  pledgedDeviceKeys,
};

const agg = aggregate(envelopes, context);
const report = {
  periodStart: PERIOD_START,
  periodEnd: PERIOD_END,
  devicesReported: agg.devicesReported,
  devicesAttested: agg.devicesAttested,
  servedSeconds: Number(agg.servedSeconds),
  missedSeconds: Number(agg.missedSeconds),
  unknownSeconds: Number(agg.unknownSeconds),
  statementRoot: agg.statementRoot,
};

const checkValid = reportProblem(report, envelopes, context);
if (checkValid !== null) {
  throw new Error(`Generated valid report failed validation: ${checkValid}`);
}

// ---------------------------------------------------------------------------
// 4 Invalid test cases
// ---------------------------------------------------------------------------

// 1. Tampered servedSeconds (signed envelope modified after signing; total seconds still balanced)
const tamperedEnvelope = {
  statement: {
    ...statements[1].envelope.statement,
    servedSeconds: '75600',
    unknownSeconds: '7200',
  },
  signature: statements[1].envelope.signature,
};
const tamperedCheck = verifyEnvelope(tamperedEnvelope);
if (tamperedCheck.ok) throw new Error('Expected tamperedServedSeconds to fail verifyEnvelope');

// 2. Statement for an unpledged device
const unpledgedDeviceKey = deviceKey(0x10de, 0x02, utf8ToBytes('SN-99999999-UNPLEDGED'));
const unpledgedStmt = baseStatement({
  device: unpledgedDeviceKey,
  pciDeviceId: '2330',
  location: 'US',
  observer: servicerAccount,
  role: 'servicer',
  method: 'site-inspection',
  checksPassed: 0,
  checksFailed: 0,
  servedSeconds: 0,
  missedSeconds: 0,
  unknownSeconds: 86400,
  evidence: [],
});
const unpledgedEnv = signStatement(unpledgedStmt, SERVICER_PK);
const unpledgedAgg = aggregate([unpledgedEnv], null);
const unpledgedReport = {
  periodStart: PERIOD_START,
  periodEnd: PERIOD_END,
  devicesReported: unpledgedAgg.devicesReported,
  devicesAttested: unpledgedAgg.devicesAttested,
  servedSeconds: Number(unpledgedAgg.servedSeconds),
  missedSeconds: Number(unpledgedAgg.missedSeconds),
  unknownSeconds: Number(unpledgedAgg.unknownSeconds),
  statementRoot: unpledgedAgg.statementRoot,
};
const unpledgedProblem = reportProblem(unpledgedReport, [unpledgedEnv], context);
if (unpledgedProblem === null) throw new Error('Expected unpledgedDevice to fail reportProblem');

// 3. Attestation method with nonzero servedSeconds
const badAttestationStatement = {
  ...statements[0].envelope.statement,
  servedSeconds: '3600',
  unknownSeconds: '82800',
};
const badAttestationProblem = statementProblem(badAttestationStatement);
if (badAttestationProblem === null) {
  throw new Error('Expected attestationWithNonzeroServedSeconds to fail statementProblem');
}

// 4. Duplicate member name in raw JSON
const duplicateMemberRawJson = canonicalizeJson(statements[1].envelope.statement).replace(
  '"servedSeconds":"72000"',
  '"servedSeconds":"72000","servedSeconds":"75600"'
);
let duplicateMemberProblem = null;
try {
  parseJson(duplicateMemberRawJson);
} catch (err) {
  duplicateMemberProblem = err.message;
}
if (duplicateMemberProblem === null) {
  throw new Error('Expected duplicateMemberName to fail parseJson');
}

const vectors = {
  description: 'ERC-8515 deterministic test vectors for device keys, statements, EIP-712 digests, Merkle roots, and reports.',
  keys: {
    servicer: { privateKey: SERVICER_PK, address: servicerAddress },
    lesseeMeter: { privateKey: LESSEE_PK, address: lesseeAddress },
    thirdPartyAttester: { privateKey: ATTESTER_PK, address: attesterAddress },
  },
  context,
  domainSeparator: domainSeparator(CHAIN_ID, REGISTRY_ADDRESS),
  emptyRoot: statementRoot([]),
  devices,
  statements,
  sortedStatementIds: agg.statementIds,
  selectedByDevice: agg.selectedByDevice,
  report,
  invalidCases: [
    {
      name: 'tamperedServedSeconds',
      check: 'verifyEnvelope',
      envelope: tamperedEnvelope,
      expectedProblem: tamperedCheck.problem,
    },
    {
      name: 'unpledgedDevice',
      check: 'reportProblem',
      report: unpledgedReport,
      envelopes: [unpledgedEnv],
      context,
      expectedProblem: unpledgedProblem,
    },
    {
      name: 'attestationWithNonzeroServedSeconds',
      check: 'statementProblem',
      statement: badAttestationStatement,
      expectedProblem: badAttestationProblem,
    },
    {
      name: 'duplicateMemberName',
      check: 'parseJson',
      rawJson: duplicateMemberRawJson,
      expectedProblem: duplicateMemberProblem,
    },
  ],
};

if (vectors.emptyRoot !== ZERO_BYTES32) {
  throw new Error('Empty root must be zero bytes32');
}

const outPath = join(__dirname, 'vectors.json');
writeFileSync(outPath, JSON.stringify(vectors, null, 2) + '\n', 'utf8');
console.log(`Wrote ${outPath}`);
console.log(`  devices:    ${devices.length}`);
console.log(`  statements: ${statements.length}`);
console.log(`  root:       ${report.statementRoot}`);
console.log(`  aggregates: reported=${report.devicesReported}, attested=${report.devicesAttested}, served=${report.servedSeconds}, missed=${report.missedSeconds}, unknown=${report.unknownSeconds}`);
