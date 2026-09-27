"""Generate on-chain conformance vectors for ERC-8412 (§6, §7).

Each case exercises exactly one invariant where possible, names it, and is
validated against the reference model before being written. Output:
vectors/onchain/<INVARIANT>.json, each holding a list of cases.

Case format
-----------
{
  "name": "...", "invariant": "E7", "level": "MUST" | "SHOULD",
  "description": "...",
  "steps": [
    {"call": "preregister", "from": "author", "timestamp": 1000,
     "args": {...}, "expect": {"ok": true, "bind": "p1", "preregistrationId": "0x..."}},
    {"call": "attestOutcome", "from": "verifier", "timestamp": 1500,
     "args": {"preregistrationId": "$p1", ...}, "expect": {"revert": "E7"}},
    {"call": "getAttestation", "args": {"preregistrationId": "$p1"},
     "expect": {"verdict": "ExpiredUnresolved"}}
  ]
}

`expect.revert` names the invariant the case targets. Conformance only
requires that the call reverts; the tag documents why.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from ethcrypto import address_of_key, keccak256  # noqa: E402
from registry import (ZERO32, Registry, Revert, VERDICT_NAMES, pack)  # noqa: E402

CHAIN_ID = 31337
REGISTRY = "0x8412000000000000000000000000000000008412"
ACTORS = {name: address_of_key(int.from_bytes(keccak256(f"erc8412:{name}".encode()), "big"))
          for name in ["author", "verifier", "stranger", "author2"]}

T0, EXPIRY = 1_000, 2_000
TASK = "0x" + keccak256(b"task-1").hex()
TASK2 = "0x" + keccak256(b"task-2").hex()


def digest(label: str) -> str:
    return "0x" + keccak256(label.encode()).hex()


# obligation flag pair values (§5): 0 optional, 1 required, 2 optional+waivable, 3 required+waivable
STD_FLAGS = [1, 3, 0]          # required, required+waivable, optional
STD_FLAGS_HEX = "0x" + pack(STD_FLAGS).hex()


def out_hex(names):
    idx = {"UNMET": 0, "MET": 1, "WAIVED": 2, "NOT_APPLICABLE": 3}
    return "0x" + pack([idx[n] for n in names]).hex()


def prereg(bind, frm="author", ts=T0, criteria="criteria-1", task=TASK, count=3,
           flags=STD_FLAGS_HEX, expiry=EXPIRY, verifier="verifier", supersedes=None, expect=None):
    return {"call": "preregister", "from": frm, "timestamp": ts,
            "args": {"criteriaDigest": digest(criteria), "taskRef": task,
                     "obligationCount": count, "obligationFlags": flags, "expiry": expiry,
                     "verifier": verifier, "supersedes": supersedes or ZERO32},
            "expect": expect or {"ok": True, "bind": bind}}


def attest(pid, verdict, outcomes, frm="verifier", ts=1_500, expect=None, outcomes_hex=None):
    return {"call": "attestOutcome", "from": frm, "timestamp": ts,
            "args": {"preregistrationId": pid, "bundleDigest": digest("bundle"),
                     "attestationDigest": digest("attestation"), "verdict": verdict,
                     "obligationOutcomes": outcomes_hex or out_hex(outcomes)},
            "expect": expect or {"ok": True}}


def resolve(pid, ts, frm="stranger", expect=None):
    return {"call": "resolveExpired", "from": frm, "timestamp": ts,
            "args": {"preregistrationId": pid}, "expect": expect or {"ok": True}}


def verdict_is(pid, v):
    return {"call": "getAttestation", "args": {"preregistrationId": pid}, "expect": {"verdict": v}}


def rev(tag):
    return {"revert": tag}


GOOD = ["MET", "WAIVED", "UNMET"]  # required MET, required+waivable WAIVED, optional UNMET

CASES = []


def case(inv, name, desc, steps, level="MUST"):
    CASES.append({"name": name, "invariant": inv, "level": level, "description": desc,
                  "steps": steps})


# ------------------------------------------------------------------ positive paths
case("OK", "lifecycle-satisfied", "Required MET, waivable WAIVED, optional UNMET -> Satisfied.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD), verdict_is("$p1", "Satisfied")])
case("OK", "lifecycle-not-satisfied", "A required obligation UNMET -> NotSatisfied.",
     [prereg("p1"), attest("$p1", "NotSatisfied", ["UNMET", "MET", "MET"]),
      verdict_is("$p1", "NotSatisfied")])
case("OK", "lifecycle-indeterminate", "Undecided required obligation encoded UNMET -> Indeterminate.",
     [prereg("p1"), attest("$p1", "Indeterminate", ["UNMET", "MET", "MET"]),
      verdict_is("$p1", "Indeterminate")])
case("OK", "optional-not-applicable", "NOT_APPLICABLE is allowed on an optional obligation.",
     [prereg("p1"), attest("$p1", "Satisfied", ["MET", "MET", "NOT_APPLICABLE"])])
case("OK", "attest-exactly-at-expiry", "E7 boundary: attestation at block.timestamp == expiry succeeds.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD, ts=EXPIRY)])
case("OK", "resolve-after-expiry-permissionless",
     "E8: any caller may resolve at expiry + 1; verdict becomes ExpiredUnresolved.",
     [prereg("p1"), resolve("$p1", EXPIRY + 1, frm="stranger"),
      verdict_is("$p1", "ExpiredUnresolved")])
case("OK", "supersede-before-attestation", "Re-registration before any verdict; new one is attestable.",
     [prereg("p1"), prereg("p2", ts=1_100, criteria="criteria-2", supersedes="$p1"),
      attest("$p2", "Satisfied", GOOD, ts=1_200)])
case("OK", "supersede-after-indeterminate", "E12 permits superseding an Indeterminate verdict.",
     [prereg("p1"), attest("$p1", "Indeterminate", ["UNMET", "MET", "MET"], ts=1_200),
      prereg("p2", ts=1_300, criteria="criteria-2", supersedes="$p1"),
      attest("$p2", "Satisfied", GOOD, ts=1_400)])

# ------------------------------------------------------------------ E1
case("E1", "expiry-equals-now", "expiry == block.timestamp is rejected.",
     [prereg("p1", expiry=T0, expect=rev("E1"))])
case("E1", "expiry-in-past", "expiry < block.timestamp is rejected.",
     [prereg("p1", expiry=T0 - 1, expect=rev("E1"))])

# ------------------------------------------------------------------ E2
case("E2", "flags-wrong-length", "3 obligations need exactly 1 flag byte.",
     [prereg("p1", flags="0x7000", expect=rev("E2"))])
case("E2", "flags-nonzero-pad", "Trailing pad bits of obligationFlags must be zero.",
     [prereg("p1", flags="0x" + format(pack(STD_FLAGS)[0] | 0b01, "02x"), expect=rev("E2"))])
case("E2", "outcomes-wrong-length", "obligationOutcomes length must match obligationCount.",
     [prereg("p1"), attest("$p1", "Satisfied", None, outcomes_hex="0x6400", expect=rev("E2"))])
case("E2", "outcomes-nonzero-pad", "Trailing pad bits of obligationOutcomes must be zero.",
     [prereg("p1"), attest("$p1", "Satisfied", None,
                           outcomes_hex="0x" + format(int(out_hex(GOOD), 16) | 0b11, "02x"),
                           expect=rev("E2"))])

# ------------------------------------------------------------------ E3
case("E3", "attest-by-stranger", "Only the recorded verifier may attest (front-running guard).",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD, frm="stranger", expect=rev("E3"))])
case("E3", "attest-by-author", "The criteria author is not the verifier and cannot attest.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD, frm="author", expect=rev("E3"))])

# ------------------------------------------------------------------ E4
case("E4", "satisfied-with-required-unmet", "Satisfied over a required UNMET is unrepresentable.",
     [prereg("p1"), attest("$p1", "Satisfied", ["UNMET", "MET", "MET"], expect=rev("E4"))])

# ------------------------------------------------------------------ E5
case("E5", "waived-not-waivable", "WAIVED on a non-waivable obligation is rejected.",
     [prereg("p1"), attest("$p1", "Satisfied", ["WAIVED", "MET", "MET"], expect=rev("E5"))])

# ------------------------------------------------------------------ E6
case("E6", "not-applicable-on-required", "NOT_APPLICABLE on a required obligation is rejected.",
     [prereg("p1"), attest("$p1", "NotSatisfied", ["NOT_APPLICABLE", "MET", "UNMET"],
                           expect=rev("E6"))])

# ------------------------------------------------------------------ E7
case("E7", "attest-after-expiry", "Attestation at expiry + 1 reverts.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD, ts=EXPIRY + 1, expect=rev("E7"))])

# ------------------------------------------------------------------ E8
case("E8", "resolve-at-expiry", "Resolution at exactly expiry reverts (windows are disjoint).",
     [prereg("p1"), resolve("$p1", EXPIRY, expect=rev("E8"))])
case("E8", "resolve-before-expiry", "Resolution before expiry reverts.",
     [prereg("p1"), resolve("$p1", 1_500, expect=rev("E8"))])
case("E8", "resolve-after-attestation", "Resolution after an attestation reverts.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD), resolve("$p1", EXPIRY + 1, expect=rev("E8")),
      verdict_is("$p1", "Satisfied")])
case("E8", "resolve-superseded", "A superseded preregistration cannot be resolved.",
     [prereg("p1"), prereg("p2", ts=1_100, criteria="criteria-2", supersedes="$p1", expiry=5_000),
      resolve("$p1", EXPIRY + 1, expect=rev("E8"))])
case("E8", "boundary-no-overwrite",
     "The reported gap: at expiry, resolution fails and attestation succeeds; nothing overwrites.",
     [prereg("p1"), resolve("$p1", EXPIRY, expect=rev("E8")),
      attest("$p1", "Satisfied", GOOD, ts=EXPIRY), verdict_is("$p1", "Satisfied")])

# ------------------------------------------------------------------ E9
case("E9", "verdict-none", "verdict == None is rejected.",
     [prereg("p1"), attest("$p1", "None", GOOD, expect=rev("E9"))])
case("E9", "verdict-expired-unresolved", "Verifiers cannot attest ExpiredUnresolved directly.",
     [prereg("p1"), attest("$p1", "ExpiredUnresolved", GOOD, expect=rev("E9"))])

# ------------------------------------------------------------------ E10
case("E10", "second-attestation", "A recorded verdict is final; a second attestation reverts.",
     [prereg("p1"), attest("$p1", "NotSatisfied", ["UNMET", "MET", "MET"], ts=1_200),
      attest("$p1", "Satisfied", GOOD, ts=1_300, expect=rev("E10")),
      verdict_is("$p1", "NotSatisfied")])
case("E10", "attest-after-expired-unresolved",
     "ExpiredUnresolved is terminal (also past expiry, so E7 applies too).",
     [prereg("p1"), resolve("$p1", EXPIRY + 1),
      attest("$p1", "Satisfied", GOOD, ts=EXPIRY + 1, expect=rev("E10")),
      verdict_is("$p1", "ExpiredUnresolved")])

# ------------------------------------------------------------------ E11
case("E11", "not-satisfied-all-met", "NotSatisfied with no UNMET obligation is rejected.",
     [prereg("p1"), attest("$p1", "NotSatisfied", ["MET", "MET", "MET"], expect=rev("E11"))])
case("E11", "indeterminate-nothing-unmet",
     "Indeterminate needs at least one undecided (UNMET) obligation.",
     [prereg("p1"), attest("$p1", "Indeterminate", ["MET", "WAIVED", "NOT_APPLICABLE"],
                           expect=rev("E11"))])

# ------------------------------------------------------------------ E12
case("E12", "supersede-unknown-prior", "Superseding an unknown preregistrationId reverts.",
     [prereg("p2", criteria="criteria-2", supersedes=digest("nope"), expect=rev("E12"))])
case("E12", "supersede-by-other-author", "Only the same author may supersede.",
     [prereg("p1"), prereg("p2", frm="author2", ts=1_100, criteria="criteria-2", supersedes="$p1",
                           expect=rev("E12"))])
case("E12", "supersede-other-task", "The superseding preregistration must share taskRef.",
     [prereg("p1"), prereg("p2", ts=1_100, criteria="criteria-2", task=TASK2, supersedes="$p1",
                           expect=rev("E12"))])
case("E12", "supersede-twice", "A preregistration can be superseded only once.",
     [prereg("p1"), prereg("p2", ts=1_100, criteria="criteria-2", supersedes="$p1"),
      prereg("p3", ts=1_200, criteria="criteria-3", supersedes="$p1", expect=rev("E12"))])
case("E12", "supersede-after-satisfied", "A Satisfied verdict cannot be superseded.",
     [prereg("p1"), attest("$p1", "Satisfied", GOOD, ts=1_200),
      prereg("p2", ts=1_300, criteria="criteria-2", supersedes="$p1", expect=rev("E12"))])
case("E12", "supersede-after-not-satisfied", "A NotSatisfied verdict cannot be superseded.",
     [prereg("p1"), attest("$p1", "NotSatisfied", ["UNMET", "MET", "MET"], ts=1_200),
      prereg("p2", ts=1_300, criteria="criteria-2", supersedes="$p1", expect=rev("E12"))])
case("E12", "supersede-after-expired", "ExpiredUnresolved cannot be superseded.",
     [prereg("p1"), resolve("$p1", EXPIRY + 1),
      prereg("p2", ts=EXPIRY + 2, criteria="criteria-2", expiry=9_000, supersedes="$p1",
             expect=rev("E12"))])

# ------------------------------------------------------------------ E13
case("E13", "attest-superseded", "A superseded preregistration cannot be attested.",
     [prereg("p1"), prereg("p2", ts=1_100, criteria="criteria-2", supersedes="$p1"),
      attest("$p1", "Satisfied", GOOD, ts=1_200, expect=rev("E13"))])

# ------------------------------------------------------------------ E14
case("E14", "zero-verifier", "verifier == address(0) is rejected.",
     [prereg("p1", verifier="zero", expect=rev("E14"))])
case("E14", "author-is-verifier", "verifier == msg.sender SHOULD be rejected.",
     [prereg("p1", verifier="author", expect=rev("E14"))], level="SHOULD")

# ------------------------------------------------------------------ §6 id and duplicates
case("DUP", "duplicate-preregistration", "Same author, criteriaDigest and taskRef twice reverts.",
     [prereg("p1"), prereg("p1b", ts=1_100, expect=rev("DUP"))])
case("ID", "preregistration-id-formula",
     "preregistrationId == keccak256(abi.encode(chainid, registry, author, criteriaDigest, taskRef)).",
     [prereg("p1", expect={"ok": True, "bind": "p1", "checkId": True})])


# ------------------------------------------------------------------ runner (shared)
def addr(name):
    if name == "zero":
        return "0x" + "00" * 20
    return ACTORS[name]


def run_case(c, disabled=frozenset(), strict_tags=True):
    """Returns (passed: bool, message). Fills checkId expectations."""
    reg = Registry(CHAIN_ID, REGISTRY, disabled=set(disabled))
    binds = {}

    def res(v):
        return binds[v[1:]] if isinstance(v, str) and v.startswith("$") else v

    for i, s in enumerate(c["steps"]):
        a = {k: res(v) for k, v in s["args"].items()}
        exp = s["expect"]
        try:
            if s["call"] == "preregister":
                out = reg.preregister(addr(s["from"]), s["timestamp"], a["criteriaDigest"],
                                      a["taskRef"], a["obligationCount"],
                                      bytes.fromhex(a["obligationFlags"][2:]), a["expiry"],
                                      addr(a["verifier"]), a["supersedes"])
                if "bind" in exp:
                    binds[exp["bind"]] = out
                if exp.get("checkId"):
                    want = reg.compute_id(addr(s["from"]), a["criteriaDigest"], a["taskRef"])
                    exp["preregistrationId"] = want
                    if out != want:
                        return False, f"step {i}: id mismatch"
            elif s["call"] == "attestOutcome":
                reg.attest_outcome(addr(s["from"]), s["timestamp"], a["preregistrationId"],
                                   a["bundleDigest"], a["attestationDigest"],
                                   VERDICT_NAMES.index(a["verdict"]),
                                   bytes.fromhex(a["obligationOutcomes"][2:]))
            elif s["call"] == "resolveExpired":
                reg.resolve_expired(addr(s["from"]), s["timestamp"], a["preregistrationId"])
            elif s["call"] == "getAttestation":
                got = VERDICT_NAMES[reg.get_attestation(a["preregistrationId"]).verdict]
                if got != exp["verdict"]:
                    return False, f"step {i}: verdict {got} != {exp['verdict']}"
                continue
            if "revert" in exp:
                return False, f"step {i} ({s['call']}): expected revert {exp['revert']}, succeeded"
        except Revert as e:
            if "revert" not in exp:
                return False, f"step {i} ({s['call']}): unexpected revert {e}"
            if strict_tags and e.tag != exp["revert"]:
                return False, f"step {i}: reverted {e.tag}, expected {exp['revert']}"
    return True, "ok"


def main():
    out = ROOT / "vectors" / "onchain"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    groups = {}
    for c in CASES:
        ok, msg = run_case(c)
        if not ok:
            raise SystemExit(f"model disagrees with vector {c['invariant']}/{c['name']}: {msg}")
        groups.setdefault(c["invariant"], []).append(c)
    meta = {"chainId": CHAIN_ID, "registry": REGISTRY, "actors": ACTORS,
            "note": "Actors are EOAs derived from keccak256('erc8412:<name>'). "
                    "'zero' denotes address(0). Conformance requires that a call with "
                    "expect.revert reverts; the tag names the targeted invariant."}
    (out / "_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    for inv, cs in groups.items():
        (out / f"{inv}.json").write_text(json.dumps(cs, indent=2) + "\n")
    print(f"wrote {len(CASES)} on-chain cases in {len(groups)} files")


if __name__ == "__main__":
    main()
