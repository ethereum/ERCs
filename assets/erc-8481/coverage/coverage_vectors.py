#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Reference checker for the ERC-8481 report `coverage` vectors.

Python 3.9+, standard library only. keccak256 and RFC 8785 JCS come from ../on-list/onlist_vectors.py.

    python3 coverage_vectors.py           # check coverage.json against this implementation
    python3 coverage_vectors.py --write   # regenerate it (deterministic)

What is checked: `coverage` is present and well formed (status and gaps agree, enum values, path syntax and range,
no two gaps with one path, `nested` agreeing with `reason`), the subject digest, `reportHash` (the report without
`signature` and `detail`, so `coverage` is inside it) and the EIP-712 digest the source signs. `signature` is a
placeholder: no key signs these vectors.
"""
import importlib.util
import json
import os
import re
import sys

sys.dont_write_bytecode = True  # importing ../on-list must not leave __pycache__ in the assets
HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("onlist_vectors", os.path.join(HERE, "..", "on-list", "onlist_vectors.py"))
_ol = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ol)
keccak256, hx, jcs, digest, eip55 = _ol.keccak256, _ol.hx, _ol.jcs, _ol.digest, _ol.eip55

CHAIN = "eip155:4663"
CHAIN_ID = 4663
MAX = 2 ** 256 - 1
ZERO32 = "0x" + "00" * 32
STATUSES = ("complete", "partial")
REASONS = ("unsupported-selector", "unverified-wrapper", "depth-limit", "undecodable-data", "not-inspected")
NESTED = ("inspected", "not-inspected")
# reason -> the only `nested` value it allows (None: either)
NESTED_BY_REASON = {"unverified-wrapper": "inspected", "depth-limit": "not-inspected", "not-inspected": "not-inspected",
                    "unsupported-selector": None, "undecodable-data": None}
PATH_RE = re.compile(r"^(?:typedData|tx(?:\.calls\[(0|[1-9][0-9]*)\](?:\.inner\[(?:0|[1-9][0-9]*)\])*(?:\.inner)?)?)$")


def _seed(tag, n=32):
    return keccak256(f"erc-8481 coverage vector {tag}".encode())[:n]


def synth_evm(tag):
    return eip55(hx(_seed(f"evm {tag}")[12:32]))


def caip10(a):
    return f"{CHAIN}:{a}"


# ---------------------------------------------------------------- ABI encoding (only what the vectors need)
def selector(sig):
    return keccak256(sig.encode())[:4]


def w_uint(n):
    return n.to_bytes(32, "big")


def w_addr(a):
    return bytes.fromhex(a[2:].rjust(64, "0"))


def w_bytes(b):
    return w_uint(len(b)) + b + b"\x00" * ((-len(b)) % 32)


def approve_data(spender, amount):
    return selector("approve(address,uint256)") + w_addr(spender) + w_uint(amount)


def erc7821_batch(calls):
    """execute(bytes32 mode, bytes executionData), batch mode 0x01, executionData = abi.encode(Call[])."""
    tuples = [w_addr(t) + w_uint(v) + w_uint(0x60) + w_bytes(d) for t, v, d in calls]
    offs, pos = [], 32 * len(tuples)
    for t in tuples:
        offs.append(w_uint(pos))
        pos += len(t)
    execution_data = w_uint(0x20) + w_uint(len(tuples)) + b"".join(offs) + b"".join(tuples)
    mode = b"\x01" + b"\x00" * 31
    return selector("execute(bytes32,bytes)") + mode + w_uint(0x40) + w_bytes(execution_data)


# ---------------------------------------------------------------- report rules
def subject_digest(request):
    s = request["subject"]
    return digest({k: s[k] for k in ("chainId", "from", "calls", "typedData", "authorizationList") if k in s})


def report_hash(report):
    return digest({k: v for k, v in report.items() if k not in ("signature", "detail")})


def eip712_digest(report):
    t_domain = keccak256(b"EIP712Domain(string name,string version,uint256 chainId)")
    domain = keccak256(t_domain + keccak256(b"Agent Pre-Sign Risk Report") + keccak256(b"1") + w_uint(CHAIN_ID))
    t_report = keccak256(b"PresignReport(bytes32 subjectDigest,bytes32 contextDigest,bytes32 reportHash)")
    struct = keccak256(t_report + bytes.fromhex(report["subjectDigest"][2:]) + bytes.fromhex(report["contextDigest"][2:])
                       + bytes.fromhex(report_hash(report)[2:]))
    return hx(keccak256(b"\x19\x01" + domain + struct))


def path_error(path, request):
    """None, or the error code for a path that does not parse or names a part the request does not have."""
    s = request["subject"]
    m = PATH_RE.match(path) if isinstance(path, str) else None
    if not m:
        return "path-syntax"
    if path == "typedData" and "typedData" not in s:
        return "path-out-of-range"
    if m.group(1) is not None and int(m.group(1)) >= len(s.get("calls", [])):
        return "path-out-of-range"
    return None


def approval_errors(report, request):
    """Error codes for the optional `path` (and its agreement with `callIndex`) of each approval entity."""
    errs = []
    for a in report["entities"]["approvals"]:
        if "path" in a:
            e = path_error(a["path"], request)
            if e:
                errs.append("approval-" + e)
            elif "callIndex" in a and a["path"] != f"tx.calls[{a['callIndex']}]":
                errs.append("approval-path-disagrees-with-callIndex")
    return errs


def report_errors(report, request):
    return coverage_errors(report, request) + approval_errors(report, request)


def coverage_errors(report, request):
    """Error codes for the report's `coverage`; [] means it conforms."""
    if "coverage" not in report:
        return ["coverage-absent"]
    c = report["coverage"]
    if not isinstance(c, dict) or set(c) != {"status", "gaps"} or not isinstance(c.get("gaps"), list):
        return ["coverage-malformed"]
    errs = []
    if c["status"] not in STATUSES:
        errs.append("status-unknown")
    elif (c["status"] == "partial") != (len(c["gaps"]) > 0):
        errs.append("status-gaps-disagree")
    s = request["subject"]
    seen = set()
    for g in c["gaps"]:
        if not isinstance(g, dict) or set(g) != {"path", "reason", "nested"}:
            errs.append("gap-malformed")
            continue
        e = path_error(g["path"], request)
        if e:
            errs.append(e)
        if isinstance(g["path"], str):
            if g["path"] in seen:
                errs.append("path-duplicate")
            seen.add(g["path"])
        if g["reason"] not in REASONS:
            errs.append("reason-unknown")
        if g["nested"] not in NESTED:
            errs.append("nested-unknown")
        elif g["reason"] in REASONS and NESTED_BY_REASON.get(g["reason"]) not in (None, g["nested"]):
            errs.append("nested-disagrees-with-reason")
    return errs


