// Node built-in test runner suite for ERC-8512 off-chain library and test vectors.
// Run with: node --test test.mjs
// SPDX-License-Identifier: CC0-1.0

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  ZERO_BYTES32,
  aggregate,
  bigIntToBytes32,
  bytesToBigInt,
  bytesToHex,
  canonicalizeJson,
  concatBytes,
  deviceKey,
  domainSeparator,
  hexToBytes,
  keccak256,
  parseJson,
  privateKeyToAddress,
  recoverAddress,
  reportProblem,
  signDigest,
  statementDigest,
  statementId,
  statementLeaf,
  statementProblem,
  statementRoot,
  utf8ToBytes,
  verifyEnvelope,
} from './evidence.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const vectorsRaw = readFileSync(join(__dirname, 'vectors.json'), 'utf8');
const vectors = parseJson(vectorsRaw);

test('crypto primitives self-check', () => {
  // Known keccak256 test vectors
  assert.equal(
    keccak256(''),
    '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
  );
  assert.equal(
    keccak256('abc'),
    '0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45'
  );
  // Multi-block (>136 bytes) input check
  const longInput = 'a'.repeat(200);
  assert.equal(keccak256(longInput).length, 66);

  // Private key 1 -> known Ethereum address
  assert.equal(
    privateKeyToAddress('0x0000000000000000000000000000000000000000000000000000000000000001'),
    '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf'
  );

  // RFC 6979 determinism + round-trip recovery + high-s rejection
  const digest = keccak256('ERC-8512 signing self-check');
  const pk = '0x0000000000000000000000000000000000000000000000000000000000000001';
  const sig1 = signDigest(digest, pk);
  const sig2 = signDigest(digest, pk);
  assert.equal(sig1, sig2);
  assert.equal(recoverAddress(digest, sig1), '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf');

  // Malleated high-s signature MUST be rejected
  const SECP_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
  const sigBytes = hexToBytes(sig1);
  const r = sigBytes.subarray(0, 32);
  const s = bytesToBigInt(sigBytes.subarray(32, 64));
  const v = sigBytes[64];
  const highS = SECP_N - s;
  const flippedV = v === 27 ? 28 : 27;
  const malleated = bytesToHex(concatBytes(r, bigIntToBytes32(highS), Uint8Array.of(flippedV)));
  assert.throws(() => recoverAddress(digest, malleated), /low-s/);
});

test('parseJson rejects duplicate member names and accepts valid JSON', () => {
  assert.deepEqual(parseJson('{"a":"1","b":["x",{"c":"2"}]}'), { a: '1', b: ['x', { c: '2' }] });
  assert.throws(() => parseJson('{"a":"1","a":"2"}'), /Duplicate member name: "a"/);
  assert.throws(() => parseJson('{"outer":{"k":"1","k":"2"}}'), /Duplicate member name: "k"/);
  assert.throws(() => parseJson('{"a":"1"} trailing'), /Unexpected trailing/);
});

test('canonicalizeJson follows RFC 8785 key ordering and escaping', () => {
  const input = { b: '1', a: '2', '\u00e9': '3', z: 'line1\n"quoted"\\\u0007' };
  assert.equal(
    canonicalizeJson(input),
    '{"a":"2","b":"1","z":"line1\\n\\"quoted\\"\\\\\\u0007","é":"3"}'
  );
});

test('vectors.json device keys, domain separator, and empty root', () => {
  assert.equal(vectors.devices.length, 3);
  for (const d of vectors.devices) {
    const raw = d.idBytesUtf8 !== null ? utf8ToBytes(d.idBytesUtf8) : hexToBytes(d.idBytesHex);
    assert.equal(bytesToHex(raw), d.idBytesHex);
    assert.equal(deviceKey(d.pciVendorId, d.idType, raw), d.deviceKey);
  }

  assert.equal(
    domainSeparator(vectors.context.chainId, vectors.context.registryAddress),
    vectors.domainSeparator
  );
  assert.equal(statementRoot([]), ZERO_BYTES32);
  assert.equal(vectors.emptyRoot, ZERO_BYTES32);
});

test('vectors.json statements, digests, signatures, and Merkle root', () => {
  assert.equal(vectors.statements.length, 6);

  for (const entry of vectors.statements) {
    assert.equal(statementProblem(entry.envelope.statement), null);
    assert.equal(canonicalizeJson(entry.envelope.statement), entry.canonicalJson);
    assert.equal(statementId(entry.envelope.statement), entry.statementId);
    assert.equal(
      statementDigest(vectors.context.chainId, vectors.context.registryAddress, entry.statementId),
      entry.digest
    );
    const verified = verifyEnvelope(entry.envelope);
    assert.equal(verified.ok, true);
    assert.equal(verified.statementId, entry.statementId);
    assert.equal(verified.digest, entry.digest);
    assert.equal(verified.signer, entry.observerAddress);
  }

  // Single-leaf root equals its leaf
  const singleId = vectors.statements[0].statementId;
  assert.equal(statementRoot([singleId]), statementLeaf(singleId));

  // Unsorted input yields identical root to sorted input
  const reversed = [...vectors.sortedStatementIds].reverse();
  assert.equal(statementRoot(reversed), vectors.report.statementRoot);

  // Duplicate statementId rejected
  assert.throws(() => statementRoot([singleId, singleId]), /Duplicate statementId/);
});

