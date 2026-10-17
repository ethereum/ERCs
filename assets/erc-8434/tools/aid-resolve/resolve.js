#!/usr/bin/env node
// ERC-8434 (AID) reference resolver.
//
//   node resolve.js --rpc <url> --registry <AIDRegistry> --anchor <address> [--now <unix>] [--from-block <n>]
//   node resolve.js --fixture <fixture.json> [--now <unix>]
//
// Output:
//   { onChainState, resolvedState, reasons[], binding, authorityIntervals[], document, alsoKnownAs[],
//     facets: { current, history, invalid, unattributable } }
//
// Rules implemented (normative in the ERC):
//  - on-chain state is taken from AIDRegistry.state(anchor) (or from the fixture);
//  - resolved state downgrades ACTIVE -> STALE when the ERC-8004 registration file says "active": false;
//  - the AID Document digest MUST equal keccak256(JCS(document)); a mismatch invalidates the document;
//  - facets past validUntil are history, never current; facets without validUntil are invalid;
//  - SELF facets are never reported as verified;
//  - AUTHORITY INTERVALS: evidence keyed by agentId (erc8004-identity / -reputation / -validation)
//    is attributable only if observed inside an interval in which the binding predicate held
//    (ownerOf == anchor or agentWallet == anchor, binding record intact). Re-establishing the
//    relation opens a new interval; it never authorizes the gap. Address-keyed evidence is kept
//    and marked `attribution: "outside-interval"` when observed in a gap.
//  - TIMING: a facet may be reported `timing: "pre-outcome"` only if it carries `committedAt` whose
//    proof verifies to a time earlier than `subjectWindow.until`; otherwise `timing: "integrity-only"`
//    (or "none" when no commitment is claimed). Timing is orthogonal to provenance.
//  - EXCLUSIVITY (reference commitment-log profile): when the issuer's declared log can be read
//    (ctx.issuerLogs / ctx.logEntries), `pre-outcome` additionally requires that the log was declared
//    by the ISSUER before subjectWindow.until and holds exactly one entry for the facet's key
//    tag = keccak256(abi.encode(subject, facetType, from, until)); otherwise the facet is downgraded to
//    `integrity-only` with `exclusivity` = undeclared | missing | duplicate. Without log access: unchecked.
//    Two entries under one tag are a duplicate UNLESS the later one carries `supersedes` = the earlier
//    one's content: then it is a supersession chain and only the latest unsuperseded entry can be current.
//  - SUPERSESSION: a facet named by another facet's `supersedes` (same issuer) — in the document or as a
//    later entry in the issuer's declared log — is history, marked `supersededBy`, even inside its window.
//    A `supersedes` naming a facet of a different issuer is ignored and reported.
//  - SUPERSESSION TIMING: a superseded facet keeps its own `timing`, and the resolver reports when the
//    replacement was proven (§8 proven time: the superseding facet's verified `committedAt`, or the anchored
//    head time `provenAt` of the superseding log entry) relative to the superseded facet's subjectWindow.until:
//    `supersessionTiming` = before-outcome | not-before-outcome | unknown. A `final` facet that was pre-outcome
//    and was replaced by a supersession not proven before the outcome is marked `reversedAfterOutcome: true`:
//    the claim made in time was withdrawn after the outcome, and a reader scoring pre-outcome claims scores it.
//  - FINALITY: `finality` is reported (absent = "final"); a provisional facet may be current but is never
//    presented as final. A current provisional facet with `finalizeBy` is reported `finalization: "open"`
//    before that time and `"overdue"` at or after it when the issuer's declared log shows no supersession.
//  - ALSO KNOWN AS: each `alsoKnownAs` link is reported `confirmed` only when the linked AID's Document
//    (ctx.linkedDocuments / ctx.fetchLinkedDocument) lists this AID back; otherwise `unconfirmed`, or
//    `unchecked` when that Document was not available. A one-sided link never merges profiles.
const fs = require("fs");
const { ethers } = require("ethers");
const { canonicalize } = require("../jcs");

