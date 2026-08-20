#!/usr/bin/env python3
"""pq_key_binding.v1 — cutoff enforcement (Python reference).

A faithful port of the live gateway enforcer (trustless-ai/vertice-gateway src/lib/pqCutoff.ts),
which is itself the operative side of this profile. v1 over v0 changes exactly two things, both to
STOP the back catalogue being retroactively invalidated:

  1. ACTIVATION (baseline governs from creation). The baseline binding (earliest, key_epoch 0)
     activates at time 0, not at its anchor time. Anchoring gives a binding a provable time, not a
     birthday: an artifact anchored before the baseline's own registration is still governed by it.
     Successors keep activated_at = their anchor time, so a rotation still cannot claim retroactive
     coverage. This is what turns v0's "artifact anchored before any binding existed -> REJECT"
     (which retro-invalidated the oldest back catalogue) into ADMIT-classical-only.

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
    """When a binding's AUTHORITY starts (not the anchor that proves it exists).
    Explicit activated_at wins. Else: the baseline (earliest binding) governs from 0; every other
    binding governs from its own anchor time."""
    if isinstance(b.get("activated_at"), int):
        return b["activated_at"]
    if not bindings:
        return b["binding_anchor_time"]
    baseline = min(bindings, key=lambda x: x["binding_anchor_time"])
    return 0 if b is baseline or b.get("name") == baseline.get("name") else b["binding_anchor_time"]


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
    resolved, reason = resolve_in_force(bindings, at)
    if resolved is None:
        # Determinate: the chain was read and nothing governs here (pre-baseline is now impossible
        # for a baseline that governs from 0; this fires for post-revocation / genuinely empty chains).
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
