"""Minimal, dependency-free Ethereum primitives for the ERC-8412 reference
model and verifier: keccak256, secp256k1 sign/recover, addresses, ABI
encoding of static types, EIP-712 hashing, and JCS (RFC 8785) for the JSON
subset ERC-8412 documents use.

For reference and test-vector generation only. Not constant-time; do not
use for production key handling.
"""
from __future__ import annotations

import hashlib
import hmac
import json

# ---------------------------------------------------------------- keccak256
_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _M if n else x


def _f(a):
    for rc in _RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        a = [[a[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y], _ROT[x][y])
        a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)]
             for x in range(5)]
        a[0][0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    msg = bytearray(data) + b"\x01"
    while len(msg) % rate:
        msg += b"\x00"
    msg[-1] |= 0x80
    st = [[0] * 5 for _ in range(5)]
    for off in range(0, len(msg), rate):
        blk = msg[off:off + rate]
        for i in range(rate // 8):
            st[i % 5][i // 5] ^= int.from_bytes(blk[8 * i:8 * i + 8], "little")
        st = _f(st)
    return b"".join(st[i % 5][i // 5].to_bytes(8, "little") for i in range(4))


def h(b: bytes) -> str:
    return "0x" + b.hex()


def unhex(s: str) -> bytes:
    return bytes.fromhex(s[2:] if s.startswith("0x") else s)


# ---------------------------------------------------------------- secp256k1
P = 2 ** 256 - 2 ** 32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    if p1[0] == p2[0] and (p1[1] + p2[1]) % P == 0:
        return None
    if p1 == p2:
        lam = 3 * p1[0] * p1[0] * pow(2 * p1[1], -1, P) % P
    else:
        lam = (p2[1] - p1[1]) * pow(p2[0] - p1[0], -1, P) % P
    x = (lam * lam - p1[0] - p2[0]) % P
    return (x, (lam * (p1[0] - x) - p1[1]) % P)


def _mul(k, pt=G):
    r = None
    while k:
        if k & 1:
            r = _add(r, pt)
        pt = _add(pt, pt)
        k >>= 1
    return r


def to_checksum(addr: str) -> str:
    a = addr.lower().replace("0x", "")
    hh = keccak256(a.encode()).hex()
    return "0x" + "".join(c.upper() if int(hh[i], 16) >= 8 else c for i, c in enumerate(a))


def address_of_point(pt) -> str:
    raw = pt[0].to_bytes(32, "big") + pt[1].to_bytes(32, "big")
    return to_checksum("0x" + keccak256(raw)[12:].hex())


def address_of_key(priv: int) -> str:
    return address_of_point(_mul(priv))


def _rfc6979_k(priv: int, digest: bytes) -> int:
    x = priv.to_bytes(32, "big")
    v, k = b"\x01" * 32, b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        cand = int.from_bytes(v, "big")
        if 1 <= cand < N:
            return cand
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def sign(priv: int, digest: bytes) -> bytes:
    """65-byte r||s||v, low-s, v in {27, 28}, deterministic k (RFC 6979)."""
    z = int.from_bytes(digest, "big")
    k = _rfc6979_k(priv, digest)
    R = _mul(k)
    r = R[0] % N
    s = pow(k, -1, N) * (z + r * priv) % N
    recid = R[1] & 1
    if s > N // 2:
        s, recid = N - s, recid ^ 1
    return r.to_bytes(32, "big") + s.to_bytes(32, "big") + bytes([27 + recid])


def recover(digest: bytes, sig: bytes) -> str | None:
    if len(sig) != 65:
        return None
    r = int.from_bytes(sig[:32], "big")
    s = int.from_bytes(sig[32:64], "big")
    v = sig[64]
    if v not in (27, 28) or not (1 <= r < N) or not (1 <= s <= N // 2):
        return None
    beta = pow((r ** 3 + 7) % P, (P + 1) // 4, P)
    y = beta if (beta & 1) == (v - 27) else P - beta
    z = int.from_bytes(digest, "big")
    rinv = pow(r, -1, N)
    Q = _add(_mul(s * rinv % N, (r, y)), _mul((-z * rinv) % N))
    return address_of_point(Q) if Q else None


# ---------------------------------------------------------------- ABI (static types)
def enc_uint(v: int) -> bytes:
    return int(v).to_bytes(32, "big")


def enc_address(a: str) -> bytes:
    return b"\x00" * 12 + unhex(a)


def enc_bytes32(b) -> bytes:
    b = unhex(b) if isinstance(b, str) else b
    assert len(b) == 32
    return b


# ---------------------------------------------------------------- EIP-712
def _type_string(primary, types):
    deps, stack = [], [primary]
    while stack:
        t = stack.pop()
        if t in deps:
            continue
        deps.append(t)
        for f in types[t]:
            base = f["type"].rstrip("[]")
            if base in types and base not in deps:
                stack.append(base)
    ordered = [primary] + sorted(d for d in deps if d != primary)
    return "".join(
        f'{t}({",".join(f["type"] + " " + f["name"] for f in types[t])})' for t in ordered)


def _encode_value(typ, val, types):
    if typ in types:
        return keccak256(_encode_struct(typ, val, types))
    if typ == "string":
        return keccak256(val.encode())
    if typ == "bytes":
        return keccak256(unhex(val))
    if typ == "address":
        return enc_address(val)
    if typ == "bytes32":
        return enc_bytes32(val)
    if typ.startswith("uint"):
        return enc_uint(val)
    raise ValueError(typ)


def _encode_struct(primary, data, types):
    th = keccak256(_type_string(primary, types).encode())
    return th + b"".join(_encode_value(f["type"], data[f["name"]], types) for f in types[primary])


def eip712_digest(types, primary, domain, message) -> bytes:
    dom_fields = [(n, t) for n, t in [("name", "string"), ("version", "string"),
                                       ("chainId", "uint256"), ("verifyingContract", "address")]
                  if n in domain]
    all_types = dict(types)
    all_types["EIP712Domain"] = [{"name": n, "type": t} for n, t in dom_fields]
    ds = keccak256(_encode_struct("EIP712Domain", domain, all_types))
    sh = keccak256(_encode_struct(primary, message, all_types))
    return keccak256(b"\x19\x01" + ds + sh)


# ---------------------------------------------------------------- JCS (RFC 8785 subset)
def jcs(obj) -> bytes:
    """Canonical JSON for objects, arrays, strings, integers, booleans, null.
    Non-integer numbers are rejected: their canonical form needs ES6 number
    serialisation, and ERC-8412 documents do not need them."""
    def check(o):
        if isinstance(o, float):
            raise ValueError("non-integer numbers are not permitted in ERC-8412 documents")
        if isinstance(o, dict):
            for k, v in o.items():
                if not isinstance(k, str):
                    raise ValueError("object keys must be strings")
                check(v)
        elif isinstance(o, list):
            for v in o:
                check(v)
    check(obj)

    def ser(o):
        if isinstance(o, dict):
            keys = sorted(o, key=lambda k: k.encode("utf-16-be"))
            return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + ser(o[k])
                                  for k in keys) + "}"
        if isinstance(o, list):
            return "[" + ",".join(ser(v) for v in o) + "]"
        return json.dumps(o, ensure_ascii=False)
    return ser(obj).encode("utf-8")


def doc_digest(obj) -> str:
    return h(keccak256(jcs(obj)))
