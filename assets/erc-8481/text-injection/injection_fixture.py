# SPDX-License-Identifier: CC0-1.0
"""Small offline ERC-8481 text.injection fixture, not a general injection detector.

The pattern document format and consumer gate are local choices; see README.md.
Hashing reuses the existing on-list implementation. Python 3.9+, no dependencies.
"""
import importlib.util
import json
from pathlib import Path
import sys
import unicodedata

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "onlist_vectors", HERE.parent / "on-list" / "onlist_vectors.py")
_ol = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ol)
keccak256, hx = _ol.keccak256, _ol.hx

KIND = "erc.presign.text.injection"
CLASSES = ("override", "value-transfer", "tool-call", "safety-claim",
           "secret-request", "concealment")
STEPS = ("NFKC-3.2.0", "remove-U+200B", "ascii-lower")
ASCII_LOWER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")


def byte_hash(raw):
    return hx(keccak256(raw))


def load_pattern_set(raw, param):
    """Verify exact published bytes before using this fixture's document format."""
    if byte_hash(raw) != param["hash"]:
        raise ValueError("pattern-set hash mismatch")
    doc = json.loads(raw)
    if doc.get("fixtureVersion") != 1 or doc.get("matching") != "literal-substring":
        raise ValueError("unsupported fixture format")
    steps = doc.get("normalization")
    if not isinstance(steps, list) or any(s not in STEPS for s in steps):
        raise ValueError("unsupported normalization")
    patterns = doc.get("patterns")
    if not isinstance(patterns, list):
        raise ValueError("patterns must be an array")
    seen = set()
    for p in patterns:
        if (not isinstance(p, dict) or set(p) != {"id", "class", "literal"}
                or not isinstance(p["id"], str) or not p["id"] or p["id"] in seen
                or p["class"] not in CLASSES
                or not isinstance(p["literal"], str) or not p["literal"]):
            raise ValueError("unsupported fixture pattern")
        seen.add(p["id"])
    return doc


def normalize(text, steps):
    for step in steps:
        if step == "NFKC-3.2.0":
            # Python bundles this frozen database, independently of its current UCD.
            text = unicodedata.ucd_3_2_0.normalize("NFKC", text)
        elif step == "remove-U+200B":
            text = text.replace("\u200b", "")
        elif step == "ascii-lower":
            text = text.translate(ASCII_LOWER)
        else:
            raise ValueError("unsupported normalization")
    return text


def inspect_text(text, field, param, raw=None, *, index=0, at=None):
    """Return one text entity and finding; raw=None means the set is unsupported.

    `at` is explicit provenance from the fixture caller, never inferred from field.
    A production source would extract entities and obtain chain evidence separately.
    """
    entity = {"index": index, "field": field, "digest": byte_hash(text.encode("utf-8"))}
    finding = {"kind": KIND, "entity": {"text": index}, "param": dict(param), "evidence": []}
    if raw is None:
        finding.update(status="not-read", reason="unsupported")
        return entity, finding
    doc = load_pattern_set(raw, param)
    normalized = normalize(text, doc["normalization"])
    matched = {p["class"] for p in doc["patterns"] if p["literal"] in normalized}
    finding.update(status="read", value=[c for c in CLASSES if c in matched])
    if at is not None:
        finding["at"] = dict(at)
    return entity, finding


def consumer_stage(report, text_index, param):
    """Illustrative strict policy AFTER report/source/binding validation.

    This is not a report validator. This consumer holds partial coverage or any
    match; even a complete, empty result only continues the remaining checks.
    """
    coverage = report.get("coverage", {})
    if coverage != {"status": "complete", "gaps": []}:
        return "hold"
    findings = [f for f in report.get("findings", [])
                if f.get("kind") == KIND and f.get("entity") == {"text": text_index}
                and f.get("param") == param]
    if len(findings) != 1:
        return "hold"
    finding = findings[0]
    if finding.get("status") != "read" or "reason" in finding:
        return "hold"
    if finding.get("value") != []:
        return "hold"
    return "continue-other-checks"