def all_listed_findings_read(report):
    return all(f["status"] == "read" for f in report["findings"])


# ---------------------------------------------------------------- fixtures
SIGNER = synth_evm("signer")
ACCOUNT = synth_evm("smart account")
TOKEN = synth_evm("token")
SPENDER = synth_evm("spender")
REGISTRY = synth_evm("identity registry")
SOURCE_KEY = synth_evm("source key")
BLOCK = {"chainId": CHAIN, "block": "100007973", "hash": hx(_seed("block 100007973"))}
AT = {"chainId": CHAIN, "block": BLOCK["block"]}
KINDS = ["erc.presign.address.code", "erc.presign.address.first-seen-block", "erc.presign.approval.amount",
         "erc.presign.approval.unlimited"]
FIRST_SEEN = {ACCOUNT: "99000001", TOKEN: "98000002", SPENDER: "100007933"}


def request(calls):
    return {"version": "erc-presign/1",
            "subject": {"type": "calls", "chainId": CHAIN, "from": caip10(SIGNER),
                        "calls": [{"to": caip10(t), "value": str(v), "data": hx(d)} for t, v, d in calls]},
            "kinds": KINDS}


def address_findings(addr, role):
    ent = {"address": caip10(addr), "role": role}
    call = {"type": "call", "chainId": CHAIN, "block": BLOCK["block"], "to": caip10(addr), "data": "0x",
            "result": "0x6080"}
    return [
        {"kind": "erc.presign.address.code", "entity": ent, "status": "read", "value": "contract", "at": AT,
         "evidence": [call]},
        {"kind": "erc.presign.address.first-seen-block", "entity": ent, "status": "read", "value": FIRST_SEEN[addr],
         "at": AT, "evidence": []},
    ]