const STATE = ["DORMANT", "ACTIVE", "STALE", "RETIRED"];
const AGENT_KEYED = new Set(["erc8004-identity", "erc8004-reputation", "erc8004-validation"]);
const REG_ABI = [
  "function state(address) view returns (uint8)",
  "function bindingOf(address) view returns (tuple(address registry,uint256 agentId,uint64 boundAt))",
  "function lastSeen(address) view returns (uint64)",
  "function livenessWindow(address) view returns (uint64)",
  "function documentURI(address) view returns (string uri, bytes32 digest)",
  "function facetTypesOf(address) view returns (bytes32[])",
  "function getFacet(address,bytes32) view returns (tuple(bytes32 digest,uint64 validFrom,uint64 validUntil,uint8 access,string uri))",
  "function successorOf(address) view returns (address)",
  "event Bound(address indexed anchor, address indexed registry, uint256 indexed agentId)",
  "event Unbound(address indexed anchor, address indexed registry, uint256 indexed agentId)",
];
const ID_ABI = [
  "function tokenURI(uint256) view returns (string)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
  "event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue)",
];

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

// ---------------------------------------------------------------------------
// Authority intervals
// ---------------------------------------------------------------------------

/** Intersect [boundAt, unboundAt) spans with predicate-true spans. Open end = null. */
function intersectSpans(a, b) {
  const out = [];
  for (const x of a) for (const y of b) {
    const from = Math.max(x.from, y.from);
    const until = x.until == null ? y.until : y.until == null ? x.until : Math.min(x.until, y.until);
    if (until == null || from < until) out.push({ from, until });
  }
  return out.sort((p, q) => p.from - q.from);
}

function inIntervals(ts, intervals) {
  return intervals.some((i) => ts >= i.from && (i.until == null || ts < i.until));
}

/**
 * Reconstruct authority intervals for `anchor` from on-chain history:
 *  - AID registry Bound/Unbound events for the anchor  -> binding-record spans
 *  - ERC-8004 Transfer + MetadataSet("agentWallet") for the agent -> predicate spans
 * Only intervals for the agent currently (or last) bound are reconstructed per (registry, agentId).
 */
async function reconstructIntervals(p, reg, anchor, fromBlock) {
  const bound = await reg.queryFilter(reg.filters.Bound(anchor), fromBlock, "latest");
  const unbound = await reg.queryFilter(reg.filters.Unbound(anchor), fromBlock, "latest");
  const tsCache = new Map();
  const ts = async (bn) => { if (!tsCache.has(bn)) tsCache.set(bn, (await p.getBlock(bn)).timestamp); return tsCache.get(bn); };
  const events = [...bound.map((e) => ({ t: "B", e })), ...unbound.map((e) => ({ t: "U", e }))]
    .sort((x, y) => x.e.blockNumber - y.e.blockNumber || x.e.index - y.e.index);
  const result = [];
  let open = null;
  for (const { t, e } of events) {
    const at = await ts(e.blockNumber);
    if (t === "B") open = { registry: e.args.registry, agentId: Number(e.args.agentId), from: at, until: null };
    else if (open) { open.until = at; result.push(open); open = null; }
  }
  if (open) result.push(open);
  // predicate spans per (registry, agentId)
  const intervals = [];
  for (const span of result) {
    const id = new ethers.Contract(span.registry, ID_ABI, p);
    const transfers = await id.queryFilter(id.filters.Transfer(null, null, span.agentId), fromBlock, "latest");
    const walletKey = "agentWallet"; // ethers hashes indexed string filter values itself
    const metas = (await id.queryFilter(id.filters.MetadataSet(span.agentId, walletKey), fromBlock, "latest"));
    const timeline = [];
    for (const e of transfers) timeline.push({ at: await ts(e.blockNumber), bn: e.blockNumber, ix: e.index, owner: e.args.to, wallet: ethers.ZeroAddress }); // transfer clears wallet (ERC-8004)
    for (const e of metas) {
      const raw = e.args.metadataValue; const hex = ethers.hexlify(raw);
      const wallet = hex.length === 66 ? ethers.getAddress("0x" + hex.slice(26)) : hex.length === 42 ? ethers.getAddress(hex) : ethers.ZeroAddress;
      timeline.push({ at: await ts(e.blockNumber), bn: e.blockNumber, ix: e.index, wallet });
    }
    timeline.sort((x, y) => x.bn - y.bn || x.ix - y.ix);
    let owner = ethers.ZeroAddress, wallet = ethers.ZeroAddress, predFrom = null; const predSpans = [];
    for (const ev of timeline) {
      if (ev.owner !== undefined) { owner = ev.owner; wallet = ethers.ZeroAddress; }
      if (ev.wallet !== undefined && ev.owner === undefined) wallet = ev.wallet;
      const holds = owner.toLowerCase() === anchor.toLowerCase() || wallet.toLowerCase() === anchor.toLowerCase();
      if (holds && predFrom == null) predFrom = ev.at;
      if (!holds && predFrom != null) { predSpans.push({ from: predFrom, until: ev.at }); predFrom = null; }
    }
    if (predFrom != null) predSpans.push({ from: predFrom, until: null });
    for (const i of intersectSpans([span], predSpans)) intervals.push({ ...i, registry: span.registry, agentId: span.agentId });
  }
  return intervals;
}

