#!/usr/bin/env python3
"""
verify.py - consumer-side (agent) verifier per KERNEL v4.3.

Simulates the on-chain read with --mdhash/--packagehash/--version (what
skillOf() returns) plus --previous-packagehash (from the SkillUpdated event
history) for version > 1, then runs the full verification procedure.

Usage:
  python3 verify.py <out-dir> --mdhash 0x.. --packagehash 0x.. [--version N]
                    [--previous-packagehash 0x..] [--key <hex>]
"""
import argparse, json, os, sys
import som
from pack import xor_stream

def fail(msg):
    print(f"FAIL: {msg}"); sys.exit(1)

def step(msg):
    print(f"  [OK] {msg}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--mdhash", required=True)
    ap.add_argument("--packagehash", required=True)
    ap.add_argument("--version", type=int, default=1)
    ap.add_argument("--previous-packagehash")
    ap.add_argument("--key", help="test profile decryption key (hex)")
    a = ap.parse_args()
    md_hash = bytes.fromhex(a.mdhash.replace("0x", ""))
    pkg_hash = bytes.fromhex(a.packagehash.replace("0x", ""))
    if a.version > 1 and not a.previous_packagehash:
        fail("--previous-packagehash required for version > 1 (from SkillUpdated history)")
    objdir = os.path.join(a.out_dir, "objects")

    def fetch(digest: bytes) -> bytes:
        data = open(os.path.join(objdir, digest.hex()), "rb").read()
        if som.sha256(data) != digest:
            fail(f"retrieved object does not match digest {digest.hex()[:12]}..")
        return data

    print("verification (KERNEL v4.3):")
    root_bytes = open(os.path.join(a.out_dir, "skillroot.cbor"), "rb").read()
    step(f"anchors read (simulated skillOf: version={a.version})")
    if som.sha256(root_bytes) != pkg_hash: fail("packageHash mismatch")
    step(f"SHA-256(SkillRoot) == packageHash  {pkg_hash.hex()[:16]}..")
    root = som.decode(root_bytes)
    if som.encode(root) != root_bytes: fail("re-encode mismatch (non-canonical encoding)")
    step("canonical re-encode byte-equality")
    som.check_skill_root(root, version=a.version)
    step("closed-map schema + path rules + entry interlock")
    # version chain (P0-3): prev must chain to the actual previous packageHash
    if a.version == 1:
        if "prev" in root: fail("prev present at version 1")
        step("version chain: v1, no prev")
    else:
        prev_digest = som.cid_digest(root["prev"].cid)
        want = bytes.fromhex(a.previous_packagehash.replace("0x", ""))
        if prev_digest != want:
            fail(f"prev chain broken: digest(prev)={prev_digest.hex()[:12]}.. != previous packageHash {want.hex()[:12]}..")
        step(f"version chain: digest(prev) == previous packageHash  {want.hex()[:12]}..")
    # confidentiality branch (P0-2): descriptor itself verified by fetch();
    # every objects[path] must cross-match the SkillRoot link
    conf, enc_objects = None, {}
    if "confidentiality" in root:
        conf = json.loads(fetch(som.cid_digest(root["confidentiality"].cid)))
        for req in ("schemaVersion", "mode", "profile", "objects"):
            if req not in conf: fail(f"confidentiality descriptor missing {req}")
        if conf["profile"] != "x-test-sha256-xor-stream-v1":
            fail(f"unknown confidentiality profile {conf['profile']}: MUST NOT guess")
        enc_objects = conf["objects"]
        files = root.get("files") or {}
        for pth, obj in enc_objects.items():
            som.validate_path(pth)
            if pth == root["md"]["path"]:
                link = root["md"]["cid"]
            elif "license" in root and pth == root["license"]["path"]:
                link = root["license"]["cid"]
            elif pth in files:
                link = files[pth]
            else:
                fail(f"descriptor object {pth} has no corresponding SkillRoot link")
            if som.cid_parse(obj["ciphertext"]) != link.cid:
                fail(f"objects[{pth}].ciphertext != SkillRoot link CID")
            ph = obj["plaintextHash"]
            if not (ph.startswith("0x") and len(ph) == 66):
                fail(f"objects[{pth}].plaintextHash not a 32-byte hex digest")
        step(f"confidentiality descriptor verified (profile={conf['profile']}, "
             f"{len(enc_objects)} objects cross-matched to SkillRoot links)")
    # md interlock
    md_path = root["md"]["path"]
    if md_path in enc_objects:
        if bytes.fromhex(enc_objects[md_path]["plaintextHash"][2:]) != md_hash:
            fail(f"descriptor plaintextHash({md_path}) != mdHash")
        step("encrypted primary doc: plaintextHash == mdHash")
    else:
        if som.cid_digest(root["md"]["cid"].cid) != md_hash: fail("digest(md.cid) != mdHash")
        step("digest(md.cid) == mdHash")
    # fetch + verify every leaf; decrypt where declared
    key = bytes.fromhex(a.key) if a.key else None
    leaves = {md_path: root["md"]["cid"], "manifest.json": root["manifest"]}
    if "license" in root: leaves[root["license"]["path"]] = root["license"]["cid"]
    for pth, link in (root.get("files") or {}).items(): leaves[pth] = link
    plain = {}
    for pth, link in leaves.items():
        data = fetch(som.cid_digest(link.cid))
        if pth in enc_objects:
            if not key: fail(f"{pth} encrypted; no key (rights not proven?)")
            pt = xor_stream(key, data)
            if som.sha256(pt) != bytes.fromhex(enc_objects[pth]["plaintextHash"][2:]):
                fail(f"plaintextHash mismatch after decrypt: {pth}")
            plain[pth] = pt
        else:
            plain[pth] = data
    step(f"all {len(leaves)} leaves fetched+verified"
         + (f", {len(enc_objects)} decrypted+plaintext-verified" if enc_objects else ""))
    if som.sha256(plain[md_path]) != md_hash: fail("plaintext primary doc != mdHash")
    try:
        plain[md_path].decode("utf-8")
    except UnicodeDecodeError:
        fail("primary document is not valid UTF-8")
    manifest = json.loads(plain["manifest.json"])
    entry = root["entry"]
    if manifest["entrypoint"] != entry["path"]: fail("manifest.entrypoint != entry.path")
    print(f"  entrypoint: {entry['path']}  profile: {entry['profile']}")
    print("PASS - package verified; safe to hand to sandboxed runtime.")

if __name__ == "__main__":
    main()
