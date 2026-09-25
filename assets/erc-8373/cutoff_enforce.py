#!/usr/bin/env python3
"""pq_key_binding.v1 — cutoff enforcement (Python reference).

A faithful port of the live gateway enforcer (trustless-ai/vertice-gateway src/lib/pqCutoff.ts),
which is itself the operative side of this profile. v1 over v0 changes exactly two things, both to
STOP the back catalogue being retroactively invalidated:

  1. PRE-BASELINE LEGACY ADMIT (admitted, NOT governed). An artifact anchored before the baseline's
     EFFECTIVE ACTIVATION BOUNDARY B (its anchor, or a later activated_at — see activation_of) is not
     governed by any binding — no binding was in force at that instant — but it is ADMITTED classical-
     only rather than refused: it claims no PQ companion, so nothing asserts protection it lacks (whether
     the artifact's classical signature holds is an input precondition, not checked here). The result is
     distinct: resolved=null, resolution_reason=pre_baseline, decision=ADMIT. The baseline governs only
     from B — no binding claims retroactive authority. This turns v0's "anchored before any binding
     existed -> REJECT" (which retro-invalidated the oldest back catalogue) into an admit that never
     manufactures governance.
     Fail-closed, four distinct ways: an UNAVAILABLE chain (bindings is None) is unverifiable; a
     RESOLVED-EMPTY chain (zero bindings) is a determinate refuse (no baseline to be "before"); a
     MALFORMED binding (activated_at before its own anchor) is unverifiable; and an UNANCHORED binding
     (binding_anchor_time None — a derived key with no immutable anchor) has no reproducible boundary and
     cannot govern (unverifiable/binding_anchor_unavailable when no binding is anchored — derivability is
     not anchored authority). pre_baseline is emitted ONLY after the chain resolves non-empty, well-formed,
     and against an ANCHORED binding whose B is known — never silently.

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
    """A binding's EFFECTIVE ACTIVATION BOUNDARY B: the time its authority begins to GOVERN. That is its
    own anchor time, OR a LATER activated_at — delayed activation / pre-registration ahead of a flag day,
    the migration shape §states describes — clamped to >= binding_anchor_time so authority can never begin
    before the binding was anchored. B is the ONE boundary the whole profile turns on, defined once here:
      • pre_baseline  = artifact anchored before B  (this binding did not yet govern — whether that is
                        before its anchor, or in the dormant gap between a delayed binding's anchor and
                        its activated_at); admitted classical-only, NOT governed.
      • in_force      = B <= t < R; governance begins at B, inclusive.
    No binding reaches back before its own anchor. (Corrected from baseline-governs-from-0, which
    manufactured retroactive authority §states forbids: pre_baseline is "anchored before any binding
    governed it" — governed, i.e. before B, not merely before it existed.)"""
    # Clamp to >= binding_anchor_time HERE so this function can never, in isolation, hand back a
    # sub-anchor activation — the exact bypass a bare `return activated_at` would leave open (an
    # activated_at=0 baseline governing an artifact anchored before it existed). A chain that even
    # CONTAINS an activated_at < binding_anchor_time is additionally rejected as malformed in admit()
    # before resolution runs; this clamp is defense-in-depth at the resolution site.
    if isinstance(b.get("activated_at"), int):
        return max(b["activated_at"], b["binding_anchor_time"])
    return b["binding_anchor_time"]


def resolve_in_force(bindings, at_time):
    """Which binding governs an artifact anchored at at_time. Generic over chain length and
    revocation: eligible from its activation boundary; a revoked_at ends authority (artifacts anchored
    at/after are no longer governed). Returns (binding | None, reason)."""
    eligible = []
    for b in bindings:
        if b.get("binding_anchor_time") is None:
            continue                                     # anchor UNAVAILABLE — no reproducible B, cannot govern
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
    if bindings is None:                                  # unavailable chain stays unavailable
        return None
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
    # Fail-closed DEPENDENCY FAILURE: the chain could not be resolved (bindings is None / unavailable).
    # UNVERIFIABLE — never a silent admit. Distinct from a chain that resolved and is legitimately empty.
    if bindings is None:
        return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "chain_unavailable",
                "evidence": "unverifiable", "unverifiable_reason": "chain_dependency_unresolved",
                "decision": project("unverifiable"), "rule": "chain_unavailable"}
    # RESOLVED-EMPTY: the chain read successfully and the agent has zero bindings. Determinate — no binding
    # governs, and with no baseline there is nothing for `at` to be "before", so this is NOT pre_baseline.
    # A successfully-read fact, hence refuted (not unverifiable). Kept separate from the unavailable case.
    if len(bindings) == 0:
        return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "no_bindings_in_chain",
                "evidence": "refuted", "decision": project("refuted"), "rule": "no_bindings_in_chain"}
    # MALFORMED chain: a binding's authority may begin at its anchor or LATER (activated_at), never before.
    # An activated_at BEFORE binding_anchor_time would let an optional field reopen the retroactive-authority
    # path §states forbids (an activated_at=0 baseline governing an artifact anchored before it existed), so
    # it is rejected fail-closed. activated_at may only DELAY the effective boundary, never advance it.
    if any(isinstance(b.get("activated_at"), int) and b.get("binding_anchor_time") is not None
           and b["activated_at"] < b["binding_anchor_time"] for b in bindings):
        return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "chain_malformed",
                "evidence": "unverifiable", "unverifiable_reason": "activation_before_anchor",
                "decision": project("unverifiable"), "rule": "chain_malformed"}
    resolved, reason = resolve_in_force(bindings, at)
    if resolved is None:
        # Chain resolved and non-empty; nothing ANCHORED governs at `at`. First the fail-closed cause
        # Pavlo's rule names: a binding whose anchor is UNAVAILABLE (binding_anchor_time is None) has no
        # reproducible activation boundary B — key derivability is NOT anchored authority. If NO binding
        # in the chain carries an immutable anchor, there is no B to resolve against at all → unverifiable,
        # never a from-always admit. (Distinct from chain_unavailable, which is the chain itself missing.)
        anchored = [b for b in bindings if b.get("binding_anchor_time") is not None]
        if not anchored:
            return {"resolved": None, "resolved_pq_pubkey": None, "resolution_reason": "binding_anchor_unavailable",
                    "evidence": "unverifiable", "unverifiable_reason": "binding_anchor_unavailable",
                    "decision": project("unverifiable"), "rule": "binding_anchor_unavailable"}
        # Otherwise split an innocent pre-baseline back catalogue (anchored before the earliest ANCHORED
        # binding's EFFECTIVE ACTIVATION BOUNDARY B — an un-anchored binding is simply ignored here, it
        # never governs) vs post-revocation / genuinely ungoverned (at >= B). Evidence stays the closed
        # set {verified, refuted, unverifiable}; the legacy admission lives in resolution_reason + rule.
        baseline = min(anchored, key=lambda x: x["binding_anchor_time"])
        if at < activation_of(bindings, baseline):
            # pre_baseline: NOT governed (resolved stays null) but ADMITTED under the legacy back-catalogue
            # rule. `verified` attests the TEMPORAL classification only — provably anchored before B (the
            # effective activation boundary), admitted classical-only. It does NOT assert a classical-
            # signature check: this evaluator performs none, and classical-signedness is an input
            # precondition of the legacy admit, not a fact proven here.
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