def report(req, entities, findings, coverage):
    r = {"version": "erc-presign/1", "subjectDigest": subject_digest(req), "contextDigest": ZERO32,
         "chainId": CHAIN, "signer": caip10(SIGNER),
         "source": {"registry": caip10(REGISTRY), "agentId": "20030", "signer": caip10(SOURCE_KEY)},
         "issuedAt": "2026-11-05T12:00:00Z", "blocks": [BLOCK], "entities": entities}
    if coverage is not None:
        r["coverage"] = coverage
    r.update({"findings": findings, "method": "coverage-vectors/1", "signature": "0x"})
    return r


def wrapped_case():
    """approve(spender, max) inside an ERC-7821 batch execute(bytes32,bytes) the source does not decode."""
    inner = [(TOKEN, 0, approve_data(SPENDER, MAX))]
    req = request([(ACCOUNT, 0, erc7821_batch(inner))])
    entities = {"tokens": [], "approvals": [], "addresses": [{"address": caip10(ACCOUNT), "role": "target"}],
                "payment": False, "texts": []}
    cov = {"status": "partial",
           "gaps": [{"path": "tx.calls[0]", "reason": "unsupported-selector", "nested": "not-inspected"}]}
    return req, report(req, entities, address_findings(ACCOUNT, "target"), cov), inner


def direct_case():
    req = request([(TOKEN, 0, approve_data(SPENDER, MAX))])
    entities = {"tokens": [caip10(TOKEN)],
                "approvals": [{"token": caip10(TOKEN), "spender": caip10(SPENDER), "form": "erc20-approve",
                               "callIndex": 0}],
                "addresses": [{"address": caip10(TOKEN), "role": "target"},
                              {"address": caip10(SPENDER), "role": "spender"},
                              {"address": caip10(TOKEN), "role": "token"}],
                "payment": False, "texts": []}
    findings = [
        {"kind": "erc.presign.approval.amount", "entity": {"approval": 0}, "status": "read", "value": str(MAX),
         "evidence": []},
        {"kind": "erc.presign.approval.unlimited", "entity": {"approval": 0}, "status": "read", "value": True,
         "evidence": []},
    ] + address_findings(TOKEN, "target") + address_findings(SPENDER, "spender") + address_findings(TOKEN, "token")
    return req, report(req, entities, findings, {"status": "complete", "gaps": []})


def decoded_case():
    """The same batch sent to a source that decodes ERC-7821 and knows the account implements it."""
    inner = [(TOKEN, 0, approve_data(SPENDER, MAX))]
    req = request([(ACCOUNT, 0, erc7821_batch(inner))])
    entities = {"tokens": [caip10(TOKEN)],
                "approvals": [{"token": caip10(TOKEN), "spender": caip10(SPENDER), "form": "erc20-approve",
                               "path": "tx.calls[0].inner[0]"}],
                "addresses": [{"address": caip10(ACCOUNT), "role": "target"},
                              {"address": caip10(SPENDER), "role": "spender"},
                              {"address": caip10(TOKEN), "role": "token"}],
                "payment": False, "texts": []}
    findings = [
        {"kind": "erc.presign.approval.amount", "entity": {"approval": 0}, "status": "read", "value": str(MAX),
         "evidence": []},
        {"kind": "erc.presign.approval.unlimited", "entity": {"approval": 0}, "status": "read", "value": True,
         "evidence": []},
    ] + address_findings(ACCOUNT, "target") + address_findings(SPENDER, "spender") + address_findings(TOKEN, "token")
    return req, report(req, entities, findings, {"status": "complete", "gaps": []})


def expected(req, rep):
    errs = report_errors(rep, req)
    out = {"conforms": not errs, "errors": errs, "subjectDigest": subject_digest(req)}
    if not errs:
        out.update({"coverageStatus": rep["coverage"]["status"], "gaps": rep["coverage"]["gaps"],
                    "allListedFindingsRead": all_listed_findings_read(rep),
                    "readsAsNoFindings": False if rep["coverage"]["status"] == "partial" else None,
                    "reportHash": report_hash(rep), "eip712Digest": eip712_digest(rep)})
        if out["readsAsNoFindings"] is None:
            del out["readsAsNoFindings"]
    return out


def mutate(rep, coverage=..., drop=False):
    r = json.loads(json.dumps(rep))
    if drop:
        del r["coverage"]
    elif coverage is not ...:
        r["coverage"] = coverage
    return r


