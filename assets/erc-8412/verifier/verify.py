"""ERC-8412 reference off-chain verifier (§8, O1–O5).

Given the on-chain state of one preregistration plus the three published
off-chain documents (criteria, evidence bundle, attestation), report whether
the recorded verdict is refuted, and by which rule.

    python verify.py case.json          # a vector file entry
    python verify.py --chain c.json --criteria k.json --bundle b.json --attestation a.json

Output: {"valid": bool, "violations": [{"rule", "detail"}], "unchecked": [...]}

Scope of mechanisation (what this verifier can and cannot check):
- O2 checks coverage and the constraint keys that are checkable from documents
  alone: required captureMetadata keys present, `notBefore`, `mediaType`.
  It cannot open salted commitments (e.g. a geofence) or inspect media.
- O4 is mechanised for the standard decision rules (§2). A namespaced custom
  rule is reported under "unchecked", not as a violation.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "model"))

from ethcrypto import doc_digest, eip712_digest, recover, unhex  # noqa: E402
from registry import OUTCOME_NAMES, flags_from_obligations, pair  # noqa: E402

REQUIRED_CONSTRAINTS = {  # §3
    "PHOTO": ["captureMetadata"],
    "VIDEO": ["captureMetadata"],
    "GPS_TRACE": ["captureMetadata", "sampleIntervalSeconds"],
    "HUMAN_SIGNATURE": ["signerBinding"],
    "DOCUMENT": ["mediaType"],
    "WITNESS_STATEMENT": ["signerBinding"],
    "DEVICE_READING": ["deviceBinding", "captureMetadata"],
    "AGENT_LOG": ["agentBinding"],
    "GENERATED_ARTIFACT": ["modelBinding", "mediaType"],
}
NAMESPACED = re.compile(r"^[a-z0-9-]+(\.[a-z0-9-]+)+$")
RULE_AT_LEAST = re.compile(r"^ALL_REQUIRED_AND_AT_LEAST\((\d+)\)$")

WAIVER_TYPES = {"Waiver": [{"name": "preregistrationId", "type": "bytes32"},
                           {"name": "obligationIndex", "type": "uint16"},
                           {"name": "reasonDigest", "type": "bytes32"}]}


def waiver_digest(chain_id, registry, pid, index, reason_digest) -> bytes:
    domain = {"name": "ERC-8412", "version": "1", "chainId": chain_id,
              "verifyingContract": registry}
    return eip712_digest(WAIVER_TYPES, "Waiver", domain,
                         {"preregistrationId": pid, "obligationIndex": index,
                          "reasonDigest": reason_digest})


def apply_rule(rule: str, obligations, outcomes) -> str | None:
    """Standard decision rules (§2). Returns 'Satisfied' / 'NotSatisfied', or
    None for a namespaced custom rule this verifier does not implement."""
    req_ok = all(outcomes[o["index"]] in ("MET", "WAIVED")
                 for o in obligations if o["required"])
    if rule == "ALL_REQUIRED":
        return "Satisfied" if req_ok else "NotSatisfied"
    m = RULE_AT_LEAST.match(rule)
    if m:
        k = int(m.group(1))
        opt_met = sum(1 for o in obligations if not o["required"] and outcomes[o["index"]] == "MET")
        return "Satisfied" if (req_ok and opt_met >= k) else "NotSatisfied"
    return None


def verify(chain: dict, criteria: dict, bundle: dict, attestation: dict) -> dict:
    v, unchecked = [], []

    def bad(rule, detail):
        v.append({"rule": rule, "detail": detail})

    pid = chain["preregistrationId"]
    att = chain["attestation"]
    obligations = criteria.get("obligations", [])
    n = chain["obligationCount"]

    # ---------------- W: criteria document well-formedness (§2, §3)
    if [o.get("index") for o in obligations] != list(range(len(obligations))):
        bad("W", "obligations must be dense and ordered by index from 0")
    if any(o.get("waivable") for o in obligations) and not criteria.get("waiverAuthority"):
        bad("W", "waiverAuthority must be non-null when any obligation is waivable")
    for o in obligations:
        t = o.get("type", "")
        if t in REQUIRED_CONSTRAINTS:
            missing = [k for k in REQUIRED_CONSTRAINTS[t] if k not in o.get("constraints", {})]
            if missing:
                bad("W", f"obligation {o.get('index')} ({t}) missing required constraints {missing}")
        elif not NAMESPACED.match(t):
            bad("W", f"obligation {o.get('index')}: unknown unnamespaced type {t!r}")
    rule = criteria.get("decisionRule", "")
    if rule != "ALL_REQUIRED" and not RULE_AT_LEAST.match(rule) and not NAMESPACED.match(rule):
        bad("W", f"decisionRule {rule!r} is neither a standard rule nor namespaced")

    # ---------------- O5: published documents match the chain
    if doc_digest(criteria) != chain["criteriaDigest"]:
        bad("O5", "criteria document does not hash to the registered criteriaDigest")
    if doc_digest(bundle) != att["bundleDigest"]:
        bad("O5", "bundle does not hash to the attested bundleDigest")
    if doc_digest(attestation) != att["attestationDigest"]:
        bad("O5", "attestation document does not hash to the attested attestationDigest")
    for field, chain_field in [("taskRef", "taskRef"), ("expiry", "expiry"),
                               ("verifier", "verifier")]:
        if str(criteria.get(field)).lower() != str(chain[chain_field]).lower():
            bad("O5", f"criteria.{field} != on-chain {chain_field}")
    doc_sup = criteria.get("supersedes")
    chain_sup = chain["supersedes"]
    if (doc_sup is None) != (int(chain_sup, 16) == 0) or (doc_sup and doc_sup.lower() != chain_sup.lower()):
        bad("O5", "criteria.supersedes does not match on-chain supersedes")
    if len(obligations) != n:
        bad("O5", "number of obligations != on-chain obligationCount")
    elif ("0x" + flags_from_obligations(obligations).hex()) != chain["obligationFlags"].lower():
        bad("O5", "on-chain obligationFlags do not match required/waivable in the document")
    allowed = (criteria.get("verifierConstraint") or {}).get("allowed")
    if allowed is not None and chain["verifier"].lower() not in [a.lower() for a in allowed]:
        bad("O5", "on-chain verifier is not in verifierConstraint.allowed")
    if attestation.get("preregistrationId", "").lower() != pid.lower():
        bad("O5", "attestation document names a different preregistrationId")
    if attestation.get("verdict") != att["verdict"]:
        bad("O5", "attestation document verdict != on-chain verdict")
    if attestation.get("obligationOutcomes", "").lower() != att["obligationOutcomes"].lower():
        bad("O5", "attestation document outcomes != on-chain obligationOutcomes")
    if attestation.get("bundleDigest", "").lower() != att["bundleDigest"].lower():
        bad("O5", "attestation document bundleDigest != on-chain bundleDigest")

    packed = unhex(att["obligationOutcomes"])
    outcomes = {i: OUTCOME_NAMES[pair(packed, i)] for i in range(n)}

    # ---------------- O1: evidence does not predate the criteria; items bind the id
    if bundle.get("preregistrationId", "").lower() != pid.lower():
        bad("O1", "bundle does not bind this preregistrationId")
    for k, it in enumerate(bundle.get("items", [])):
        if it.get("preregistrationId", "").lower() != pid.lower():
            bad("O1", f"bundle item {k} does not bind this preregistrationId")
        ts = (it.get("captureMetadata") or {}).get("timestamp")
        if not isinstance(ts, int) or ts < chain["registeredAt"]:
            bad("O1", f"bundle item {k} captured at {ts}, before registeredAt {chain['registeredAt']}")

    # ---------------- O2: every MET obligation is covered and its checkable constraints hold
    by_index = {}
    for it in bundle.get("items", []):
        by_index.setdefault(it.get("obligationIndex"), []).append(it)
    for o in obligations:
        i = o["index"]
        if outcomes.get(i) != "MET":
            continue
        c = o.get("constraints", {})

        def satisfies(it):
            meta = it.get("captureMetadata") or {}
            if any(key not in meta for key in c.get("captureMetadata", [])):
                return False
            if "notBefore" in c and meta.get("timestamp", -1) < c["notBefore"]:
                return False
            if "mediaType" in c and it.get("mediaType") != c["mediaType"]:
                return False
            return True
        items = by_index.get(i, [])
        if not items:
            bad("O2", f"obligation {i} is MET but no bundle item covers it")
        elif not any(satisfies(it) for it in items):
            bad("O2", f"obligation {i} is MET but no covering item satisfies its constraints")

    # ---------------- O3: every WAIVED outcome carries a waiver signed by waiverAuthority
    waivers = {}
    for w in attestation.get("waivers", []):
        waivers.setdefault(w.get("obligationIndex"), []).append(w)
    authority = criteria.get("waiverAuthority")
    for i, out in outcomes.items():
        ws = waivers.get(i, [])
        if out == "WAIVED":
            if len(ws) != 1:
                bad("O3", f"obligation {i} is WAIVED but has {len(ws)} waiver records")
                continue
            w = ws[0]
            d = waiver_digest(chain["chainId"], chain["registry"], pid, i, w["reasonDigest"])
            signer = recover(d, unhex(w["signature"]))
            if not authority or not signer or signer.lower() != authority.lower():
                bad("O3", f"waiver for obligation {i} is not signed by waiverAuthority")
        elif ws:
            bad("O3", f"waiver record present for obligation {i}, which is {out}, not WAIVED")

    # ---------------- O4: verdict follows the decision rule
    verdict = att["verdict"]
    undecided = attestation.get("undecided", [])
    r = apply_rule(rule, obligations, outcomes) if obligations else None
    if r is None:
        unchecked.append("O4: custom decisionRule not implemented by this verifier")
    elif verdict in ("Satisfied", "NotSatisfied"):
        if verdict != r:
            bad("O4", f"decisionRule yields {r}, verdict is {verdict}")
        if undecided:
            bad("O4", "undecided must be empty unless the verdict is Indeterminate")
    elif verdict == "Indeterminate":
        if r == "Satisfied":
            bad("O4", "Indeterminate recorded although the decision rule is already Satisfied")
        if not undecided:
            bad("O4", "Indeterminate requires a non-empty undecided list")
        for i in undecided:
            if outcomes.get(i) != "UNMET":
                bad("O4", f"undecided obligation {i} must be encoded UNMET, is {outcomes.get(i)}")

    return {"valid": not v, "violations": v, "unchecked": unchecked}


def main(argv):
    if len(argv) == 2:
        case = json.loads(Path(argv[1]).read_text())
        case = case[0] if isinstance(case, list) else case
        res = verify(case["chain"], case["criteria"], case["bundle"], case["attestation"])
    else:
        args = dict(zip(argv[1::2], argv[2::2]))
        load = lambda k: json.loads(Path(args[k]).read_text())  # noqa: E731
        res = verify(load("--chain"), load("--criteria"), load("--bundle"), load("--attestation"))
    print(json.dumps(res, indent=2))
    return 0 if res["valid"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
