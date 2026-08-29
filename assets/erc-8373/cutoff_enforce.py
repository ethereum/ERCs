#!/usr/bin/env python3
"""pq_key_binding.v1 — cutoff enforcement (Python reference).

A faithful port of the live gateway enforcer (trustless-ai/vertice-gateway src/lib/pqCutoff.ts),
which is itself the operative side of this profile. v1 over v0 changes exactly two things, both to
STOP the back catalogue being retroactively invalidated:

  1. PRE-BASELINE LEGACY ADMIT (admitted, NOT governed). An artifact anchored before the baseline's
     OWN anchor time B is not governed by any binding — there was no anchored binding in force at that
     instant — but it is ADMITTED classical-only rather than refused: it was legitimately classical-
     signed when classical was the norm and claims no PQ companion, so nothing asserts protection it
     lacks. The result is distinct: resolved=null, resolution_reason=pre_baseline, decision=ADMIT. The
     baseline governs only from B, exactly like a successor from its own anchor — no binding claims
     retroactive authority. This turns v0's "anchored before any binding existed -> REJECT" (which
     retro-invalidated the oldest back catalogue) into an admit that never manufactures governance.
     Fail-closed: pre_baseline is emitted ONLY after the chain and B resolve; an empty/unresolvable
     chain stays unverifiable, never a silent pre_baseline admit.

  2. TRI-STATE EVIDENCE. The verdict carries evidence in {verified, refuted, unverifiable}; the
     boolean decision (ADMIT/REJECT) is a DERIVED projection of it (project()). "checked and failed"
     (refuted) and "never checked" (unverifiable) are different facts with different next actions and
     no longer collapse into one REJECT. unverifiable carries a required reason.

What v1 deliberately does NOT change: a REVOCATION still ends a binding's authority at its
revocation anchor time. A post-revocation artifact resolves to no-in-force-binding and is REFUTED
even pre-cutoff — a revocation is a deliberate trust-ending signal, distinct from an innocent
pre-baseline artifact. That distinction is the whole point; v0 hid both behind one reason string.

Run:  python3 cutoff_enforce.py [cutoff-vectors.json]   -> exit 0 all cases reproduce, 1 otherwise.
"""
import sys, json, os


def activation_of(bindings, b):
    """When a binding's AUTHORITY starts: its own anchor time (not the moment the key was created).
    Explicit activated_at wins; otherwise every binding — the baseline included — governs only from
    its binding_anchor_time. No binding reaches back before its own anchor: an artifact anchored
    before the baseline's anchor is NOT governed (it is handled as pre_baseline in admit()), never
    retroactively governed. (Corrected from baseline-governs-from-0, which manufactured retroactive
    authority the spec's §states forbids: pre_baseline is "anchored before any binding governed it".)"""
    if isinstance(b.get("activated_at"), int):
        return b["activated_at"]
    return b["binding_anchor_time"]


def resolve_in_force(bindings, at_time):
    """Which binding governs an artifact anchored at at_time. Generic over chain length and
    revocation: eligible from its activation boundary; a revoked_at ends authority (artifacts anchored
    at/after are no longer governed). Returns (binding | None, reason)."""
    eligible = []
    for b in bindings:
        if activation_of(bindings, b) > at_time:
            continue
        rev = b.get("revoked_at")
        if rev is not None and at_time >= rev:
            continue                                     # revocation slot — authority ended
        eligible.append(b)
    if not eligible:
        return None, "no_in_force_binding"
    return max(eligible, key=lambda b: activation_of(bindings, b)), "resolved_at_anchor_time"


def apply_revocations(bindings, revocations):
    if not revocations:
        return bindings
    earliest = {}
    for r in revocations:
        cc, t = r["revokes_content_address"], r["revocation_anchor_time"]
        if cc not in earliest or t < earliest[cc]:
            earliest[cc] = t
    return [({**b, "revoked_at": earliest[b["content_address"]]}
             if b.get("content_address") in earliest else b) for b in bindings]


def project(evidence):
    """Fail-closed: only 'verified' admits. The projection is deliberately lossy — evidence travels
    beside the decision, it is not reconstructable from it."""
    return "ADMIT" if evidence == "verified" else "REJECT"


