"""Mutation test: prove every invariant is exercised by the on-chain vectors.

For each invariant, run all vectors against a model with that invariant
switched off. At least one vector must fail; otherwise the invariant is
untested. Also replays the ORIGINAL (pre-fix) spec text for E8/E10 to show
the vectors catch the expiry-boundary overwrite that reviewers reported.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
sys.path.insert(0, str(ROOT / "tools"))
from gen_onchain_vectors import run_case  # noqa: E402

cases = []
for f in sorted((ROOT / "vectors" / "onchain").glob("*.json")):
    if f.name.startswith("_"):
        continue
    cases += json.loads(f.read_text())

mutations = {f"disable {t}": {t} for t in
             ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10",
              "E11", "E12", "E13", "E14", "DUP"]}
mutations["original spec text (E8 '< expiry', no E10)"] = {"ORIGINAL_E8", "E10"}

all_caught = True
for label, disabled in mutations.items():
    failing = [c["name"] for c in cases if not run_case(c, frozenset(disabled), strict_tags=False)[0]]
    status = "caught" if failing else "NOT CAUGHT"
    all_caught &= bool(failing)
    print(f"{label:48} {status:10} by {len(failing)} case(s): {', '.join(failing[:3])}")
sys.exit(0 if all_caught else 1)
