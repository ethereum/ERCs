// Offline narrated ERC-8515 walkthrough using vectors.json (no RPC required).
// Run with: node demo.mjs
// SPDX-License-Identifier: CC0-1.0

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  formatAccount,
  parseJson,
  privateKeyToAddress,
  reportProblem,
  verifyEnvelope,
} from './evidence.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const vectors = parseJson(readFileSync(join(__dirname, 'vectors.json'), 'utf8'));

// Minimal in-memory mirror of GPUCollateralEvidence.sol for an offline walkthrough.
class OfflineRegistry {
  constructor() {
    this.pledgesByDevice = new Map();
    this.latestReports = new Map();
  }

  pledge(servicer, collateralId, deviceKeys, timestamp) {
    for (const key of deviceKeys) {
      let list = this.pledgesByDevice.get(key);
      if (!list) {
        list = [];
        this.pledgesByDevice.set(key, list);
      }
      if (list.some((p) => p.servicer === servicer && p.collateralId === collateralId)) {
        throw new Error(`AlreadyPledged(${key})`);
      }
      list.push({ servicer, collateralId, pledgedAt: timestamp });
    }
  }

  pledgeCount(deviceKey) {
    return (this.pledgesByDevice.get(deviceKey) ?? []).length;
  }

  pledgesOf(deviceKey) {
    return [...(this.pledgesByDevice.get(deviceKey) ?? [])];
  }

  deviceCount(servicer, collateralId) {
    let count = 0;
    for (const list of this.pledgesByDevice.values()) {
      if (list.some((p) => p.servicer === servicer && p.collateralId === collateralId)) {
        count++;
      }
    }
    return count;
  }

  report(servicer, collateralId, r, uri, timestamp) {
    if (r.periodStart >= r.periodEnd || r.periodEnd > timestamp) {
      throw new Error('InvalidPeriod()');
    }
    const active = this.deviceCount(servicer, collateralId);
    if (r.devicesAttested > r.devicesReported || r.devicesReported > active) {
      throw new Error('InvalidDeviceCounts()');
    }
    const lhs = BigInt(r.servedSeconds) + BigInt(r.missedSeconds) + BigInt(r.unknownSeconds);
    const rhs = BigInt(r.devicesReported) * (BigInt(r.periodEnd) - BigInt(r.periodStart));
    if (lhs !== rhs) {
      throw new Error('InvalidSecondsTotal()');
    }
    const k = `${servicer}:${collateralId}`;
    this.latestReports.set(k, { report: r, uri, reportedAt: timestamp });
  }
}

const registry = new OfflineRegistry();
const lenderA = vectors.context.servicerAddress;
const lenderB = privateKeyToAddress('0x000000000000000000000000000000000000000000000000000000000000000b');
const collateralA = vectors.context.collateralId;
const collateralB = '0x000000000000000000000000000000000000000000000000000000000000c022';

const gpu1 = vectors.devices[0];
const allKeys = vectors.devices.map((d) => d.deviceKey);

console.log('=== ERC-8515 Offline Walkthrough ===\n');

// Step 1: Double-pledge visibility
console.log('1. Exclusivity check: Lender A and Lender B both pledge GPU #1');
registry.pledge(lenderA, collateralA, allKeys, 1735680000);
console.log(`   Lender A (${lenderA}) pledges 3 GPUs under collateral ${collateralA}.`);
console.log(`   GPU #1 (${gpu1.deviceKey}) pledgeCount = ${registry.pledgeCount(gpu1.deviceKey)}`);

registry.pledge(lenderB, collateralB, [gpu1.deviceKey], 1735683600);
console.log(`   Lender B (${lenderB}) also pledges GPU #1 under collateral ${collateralB}.`);
console.log(`   The registry does NOT revert; it records both filings so any lender sees the conflict:`);
console.log(`   GPU #1 pledgeCount = ${registry.pledgeCount(gpu1.deviceKey)}`);
for (const [idx, p] of registry.pledgesOf(gpu1.deviceKey).entries()) {
  console.log(`     pledgeAt(gpu1, ${idx}) -> servicer=${p.servicer}, collateralId=${p.collateralId}, pledgedAt=${p.pledgedAt}`);
}
console.log('');

// Step 2: Servicer publishes an honest period report
console.log('2. Servicer publishes a period report for [1735689600, 1735776000)');
const report = vectors.report;
const envelopes = vectors.statements.map((s) => s.envelope);
const uri = 'ipfs://bafybeierc8515period1statements';
registry.report(lenderA, collateralA, report, uri, 1735779600);
console.log(`   On-chain registry accepted report (uri=${uri}):`);
console.log(`     devicesReported=${report.devicesReported}, devicesAttested=${report.devicesAttested}`);
console.log(`     servedSeconds=${report.servedSeconds}, missedSeconds=${report.missedSeconds}, unknownSeconds=${report.unknownSeconds}`);
console.log(`     statementRoot=${report.statementRoot}\n`);

// Step 3: Consumer fetches the statements and verifies the report
console.log('3. Consumer fetches the 6 statement envelopes and verifies them off-chain');
for (const entry of vectors.statements) {
  const res = verifyEnvelope(entry.envelope);
  const s = entry.envelope.statement;
  console.log(
    `   [OK] ${entry.label.padEnd(30)} role=${s.role.padEnd(11)} method=${s.method.padEnd(15)} signer=${res.signer}`
  );
}
const validCheck = reportProblem(report, envelopes, vectors.context);
console.log(`   reportProblem(honestReport) => ${validCheck === null ? 'null (VALID)' : validCheck}\n`);

// Step 4: Servicer publishes an inflated report that STILL passes on-chain checks
console.log('4. Servicer attempts to inflate servedSeconds by +10,800s (reducing unknownSeconds by 10,800s)');
const inflatedReport = {
  ...report,
  servedSeconds: report.servedSeconds + 10800,
  unknownSeconds: report.unknownSeconds - 10800,
};
// Note: served + missed + unknown is unchanged, so the on-chain registry accepts this replacement report!
registry.report(lenderA, collateralA, inflatedReport, uri, 1735780200);
console.log(`   On-chain registry ACCEPTED the replacement report because its arithmetic total still balances:`);
console.log(`     servedSeconds=${inflatedReport.servedSeconds}, missedSeconds=${inflatedReport.missedSeconds}, unknownSeconds=${inflatedReport.unknownSeconds}`);
console.log(`   Now the consumer re-checks the replacement report against the committed signed statements:`);
const inflatedCheck = reportProblem(inflatedReport, envelopes, vectors.context);
console.log(`   reportProblem(inflatedReport) => "${inflatedCheck}"`);
console.log(`   Caught! The registry records assertions; off-chain verification turns them into checked evidence.`);
console.log(`   (Registry account: ${formatAccount(vectors.context.chainId, vectors.context.registryAddress)})`);
