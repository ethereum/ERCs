"""Generate off-chain conformance vectors for ERC-8412 (§8, O1–O5, plus W for
criteria well-formedness).

Every vector is a complete, internally consistent package (chain state,
criteria document, evidence bundle, attestation document) with real keccak256
digests and a real EIP-712 waiver signature. Each negative vector breaks
exactly one rule.

Each vector also records `chainAccepts`: whether the on-chain registry model
accepts the same preregistration and attestation. For most refutations it
does, which is the point of §8: these are contradictions only the published
documents reveal.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
sys.path.insert(0, str(ROOT / "verifier"))

from ethcrypto import address_of_key, doc_digest, h, keccak256, sign  # noqa: E402
from registry import (Registry, Revert, VERDICT_NAMES, flags_from_obligations,  # noqa: E402
                      outcomes_from_names)
from verify import verify, waiver_digest  # noqa: E402

CHAIN_ID = 31337
REGISTRY = "0x8412000000000000000000000000000000008412"
KEYS = {name: int.from_bytes(keccak256(f"erc8412:{name}".encode()), "big")
        for name in ["author", "verifier", "waiverAuthority", "stranger"]}
ADDR = {k: address_of_key(v) for k, v in KEYS.items()}
REGISTERED_AT, EXPIRY, ATTESTED_AT = 1_788_000_000, 1_788_600_000, 1_788_100_000
TASK = h(keccak256(b"task-offchain-1"))


def dg(label):
    return h(keccak256(label.encode()))


def base_criteria():
    return {
        "version": "1",
        "taskRef": TASK,
        "supersedes": None,
        "decisionRule": "ALL_REQUIRED",
        "obligations": [
            {"index": 0, "type": "PHOTO", "required": True, "waivable": False,
             "constraints": {"captureMetadata": ["timestamp", "geolocation"],
                             "geofence": {"commitment": dg("salted-geofence")},
                             "notBefore": REGISTERED_AT, "mediaType": "image/jpeg"}},
            {"index": 1, "type": "DOCUMENT", "required": True, "waivable": True,
             "constraints": {"mediaType": "application/pdf"}},
            {"index": 2, "type": "GPS_TRACE", "required": False, "waivable": False,
             "constraints": {"captureMetadata": ["timestamp"], "sampleIntervalSeconds": 30}},
        ],
        "waiverAuthority": ADDR["waiverAuthority"],
        "verifier": ADDR["verifier"],
        "verifierConstraint": {"allowed": [ADDR["verifier"]], "maxRiskScore": 20},
        "expiry": EXPIRY,
        "terminalOnExpiry": "REFUND_WITH_RECORD",
    }


def build(name, rule, description, outcomes=("MET", "WAIVED", "UNMET"), verdict="Satisfied",
          undecided=(), mut_criteria=None, mut_bundle=None, mut_attestation=None,
          mut_chain=None, waiver_signer="waiverAuthority", expect_rules=()):
    crit = base_criteria()
    if mut_criteria:
        mut_criteria(crit)
    cdig = doc_digest(crit)
    reg = Registry(CHAIN_ID, REGISTRY)
    pid = reg.compute_id(ADDR["author"], cdig, crit["taskRef"])

    bundle = {"version": "1", "preregistrationId": pid, "items": [
        {"obligationIndex": 0, "preregistrationId": pid, "digest": dg("photo-bytes"),
         "mediaType": "image/jpeg", "locator": "ipfs://photo",
         "captureMetadata": {"timestamp": REGISTERED_AT + 3_600,
                             "geolocation": dg("salted-location")}},
        {"obligationIndex": 2, "preregistrationId": pid, "digest": dg("gps-bytes"),
         "mediaType": "application/geo+json", "locator": "ipfs://gps",
         "captureMetadata": {"timestamp": REGISTERED_AT + 3_700}},
    ]}
    if mut_bundle:
        mut_bundle(bundle, pid)

    waivers = []
    for i, o in enumerate(outcomes):
        if o == "WAIVED":
            reason = dg(f"waiver-reason-{i}")
            d = waiver_digest(CHAIN_ID, REGISTRY, pid, i, reason)
            waivers.append({"obligationIndex": i, "reasonDigest": reason,
                            "signature": h(sign(KEYS[waiver_signer], d))})
    packed = "0x" + outcomes_from_names(list(outcomes)).hex()
    attestation = {"version": "1", "preregistrationId": pid, "bundleDigest": doc_digest(bundle),
                   "verdict": verdict, "obligationOutcomes": packed,
                   "waivers": waivers, "undecided": list(undecided)}
    if mut_attestation:
        mut_attestation(attestation)

    chain = {
        "chainId": CHAIN_ID, "registry": REGISTRY, "preregistrationId": pid,
        "author": ADDR["author"], "criteriaDigest": cdig, "taskRef": crit["taskRef"],
        "obligationCount": len(crit["obligations"]),
        "obligationFlags": "0x" + flags_from_obligations(crit["obligations"]).hex(),
        "expiry": crit["expiry"], "registeredAt": REGISTERED_AT,
        "verifier": ADDR["verifier"], "supersedes": "0x" + "00" * 32,
        "attestation": {"verifier": ADDR["verifier"], "bundleDigest": doc_digest(bundle),
                        "attestationDigest": doc_digest(attestation), "verdict": verdict,
                        "obligationOutcomes": packed, "attestedAt": ATTESTED_AT},
    }
    if mut_chain:
        mut_chain(chain, crit, bundle, attestation)

    # would the contract have accepted this?
    try:
        r = Registry(CHAIN_ID, REGISTRY)
        rid = r.preregister(ADDR["author"], REGISTERED_AT, chain["criteriaDigest"], chain["taskRef"],
                            chain["obligationCount"], bytes.fromhex(chain["obligationFlags"][2:]),
                            chain["expiry"], chain["verifier"], chain["supersedes"])
        r.attest_outcome(chain["verifier"], ATTESTED_AT, rid, chain["attestation"]["bundleDigest"],
                         chain["attestation"]["attestationDigest"],
                         VERDICT_NAMES.index(chain["attestation"]["verdict"]),
                         bytes.fromhex(chain["attestation"]["obligationOutcomes"][2:]))
        accepts = True
    except Revert:
        accepts = False

    return {"name": name, "rule": rule, "description": description,
            "expect": {"valid": not expect_rules, "violations": sorted(set(expect_rules))},
            "chainAccepts": accepts,
            "chain": chain, "criteria": crit, "bundle": bundle, "attestation": attestation}


def set_path(d, path, value):
    for k in path[:-1]:
        d = d[k]
    d[path[-1]] = value


V = []
# ------------------------------------------------------------------ valid
V.append(build("valid-satisfied", "OK", "Photo MET, document WAIVED with a valid signed waiver, "
               "optional GPS UNMET; ALL_REQUIRED -> Satisfied."))
V.append(build("valid-not-satisfied", "OK", "Required photo UNMET -> NotSatisfied.",
               outcomes=("UNMET", "WAIVED", "MET"), verdict="NotSatisfied"))
V.append(build("valid-indeterminate", "OK",
               "Photo undecided (encoded UNMET, listed in undecided) -> Indeterminate.",
               outcomes=("UNMET", "WAIVED", "MET"), verdict="Indeterminate", undecided=(0,)))
V.append(build("valid-custom-rule", "OK",
               "Namespaced decisionRule: valid, O4 reported as unchecked.",
               mut_criteria=lambda c: c.update(decisionRule="io.example.weighted-v1")))

# ------------------------------------------------------------------ O1
V.append(build("o1-evidence-predates-criteria", "O1",
               "Photo captured one hour before the criteria were registered (replayed evidence).",
               mut_bundle=lambda b, pid: set_path(b, ["items", 0, "captureMetadata", "timestamp"],
                                                   REGISTERED_AT - 3_600),
               expect_rules=["O1", "O2"]))
V.append(build("o1-item-binds-other-id", "O1", "A bundle item binds a different preregistrationId.",
               mut_bundle=lambda b, pid: set_path(b, ["items", 1, "preregistrationId"], dg("other")),
               expect_rules=["O1"]))

# ------------------------------------------------------------------ O2
V.append(build("o2-met-without-evidence", "O2", "Photo marked MET but the bundle has no photo item.",
               mut_bundle=lambda b, pid: b["items"].pop(0), expect_rules=["O2"]))
V.append(build("o2-missing-capture-metadata", "O2", "Photo item lacks the required geolocation key.",
               mut_bundle=lambda b, pid: b["items"][0]["captureMetadata"].pop("geolocation"),
               expect_rules=["O2"]))
V.append(build("o2-wrong-media-type", "O2", "Photo item is image/png; criteria require image/jpeg.",
               mut_bundle=lambda b, pid: set_path(b, ["items", 0, "mediaType"], "image/png"),
               expect_rules=["O2"]))

# ------------------------------------------------------------------ O3
V.append(build("o3-waiver-missing", "O3", "Document WAIVED with no waiver record.",
               mut_attestation=lambda a: a.update(waivers=[]), expect_rules=["O3"]))
V.append(build("o3-waiver-signed-by-verifier", "O3",
               "Waiver signed by the verifier instead of waiverAuthority.",
               waiver_signer="verifier", expect_rules=["O3"]))


def tamper_reason(a):
    a["waivers"][0]["reasonDigest"] = dg("edited-reason")


V.append(build("o3-waiver-reason-edited", "O3", "Waiver reason changed after signing.",
               mut_attestation=tamper_reason, expect_rules=["O3"]))

# ------------------------------------------------------------------ O4
V.append(build("o4-false-fail", "O4",
               "All required met or waived, yet NotSatisfied (an optional UNMET lets it past E11).",
               verdict="NotSatisfied", expect_rules=["O4"]))
V.append(build("o4-indeterminate-when-satisfied", "O4",
               "Indeterminate recorded although ALL_REQUIRED already yields Satisfied.",
               verdict="Indeterminate", undecided=(2,), expect_rules=["O4"]))
V.append(build("o4-undecided-not-unmet", "O4", "undecided names an obligation encoded MET.",
               outcomes=("UNMET", "WAIVED", "MET"), verdict="Indeterminate", undecided=(0, 2),
               expect_rules=["O4"]))
V.append(build("o4-at-least-k", "O4",
               "ALL_REQUIRED_AND_AT_LEAST(1) with the only optional obligation UNMET, yet Satisfied.",
               mut_criteria=lambda c: c.update(decisionRule="ALL_REQUIRED_AND_AT_LEAST(1)"),
               expect_rules=["O4"]))

# ------------------------------------------------------------------ O5


def edit_criteria_after_registration(chain, crit, bundle, att):
    crit["obligations"][0]["constraints"]["captureMetadata"] = ["timestamp"]  # loosened later


V.append(build("o5-criteria-edited-after-registration", "O5",
               "Outcome switching: the published criteria were loosened after registration.",
               mut_chain=edit_criteria_after_registration, expect_rules=["O5"]))


def flags_disagree(chain, crit, bundle, att):
    chain["obligationFlags"] = "0x" + flags_from_obligations(
        [{"required": False, "waivable": False}, {"required": True, "waivable": True},
         {"required": False, "waivable": False}]).hex()


V.append(build("o5-flags-disagree-with-document", "O5",
               "On-chain flags register the photo as optional; the document says required. "
               "E4 then cannot protect the payer.", outcomes=("UNMET", "WAIVED", "MET"),
               mut_chain=flags_disagree, expect_rules=["O4", "O5"]))
V.append(build("o5-verifier-not-allowed", "O5", "Recorded verifier is not in verifierConstraint.allowed.",
               mut_criteria=lambda c: c["verifierConstraint"].update(allowed=[ADDR["stranger"]]),
               expect_rules=["O5"]))


def attestation_doc_disagrees(chain, crit, bundle, att):
    att["verdict"] = "NotSatisfied"


V.append(build("o5-attestation-document-disagrees", "O5",
               "Published attestation document says NotSatisfied; chain says Satisfied.",
               mut_chain=attestation_doc_disagrees, expect_rules=["O5"]))

# ------------------------------------------------------------------ W


def waivable_no_authority(c):
    c["waiverAuthority"] = None


V.append(build("w-waivable-without-authority", "W",
               "An obligation is waivable but waiverAuthority is null.",
               mut_criteria=waivable_no_authority, expect_rules=["W", "O3"]))
V.append(build("w-missing-required-constraint", "W", "GPS_TRACE without sampleIntervalSeconds.",
               mut_criteria=lambda c: c["obligations"][2]["constraints"].pop("sampleIntervalSeconds"),
               expect_rules=["W"]))
V.append(build("w-free-text-decision-rule", "W", "decisionRule is prose, not an evaluable rule.",
               mut_criteria=lambda c: c.update(decisionRule="looks good to the reviewer"),
               expect_rules=["W"]))


def main():
    out = ROOT / "vectors" / "offchain"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    failures = 0
    for vec in V:
        res = verify(vec["chain"], vec["criteria"], vec["bundle"], vec["attestation"])
        got = sorted({x["rule"] for x in res["violations"]})
        if res["valid"] != vec["expect"]["valid"] or got != vec["expect"]["violations"]:
            failures += 1
            print(f"MISMATCH {vec['name']}: got {got}, expected {vec['expect']['violations']}")
            for x in res["violations"]:
                print("   ", x)
        (out / f"{vec['name']}.json").write_text(json.dumps(vec, indent=2) + "\n")
    if failures:
        raise SystemExit(f"{failures} off-chain vector(s) disagree with the reference verifier")
    acc = sum(v["chainAccepts"] for v in V if not v["expect"]["valid"])
    neg = sum(1 for v in V if not v["expect"]["valid"])
    print(f"wrote {len(V)} off-chain vectors; {acc}/{neg} refuted packages are ones the "
          f"contract alone would have accepted")


if __name__ == "__main__":
    main()
