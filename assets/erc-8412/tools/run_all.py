"""Run every check in assets/erc-8412 with no dependencies beyond Python 3.10+.

    python tools/run_all.py

1. Known-answer tests for keccak256, secp256k1 recovery, EIP-712 and JCS.
2. On-chain vectors (vectors/onchain) against the registry model.
3. Mutation test: every invariant is exercised by at least one vector.
4. Off-chain vectors (vectors/offchain) against the reference verifier.
5. contracts/test/Vectors.t.sol is in sync with the vectors.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "verifier"))

failed = []


def step(title, fn):
    try:
        msg = fn()
        print(f"PASS  {title}" + (f" — {msg}" if msg else ""))
    except Exception as e:  # noqa: BLE001
        failed.append(title)
        print(f"FAIL  {title} — {e}")


def crypto():
    import test_ethcrypto
    test_ethcrypto.test()
    return "published keccak256 / EIP-712 / address vectors"


def onchain():
    from gen_onchain_vectors import run_case
    n = 0
    for f in sorted((ROOT / "vectors" / "onchain").glob("*.json")):
        if f.name.startswith("_"):
            continue
        for c in json.loads(f.read_text()):
            ok, msg = run_case(c)
            if not ok:
                raise AssertionError(f"{c['invariant']}/{c['name']}: {msg}")
            n += 1
    return f"{n} cases"


def mutation():
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "mutation_test.py")],
                       capture_output=True, text=True)
    if r.returncode:
        raise AssertionError("\n" + r.stdout)
    return f"{len(r.stdout.strip().splitlines())} mutations, all caught"


def offchain():
    from verify import verify
    n = 0
    for f in sorted((ROOT / "vectors" / "offchain").glob("*.json")):
        v = json.loads(f.read_text())
        res = verify(v["chain"], v["criteria"], v["bundle"], v["attestation"])
        got = sorted({x["rule"] for x in res["violations"]})
        if res["valid"] != v["expect"]["valid"] or got != v["expect"]["violations"]:
            raise AssertionError(f"{v['name']}: got {got}, expected {v['expect']['violations']}")
        n += 1
    return f"{n} document packages"


def foundry_sync():
    target = ROOT / "contracts" / "test" / "Vectors.t.sol"
    before = target.read_text()
    subprocess.run([sys.executable, str(ROOT / "tools" / "gen_foundry_tests.py")],
                   capture_output=True, check=True)
    if target.read_text() != before:
        raise AssertionError("Vectors.t.sol was stale and has been regenerated; commit it")
    return "generated Foundry suite matches vectors"


step("crypto primitives", crypto)
step("on-chain vectors vs model", onchain)
step("mutation coverage", mutation)
step("off-chain vectors vs verifier", offchain)
step("Foundry suite in sync", foundry_sync)
print("\nALL CHECKS PASSED" if not failed else f"\n{len(failed)} CHECK(S) FAILED: {failed}")
sys.exit(1 if failed else 0)
