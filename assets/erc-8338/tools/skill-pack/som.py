"""
som.py — Skill Object Model canonical encoding (KERNEL v4.3, normative rules)

Pure-Python, zero dependencies. Implements:
  - deterministic DAG-CBOR encoding (RFC 8949 core deterministic rules,
    definite lengths, shortest-form integers, map keys sorted by bytewise
    lexical order of their ENCODED bytes)
  - CID construction: CIDv1, sha2-256; codec dag-cbor (0x71) for the root,
    raw (0x55) for leaves
  - DAG-CBOR links: tag 42 over identity-multibase-prefixed (0x00) binary CID
  - SkillRoot build + closed-map schema checks + interlock rules
"""
import hashlib

RAW_CODEC = 0x55
DAGCBOR_CODEC = 0x71
SHA2_256 = 0x12
DIGEST_LEN = 0x20


def sha256(b: bytes) -> bytes:
    return hashlib.sha256(b).digest()


def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def make_cid(digest: bytes, codec: int) -> bytes:
    """Binary CIDv1: version varint + codec varint + multihash(sha2-256)."""
    assert len(digest) == 32
    return varint(1) + varint(codec) + bytes([SHA2_256, DIGEST_LEN]) + digest


def cid_check(cid: bytes, codecs=(RAW_CODEC, DAGCBOR_CODEC)) -> int:
    """Strict CIDv1 validation (v4.3): exactly 37 bytes, version 1, allowed
    codec, sha2-256 multihash, 32-byte digest. Returns the codec."""
    if not isinstance(cid, bytes) or len(cid) != 36:
        raise ValueError("bare CID must be exactly 36 bytes (37 with the 0x00 multibase prefix)")
    if cid[0] != 0x01:
        raise ValueError("CID version must be 1")
    codec = cid[1]
    if codec not in codecs:
        raise ValueError(f"CID codec 0x{codec:02x} not allowed here")
    if cid[2] != SHA2_256 or cid[3] != DIGEST_LEN:
        raise ValueError("CID multihash must be sha2-256/32")
    return codec


def cid_digest(cid: bytes) -> bytes:
    """Extract the 32-byte digest from a validated binary CIDv1."""
    cid_check(cid)
    return cid[-32:]


class Link:
    """A DAG-CBOR link (CID). Encodes as tag 42 over 0x00 + binary CID."""
    __slots__ = ("cid",)

    def __init__(self, cid: bytes):
        self.cid = cid


# ---------- deterministic CBOR encoder (subset needed by SkillRoot) ----------

def _head(major: int, arg: int) -> bytes:
    if arg < 24:
        return bytes([(major << 5) | arg])
    for ai, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
        if arg < (1 << (8 * size)):
            return bytes([(major << 5) | ai]) + arg.to_bytes(size, "big")
    raise ValueError("integer too large")


def encode(obj) -> bytes:
    if isinstance(obj, Link):
        # tag 42, byte string = 0x00 (identity multibase) + binary CID
        return _head(6, 42) + encode(b"\x00" + obj.cid)
    if isinstance(obj, bytes):
        return _head(2, len(obj)) + obj
    if isinstance(obj, str):
        raw = obj.encode("utf-8")
        return _head(3, len(raw)) + raw
    if isinstance(obj, int) and not isinstance(obj, bool):
        return _head(0, obj) if obj >= 0 else _head(1, -1 - obj)
    if isinstance(obj, dict):
        # keys MUST be strings; sort by bytewise order of ENCODED key bytes
        items = [(encode(k), encode(v)) for k, v in obj.items()]
        for k in obj:
            if not isinstance(k, str):
                raise TypeError("map keys must be strings")
        items.sort(key=lambda kv: kv[0])
        return _head(5, len(items)) + b"".join(k + v for k, v in items)
    if isinstance(obj, list):
        return _head(4, len(obj)) + b"".join(encode(x) for x in obj)
    raise TypeError(f"unsupported type in SkillRoot: {type(obj)}")


# ---------- minimal decoder (for re-encode verification) ----------

def decode(data: bytes):
    val, off = _decode(data, 0)
    if off != len(data):
        raise ValueError("trailing bytes")
    return val


def _decode(d: bytes, i: int):
    ib = d[i]
    major, ai = ib >> 5, ib & 0x1F
    i += 1
    if ai < 24:
        arg = ai
    elif ai in (24, 25, 26, 27):
        size = 1 << (ai - 24)
        arg = int.from_bytes(d[i:i + size], "big")
        i += size
    else:
        raise ValueError("indefinite lengths forbidden")
    if major == 0:
        return arg, i
    if major == 1:
        return -1 - arg, i
    if major == 2:
        return d[i:i + arg], i + arg
    if major == 3:
        return d[i:i + arg].decode("utf-8"), i + arg
    if major == 4:
        out = []
        for _ in range(arg):
            v, i = _decode(d, i)
            out.append(v)
        return out, i
    if major == 5:
        out = {}
        for _ in range(arg):
            k, i = _decode(d, i)
            v, i = _decode(d, i)
            out[k] = v
        return out, i
    if major == 6:
        if arg != 42:
            raise ValueError("only tag 42 allowed")
        v, i = _decode(d, i)
        if not isinstance(v, bytes) or v[:1] != b"\x00":
            raise ValueError("bad link encoding")
        cid_check(v[1:])
        return Link(v[1:]), i
    raise ValueError("unsupported major type")


