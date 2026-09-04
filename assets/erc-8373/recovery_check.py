#!/usr/bin/env python3
"""pq-recovery-classes.v0 — recomputable authority-transition classes for per-agent PQ keys.

A key-binding scheme survives past a single incident only if a third party can INDEPENDENTLY tell what
kind of authority transition happened — routine rotation, full-agent kill, or a fleet-wide seed-recovery —
from the anchored trail alone. Each class is a FALSIFIABLE claim; a record is judged ONLY against its
declared class and, if the predicate fails, is `rejected` — never silently relabeled (cross-class confusion
is the failure this guards).

Two evaluation modes:
  mode=classify  — verdict for a single statement (continuity / terminated / systemic_recovery / rejected).
  mode=bind_gate — the STANDING binding-path constraint (babyblueviper1): terminality can't be only an
                   auditor snapshot, it has to be enforced going forward. Before accepting a new binding for
                   an agent, reject it if an *unlifted* agent_terminal record exists — same discipline as
                   leg-2's terminal states (fail-closed, never retried).

Terminality is split by intent (decided 2026-07-31, folding Fede's lift-ability sub-question):
  terminal_owner    — deliberate retirement. ABSOLUTE. No later binding, ever. Not liftable.
  terminal_incident — defensive kill (e.g. a compromised key). Liftable, but ONLY by a valid fleet
                      seed_epoch_rotation that covers the agent — never by a per-agent path, which would let
                      the compromised key resurrect itself. Liftability is thus itself domain-separated.

Classes (design 2026-07-31 with babyblueviper1 + pipavlo82):
  rotation           continuity  — names a successor binding that exists, is in force from >= this anchor
                                   time, and is not revoked. (per-agent · SIWE owner)
  agent_terminal     termination — no key can resolve in force for any t after this anchor time. (per-agent
                                   · SIWE owner) — plus the bind_gate constraint above.
  seed_epoch_rotation systemic   — every new key == derive(S', registry, agent_id), AND anchored under an
                                   identity that provably does not derive from any seed (the classical
                                   deployer key, control proven by the anchor-tx sender). (fleet · deployer)
"""
import hashlib, json, sys

DEPLOYER = "0xff9a176577fb42b6bc9c19fd05a241e8fcd0ca14"  # classical anchor identity; not a seed-derived key

def derive(seed_epoch, registry, agent_id):  # pinned key-derivation SHAPE, not the live master seed
    return "kd:" + hashlib.sha256(f"SEED{seed_epoch}:{registry.lower()}:{agent_id}".encode()).hexdigest()

def in_force(bindings, at):
    elig = [b for b in bindings if b["binding_anchor_time"] <= at and not (b.get("revoked_at") is not None and at >= b["revoked_at"])]
    return max(elig, key=lambda b: b["binding_anchor_time"]) if elig else None

def has_any_in_force_after(bindings, t0):
    return any(b.get("revoked_at") is None or b["revoked_at"] > t0 for b in bindings)

def valid_seed_rotation(s):
    a = s.get("auth", {})
    dep_ok = (a.get("path") == "deployer_tx" and a.get("identity", "").lower() == DEPLOYER
              and a.get("anchor_tx_from", "").lower() == a.get("identity", "").lower())
    keys_ok = len(s.get("new_keys", [])) > 0 and all(k["pq_pubkey"] == derive(s["seed_epoch"], k["registry"], k["agent_id"]) for k in s["new_keys"])
    return dep_ok and keys_ok

def _same_agent(s, reg, aid):
    return s.get("registry", "").lower() == reg.lower() and str(s.get("agent_id")) == str(aid)

