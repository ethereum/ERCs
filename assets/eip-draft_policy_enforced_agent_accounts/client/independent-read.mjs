#!/usr/bin/env node
// Independent read test for the draft ERC "Policy-Enforced Agent Accounts". Uses only this library, a
// public RPC and the chain: no Palisec API, no API key, no private key. The policy document is fetched
// from the policyURI the chain points to, and must hash to the committed policyHash.
//
//   npm install policy-enforced-accounts viem
//   node independent-read.mjs [account] [receipt.json]
import { readFileSync } from "node:fs";
import { createPublicClient, http } from "viem";
import { REGISTRY_ADDRESSES, REGISTRY_V1_ADDRESSES, REGISTRY_V2_ADDRESSES, SIGNER_TYPES, fetchPolicy, readAccount, verifyReceipt } from "policy-enforced-accounts";

const RPC = process.env.RPC ?? "https://rpc.mainnet.chain.robinhood.com"; // public Robinhood Chain RPC
const account = process.argv[2] ?? "0x9aEC761B2F0FdA08C683e8388478C9A2F7C9170c";
const receiptFile = process.argv[3];
const client = createPublicClient({ transport: http(RPC) });
const chainId = await client.getChainId();
// v3 registry by default; a receipt issued under v2 or the first draft is checked against the registry it names.
const registry = REGISTRY_ADDRESSES[chainId];
const t = (s) => new Date(Number(s) * 1000).toISOString().replace(".000Z", "Z");

console.log(`chain ${chainId} · registry ${registry} · account ${account}`);
const s = await readAccount(client, account, registry);
console.log(`enforced by a policy signer: ${s.enforced ? "yes" : "no"}`);
console.log(`  policy signer   ${s.policySigner}`);
console.log(`  publisher       ${s.publisher}`);
console.log(`  receipt signer  ${s.receiptSigner}`);
console.log(`  signer type     ${s.signerType} (${SIGNER_TYPES[s.signerType] ?? "none"})`);
console.log(`  minimum delay   ${s.minDelay} s (every publisher change and later signer change waits this long)`);
if (s.pendingSigners) console.log(`  pending signer change: publisher ${s.pendingSigners.publisher}, receipt signer ${s.pendingSigners.receiptSigner}, from ${t(s.pendingSigners.since)}`);
console.log(`  emergency stop  ${s.stopped ? (s.stopHeldByAccount ? "ENGAGED by the account (only the account can lift it)" : "ENGAGED") : "off"}`);
if (s.policy) {
  console.log(`active policy: v${s.policy.version}, hash ${s.policy.policyHash}, effective ${t(s.policy.effectiveAt)}`);
  if (s.policy.policyURI) {
    const p = await fetchPolicy(s.policy);
    console.log(`  document ${s.policy.policyURI}`);
    console.log(`  hash of fetched document ${p.hash}: ${p.matches ? "MATCHES the on-chain commitment" : "DOES NOT MATCH"}`);
  }
} else console.log("active policy: none committed");
console.log(s.pending ? `pending change: v${s.pending.version}, hash ${s.pending.policyHash}, effective ${t(s.pending.effectiveAt)}` : "pending change: none");
if (s.mandate) console.log(`mandate: ${s.mandate.uri} (config hash ${s.mandate.configHash})`);

if (receiptFile) {
  const receipt = JSON.parse(readFileSync(receiptFile, "utf8"));
  // The receipt's validity window has normally passed by now; checking an old receipt is an audit.
  const older = [REGISTRY_V1_ADDRESSES[chainId], REGISTRY_V2_ADDRESSES[chainId]].filter(Boolean);
  const under = older.find((r) => receipt.registry.toLowerCase() === r.toLowerCase()) ?? registry;
  const v = await verifyReceipt(client, receipt, { registry: under, now: BigInt(receipt.issuedAt), allowRotatedSigner: true });
  console.log(`receipt ${receipt.decisionId.slice(0, 10)}…: ${receipt.decision}, reason ${receipt.reasonCode} (${receipt.detailCode}), issued ${t(receipt.issuedAt)}`);
  console.log(`  signed by ${v.signer} · declared receipt signer ${v.expectedSigner}`);
  console.log(`  ${v.valid ? "RECEIPT VERIFIED" : `RECEIPT INVALID: ${v.problems.join("; ")}`}`);
  if (s.policy && receipt.policyHash.toLowerCase() === s.policy.policyHash.toLowerCase()) console.log("  decided under the active committed policy");
}