// ---------------------------------------------------------------------------
// Timing commitments
// ---------------------------------------------------------------------------

/**
 * Verify a facet's `committedAt` and return the proven time, or null.
 *  - kind "block": the facet digest must appear in the referenced transaction's calldata or logs on
 *    `proof.chainId`; the proven time is that block's timestamp (RPC mode only).
 *  - kinds "rfc3161" / "ots": not verified by this reference resolver; a deployment plugs in a verifier
 *    via ctx.verifiers[kind](facet) -> unix time | null.
 *  - fixture mode: ctx.trustedTimestamps[facetType] supplies the output of an external verifier.
 */
async function verifyCommitment(facet, ctx) {
  const c = facet.committedAt;
  if (!c || !c.anchor) return null;
  const tt = ctx.trustedTimestamps;
  if (tt && facet.digest && tt[String(facet.digest).toLowerCase()] != null) return tt[String(facet.digest).toLowerCase()];
  if (tt && tt[facet.facetType] != null) return tt[facet.facetType];
  if (ctx.verifiers && ctx.verifiers[c.anchor]) return ctx.verifiers[c.anchor](facet);
  if (c.anchor === "block" && ctx.provider && c.proof && c.proof.txHash) {
    try {
      const net = await ctx.provider.getNetwork();
      if (c.proof.chainId != null && Number(c.proof.chainId) !== Number(net.chainId)) return null;
      const [tx, rc] = await Promise.all([ctx.provider.getTransaction(c.proof.txHash), ctx.provider.getTransactionReceipt(c.proof.txHash)]);
      if (!tx || !rc) return null;
      const needle = facet.digest.toLowerCase().slice(2);
      const hay = [tx.data, ...rc.logs.flatMap((l) => [l.data, ...l.topics])].join("").toLowerCase();
      if (!hay.includes(needle)) return null;
      return (await ctx.provider.getBlock(rc.blockNumber)).timestamp;
    } catch { return null; }
  }
  return null;
}

/** Key tag of a facet in an issuer commitment log. */
function logTag(facet) {
  const w = facet.subjectWindow || { from: 0, until: 0 };
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["string", "string", "uint64", "uint64"], [facet.subject || facet.issuerSubject || "", facet.facetType, w.from || 0, w.until || 0]));
}

