#!/usr/bin/env node
// ERC-AID reference resolver.
//
//   node resolve.js --rpc <url> --registry <AIDRegistry> --anchor <address> [--now <unix>]
//   node resolve.js --fixture <fixture.json> [--now <unix>]
//
// Output: { onChainState, resolvedState, reasons[], binding, document, facets: { current, history, invalid } }
//
// Rules implemented (normative in the ERC):
//  - on-chain state is taken from AIDRegistry.state(anchor) (or recomputed from the fixture);
//  - resolved state downgrades ACTIVE -> STALE when the ERC-8004 registration file says "active": false;
//  - the AID Document digest MUST equal keccak256(JCS(document)); a mismatch invalidates the document;
//  - facets past validUntil are history, never current; facets without validUntil are invalid;
//  - credit-kind facets without a finite validUntil are invalid;
//  - SELF facets are never reported as verified.
const fs = require("fs");
const { ethers } = require("ethers");
const { canonicalize } = require("../jcs");

const STATE = ["DORMANT", "ACTIVE", "STALE", "RETIRED"];
const REG_ABI = [
  "function state(address) view returns (uint8)",
  "function bindingOf(address) view returns (tuple(address registry,uint256 agentId,uint64 boundAt))",
  "function lastSeen(address) view returns (uint64)",
  "function livenessWindow(address) view returns (uint64)",
  "function documentURI(address) view returns (string uri, bytes32 digest)",
  "function facetTypesOf(address) view returns (bytes32[])",
  "function getFacet(address,bytes32) view returns (tuple(bytes32 digest,uint64 validFrom,uint64 validUntil,uint8 access,string uri))",
  "function successorOf(address) view returns (address)",
];
const ID_ABI = ["function tokenURI(uint256) view returns (string)"];

function args() {
  const a = {}; const v = process.argv.slice(2);
  for (let i = 0; i < v.length; i++) if (v[i].startsWith("--")) a[v[i].slice(2)] = v[i + 1] && !v[i + 1].startsWith("--") ? v[++i] : true;
  return a;
}

async function loadURI(uri, fetchImpl) {
  if (!uri) return null;
  if (uri.startsWith("data:application/json;base64,")) return JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString("utf8"));
  if (uri.startsWith("data:application/json,")) return JSON.parse(decodeURIComponent(uri.split(",")[1]));
  if (uri.startsWith("file://")) return JSON.parse(fs.readFileSync(uri.slice(7), "utf8"));
  if (!fetchImpl) return null;
  const r = await fetchImpl(uri); return r.ok ? r.json() : null;
}

/** Pure resolution over an already-fetched snapshot (used by both RPC and fixture modes). */
function resolveSnapshot(snap, now) {
  const reasons = [];
  const onChainState = STATE[snap.state];
  let resolvedState = onChainState;
  if (onChainState === "ACTIVE" && snap.registrationFile && snap.registrationFile.active === false) {
    resolvedState = "STALE"; reasons.push("registration file active=false");
  }
  // document integrity
  let document = null;
  if (snap.document) {
    const digest = ethers.keccak256(ethers.toUtf8Bytes(canonicalize(snap.document)));
    if (digest.toLowerCase() === (snap.documentDigest || "").toLowerCase()) document = snap.document;
    else reasons.push(`document digest mismatch: computed ${digest}, on-chain ${snap.documentDigest}`);
    if (document && document.aid && snap.aid && document.aid.toLowerCase() !== snap.aid.toLowerCase()) { reasons.push("document.aid != anchor"); document = null; }
  }
  const facets = { current: [], history: [], invalid: [] };
  const listed = document ? document.facets || [] : [];
  for (const f of listed) {
    const tag = { ...f, verified: f.provenance !== "SELF" ? undefined : false };
    if (!f.validUntil || !Number.isFinite(f.validUntil)) { facets.invalid.push({ ...tag, reason: "missing validUntil" }); continue; }
    if (f.validFrom && f.validFrom > now) { facets.invalid.push({ ...tag, reason: "not yet valid" }); continue; }
    if (f.validUntil <= now) { facets.history.push(tag); continue; }
    // on-chain self facet record must agree with the document when present
    const key = ethers.keccak256(ethers.toUtf8Bytes(f.facetType));
    const oc = snap.onChainFacets && snap.onChainFacets[key];
    if (f.provenance === "SELF" && oc && oc.digest.toLowerCase() !== f.digest.toLowerCase()) { facets.invalid.push({ ...tag, reason: "on-chain digest mismatch" }); continue; }
    facets.current.push(tag);
  }
  // post-retirement rule
  if (onChainState === "RETIRED") reasons.push("RETIRED: activity after retirement MUST NOT be attributed to this AID; successor=" + (snap.successor || "none"));
  return { onChainState, resolvedState, reasons, binding: snap.binding, lastSeen: snap.lastSeen, livenessWindow: snap.livenessWindow, document, facets };
}

async function snapshotFromChain(rpc, registry, anchor, fetchImpl) {
  const p = typeof rpc === "string" ? new ethers.JsonRpcProvider(rpc) : rpc;
  const reg = new ethers.Contract(registry, REG_ABI, p);
  const net = await p.getNetwork();
  const [st, b, ls, lw, doc, types, succ] = await Promise.all([
    reg.state(anchor), reg.bindingOf(anchor), reg.lastSeen(anchor), reg.livenessWindow(anchor), reg.documentURI(anchor), reg.facetTypesOf(anchor), reg.successorOf(anchor),
  ]);
  const onChainFacets = {};
  for (const t of types) { const f = await reg.getFacet(anchor, t); onChainFacets[t] = { digest: f.digest, validFrom: Number(f.validFrom), validUntil: Number(f.validUntil), access: Number(f.access), uri: f.uri }; }
  let registrationFile = null;
  if (b.registry !== ethers.ZeroAddress) {
    try { const id = new ethers.Contract(b.registry, ID_ABI, p); registrationFile = await loadURI(await id.tokenURI(b.agentId), fetchImpl); } catch {}
  }
  return {
    aid: `eip155:${net.chainId}:${anchor}`, state: Number(st),
    binding: b.registry === ethers.ZeroAddress ? null : { registry: b.registry, agentId: Number(b.agentId), boundAt: Number(b.boundAt) },
    lastSeen: Number(ls), livenessWindow: Number(lw), successor: succ === ethers.ZeroAddress ? null : succ,
    documentDigest: doc.digest, document: await loadURI(doc.uri, fetchImpl), onChainFacets, registrationFile,
  };
}

async function main() {
  const a = args();
  const now = a.now ? Number(a.now) : Math.floor(Date.now() / 1000);
  let snap;
  if (a.fixture) snap = JSON.parse(fs.readFileSync(a.fixture, "utf8"));
  else if (a.rpc && a.registry && a.anchor) snap = await snapshotFromChain(a.rpc, a.registry, a.anchor, typeof fetch === "function" ? fetch : null);
  else { console.error("usage: --rpc <url> --registry <addr> --anchor <addr> | --fixture <file>  [--now <unix>]"); process.exit(2); }
  console.log(JSON.stringify(resolveSnapshot(snap, now), null, 2));
}

module.exports = { resolveSnapshot, snapshotFromChain, STATE };
if (require.main === module) main().catch((e) => { console.error(e); process.exit(1); });
