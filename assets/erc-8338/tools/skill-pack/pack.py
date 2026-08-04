#!/usr/bin/env python3
"""
pack.py — package a skill directory into a SkillRoot per KERNEL v4.3.

Usage:
  python3 pack.py <skill-dir> [--out <dir>] [--primary <path>]
                  [--version N --prev <previous-packageHash-hex>]
                  [--encrypt path1,path2 --key <hex>]  # x-test-sha256-xor-stream-v1

Outputs (to --out, default ./out):
  skillroot.cbor      canonical SkillRoot bytes
  vector.json         mdHash, packageHash, root CID, per-file CIDs, version info
  objects/            content-addressed leaves as published (ciphertext if encrypted)
"""
import argparse, hashlib, json, os, sys
import som

MANIFEST = "manifest.json"

def detect_primary(paths):
    """v4.2 conventions: SKILL.md SHOULD be the default; README.md accepted;
    else a sole root-level .md/.markdown file."""
    for cand in ("SKILL.md", "README.md"):
        if cand in paths:
            return cand
    mds = [p for p in paths if "/" not in p and p.lower().endswith((".md", ".markdown"))]
    if len(mds) == 1:
        return mds[0]
    sys.exit("cannot determine primary document (need SKILL.md, README.md, or a single root .md)")