# ---------- SkillRoot construction & checks ----------

ROOT_KEYS = {"md", "manifest", "entry", "license", "files", "confidentiality", "prev"}
ROOT_REQUIRED = {"md", "manifest", "entry"}
ENTRY_KEYS = {"path", "cid", "profile"}
MD_KEYS = {"path", "cid"}
LICENSE_KEYS = {"path", "cid"}


def validate_path(p: str):
    """KERNEL v4.2 path rules: relative, case-sensitive UTF-8 POSIX; no leading
    '/', no '\\', no empty/'.'/'..' segments; no normalization."""
    if not isinstance(p, str) or not p:
        raise ValueError("path must be a nonempty string")
    if p.startswith("/") or "\\" in p:
        raise ValueError(f"invalid path: {p!r}")
    for seg in p.split("/"):
        if seg in ("", ".", ".."):
            raise ValueError(f"invalid path segment in: {p!r}")


def leaf_cid(content: bytes) -> Link:
    return Link(make_cid(sha256(content), RAW_CODEC))


def build_skill_root(md: dict, manifest: Link, entry: dict,
                     license_=None, files: dict = None,
                     confidentiality: Link = None, prev: Link = None,
                     version: int = None) -> dict:
    root = {"md": md, "manifest": manifest, "entry": entry}
    if license_ is not None:
        root["license"] = license_
    if files:
        root["files"] = files
    if confidentiality is not None:
        root["confidentiality"] = confidentiality
    if prev is not None:
        root["prev"] = prev
    check_skill_root(root, version=version if version else (1 if prev is None else 2))
    return root


def check_skill_root(root: dict, version: int):
    if not ROOT_REQUIRED.issubset(root):
        raise ValueError(f"missing required fields: {ROOT_REQUIRED - set(root)}")
    if set(root) - ROOT_KEYS:
        raise ValueError(f"unknown fields (closed map): {set(root) - ROOT_KEYS}")
    md = root["md"]
    if not isinstance(md, dict) or set(md) != MD_KEYS:
        raise ValueError("md must have exactly path/cid (v4.2)")
    e = root["entry"]
    if set(e) != ENTRY_KEYS:
        raise ValueError("entry must have exactly path/cid/profile")
    # path rules (v4.2)
    validate_path(md["path"])
    validate_path(e["path"])
    for k in (root.get("files") or {}):
        validate_path(k)
    if md["path"] in (root.get("files") or {}):
        raise ValueError("md.path MUST NOT appear in files")
    # license-entry (v4.3): explicit path, closed map, distinct from md, not in files
    if "license" in root:
        lic = root["license"]
        if not isinstance(lic, dict) or set(lic) != LICENSE_KEYS:
            raise ValueError("license must have exactly path/cid (v4.3)")
        validate_path(lic["path"])
        if lic["path"] == md["path"] or lic["path"] in (root.get("files") or {}):
            raise ValueError("license.path MUST differ from md.path and not appear in files")
        cid_check(lic["cid"].cid, codecs=(RAW_CODEC,))
    # codec expectations (v4.3): leaves raw, prev dag-cbor
    cid_check(md["cid"].cid, codecs=(RAW_CODEC,))
    cid_check(root["manifest"].cid, codecs=(RAW_CODEC,))
    cid_check(e["cid"].cid, codecs=(RAW_CODEC,))
    for lk in (root.get("files") or {}).values():
        cid_check(lk.cid, codecs=(RAW_CODEC,))
    if "confidentiality" in root:
        cid_check(root["confidentiality"].cid, codecs=(RAW_CODEC,))
    if "prev" in root:
        cid_check(root["prev"].cid, codecs=(DAGCBOR_CODEC,))
    # prev rule: absent at v1, present at v>1
    if version == 1 and "prev" in root:
        raise ValueError("prev MUST be omitted at version 1")
    if version > 1 and "prev" not in root:
        raise ValueError("prev MUST be present at version > 1")
    # interlock
    if e["path"] == md["path"]:
        if e["cid"].cid != md["cid"].cid:
            raise ValueError("entry.cid must equal md.cid when entry.path == md.path")
    else:
        files = root.get("files") or {}
        if e["path"] not in files or files[e["path"]].cid != e["cid"].cid:
            raise ValueError("files[entry.path] missing or != entry.cid")


def package_hash(root: dict) -> bytes:
    return sha256(encode(root))


def root_cid(root: dict) -> bytes:
    return make_cid(package_hash(root), DAGCBOR_CODEC)


# ---------- CID string form (multibase base32lower, no padding) ----------
import base64 as _b64

def cid_str(cid: bytes) -> str:
    """Multibase 'b' + RFC4648 base32 lowercase, no padding (the 'bafy...' form)."""
    return "b" + _b64.b32encode(cid).decode("ascii").lower().rstrip("=")


def cid_parse(s: str) -> bytes:
    if not s.startswith("b"):
        raise ValueError("only base32 multibase supported")
    body = s[1:].upper()
    body += "=" * (-len(body) % 8)
    raw = _b64.b32decode(body)
    if cid_str(raw) != s:
        raise ValueError("non-canonical base32 CID string")
    cid_check(raw)
    return raw