def admit(bindings, consumer_cutoff, artifact):
    at = artifact["anchor_time"]
    # Fail-closed: an empty / unresolvable chain cannot be read, so the verdict is UNVERIFIABLE — never
    # a silent pre_baseline admit. pre_baseline may be emitted ONLY after the chain and its baseline
    # anchor B have resolved successfully (below), where `at` is provably before B.
    if not bindings:
        return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "unresolvable_chain",
                "evidence": "unverifiable", "unverifiable_reason": "chain_unavailable",
                "decision": project("unverifiable"), "rule": "chain_unavailable"}
    resolved, reason = resolve_in_force(bindings, at)
    if resolved is None:
        # Chain resolved, nothing governs at `at`. Split the two determinate causes: an innocent
        # pre-baseline back catalogue (anchored before the baseline's OWN anchor B) vs post-revocation /
        # genuinely ungoverned (at >= B). The evidence axis stays the closed set {verified, refuted,
        # unverifiable} — the legacy admission lives in resolution_reason + rule, not a new value.
        baseline = min(bindings, key=lambda x: x["binding_anchor_time"])
        if at < activation_of(bindings, baseline):
            # pre_baseline: NOT governed (resolved stays null) but ADMITTED classical-only. Verified: a
            # legitimately classical-signed artifact from before the migration, claiming no PQ companion.
            return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "pre_baseline",
                    "evidence": "verified", "decision": project("verified"), "rule": "pre_baseline_legacy_admit"}
        return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": reason,
                "evidence": "refuted", "decision": project("refuted"), "rule": "no_in_force_binding"}

    base = {"resolved": resolved["name"], "resolved_pq_pubkey": resolved["pq_pubkey"],
            "resolution_reason": reason}
    anchor_known = isinstance(artifact.get("anchored"), bool)
    pre_cutoff = artifact.get("anchored") is True and at < consumer_cutoff
    c = artifact.get("pq_companion") or {}
    present = bool(c.get("present"))
    checked = isinstance(c.get("valid"), bool)
    binds_key = c.get("pq_pubkey") == resolved["pq_pubkey"]

    if pre_cutoff:
        return {**base, "evidence": "verified", "decision": project("verified"),
                "rule": "anchored_before_cutoff"}
    if present and checked and c.get("valid") is True and binds_key:
        return {**base, "evidence": "verified", "decision": project("verified"),
                "rule": "valid_pq_companion"}
    if present and not checked:
        return {**base, "evidence": "unverifiable", "unverifiable_reason": "companion_not_checked",
                "decision": project("unverifiable"), "rule": "post_cutoff_companion_unchecked"}
    if (not present) and (not anchor_known) and at < consumer_cutoff:
        return {**base, "evidence": "unverifiable", "unverifiable_reason": "anchor_status_unknown",
                "decision": project("unverifiable"), "rule": "post_cutoff_anchor_status_unknown"}
    if present and checked and c.get("valid") is True and not binds_key:
        return {**base, "evidence": "refuted", "decision": project("refuted"),
                "rule": "post_cutoff_no_valid_companion", "refuted_because": "companion_under_wrong_key"}
    return {**base, "evidence": "refuted", "decision": project("refuted"),
            "rule": "post_cutoff_no_valid_companion"}


def run(path):
    fx = json.load(open(path))
    baseB, baseR, baseC = fx.get("bindings", []), fx.get("revocations", []), fx["consumer_cutoff"]
    fails = 0
    for c in fx["cases"]:
        bindings = apply_revocations(c.get("bindings", baseB), c.get("revocations", baseR))
        got, exp = admit(bindings, c.get("consumer_cutoff", baseC), c["artifact"]), c["expected"]
        keys = ("decision", "rule", "resolved", "resolution_reason", "evidence")
        ok = all(got.get(k) == exp.get(k) for k in keys if k in exp)
        fails += not ok
        print(f"{'OK ' if ok else 'BAD'} {c['name']:<52} {got['evidence']:<12} {got['rule']:<34} -> {got['decision']}")
        if not ok:
            for k in keys:
                if k in exp and got.get(k) != exp.get(k):
                    print(f"      {k}: got {got.get(k)!r} != exp {exp.get(k)!r}")
    print(f"{len(fx['cases']) - fails}/{len(fx['cases'])} cases reproduced")
    return fails


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    arg = next((a for a in sys.argv[1:] if not a.startswith("--")), None)
    sys.exit(1 if run(arg or os.path.join(here, "pq-key-binding-v1.cutoff-vectors.json")) else 0)