def build():
    wreq, wrep, inner = wrapped_case()
    dreq, drep = direct_case()
    breq, brep = decoded_case()
    vectors = [
        {"id": "wrapped-approve-unsupported-batch", "basis": "spec",
         "note": "The reviewer's case: approve(spender, 2^256 - 1) to the token inside an ERC-7821 batch "
                 "execute(bytes32,bytes) that this source does not decode. The source lists only the outer target, "
                 "every finding for it is read, and coverage names the gap; the report must not read as no findings.",
         "hidden": {"path": "tx.calls[0].inner[0]", "to": caip10(inner[0][0]), "data": hx(inner[0][2]),
                    "decoded": {"function": "approve(address,uint256)", "spender": caip10(SPENDER), "amount": str(MAX)}},
         "request": wreq, "report": wrep, "expected": expected(wreq, wrep)},
        {"id": "direct-approve-complete", "basis": "spec",
         "note": "The same approval as a direct call: every call decoded, coverage complete, one approval entity. "
                 "Complete says the request was decoded, not that the approval is safe.",
         "request": dreq, "report": drep, "expected": expected(dreq, drep)},
    ]
    vectors.append(
        {"id": "wrapped-approve-decoded-batch", "basis": "spec",
         "note": "The same batch sent to a source that decodes ERC-7821 and knows the account implements it: coverage "
                 "complete, and the approval entity is located by path tx.calls[0].inner[0], with no callIndex.",
         "request": breq, "report": brep, "expected": expected(breq, brep)})
    lie = mutate(wrep, {"status": "complete", "gaps": []})
    signed = {"id": "coverage-is-signed", "basis": "spec",
              "note": "The wrapped report with its coverage rewritten to complete conforms on its own but has another "
                      "reportHash, so the source's signature over the partial report does not verify for it.",
              "request": wreq, "report": lie, "expected": expected(wreq, lie)}
    signed["expected"]["differsFrom"] = {"id": "wrapped-approve-unsupported-batch",
                                         "reportHash": report_hash(wrep)}
    assert signed["expected"]["reportHash"] != report_hash(wrep)
    vectors.append(signed)
    g = {"path": "tx.calls[0]", "reason": "unsupported-selector", "nested": "not-inspected"}
    bad = [
        ("coverage-absent", "a report without coverage does not conform", None, True),
        ("coverage-null", "coverage must be an object", None, False),
        ("complete-with-gaps", "status complete with a gap", {"status": "complete", "gaps": [g]}, False),
        ("partial-without-gaps", "status partial with no gap", {"status": "partial", "gaps": []}, False),
        ("status-unknown", "status outside the enum", {"status": "full", "gaps": []}, False),
        ("reason-unknown", "reason outside the enum", {"status": "partial", "gaps": [dict(g, reason="unknown-selector")]}, False),
        ("reason-array", "reason must be an enum string, not an array",
         {"status": "partial", "gaps": [dict(g, reason=[])]}, False),
        ("reason-object", "reason must be an enum string, not an object",
         {"status": "partial", "gaps": [dict(g, reason={})]}, False),
        ("nested-unknown", "nested outside the enum", {"status": "partial", "gaps": [dict(g, nested="partly")]}, False),
        ("path-no-root", "a path starts at tx or typedData", {"status": "partial", "gaps": [dict(g, path="calls[0]")]}, False),
        ("path-array", "path must be a string, not an array",
         {"status": "partial", "gaps": [dict(g, path=[])]}, False),
        ("path-object", "path must be a string, not an object",
         {"status": "partial", "gaps": [dict(g, path={})]}, False),
        ("path-leading-zero", "indexes have no leading zero", {"status": "partial", "gaps": [dict(g, path="tx.calls[00]")]}, False),
        ("path-out-of-range", "the request has one call", {"status": "partial", "gaps": [dict(g, path="tx.calls[1]")]}, False),
        ("path-typeddata-absent", "the request has no typed data", {"status": "partial", "gaps": [dict(g, path="typedData")]}, False),
        ("path-duplicate", "two gaps with one path", {"status": "partial", "gaps": [g, dict(g, reason="undecodable-data")]}, False),
        ("depth-limit-inspected", "depth-limit means the nested calls were not inspected",
         {"status": "partial", "gaps": [{"path": "tx.calls[0].inner[0]", "reason": "depth-limit", "nested": "inspected"}]}, False),
        ("not-inspected-inspected", "a part not inspected has no inspected nested calls",
         {"status": "partial", "gaps": [dict(g, reason="not-inspected", nested="inspected")]}, False),
        ("wrapper-not-inspected", "unverified-wrapper means the nested calls were decoded",
         {"status": "partial", "gaps": [dict(g, reason="unverified-wrapper")]}, False),
        ("gap-extra-member", "a gap has exactly path, reason and nested",
         {"status": "partial", "gaps": [dict(g, severity="high")]}, False),
    ]
    good = [
        ("inner-path-depth-limit", "a gap below the top-level call",
         {"status": "partial", "gaps": [{"path": "tx.calls[0].inner[0].inner", "reason": "depth-limit", "nested": "not-inspected"}]}),
        ("unverified-wrapper-inspected", "nested calls decoded, wrapper semantics not established",
         {"status": "partial", "gaps": [dict(g, reason="unverified-wrapper", nested="inspected")]}),
        ("whole-transaction", "the source could not take the transaction apart at all",
         {"status": "partial", "gaps": [{"path": "tx", "reason": "undecodable-data", "nested": "not-inspected"}]}),
    ]
    conformance = []
    for cid, note, cov, drop in bad:
        r = mutate(wrep, drop=True) if drop else mutate(wrep, cov)
        e = coverage_errors(r, wreq)
        assert e, cid
        conformance.append({"id": cid, "basis": "spec", "note": note, "coverage": r.get("coverage", "<absent>"),
                            "expected": {"conforms": False, "errors": e}})
    for cid, note, cov in good:
        r = mutate(wrep, cov)
        assert not coverage_errors(r, wreq), cid
        conformance.append({"id": cid, "basis": "spec", "note": note, "coverage": cov,
                            "expected": {"conforms": True, "errors": []}})
    approval_cases = [
        ("approval-path-syntax", "an approval path uses the gap path syntax", {"path": "calls[0].inner[0]"}, False),
        ("approval-path-out-of-range", "the request has one call", {"path": "tx.calls[1].inner[0]"}, False),
        ("approval-path-disagrees-with-callIndex", "a top-level approval's path is tx.calls[callIndex]",
         {"callIndex": 0, "path": "tx.calls[0].inner[0]"}, False),
        ("approval-top-level-both", "a top-level approval may carry callIndex and path together",
         {"callIndex": 0, "path": "tx.calls[0]"}, True),
    ]
    for cid, note, fields, ok in approval_cases:
        r = json.loads(json.dumps(brep))
        a = {k: v for k, v in r["entities"]["approvals"][0].items() if k not in ("path", "callIndex")}
        a.update(fields)
        r["entities"]["approvals"][0] = a
        e = report_errors(r, breq)
        assert (not e) == ok, cid
        conformance.append({"id": cid, "basis": "spec", "note": note, "approval": a,
                            "expected": {"conforms": ok, "errors": e}})
    return {"description": "report coverage and approval paths: status, gaps, path syntax, signing; coverage "
                           "conformance cases are checked against the request of wrapped-approve-unsupported-batch, "
                           "approval cases against the report of wrapped-approve-decoded-batch",
            "pathGrammar": "path = \"typedData\" / \"tx\" [ \".calls[\" index \"]\" *( \".inner[\" index \"]\" ) "
                           "[ \".inner\" ] ]; index = \"0\" / %x31-39 *DIGIT",
            "vectors": vectors, "conformance": conformance, "open": []}


def selftest():
    _ol.primitive_selftest()
    assert selector("approve(address,uint256)").hex() == "095ea7b3"
    assert selector("execute(bytes32,bytes)").hex() == "e9ae5c53"  # ERC-7821
    assert selector("transfer(address,uint256)").hex() == "a9059cbb"


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def main():
    write = "--write" in sys.argv[1:]
    selftest()
    data = build()
    text = dump(data)
    p = os.path.join(HERE, "coverage.json")
    ok = True
    if write:
        open(p, "w", encoding="utf-8").write(text)
    else:
        cur = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
        if cur != text:
            ok = False
            print("FAIL coverage.json: differs from what this implementation computes")
        else:  # also re-validate what is on disk, not only what was rebuilt
            d = json.loads(cur)
            for v in d["vectors"]:
                if report_errors(v["report"], v["request"]) != v["expected"]["errors"]:
                    ok = False
                    print(f"FAIL {v['id']}")
    print(f"{'wrote' if write else 'ok  '} coverage.json: {len(data['vectors']) + len(data['conformance'])}"
          f" checked, {len(data['open'])} open")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