/**
 * Exclusivity check against the issuer-declared log.
 *  ctx.issuerLogs: { [issuerCaip10]: { uri, declaredAt } }   (from the issuer's AID Document `commitmentLog`)
 *  ctx.logEntries: { [uri]: [{ tag, content }] }             (entries up to an anchored head, as read by the deployment)
 * Returns { exclusivity: "unchecked" | "undeclared" | "missing" | "duplicate" | "unique" }.
 */
function exclusivityOf(facet, subject, ctx) {
  const ref = facet.committedAt && facet.committedAt.log;
  const declared = ctx.issuerLogs && ctx.issuerLogs[facet.issuer];
  if (!ref || !declared) return { exclusivity: declared || ref ? "undeclared" : "unchecked" };
  if (declared.uri !== ref.uri) return { exclusivity: "undeclared", exclusivityReason: "log not the issuer's declared log" };
  if (facet.subjectWindow && declared.declaredAt >= facet.subjectWindow.until) return { exclusivity: "undeclared", exclusivityReason: "log declared after subjectWindow.until" };
  const entries = ctx.logEntries && ctx.logEntries[ref.uri];
  if (!entries) return { exclusivity: "unchecked" };
  const tag = logTag({ ...facet, subject });
  const hits = entries.filter((e) => e.tag.toLowerCase() === tag.toLowerCase());
  if (hits.length === 0) return { exclusivity: "missing" };
  const lc = (x) => String(x || "").toLowerCase();
  const mine = hits.find((e) => lc(e.content) === lc(facet.digest));
  if (!mine) return { exclusivity: "missing", exclusivityReason: "entry content differs from facet digest" };
  // supersession chain: every entry except the first must supersede another entry of the same tag; otherwise equivocation
  const contents = new Set(hits.map((e) => lc(e.content)));
  const unlinked = hits.filter((e) => !e.supersedes || !contents.has(lc(e.supersedes)));
  if (unlinked.length > 1) return { exclusivity: "duplicate" };
  const later = hits.find((e) => lc(e.supersedes) === lc(facet.digest));
  if (later) return { exclusivity: "superseded", supersededBy: later.content, supersededAtProven: Number.isFinite(later.provenAt) ? later.provenAt : null, supersededAnchor: later.anchor || (facet.committedAt && facet.committedAt.anchor) };
  return { exclusivity: hits.length > 1 ? "unique-latest" : "unique" };
}

/** Finalization status of a current `provisional` facet that carries `finalizeBy` (see the ERC, "Supersession and finality").
 *  `open` before finalizeBy; `overdue` at or after it when the issuer's declared log shows no supersession (a facet the log
 *  shows as superseded never reaches this point: it is history). `finalizeBy` on a `final` facet is ignored. */
function finalizationOf(facet, now, exclusivity) {
  if ((facet.finality || "final") !== "provisional" || !Number.isFinite(facet.finalizeBy)) return {};
  if (now < facet.finalizeBy) return { finalization: "open" };
  const out = { finalization: "overdue" };
  if (!(facet.committedAt && facet.committedAt.log)) out.finalizationReason = "no declared log to check for a supersession";
  else if (exclusivity === "unchecked" || exclusivity === "undeclared") out.finalizationReason = "issuer log " + exclusivity;
  return out;
}

const lcAid = (x) => String(x || "").toLowerCase();

/** Mutual-link check for `alsoKnownAs` (see the ERC, §1): a link is `confirmed` only when the linked AID's Document lists this
 *  AID back in its own `alsoKnownAs`; `unconfirmed` when the linked Document was read and does not; `unchecked` when it was
 *  not available. ctx.linkedDocuments maps CAIP-10 -> AID Document (fixture mode); ctx.fetchLinkedDocument(aid) may load one. */