test('vectors.json report aggregation and reportProblem', () => {
  const envelopes = vectors.statements.map((s) => s.envelope);
  const agg = aggregate(envelopes, vectors.context);

  assert.deepEqual(agg.statementIds, vectors.sortedStatementIds);
  assert.deepEqual(agg.selectedByDevice, vectors.selectedByDevice);
  assert.equal(agg.devicesReported, vectors.report.devicesReported);
  assert.equal(agg.devicesAttested, vectors.report.devicesAttested);
  assert.equal(agg.servedSeconds, BigInt(vectors.report.servedSeconds));
  assert.equal(agg.missedSeconds, BigInt(vectors.report.missedSeconds));
  assert.equal(agg.unknownSeconds, BigInt(vectors.report.unknownSeconds));
  assert.equal(agg.statementRoot, vectors.report.statementRoot);

  assert.equal(reportProblem(vectors.report, envelopes, vectors.context), null);

  // Also test passing raw JSON text to reportProblem
  assert.equal(reportProblem(vectors.report, JSON.stringify(envelopes), vectors.context), null);

  // Inflated report servedSeconds (even when served+missed+unknown still matches on-chain rule 3)
  const inflatedReport = {
    ...vectors.report,
    servedSeconds: vectors.report.servedSeconds + 3600,
    unknownSeconds: vectors.report.unknownSeconds - 3600,
  };
  const inflatedProb = reportProblem(inflatedReport, envelopes, vectors.context);
  assert.match(inflatedProb, /^servedSeconds mismatch:/);
});

test('vectors.json invalidCases match expected problem strings', () => {
  assert.equal(vectors.invalidCases.length, 4);

  for (const tc of vectors.invalidCases) {
    if (tc.check === 'verifyEnvelope') {
      assert.equal(statementProblem(tc.envelope.statement), null);
      const res = verifyEnvelope(tc.envelope);
      assert.equal(res.ok, false, `Case ${tc.name} should fail verifyEnvelope`);
      assert.equal(res.problem, tc.expectedProblem);
    } else if (tc.check === 'reportProblem') {
      const prob = reportProblem(tc.report, tc.envelopes, tc.context);
      assert.equal(prob, tc.expectedProblem);
    } else if (tc.check === 'statementProblem') {
      const prob = statementProblem(tc.statement);
      assert.equal(prob, tc.expectedProblem);
    } else if (tc.check === 'parseJson') {
      assert.throws(
        () => parseJson(tc.rawJson),
        (err) => err instanceof SyntaxError && err.message === tc.expectedProblem
      );
      // Also caught when passed as raw envelopes JSON to reportProblem
      const rawArray = `[${JSON.stringify({ statement: {}, signature: '0x' + '00'.repeat(65) }).replace('{}', tc.rawJson)}]`;
      const prob = reportProblem(vectors.report, rawArray, vectors.context);
      assert.match(prob, /Duplicate member name/);
    } else {
      assert.fail(`Unknown check kind: ${tc.check}`);
    }
  }
});

test('statementProblem enforces encoding and statement rules 1-4', () => {
  const valid = vectors.statements[1].envelope.statement;
  assert.equal(statementProblem(valid), null);

  // Missing member
  const missing = { ...valid };
  delete missing.location;
  assert.match(statementProblem(missing), /missing required member: location/);

  // Unexpected member
  assert.match(statementProblem({ ...valid, extra: 'x' }), /unexpected member: extra/);

  // Wrong kind
  assert.match(statementProblem({ ...valid, kind: 'ERC8512/statement/2' }), /kind must be/);

  // Mismatched chainId
  assert.match(
    statementProblem({ ...valid, observer: valid.observer.replace('eip155:1:', 'eip155:10:') }),
    /same chainId/
  );

  // Uppercase address rejected
  assert.match(
    statementProblem({ ...valid, observer: valid.observer.replace('0x', '0x').toUpperCase().replace('EIP155:', 'eip155:') }),
    /invalid observer account/
  );

  // Leading-zero integer rejected
  assert.match(statementProblem({ ...valid, servedSeconds: '072000' }), /invalid servedSeconds/);

  // periodStart overflow uint64
  assert.match(
    statementProblem({ ...valid, periodEnd: '18446744073709551616' }),
    /invalid periodEnd/
  );

  // Rule 1: periodEnd <= periodStart
  assert.match(
    statementProblem({ ...valid, periodEnd: valid.periodStart }),
    /periodEnd must be greater than periodStart/
  );

  // Rule 1: seconds sum mismatch
  assert.match(
    statementProblem({ ...valid, servedSeconds: '72001' }),
    /servedSeconds \+ missedSeconds \+ unknownSeconds/
  );

  // Rule 3: site-inspection must have all unknownSeconds
  const badSite = {
    ...vectors.statements[5].envelope.statement,
    missedSeconds: '60',
    unknownSeconds: '86340',
  };
  assert.match(statementProblem(badSite), /site-inspection must report the whole period as unknownSeconds/);

  // Rule 3: non-hw-attestation must have zero checksPassed / checksFailed
  assert.match(
    statementProblem({ ...valid, checksPassed: '1' }),
    /checksPassed and checksFailed must be zero/
  );
  assert.match(
    statementProblem({ ...valid, checksFailed: '1' }),
    /checksPassed and checksFailed must be zero/
  );
});

test('reportProblem requires the report context', () => {
  const envelopes = vectors.statements.map((s) => s.envelope);
  assert.equal(reportProblem(vectors.report, envelopes, {}), 'context.registry is required');
});

test('contract observers are not accepted by ECDSA recovery alone', () => {
  const env = vectors.statements[0].envelope;
  const obs = env.statement.observer.split(':')[2];
  const res = verifyEnvelope(env, { contractObservers: [obs] });
  assert.equal(res.ok, false);
  assert.match(res.problem, /ERC-1271/);
});
