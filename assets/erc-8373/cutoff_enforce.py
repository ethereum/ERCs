#!/usr/bin/env python3
"""pq_key_binding.v0 — cutoff enforcement: the rule that makes the PQ companion LOAD-BEARING.

Migration rule (spec §"Verifier rule"): admit an artifact iff it is PROVEN ANCHORED BEFORE the consumer's
cutoff, OR it carries a VALID PQ companion under the pq_pubkey of the binding IN FORCE at the artifact's
anchor time. Cutoff is by ANCHOR TIME (never created_at) and is CONSUMER-side policy — not issuer-declared.

Design shaped by pipavlo82 (2026-07-30) so exercised rotation (#133) and the revocation lane (#134) EXTEND
this predicate instead of rewriting it:
  1. the in-force binding is resolved FROM THE CHAIN even while the chain has length one;
  2. the admit/reject path carries a REVOCATION SLOT from the start (a binding's authority ends at its
     revoked_at; artifacts anchored at/after that time are no longer governed by it);
  3. the vector asserts the RESOLUTION step, not only the admit/reject outcome (predicate-not-number).

Signature validity (SLH-DSA / ML-DSA) is the separate DEEP lane; here it is supplied as evidence
(pq_companion.valid) so the POLICY is recomputable independently of any crypto library. The enforcer also
binds the companion to the resolution: a companion only counts if it verifies under the IN-FORCE key.

Run:  python3 cutoff_enforce.py [cutoff-vectors.json]   -> exit 0 all cases reproduce, 1 otherwise.
"""
import sys, json, os


def resolve_in_force(bindings, at_time):
    """Which binding governs an artifact anchored at `at_time`. Generic over chain length (1..n) and
    revocation: a binding governs from its own binding_anchor_time; an optional revoked_at ends its
    authority — artifacts anchored at/after revoked_at are no longer governed by it. Returns
    (binding | None, reason)."""
    eligible = []
    for b in bindings:
        if b["binding_anchor_time"] > at_time:
            continue                                    # not yet in force at this artifact's anchor time
        rev = b.get("revoked_at")
        if rev is not None and at_time >= rev:
            continue                                    # revocation slot — authority ended at revoked_at
        eligible.append(b)
    if not eligible:
        return None, "no_in_force_binding"
    return max(eligible, key=lambda b: b["binding_anchor_time"]), "resolved_at_anchor_time"


def apply_revocations(bindings, revocations):
    """Revocation lane (#134): a revocation is its OWN anchored statement class — it names the binding it
    revokes (by content_address) and takes effect at ITS OWN anchor time (never a self-declared field, same
    reason cutoff uses anchor time not created_at). Here it fills the `revoked_at` slot that resolve_in_force
    already honours, so revocation extends the predicate rather than rewriting it. Returns a copy; artifacts
    anchored before the revocation's anchor time stay governed, at/after do not."""
    if not revocations:
        return bindings
    earliest = {}
    for r in revocations:
        cc, t = r["revokes_content_address"], r["revocation_anchor_time"]
        if cc not in earliest or t < earliest[cc]:
            earliest[cc] = t                            # earliest anchored revocation of a binding wins
    return [({**b, "revoked_at": earliest[b["content_address"]]}
             if b.get("content_address") in earliest else b) for b in bindings]


def admit(bindings, consumer_cutoff, artifact):
    """Resolve the in-force binding FIRST (the step the vector asserts), then apply the cutoff rule."""
    at = artifact["anchor_time"]
    resolved, why = resolve_in_force(bindings, at)
    out = {
        "resolved": resolved["name"] if resolved else None,
        "resolved_pq_pubkey": resolved["pq_pubkey"] if resolved else None,
        "resolution_reason": why,
    }
    if resolved is None:
        out.update(decision="REJECT", rule="no_in_force_binding")
        return out

    pre_cutoff = bool(artifact.get("anchored")) and at < consumer_cutoff
    comp = artifact.get("pq_companion") or {}
    # a companion counts only if present, valid, AND verified under the IN-FORCE key (binds resolution↔sig)
    companion_binds = (comp.get("present") and comp.get("valid")
                       and comp.get("pq_pubkey") == resolved["pq_pubkey"])

    if pre_cutoff:
        out.update(decision="ADMIT", rule="anchored_before_cutoff")
    elif companion_binds:
        out.update(decision="ADMIT", rule="valid_pq_companion")
    else:
        out.update(decision="REJECT", rule="post_cutoff_no_valid_companion")
    return out


def run(path):
    fx = json.load(open(path))
    base_bindings, base_cutoff = fx.get("bindings", []), fx["consumer_cutoff"]
    base_revocations = fx.get("revocations", [])
    fails = 0
    for c in fx["cases"]:
        bindings = c.get("bindings", base_bindings)
        bindings = apply_revocations(bindings, c.get("revocations", base_revocations))
        cutoff = c.get("consumer_cutoff", base_cutoff)
        got, exp = admit(bindings, cutoff, c["artifact"]), c["expected"]
        # assert the RESOLUTION step (which binding, by which reason) AND the decision+rule — not just the boolean
        ok = (got["decision"] == exp["decision"] and got["rule"] == exp["rule"]
              and got["resolved"] == exp["resolved"] and got["resolution_reason"] == exp["resolution_reason"])
        fails += not ok
        print(f"{'OK ' if ok else 'BAD'} {c['name']:<46} resolved={str(got['resolved']):<12} {got['rule']:<30} -> {got['decision']}")
    print(f"{len(fx['cases']) - fails}/{len(fx['cases'])} cases reproduced")
    return fails


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    arg = next((a for a in sys.argv[1:] if not a.startswith("--")), None)
    sys.exit(1 if run(arg or os.path.join(here, "pq-key-binding-v0.cutoff-vectors.json")) else 0)