async function alsoKnownAsOf(document, self, ctx) {
  const links = (document && Array.isArray(document.alsoKnownAs)) ? document.alsoKnownAs : [];
  const out = [];
  for (const aid of links) {
    let d = ctx.linkedDocuments ? (ctx.linkedDocuments[aid] ?? ctx.linkedDocuments[lcAid(aid)]) : undefined;
    if (d === undefined && typeof ctx.fetchLinkedDocument === "function") { try { d = await ctx.fetchLinkedDocument(aid); } catch { d = undefined; } }
    if (!d) { out.push({ aid, status: "unchecked" }); continue; }
    if (lcAid(d.aid) !== lcAid(aid)) { out.push({ aid, status: "unconfirmed", reason: "linked document is for a different AID" }); continue; }
    const back = Array.isArray(d.alsoKnownAs) && d.alsoKnownAs.some((x) => lcAid(x) === lcAid(self));
    out.push({ aid, status: back ? "confirmed" : "unconfirmed", ...(back ? {} : { reason: "linked document does not list this AID back" }) });
  }
  return out;
}

/** Document-side supersession: map digest -> { by, issuer } for facets superseded by a same-issuer facet. */
function supersessionMap(facets) {
  const byDigest = new Map(facets.map((f) => [String(f.digest).toLowerCase(), f]));
  const out = new Map(); const rejected = [];
  for (const f of facets) {
    if (!f.supersedes) continue;
    const target = byDigest.get(String(f.supersedes).toLowerCase());
    if (!target) continue;
    if (target.issuer !== f.issuer) { rejected.push({ facetType: f.facetType, supersedes: f.supersedes, reason: "cross-issuer supersession ignored" }); continue; }
    out.set(String(f.supersedes).toLowerCase(), f.digest);
  }
  return { out, rejected };
}

/** Clock tolerance of each anchor kind, in seconds (see the ERC, "timing"): the resolver subtracts it before deciding. */
const ANCHOR_TOLERANCE = {
  block: () => 12,                                                  // post-merge Ethereum: one slot
  ots: () => 7200,                                                  // Bitcoin header time: within 2 h of network time
  rfc3161: (facet) => { const a = facet.committedAt && facet.committedAt.proof && facet.committedAt.proof.accuracySeconds; return Number.isFinite(a) ? a : 60; },
};
function toleranceOf(facet) { const f = ANCHOR_TOLERANCE[facet.committedAt && facet.committedAt.anchor]; return f ? f(facet) : Infinity; }

/**
 * When the replacement of a superseded facet was proven, relative to that facet's subjectWindow.until.
 * provenAt: proven time of the superseding facet or log entry (null if it has none); anchor: its anchor kind.
 */
function supersessionTimingOf(facet, ownTiming, provenAt, anchor) {
  const w = facet.subjectWindow;
  let st;
  if (provenAt == null || !w || !Number.isFinite(w.until)) st = "unknown";
  else {
    const f = ANCHOR_TOLERANCE[anchor]; const tol = f ? f({ committedAt: { anchor } }) : Infinity;
    st = provenAt + tol < w.until ? "before-outcome" : "not-before-outcome";
  }
  const out = { supersessionTiming: st };
  if (provenAt != null) out.supersededAtProven = provenAt;
  if ((facet.finality || "final") === "final" && ownTiming === "pre-outcome" && st === "not-before-outcome") out.reversedAfterOutcome = true;
  return out;
}

function timingOf(facet, provenAt) {
  if (!facet.committedAt) return { timing: "none" };
  if (provenAt == null) return { timing: "integrity-only", timingReason: "commitment not verified" };
  if (!facet.subjectWindow || !Number.isFinite(facet.subjectWindow.until)) return { timing: "integrity-only", timingReason: "no subjectWindow", committedAtVerified: provenAt };
  const tol = toleranceOf(facet);
  if (provenAt + tol < facet.subjectWindow.until) return { timing: "pre-outcome", committedAtVerified: provenAt, anchorTolerance: tol };
  if (provenAt < facet.subjectWindow.until) return { timing: "integrity-only", timingReason: `subjectWindow.until within anchor tolerance (${tol}s) of the proven time`, committedAtVerified: provenAt, anchorTolerance: tol };
  return { timing: "integrity-only", timingReason: "committed after subjectWindow.until", committedAtVerified: provenAt, anchorTolerance: tol };
}