# ── mode=classify ────────────────────────────────────────────────────────────────────────────────────
def classify(s, hist):
    cls = s["class"]; auth = s.get("auth", {}); at = s["anchor_time"]; notes = []
    if cls == "rotation":
        owner_ok = auth.get("path") == "siwe_owner" and auth.get("identity", "").lower() == s.get("owner", "").lower()
        succ = next((b for b in hist if b["content_address"] == s.get("superseded_by_content_address")), None)
        succ_ok = bool(succ) and succ["binding_anchor_time"] >= at and succ.get("revoked_at") is None
        notes += [f"owner_authorized={owner_ok}", f"successor_in_force_unrevoked={succ_ok}"]
        return ("continuity" if owner_ok and succ_ok else "rejected"), notes
    if cls == "agent_terminal":
        owner_ok = auth.get("path") == "siwe_owner" and auth.get("identity", "").lower() == s.get("owner", "").lower()
        subtype_ok = s.get("subtype") in ("terminal_owner", "terminal_incident")
        terminated = not has_any_in_force_after(hist, at)
        notes += [f"owner_authorized={owner_ok}", f"subtype={s.get('subtype')}", f"no_in_force_key_after={terminated}"]
        return ("terminated" if owner_ok and subtype_ok and terminated else "rejected"), notes
    if cls == "seed_epoch_rotation":
        ok = valid_seed_rotation(s)
        a = s.get("auth", {})
        notes += [f"deployer_tx_authority={a.get('path')=='deployer_tx' and a.get('identity','').lower()==DEPLOYER and a.get('anchor_tx_from','').lower()==a.get('identity','').lower()}",
                  f"all_new_keys_derive_from_S'={len(s.get('new_keys',[]))>0 and all(k['pq_pubkey']==derive(s['seed_epoch'],k['registry'],k['agent_id']) for k in s.get('new_keys',[]))}"]
        return ("systemic_recovery" if ok else "rejected"), notes
    return "rejected", [f"unknown_class={cls}"]

# ── mode=bind_gate ───────────────────────────────────────────────────────────────────────────────────
# The standing constraint: reject a new binding at its anchor time if an UNLIFTED agent_terminal exists.
def bind_gate(prior, bind):
    reg, aid, at = bind["registry"], bind["agent_id"], bind["anchor_time"]
    terms = [s for s in prior if s.get("class") == "agent_terminal" and _same_agent(s, reg, aid) and s["anchor_time"] < at]
    if not terms:
        return "bind_admit", ["no_prior_terminal"]
    for t in terms:
        if t.get("subtype") == "terminal_owner":
            return "bind_reject", ["terminal_owner=absolute"]
        # terminal_incident: lifted iff a VALID fleet seed_epoch_rotation covering this agent lands after the
        # kill and by bind time. Per-agent rotations can NEVER lift it (domain separation on the lift itself).
        lifted = any(
            s.get("class") == "seed_epoch_rotation"
            and valid_seed_rotation(s)
            and any(_same_agent({"registry": k["registry"], "agent_id": k["agent_id"]}, reg, aid) for k in s.get("new_keys", []))
            and t["anchor_time"] < s["anchor_time"] <= at
            for s in prior
        )
        if not lifted:
            return "bind_reject", ["terminal_incident=unlifted"]
    return "bind_admit", ["terminal_incident=lifted_by_valid_seed_rotation"]

def check(case):
    mode = case.get("mode", "classify")
    if mode == "bind_gate":
        verdict, notes = bind_gate(case["prior_statements"], case["bind"])
    else:
        verdict, notes = classify(case["statement"], case.get("history_after", []))
    ok = verdict == case["expected_verdict"]
    return ok, verdict, notes

if __name__ == "__main__":
    fx = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "vectors.json"))
    fails = 0
    for c in fx["cases"]:
        ok, verdict, notes = check(c)
        fails += not ok
        print(f"{'OK ' if ok else 'BAD'} {c['case_id']:<52} → {verdict:<17} (want {c['expected_verdict']})  · {' · '.join(notes)}")
    print(f"\n{len(fx['cases'])-fails}/{len(fx['cases'])} cases reproduced" + ("" if not fails else "  ← MISMATCH"))
    sys.exit(1 if fails else 0)
