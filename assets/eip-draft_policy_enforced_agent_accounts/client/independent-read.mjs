#!/usr/bin/env node
// Independent read test for the draft ERC "Policy-Enforced Agent Accounts". Uses only this library, a
// public RPC and the chain: no Palisec API, no API key, no private key. The policy document is fetched
// from the policyURI the chain points to, and must hash to the committed policyHash.
//
//   npm install policy-enforced-accounts viem
//   node independent-read.mjs [account] [receipt.json]
import { readFileSync } from "node:fs";
import { createPublicClient, http } from "viem";
import { REGISTRY_ADDRESSES, fetchPolicy, readAccount, verifyReceipt } from "policy-enforced-accounts";

const RPC = process.env.RPC ?? "https://rpc.mainnet.chain.robinhood.com"; // public Robinhood Chain RPC
const account = process.argv[2] ?? "0x9aEC761B2F0FdA08C683e8388478C9A2F7C9170c";
const receiptFile = process.argv[3];
const client = createPublicClient({ transport: http(RPC) });
const chainId = await client.getChainId();
const registry = REGISTRY_ADDRESSES[chainId];
const t = (s) => new Date(Number(s) * 1000).toISOString().replace(".000Z", "Z");

console.log(`chain ${chainId} · registry ${registry} · account ${account}`);
const s = await readAccount(client, account, registry);
console.log(`enforced by a policy signer: ${s.enforced ? "yes" : "no"}`);
console.log(`  policy signer   ${s.policySigner}`);
console.log(`  publisher       ${s.publisher}`);
console.log(`  receipt signer  ${s.receiptSigner}`);
console.log(`  emergency stop  ${s.stopped ? "ENGAGED" : "off"}`);
if (s.policy) {
  console.log(`active policy: v${s.policy.version}, hash ${s.policy.policyHash}, effective ${t(s.policy.effectiveAt)}`);
  if (s.policy.policyURI) {
    const p = await fetchPolicy(s.policy);
    console.log(`  document ${s.policy.policyURI}`);
    console.log(`  hash of fetched document ${p.hash}: ${p.matches ? "MATCHES the on-chain commitment" : "DOES NOT MATCH"}`);
  }
} else console.log("active policy: none committed");
console.log(s.pending ? `pending loosening: v${s.pending.version}, hash ${s.pending.policyHash}, effective ${t(s.pending.effectiveAt)}` : "pending loosening: none");
if (s.mandate) console.log(`mandate: ${s.mandate.uri} (config hash ${s.mandate.configHash})`);

if (receiptFile) {
  const receipt = JSON.parse(readFileSync(receiptFile, "utf8"));
  // The receipt's validity window has normally passed by now; checking an old receipt is an audit.
  const v = await verifyReceipt(client, receipt, { registry, now: BigInt(receipt.issuedAt), allowRotatedSigner: true });
  console.log(`receipt ${receipt.decisionId.slice(0, 10)}…: ${receipt.decision}, reason ${receipt.reasonCode} (${receipt.detailCode}), issued ${t(receipt.issuedAt)}`);
  console.log(`  signed by ${v.signer} · declared receipt signer ${v.expectedSigner}`);
  console.log(`  ${v.valid ? "RECEIPT VERIFIED" : `RECEIPT INVALID: ${v.problems.join("; ")}`}`);
  if (s.policy && receipt.policyHash.toLowerCase() === s.policy.policyHash.toLowerCase()) console.log("  decided under the active committed policy");
}