// ---------------------------------------------------------------------------
// Resolution (pure, over a snapshot)
// ---------------------------------------------------------------------------

/** @param snap  snapshot (see snapshotFromChain / fixtures); @param now unix; @param ctx { provider?, verifiers?, trustedTimestamps? } */
async function resolveSnapshot(snap, now, ctx = {}) {
  const reasons = [];
  const onChainState = STATE[snap.state];
  let resolvedState = onChainState;
  if (onChainState === "ACTIVE" && snap.registrationFile && snap.registrationFile.active === false) {
    resolvedState = "STALE"; reasons.push("registration file active=false");
  }
  const intervals = snap.authorityIntervals || [];
  // document integrity
  let document = null;
  if (snap.document) {
    const digest = ethers.keccak256(ethers.toUtf8Bytes(canonicalize(snap.document)));
    if (digest.toLowerCase() === (snap.documentDigest || "").toLowerCase()) document = snap.document;
    else reasons.push(`document digest mismatch: computed ${digest}, on-chain ${snap.documentDigest}`);
    if (document && document.aid && snap.aid && document.aid.toLowerCase() !== snap.aid.toLowerCase()) { reasons.push("document.aid != anchor"); document = null; }
  }
  const facets = { current: [], history: [], invalid: [], unattributable: [] };
  const listed = document ? document.facets || [] : [];
  const sup = supersessionMap(listed);
  for (const r of sup.rejected) reasons.push(`supersedes ignored (${r.facetType}): ${r.reason}`);
  for (const f of listed) {
    const tag = { ...f, verified: f.provenance !== "SELF" ? undefined : false, finality: f.finality || "final" };
    if (!f.validUntil || !Number.isFinite(f.validUntil)) { facets.invalid.push({ ...tag, reason: "missing validUntil" }); continue; }
    // supersession visible in the document (same issuer)
    const by = sup.out.get(String(f.digest).toLowerCase());
    if (by) {
      const own = timingOf(f, await verifyCommitment(f, ctx));
      const repl = listed.find((x) => String(x.digest).toLowerCase() === String(by).toLowerCase());
      const replAt = repl && repl.committedAt ? await verifyCommitment(repl, ctx) : null;
      facets.history.push({ ...tag, ...own, supersededBy: by, reason: "superseded", ...supersessionTimingOf(f, own.timing, replAt, repl && repl.committedAt && repl.committedAt.anchor) });
      continue;
    }
    // supersession visible only in the issuer's declared log
    if (f.committedAt && f.committedAt.log) {
      const ex = exclusivityOf(f, snap.aid, ctx);
      if (ex.exclusivity === "superseded") {
        const own = timingOf(f, await verifyCommitment(f, ctx));
        const { supersededAtProven, supersededAnchor, ...exRest } = ex;
        facets.history.push({ ...tag, ...own, ...exRest, reason: "superseded in issuer log", ...supersessionTimingOf(f, own.timing, supersededAtProven, supersededAnchor) });
        continue;
      }
    }
    if (f.validFrom && f.validFrom > now) { facets.invalid.push({ ...tag, reason: "not yet valid" }); continue; }
    // on-chain self facet record must agree with the document when present
    const key = ethers.keccak256(ethers.toUtf8Bytes(f.facetType));
    const oc = snap.onChainFacets && snap.onChainFacets[key];
    if (f.provenance === "SELF" && oc && oc.digest.toLowerCase() !== f.digest.toLowerCase()) { facets.invalid.push({ ...tag, reason: "on-chain digest mismatch" }); continue; }
    // authority intervals
    const observed = f.observedAt ?? f.validFrom ?? null;
    const agentKeyed = f.resolver && AGENT_KEYED.has(f.resolver.kind);
    if (intervals.length && observed != null) {
      tag.attribution = inIntervals(observed, intervals) ? "in-interval" : "outside-interval";
      if (agentKeyed && tag.attribution === "outside-interval") { facets.unattributable.push({ ...tag, reason: "observed outside every authority interval" }); continue; }
    } else if (agentKeyed && intervals.length === 0 && snap.authorityIntervals) {
      facets.unattributable.push({ ...tag, reason: "no authority interval" }); continue;
    }
    // timing (orthogonal to provenance) + exclusivity against the issuer-declared log
    Object.assign(tag, timingOf(f, await verifyCommitment(f, ctx)));
    if (tag.timing === "pre-outcome") {
      const ex = exclusivityOf(f, snap.aid, ctx);
      Object.assign(tag, ex);
      if (["undeclared", "missing", "duplicate"].includes(ex.exclusivity)) { tag.timing = "integrity-only"; tag.timingReason = "exclusivity: " + ex.exclusivity; }
    }
    if (f.validUntil <= now) { facets.history.push(tag); continue; }
    Object.assign(tag, finalizationOf(f, now, tag.exclusivity));
    facets.current.push(tag);
  }
  const alsoKnownAs = await alsoKnownAsOf(document, snap.aid, ctx);
  if (onChainState === "RETIRED") reasons.push("RETIRED: activity after retirement MUST NOT be attributed to this AID; successor=" + (snap.successor || "none"));
  return { onChainState, resolvedState, reasons, binding: snap.binding, lastSeen: snap.lastSeen, livenessWindow: snap.livenessWindow, authorityIntervals: intervals, document, alsoKnownAs, facets };
}

