#!/usr/bin/env python3
"""
pack.py — package a task directory into a TaskRoot per TASK-KERNEL v1.0.

Usage:
  python3 pack.py <task-dir> [--out <dir>] [--primary <path>]
                  [--spec <path>] [--acceptance <path> --acceptance-profile <id>]
                  [--version N --prev <previous-taskHash-hex>]
                  [--encrypt path1,path2 --key <hex>]  # x-test-sha256-xor-stream-v1

Conventions inside <task-dir>:
  TASK.md            primary document (or --primary; README.md accepted)
  manifest.json      task manifest (auto-generated minimally when absent)
  fulfillment.json   fulfillment policy descriptor (linked as "fulfillment" when present)
  terms / TERMS.md   legal/commercial terms (linked as "terms" when present)

Outputs (to --out, default ./out):
  taskroot.cbor      canonical TaskRoot bytes
  vector.json        tdHash, taskHash, root CID, per-file CIDs, version info
  objects/           content-addressed leaves as published (ciphertext if encrypted)
"""
import argparse, hashlib, json, os, shutil, sys
import tom

MANIFEST = "manifest.json"
FULFILLMENT = "fulfillment.json"
TERMS_CANDIDATES = ("terms", "TERMS", "TERMS.md", "terms.json")


def detect_primary(paths):
    """TASK.md SHOULD be the default; README.md accepted;
    else a sole root-level .md/.markdown file."""
    for cand in ("TASK.md", "README.md"):
        if cand in paths:
            return cand
    mds = [p for p in paths if "/" not in p and p.lower().endswith((".md", ".markdown"))]
    if len(mds) == 1:
        return mds[0]
    sys.exit("cannot determine primary document (need TASK.md, README.md, or a single root .md)")


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
    ap.add_argument("task_dir")
    ap.add_argument("--out", default="out")
    ap.add_argument("--force", action="store_true",
                    help="replace a non-empty output directory instead of refusing")
    ap.add_argument("--prev", help="previous taskHash (hex); REQUIRED iff --version > 1")
    ap.add_argument("--version", type=int, default=None, help="content version (default: 1, or 2 if --prev)")
    ap.add_argument("--primary", help="explicit primary document path (overrides auto-detection)")
    ap.add_argument("--spec", help="explicit spec path (default: manifest.specPath, else the primary document)")
    ap.add_argument("--spec-profile", default=None, help="spec profile id (default: manifest x-spec-profile or llm-markdown-v1)")
    ap.add_argument("--acceptance", help="acceptance criteria/harness path")
    ap.add_argument("--acceptance-profile", default="x-human-review-v1")
    ap.add_argument("--max-completions", type=int, default=None,
                    help="cross-check against fulfillment.json maxCompletions when present")
    ap.add_argument("--encrypt", help="comma-separated paths to encrypt")
    ap.add_argument("--key", help="hex key for demo encryption profile")
    a = ap.parse_args()

    base = a.task_dir.rstrip("/")
    enc_paths = set(a.encrypt.split(",")) if a.encrypt else set()
    key = bytes.fromhex(a.key) if a.key else None
    if enc_paths and not key:
        sys.exit("--encrypt requires --key")

    # The output directory is commonly placed inside the task directory. It must never
    # be scanned as input: a second pack would swallow the first pack's objects, change
    # the taskHash, and -- worst of all -- carry the earlier plaintext into a package
    # that was supposed to be confidential. And packing ON TOP of the task directory
    # would delete the sources, so refuse that outright.
    # Compare RESOLVED, CASE-NORMALISED paths. A plain string comparison of abspath is
    # a Windows footgun: NTFS is case-insensitive, so --out casesource addresses the very
    # same directory as CaseSource and slips straight past an == test, after which the
    # publish step deletes the sources it was told never to touch. Symlinks alias the
    # same way on every platform.
    def pathkey(path: str) -> str:
        return os.path.normcase(os.path.realpath(os.path.abspath(path)))

    def inside(child: str, parent: str) -> bool:
        try:
            return os.path.commonpath([child, parent]) == parent
        except ValueError:      # different drives -- unrelated by construction
            return False

    base_abs, out_abs = pathkey(base), pathkey(a.out)
    if base_abs == out_abs:
        sys.exit(f"--out must not be the task directory itself: publishing would delete {base!r}")
    if inside(base_abs, out_abs):
        sys.exit(f"--out must not contain the task directory: publishing would delete {base!r}")
    skip = {out_abs, pathkey(a.out.rstrip("/\\") + ".staging")}

    def excluded(full: str) -> bool:
        k = pathkey(full)
        return any(k == s or inside(k, s) for s in skip)

    # collect files
    paths = []
    for root, _, files in os.walk(base):
        if excluded(root):
            continue
        for f in files:
            full = os.path.join(root, f)
            if excluded(full):
                continue
            rel = os.path.relpath(full, base).replace(os.sep, "/")
            paths.append(rel)
    paths.sort()
    missing = enc_paths - set(paths)
    if missing:
        sys.exit(f"--encrypt paths not in package: {sorted(missing)}")

    # full version chain semantics
    version = a.version if a.version is not None else (2 if a.prev else 1)
    if version < 1:
        sys.exit("--version must be >= 1")
    if version == 1 and a.prev:
        sys.exit("version 1 MUST NOT provide --prev")
    if version > 1 and not a.prev:
        sys.exit("version > 1 MUST provide --prev")

    # explicit --primary overrides convenience auto-detection
    if a.primary:
        tom.validate_path(a.primary)
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
                "taskVersion": "0.0.1", "summary": first_line or "Task tender package.",
                "specPath": a.spec or PRIMARY}
        manifest_bytes = json.dumps(auto, indent=2).encode()
        print(f"[task-pack] manifest.json not found; auto-generated (specPath={a.spec or PRIMARY})", file=sys.stderr)
    manifest = json.loads(manifest_bytes)
    for req in ("schemaVersion", "name", "taskVersion", "summary", "specPath"):
        if req not in manifest:
            sys.exit(f"manifest missing REQUIRED field: {req}")
    spec_path = a.spec or manifest["specPath"]
    if manifest["specPath"] != spec_path:
        sys.exit("manifest.specPath MUST equal TaskRoot.spec.path (pass matching --spec)")
    spec_profile = a.spec_profile or manifest.get("x-spec-profile", "llm-markdown-v1")

    td_plain = read(PRIMARY)
    try:
        td_plain.decode("utf-8")  # primary MUST be valid UTF-8
    except UnicodeDecodeError as ex:
        sys.exit(f"primary document is not valid UTF-8: {ex}")
    td_hash = tom.sha256(td_plain)  # ALWAYS the plaintext commitment

    # Publish atomically into a FRESH directory. Writing into an existing output
    # directory silently keeps whatever was there before: repacking a public package
    # as a confidential one used to leave the plaintext objects sitting next to the
    # ciphertext, and verification still passed because it only walks the objects the
    # TaskRoot references. A "confidential" package that ships its own plaintext is
    # the worst possible failure, so refuse to reuse a non-empty directory and stage
    # every write in a temporary sibling that replaces it only on success.
    stage = a.out.rstrip("/\\") + ".staging"
    if os.path.exists(a.out) and os.listdir(a.out):
        if not a.force:
            sys.exit(
                f"output directory {a.out!r} is not empty. Packing into it would keep stale "
                f"objects from an earlier run -- including plaintext that a later confidential "
                f"pack was meant to replace. Remove it, choose another path, or pass --force."
            )
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(os.path.join(stage, "objects"))
    conf_objects, leaves = {}, {}

    def publish(rel: str, plain: bytes) -> tom.Link:
        data = plain
        if rel in enc_paths:
            data = xor_stream(key, plain)
            link = tom.leaf_cid(data)
            conf_objects[rel] = {
                "ciphertext": tom.cid_str(link.cid),
                "plaintextHash": "0x" + tom.sha256(plain).hex(),
            }
        else:
            link = tom.leaf_cid(data)
        with open(os.path.join(stage, "objects", tom.cid_digest(link.cid).hex()), "wb") as fh:
            fh.write(data)
        leaves[rel] = link
        return link

    td_link = publish(PRIMARY, td_plain)
    manifest_link = publish(MANIFEST, manifest_bytes)
    if MANIFEST in enc_paths or FULFILLMENT in enc_paths or "confidentiality" in enc_paths:
        sys.exit("manifest/fulfillment/confidentiality MUST remain public")

    files_map = {}
    terms_entry = None
    fulfillment_link = None
    for rel in paths:
        if rel in (PRIMARY, MANIFEST):
            continue
        link = publish(rel, read(rel))
        if rel == FULFILLMENT:
            # cross-check descriptor/chain agreement on maxCompletions
            desc = json.loads(read(rel))
            for req in ("schemaVersion", "mode", "maxCompletions"):
                if req not in desc:
                    sys.exit(f"fulfillment descriptor missing REQUIRED field: {req}")
            if a.max_completions is not None and desc["maxCompletions"] != a.max_completions:
                sys.exit(f"fulfillment.maxCompletions ({desc['maxCompletions']}) != on-chain terms ({a.max_completions})")
            fulfillment_link = link
        elif terms_entry is None and rel in TERMS_CANDIDATES:
            terms_entry = {"path": rel, "cid": link}
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
        conf_link = tom.leaf_cid(conf_bytes)
        with open(os.path.join(stage, "objects", tom.cid_digest(conf_link.cid).hex()), "wb") as fh:
            fh.write(conf_bytes)

    spec_link = leaves.get(spec_path) or (td_link if spec_path == PRIMARY else None)
    if spec_link is None:
        sys.exit(f"spec {spec_path} not found in package")

    acceptance_entry = None
    if a.acceptance:
        if a.acceptance not in leaves or a.acceptance in (PRIMARY, MANIFEST):
            sys.exit(f"--acceptance {a.acceptance} not found among package files")
        acceptance_entry = {"path": a.acceptance, "cid": leaves[a.acceptance],
                            "profile": a.acceptance_profile}

    prev_link = tom.Link(tom.make_cid(bytes.fromhex(a.prev.replace("0x", "")), tom.DAGCBOR_CODEC)) if a.prev else None

    root = tom.build_task_root(
        td={"path": PRIMARY, "cid": td_link}, manifest=manifest_link,
        spec={"path": spec_path, "cid": spec_link, "profile": spec_profile},
        acceptance=acceptance_entry, fulfillment=fulfillment_link,
        terms=terms_entry, files=files_map or None,
        confidentiality=conf_link, prev=prev_link, version=version,
    )
    root_bytes = tom.encode(root)

    # self-check: decode -> re-encode -> byte equality (verification rule)
    assert tom.encode(tom.decode(root_bytes)) == root_bytes, "re-encode mismatch"

    t_hash = tom.sha256(root_bytes)
    with open(os.path.join(stage, "taskroot.cbor"), "wb") as fh:
        fh.write(root_bytes)
    vector = {
        "standard": "TASK-KERNEL v1.0",
        "tdHash": "0x" + td_hash.hex(),
        "taskHash": "0x" + t_hash.hex(),
        "rootCID_digest": "0x" + t_hash.hex(),
        "version": version,
        "confidential": bool(enc_paths),
        "encryptedPaths": sorted(enc_paths),
        "leaves": {rel: "0x" + tom.cid_digest(l.cid).hex() for rel, l in leaves.items()},
    }
    with open(os.path.join(stage, "vector.json"), "w") as fh:
        json.dump(vector, fh, indent=2)

    # atomic-enough publish: the output directory only ever holds one complete pack
    if os.path.exists(a.out):
        shutil.rmtree(a.out)
    os.replace(stage, a.out)
    print(json.dumps(vector, indent=2))


if __name__ == "__main__":
    main()