def xor_stream(key: bytes, data: bytes) -> bytes:
    """NON-CRYPTOGRAPHIC TEST PROFILE x-test-sha256-xor-stream-v1:
    SHA-256(key||counter) keystream XOR. TEST VECTORS ONLY."""
    out = bytearray()
    counter = 0
    while len(out) < len(data):
        block = hashlib.sha256(key + counter.to_bytes(16, "big")).digest()
        out.extend(block)
        counter += 1
    return bytes(x ^ y for x, y in zip(data, out[:len(data)]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skill_dir")
    ap.add_argument("--out", default="out")
    ap.add_argument("--prev", help="previous packageHash (hex); REQUIRED iff --version > 1")
    ap.add_argument("--version", type=int, default=None, help="content version (default: 1, or 2 if --prev)")
    ap.add_argument("--primary", help="explicit primary document path (overrides auto-detection)")
    ap.add_argument("--encrypt", help="comma-separated paths to encrypt")
    ap.add_argument("--key", help="hex key for demo encryption profile")
    a = ap.parse_args()

    base = a.skill_dir.rstrip("/")
    enc_paths = set(a.encrypt.split(",")) if a.encrypt else set()
    key = bytes.fromhex(a.key) if a.key else None
    if enc_paths and not key:
        sys.exit("--encrypt requires --key")

    # collect files
    paths = []
    for root, _, files in os.walk(base):
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, base).replace(os.sep, "/")
            paths.append(rel)
    paths.sort()
    missing = enc_paths - set(paths)
    if missing:
        sys.exit(f"--encrypt paths not in package: {sorted(missing)}")
    # Fix 4: full version chain semantics
    version = a.version if a.version is not None else (2 if a.prev else 1)
    if version < 1:
        sys.exit("--version must be >= 1")
    if version == 1 and a.prev:
        sys.exit("version 1 MUST NOT provide --prev")
    if version > 1 and not a.prev:
        sys.exit("version > 1 MUST provide --prev")
    # Fix 2: explicit --primary overrides convenience auto-detection
    if a.primary:
        som.validate_path(a.primary)
        if a.primary not in paths:
            sys.exit(f"--primary {a.primary} not found in package")
        PRIMARY = a.primary
    else:
        PRIMARY = detect_primary(paths)

    read = lambda rel: open(os.path.join(base, rel), "rb").read()

    if MANIFEST in paths:
        manifest_bytes = read(MANIFEST)
    else:
        # auto-generate minimal manifest (creator zero-knowledge path)
        try:
            first_line = read(PRIMARY).decode("utf-8").splitlines()[0].lstrip("# ").strip()
        except UnicodeDecodeError as ex:
            sys.exit(f"primary document is not valid UTF-8: {ex}")
        auto = {"schemaVersion": "1.0", "name": os.path.basename(base),
                "skillVersion": "0.0.1", "summary": first_line or "Skill package.",
                "entrypoint": PRIMARY}
        manifest_bytes = json.dumps(auto, indent=2).encode()
        print(f"[skill-pack] manifest.json not found; auto-generated (entrypoint={PRIMARY})", file=sys.stderr)
    manifest = json.loads(manifest_bytes)
    for req in ("schemaVersion", "name", "skillVersion", "summary", "entrypoint"):
        if req not in manifest:
            sys.exit(f"manifest missing REQUIRED field: {req}")
    entry_path = manifest["entrypoint"]
    entry_profile = manifest.get("x-entry-profile", "llm-markdown-v1")

    md_plain = read(PRIMARY)
    try:
        md_plain.decode("utf-8")  # Fix 5: primary MUST be valid UTF-8
    except UnicodeDecodeError as ex:
        sys.exit(f"primary document is not valid UTF-8: {ex}")
    md_hash = som.sha256(md_plain)  # ALWAYS the plaintext commitment

    os.makedirs(os.path.join(a.out, "objects"), exist_ok=True)
    conf_objects, leaves = {}, {}

    def publish(rel: str, plain: bytes) -> som.Link:
        data = plain
        if rel in enc_paths:
            data = xor_stream(key, plain)
            link = som.leaf_cid(data)
            conf_objects[rel] = {
                "ciphertext": som.cid_str(link.cid),
                "plaintextHash": "0x" + som.sha256(plain).hex(),
            }
        else:
            link = som.leaf_cid(data)
        with open(os.path.join(a.out, "objects", som.cid_digest(link.cid).hex()), "wb") as fh:
            fh.write(data)
        leaves[rel] = link
        return link

    md_link = publish(PRIMARY, md_plain)
    manifest_link = publish(MANIFEST, manifest_bytes)
    if MANIFEST in enc_paths or "confidentiality" in enc_paths:
        sys.exit("manifest/confidentiality MUST remain public")

    files_map = {}
    license_entry = None
    for rel in paths:
        if rel in (PRIMARY, MANIFEST):
            continue
        link = publish(rel, read(rel))
        if license_entry is None and rel in ("license", "LICENSE", "license.json"):
            license_entry = {"path": rel, "cid": link}
        else:
            files_map[rel] = link

    conf_link = None
    if enc_paths:
        descriptor = {
            "schemaVersion": "1.0",
            "mode": "encrypted",
            "profile": "x-test-sha256-xor-stream-v1",
            "objects": conf_objects,
            "keyManagement": {"type": "pre-shared-demo-key"},
        }
        conf_bytes = json.dumps(descriptor, sort_keys=True, separators=(",", ":")).encode()
        conf_link = som.leaf_cid(conf_bytes)
        with open(os.path.join(a.out, "objects", som.cid_digest(conf_link.cid).hex()), "wb") as fh:
            fh.write(conf_bytes)

    entry_link = leaves.get(entry_path) or (md_link if entry_path == PRIMARY else None)
    if entry_link is None:
        sys.exit(f"entrypoint {entry_path} not found in package")

    prev_link = som.Link(som.make_cid(bytes.fromhex(a.prev.replace("0x", "")), som.DAGCBOR_CODEC)) if a.prev else None

    root = som.build_skill_root(
        md={"path": PRIMARY, "cid": md_link}, manifest=manifest_link,
        entry={"path": entry_path, "cid": entry_link, "profile": entry_profile},
        license_=license_entry, files=files_map or None,
        confidentiality=conf_link, prev=prev_link, version=version,
    )
    root_bytes = som.encode(root)

    # self-check: decode -> re-encode -> byte equality (KERNEL v4.3 verification rule)
    assert som.encode(som.decode(root_bytes)) == root_bytes, "re-encode mismatch"

    pkg_hash = som.sha256(root_bytes)
    with open(os.path.join(a.out, "skillroot.cbor"), "wb") as fh:
        fh.write(root_bytes)
    vector = {
        "standard": "KERNEL v4.3",
        "mdHash": "0x" + md_hash.hex(),
        "packageHash": "0x" + pkg_hash.hex(),
        "rootCID_digest": "0x" + pkg_hash.hex(),
        "version": version,
        "confidential": bool(enc_paths),
        "encryptedPaths": sorted(enc_paths),
        "leaves": {rel: "0x" + som.cid_digest(l.cid).hex() for rel, l in leaves.items()},
    }
    with open(os.path.join(a.out, "vector.json"), "w") as fh:
        json.dump(vector, fh, indent=2)
    print(json.dumps(vector, indent=2))


if __name__ == "__main__":
    main()