async function snapshotFromChain(rpc, registry, anchor, fetchImpl, fromBlock = 0) {
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
  const authorityIntervals = await reconstructIntervals(p, reg, anchor, fromBlock);
  return {
    aid: `eip155:${net.chainId}:${anchor}`, state: Number(st),
    binding: b.registry === ethers.ZeroAddress ? null : { registry: b.registry, agentId: Number(b.agentId), boundAt: Number(b.boundAt) },
    lastSeen: Number(ls), livenessWindow: Number(lw), successor: succ === ethers.ZeroAddress ? null : succ,
    documentDigest: doc.digest, document: await loadURI(doc.uri, fetchImpl), onChainFacets, registrationFile, authorityIntervals,
  };
}

async function main() {
  const a = args();
  const now = a.now ? Number(a.now) : Math.floor(Date.now() / 1000);
  let snap; const ctx = {};
  if (a.fixture) { snap = JSON.parse(fs.readFileSync(a.fixture, "utf8")); ctx.trustedTimestamps = snap.trustedTimestamps || null; ctx.issuerLogs = snap.issuerLogs || null; ctx.logEntries = snap.logEntries || null; ctx.linkedDocuments = snap.linkedDocuments || null; }
  else if (a.rpc && a.registry && a.anchor) { ctx.provider = new ethers.JsonRpcProvider(a.rpc); snap = await snapshotFromChain(ctx.provider, a.registry, a.anchor, typeof fetch === "function" ? fetch : null, a["from-block"] ? Number(a["from-block"]) : 0); }
  else { console.error("usage: --rpc <url> --registry <addr> --anchor <addr> [--from-block n] | --fixture <file>  [--now <unix>]"); process.exit(2); }
  console.log(JSON.stringify(await resolveSnapshot(snap, now, ctx), null, 2));
}

module.exports = { supersessionTimingOf, finalizationOf, alsoKnownAsOf, resolveSnapshot, snapshotFromChain, reconstructIntervals, verifyCommitment, timingOf, toleranceOf, ANCHOR_TOLERANCE, exclusivityOf, supersessionMap, logTag, STATE };
if (require.main === module) main().catch((e) => { console.error(e); process.exit(1); });
