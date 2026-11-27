#!/usr/bin/env python3
"""
verify.py - fulfiller-side (agent) verifier per TASK-KERNEL v1.0.

Simulates the on-chain read with --tdhash/--taskhash/--version (what
taskOf() returns) plus --previous-taskhash (from the TaskUpdated event
history) for version > 1, then runs the full verification procedure.
Optionally cross-checks the fulfillment descriptor against the on-chain
maxCompletions (--max-completions, from tenderTermsOf()).

Usage:
  python3 verify.py <out-dir> --tdhash 0x.. --taskhash 0x.. [--version N]
                    [--previous-taskhash 0x..] [--max-completions N] [--key <hex>]
"""
import argparse, json, os, sys
import tom
from pack import xor_stream

def fail(msg):
    print(f"FAIL: {msg}"); sys.exit(1)

def step(msg):
    print(f"  [OK] {msg}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--tdhash", required=True)
    ap.add_argument("--taskhash", required=True)
    ap.add_argument("--version", type=int, default=1)
    ap.add_argument("--previous-taskhash")
    ap.add_argument("--max-completions", type=int, default=None,
                    help="on-chain TenderTerms.maxCompletions for descriptor cross-check")
    ap.add_argument("--key", help="test profile decryption key (hex)")
    a = ap.parse_args()
    td_hash = bytes.fromhex(a.tdhash.replace("0x", ""))
    t_hash = bytes.fromhex(a.taskhash.replace("0x", ""))
    if a.version > 1 and not a.previous_taskhash:
        fail("--previous-taskhash required for version > 1 (from TaskUpdated history)")
    objdir = os.path.join(a.out_dir, "objects")

    def fetch(digest: bytes) -> bytes:
        data = open(os.path.join(objdir, digest.hex()), "rb").read()
        if tom.sha256(data) != digest:
            fail(f"retrieved object does not match digest {digest.hex()[:12]}..")
        return data

    print("verification (TASK-KERNEL v1.0):")
    root_bytes = open(os.path.join(a.out_dir, "taskroot.cbor"), "rb").read()
    step(f"anchors read (simulated taskOf: version={a.version})")
    if tom.sha256(root_bytes) != t_hash: fail("taskHash mismatch")
    step(f"SHA-256(TaskRoot) == taskHash  {t_hash.hex()[:16]}..")
    root = tom.decode(root_bytes)
    if tom.encode(root) != root_bytes: fail("re-encode mismatch (non-canonical encoding)")
    step("canonical re-encode byte-equality")
    tom.check_task_root(root, version=a.version)
    step("closed-map schema + path rules + spec/acceptance interlocks")
    # version chain: prev must chain to the actual previous taskHash
    if a.version == 1:
        if "prev" in root: fail("prev present at version 1")
        step("version chain: v1, no prev")
    else:
        prev_digest = tom.cid_digest(root["prev"].cid)
        want = bytes.fromhex(a.previous_taskhash.replace("0x", ""))
        if prev_digest != want:
            fail(f"prev chain broken: digest(prev)={prev_digest.hex()[:12]}.. != previous taskHash {want.hex()[:12]}..")
        step(f"version chain: digest(prev) == previous taskHash  {want.hex()[:12]}..")
    # confidentiality branch: descriptor itself verified by fetch();
    # every objects[path] must cross-match the TaskRoot link
    conf, enc_objects = None, {}
    if "confidentiality" in root:
        conf = json.loads(fetch(tom.cid_digest(root["confidentiality"].cid)))
        for req in ("schemaVersion", "mode", "profile", "objects"):
            if req not in conf: fail(f"confidentiality descriptor missing {req}")
        if conf["profile"] != "x-test-sha256-xor-stream-v1":
            fail(f"unknown confidentiality profile {conf['profile']}: MUST NOT guess")
        enc_objects = conf["objects"]
        files = root.get("files") or {}
        for pth, obj in enc_objects.items():
            tom.validate_path(pth)
            if pth == root["td"]["path"]:
                link = root["td"]["cid"]
            elif "terms" in root and pth == root["terms"]["path"]:
                link = root["terms"]["cid"]
            elif "acceptance" in root and pth == root["acceptance"]["path"]:
                link = root["acceptance"]["cid"]
            elif pth in files:
                link = files[pth]
            else:
                fail(f"descriptor object {pth} has no corresponding TaskRoot link")
            if tom.cid_parse(obj["ciphertext"]) != link.cid:
                fail(f"objects[{pth}].ciphertext != TaskRoot link CID")
            ph = obj["plaintextHash"]
            if not (ph.startswith("0x") and len(ph) == 66):
                fail(f"objects[{pth}].plaintextHash not a 32-byte hex digest")
        step(f"confidentiality descriptor verified (profile={conf['profile']}, "
             f"{len(enc_objects)} objects cross-matched to TaskRoot links)")
    # td interlock
    td_path = root["td"]["path"]
    if td_path in enc_objects:
        if bytes.fromhex(enc_objects[td_path]["plaintextHash"][2:]) != td_hash:
            fail(f"descriptor plaintextHash({td_path}) != tdHash")
        step("encrypted primary doc: plaintextHash == tdHash")
    else:
        if tom.cid_digest(root["td"]["cid"].cid) != td_hash: fail("digest(td.cid) != tdHash")
        step("digest(td.cid) == tdHash")
    # fetch + verify every leaf; decrypt where declared
    key = bytes.fromhex(a.key) if a.key else None
    leaves = {td_path: root["td"]["cid"], "manifest.json": root["manifest"]}
    if "fulfillment" in root: leaves["fulfillment.json"] = root["fulfillment"]
    if "terms" in root: leaves[root["terms"]["path"]] = root["terms"]["cid"]
    if "acceptance" in root: leaves[root["acceptance"]["path"]] = root["acceptance"]["cid"]
    for pth, link in (root.get("files") or {}).items(): leaves[pth] = link
    plain = {}
    for pth, link in leaves.items():
        data = fetch(tom.cid_digest(link.cid))
        if pth in enc_objects:
            if not key: fail(f"{pth} encrypted; no key (rights not proven?)")
            pt = xor_stream(key, data)
            if tom.sha256(pt) != bytes.fromhex(enc_objects[pth]["plaintextHash"][2:]):
                fail(f"plaintextHash mismatch after decrypt: {pth}")
            plain[pth] = pt
        else:
            plain[pth] = data
    step(f"all {len(leaves)} leaves fetched+verified"
         + (f", {len(enc_objects)} decrypted+plaintext-verified" if enc_objects else ""))
    if tom.sha256(plain[td_path]) != td_hash: fail("plaintext primary doc != tdHash")
    try:
        plain[td_path].decode("utf-8")
    except UnicodeDecodeError:
        fail("primary document is not valid UTF-8")
    manifest = json.loads(plain["manifest.json"])
    spec = root["spec"]
    if manifest["specPath"] != spec["path"]: fail("manifest.specPath != spec.path")
    # descriptor/chain agreement on maxCompletions (tender-side inspection)
    if "fulfillment" in root:
        desc = json.loads(plain["fulfillment.json"])
        for req in ("schemaVersion", "mode", "maxCompletions"):
            if req not in desc: fail(f"fulfillment descriptor missing {req}")
        if a.max_completions is not None and desc["maxCompletions"] != a.max_completions:
            fail(f"fulfillment.maxCompletions ({desc['maxCompletions']}) != on-chain maxCompletions ({a.max_completions})")
        step(f"fulfillment descriptor: mode={desc['mode']}, maxCompletions={desc['maxCompletions']}"
             + (" (matches chain)" if a.max_completions is not None else ""))
    print(f"  spec: {spec['path']}  profile: {spec['profile']}")
    if "acceptance" in root:
        print(f"  acceptance: {root['acceptance']['path']}  profile: {root['acceptance']['profile']}")
    print("PASS - task package verified; safe to price, fulfill, and cite this version.")

if __name__ == "__main__":
    main()
