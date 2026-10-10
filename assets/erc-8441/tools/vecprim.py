"""Primitives for the conformance-vector generator, and **nothing from this repository**.

`tools/gen_vectors.py` may not import the code it validates -- a fixture derived from that code
tests self-consistency and nothing else, which is why the generator comes ahead of any
cryptography. This module is the other half of that rule: the arithmetic
the generator needs, written from the standards rather than taken from `crates/`.

Not a KEM either. ML-KEM-768 in pure Python is a project rather than a function, and writing
one would put a second unreviewed KEM in the tree -- so the generator consumes NIST ACVP
`(ek, m, ct, ss)` tuples instead, which is what the tier-1/tier-2 split already says: tier 1
is ACVP and "we generate nothing".

Every function below is checked by `tools/test-gen-vectors.py` against a value published
somewhere other than this repository.
"""

from __future__ import annotations

import hashlib
import os

# --------------------------------------------------------------------------------------
# keccak256, from FIPS 202's permutation with the ORIGINAL Keccak padding
# --------------------------------------------------------------------------------------
#
# The difference between this and SHA3-256 is one byte: SHA3 appends the domain separator
# `0x06` and Keccak appends `0x01`. Nothing else. That single byte is why substituting
# `hashlib.sha3_256` for keccak256 produces a plausible-looking address that no Ethereum node
# agrees with, and it is the reason this is written out rather than approximated.

_RC = (
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
)
_ROT = (
    (0, 36, 3, 41, 18), (1, 44, 10, 45, 2), (62, 6, 43, 15, 61),
    (28, 55, 25, 21, 56), (27, 20, 39, 8, 14),
)
_MASK = (1 << 64) - 1


def _rotl(x: int, n: int) -> int:
    return ((x << n) | (x >> (64 - n))) & _MASK


def _keccak_f1600(a: list[list[int]]) -> None:
    for rnd in range(24):
        # theta
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rotl(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                a[x][y] ^= d[x]
        # rho and pi
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rotl(a[x][y], _ROT[x][y])
        # chi
        for x in range(5):
            for y in range(5):
                a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y] & _MASK) & b[(x + 2) % 5][y])
        # iota
        a[0][0] ^= _RC[rnd]


def keccak256(data: bytes) -> bytes:
    """Original-Keccak 256, as Ethereum uses it. **Not SHA3-256** -- see this module's note."""
    rate = 136  # 1088 bits, for a 256-bit digest
    padded = bytearray(data)
    padded.append(0x01)  # Keccak's domain byte. SHA3-256 would append 0x06.
    while len(padded) % rate != 0:
        padded.append(0x00)
    padded[-1] |= 0x80

    state = [[0] * 5 for _ in range(5)]
    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        for i in range(rate // 8):
            lane = int.from_bytes(block[i * 8:(i + 1) * 8], "little")
            state[i % 5][i // 5] ^= lane
        _keccak_f1600(state)

    out = bytearray()
    for i in range(4):  # 4 lanes = 32 bytes
        out += state[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out)


# --------------------------------------------------------------------------------------
# secp256k1, from SEC 2 §2.4.1
# --------------------------------------------------------------------------------------

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
G = (GX, GY)

Point = tuple[int, int] | None
def add(a: Point, b: Point) -> Point:
    """Affine addition. Slow and clear; correctness is the only requirement here."""
    if a is None:
        return b
    if b is None:
        return a
    ax, ay = a
    bx, by = b
    if ax == bx and (ay + by) % P == 0:
        return None
    if a == b:
        lam = (3 * ax * ax) * pow(2 * ay, P - 2, P) % P
    else:
        lam = (by - ay) * pow(bx - ax, P - 2, P) % P
    x = (lam * lam - ax - bx) % P
    y = (lam * (ax - x) - ay) % P
    return (x, y)


def mul(k: int, pt: Point = G) -> Point:
    """Scalar multiplication. **Not constant-time**, deliberately -- see the module note."""
    if k % N == 0 or pt is None:
        return None
    acc: Point = None
    addend = pt
    k %= N
    while k:
        if k & 1:
            acc = add(acc, addend)
        addend = add(addend, addend)
        k >>= 1
    return acc


def encode_compressed(pt: Point) -> bytes:
    """SEC1 compressed: 33 bytes, tag `0x02` for even y and `0x03` for odd."""
    if pt is None:
        raise ValueError("the point at infinity has no SEC1 encoding")
    x, y = pt
    return bytes([0x02 + (y & 1)]) + x.to_bytes(32, "big")


def encode_uncompressed(pt: Point) -> bytes:
    """SEC1 uncompressed: 65 bytes, `0x04 ‖ x ‖ y`. The address derivation drops the tag."""
    if pt is None:
        raise ValueError("the point at infinity has no SEC1 encoding")
    x, y = pt
    return b"\x04" + x.to_bytes(32, "big") + y.to_bytes(32, "big")


def decode_compressed(b: bytes) -> Point:
    """Decode, accepting **only** `0x02` and `0x03`.

    Rejects the SEC1 **compact** `0x05` form, which §2.2 turns on: at least one widely used
    stack canonicalises it to the same point as the compressed encodings, so accepting it gives
    one key two on-chain encodings and therefore two meta-addresses. Raises `ValueError` for
    every rejection, without distinguishing which check failed -- §2.2 asks for rejection, not
    diagnosis.
    """
    if len(b) != 33 or b[0] not in (0x02, 0x03):
        raise ValueError("not a SEC1 compressed point")
    x = int.from_bytes(b[1:], "big")
    if x >= P:
        raise ValueError("x is at or above the field modulus")
    y2 = (x * x * x + 7) % P
    y = pow(y2, (P + 1) // 4, P)
    if (y * y - y2) % P != 0:
        raise ValueError("x is not on the curve")
    if (y & 1) != (b[0] & 1):
        y = P - y
    return (x, y)


def address_of(pt: Point) -> bytes:
    """The Ethereum address: `keccak256(uncompressed(pk)[1..])[12..32]`.

    The `[1..]` drops the `0x04` tag; including it is the likely error, and `[12..32]` rather
    than `[0..20]` is the other. A former fixture named both alternatives; see the
    record in `vectors/PLAN.md` -- so `tools/test-gen-vectors.py` is what holds this to a
    published answer now.
    """
    return keccak256(encode_uncompressed(pt)[1:])[12:]


def eip55(addr20: bytes) -> str:
    """The EIP-55 mixed-case checksum form. Held to a published address by the self-test."""
    low = addr20.hex()
    h = keccak256(low.encode()).hex()
    return "0x" + "".join(
        c.upper() if c.isalpha() and int(h[i], 16) >= 8 else c for i, c in enumerate(low)
    )
# --------------------------------------------------------------------------------------
# The derivations of §1, from the specification text
# --------------------------------------------------------------------------------------

DS_OFFSET = b"pq-stealth/offset/v1"
DS_VIEWTAG = b"pq-stealth/view-tag/v1"
# --------------------------------------------------------------------------------------
# ML-KEM-768, from a third-party implementation, OPTIONAL
# --------------------------------------------------------------------------------------
#
# `kyber-py` if it is installed, `None` otherwise. OPTIONAL on purpose: nothing else here has
# an external dependency, and a generator a reviewer cannot run from a bare checkout is a check
# that reports nothing. Rows needing a KEM are emitted when it is present and recorded as absent
# WITH THE REASON when it is not, so the plan-coverage invariant holds either way.
#
# A third-party implementation is the right oracle rather than a convenience: the standalone
# rule forbids importing the code the vectors validate, and this one is trusted for exactly the
# tuples it reproduces from NIST's ACVP file -- `acvp_selftest()` below, run every time.
#
# `PQSA_NO_KEM=1` forces the absent branch, so one machine can exercise both worlds. The absent
# branch is the one a bare checkout takes, so it is the one a reviewer meets first.
if os.environ.get("PQSA_NO_KEM") == "1":                    # pragma: no cover - env dependent
    _ML_KEM_768 = None
else:
    try:                                                    # pragma: no cover - env dependent
        from kyber_py.ml_kem import ML_KEM_768 as _ML_KEM_768
    except ImportError:                                     # pragma: no cover
        _ML_KEM_768 = None
def have_kem() -> bool:
    """Whether an ML-KEM implementation is available to this process."""
    return _ML_KEM_768 is not None


def kem_keygen(dz: bytes) -> tuple[bytes, bytes]:
    """`ML-KEM.KeyGen_internal(d, z)` -> `(ek, dk)`. §1 requires the internal entry point.

    Takes the 64-byte `(d, z)` seed because §2.1 makes the tracking key carry that seed rather
    than the expanded form -- so the caller holds 64 bytes and expands on demand, which is the
    property that makes the tracking key 96 bytes and not 2 432.
    """
    assert len(dz) == 64, f"(d, z) is 64 bytes, got {len(dz)}"
    return _ML_KEM_768._keygen_internal(dz[:32], dz[32:])


def kem_encaps(ek: bytes, m: bytes) -> tuple[bytes, bytes]:
    """`ML-KEM.Encaps_internal(ek, m)` -> `(ct, ss)`. Deterministic in `m`, per §1.

    Returned in the order the specification writes them, `(ct, ss)`, which is the REVERSE of
    the library's `(ss, ct)`. Normalised here rather than at each call site: a fixture with the
    two swapped is 1 088 bytes of plausible hex in a 32-byte field and would be caught, but the
    32/1088 confusion in the other direction would not be.
    """
    assert len(m) == 32, f"m is 32 bytes, got {len(m)}"
    ss, ct = _ML_KEM_768._encaps_internal(ek, m)
    return ct, ss
def kem_decaps_expanded(dk: bytes, ct: bytes) -> bytes:
    """`ML-KEM.Decaps(dk, ct)` from the EXPANDED 2 400-byte key.

    **This exists for one purpose: consuming NIST's ACVP decapsulation cases**, whose `dk` is
    the expanded form. §2.1 makes the tracking key carry the 64-byte `(d, z)` seed, and the
    difference is what makes a delegated tracking key 96 bytes rather than 2 432 -- so no
    derivation in this repository takes this path, and `kem_decaps` above is the one our vectors
    use.

    Kept separate rather than folded into `kem_decaps` with a length switch, because a function
    that silently accepts either representation is a function through which the expanded form
    can reach a fixture. §2.1's delegated object is defined by its exact contents.
    """
    assert len(dk) == 2400, f"the expanded dk is 2 400 bytes, got {len(dk)}"
    return _ML_KEM_768.decaps(dk, ct)


def acvp_selftest(tier1: dict) -> list[str]:
    """Reproduce NIST's ACVP tuples with the installed library. Returns disagreements.

    This is what makes the dependency trustworthy for exactly what it is used for, and it runs
    on every generator invocation rather than once by hand. An empty list is agreement; the
    caller decides whether that is required or merely reported.
    """
    if not have_kem():
        return []
    bad: list[str] = []
    for c in tier1.get("keygen", []):
        ek, _dk = kem_keygen(bytes.fromhex(c["d"] + c["z"]))
        if ek.hex() != c["ek"]:
            bad.append(f"keyGen tcId {c['tcId']}: ek disagrees with ACVP")
    for c in tier1.get("encapsulation", []):
        ct, ss = kem_encaps(bytes.fromhex(c["ek"]), bytes.fromhex(c["m"]))
        if ct.hex() != c["c"]:
            bad.append(f"encaps tcId {c['tcId']}: ct disagrees with ACVP")
        if ss.hex() != c["k"]:
            bad.append(f"encaps tcId {c['tcId']}: ss disagrees with ACVP")
    # DECAPSULATION, deliberately. Without it a KEM with correct keygen and encapsulation for
    # the sampled cases, and a subtly wrong decapsulation path, would pass the advertised
    # oracle. Five of these cases are `modified ciphertext`, which is IMPLICIT REJECTION
    # against NIST's own expected secret -- the behaviour §2.4's required address comparison
    # rests on, the subject of fixture V3-14, and this is its only external check.
    for c in tier1.get("decapsulation", []):
        ss = kem_decaps_expanded(bytes.fromhex(c["dk"]), bytes.fromhex(c["c"]))
        if ss.hex() != c["k"]:
            bad.append(f"decaps tcId {c['tcId']} ({c['reason']}): ss disagrees with ACVP")
    return bad


ML_KEM_Q = 3329


def ek_out_of_range(ek: bytes) -> tuple[int, int] | None:
    """FIPS 203 §7.2's modulus check on an ML-KEM-768 `ek`: the first 12-bit coefficient of
    `ek[0:1152]` that is at least q, as `(index, value)`, or None if every one is below q.

    ByteDecode12 then ByteEncode12 is the identity exactly when no coefficient is at least q, so
    this is the check FIPS 203 states, read off the packing: three bytes hold two coefficients,
    low nibble of the middle byte with the first. The type check (1 184 bytes) is the caller's.
    """
    assert len(ek) == 1184, f"an ML-KEM-768 ek is 1 184 bytes, got {len(ek)}"
    for i in range(0, 1152, 3):
        b0, b1, b2 = ek[i], ek[i + 1], ek[i + 2]
        for j, c in enumerate((b0 | (b1 & 0x0F) << 8, b1 >> 4 | b2 << 4)):
            if c >= ML_KEM_Q:
                return (2 * (i // 3) + j, c)
    return None
def offset_scalar(base: bytes) -> int:
    """§1's range check. Returns `base` as an integer if `0 < base < n`.

    There is no reduction and no retry: an out-of-range `base` raises `ValueError`, and the
    sender draws new randomness. That happens with probability about 2**-128, so no findable
    `ss` reaches it; V1-03 and V1-04 supply `base` directly.

    Big-endian, which V1-02 exists to pin: a little-endian read gives a different scalar,
    therefore a different address, therefore funds the recipient cannot spend. Silent and total.
    """
    candidate = int.from_bytes(base, "big")
    if not 0 < candidate < N:
        raise ValueError("offset out of range")
    return candidate


def h_of_ss(ss: bytes) -> tuple[bytes, int]:
    """§1's `H(ss)`. Returns `(base, scalar)`."""
    base = hashlib.sha256(DS_OFFSET + ss).digest()
    return base, offset_scalar(base)


VIEW_TAG_BYTES = 1


def view_tag(ss: bytes) -> bytes:
    """§1's view tag: a **separate digest**, its first `VIEW_TAG_BYTES` bytes.

    **One byte, returned as `bytes` and not as an `int`.** The width is a parameter and has
    already moved once -- it was eight bytes until the announced `stealthAddress` was made
    the authoritative check (§2.4) and the tag was narrowed to a prefilter. An `int` return
    would let every call site format the value itself, and a call site formatting a widened
    tag as `f"{tag:02x}"` would emit two hex characters of it: a truncation that produces a
    well-formed fixture nobody can pass. `bytes` makes the width the primitive's business
    and a formatting mistake a type error.

    V1-07's `wrong` column names the errors it distinguishes: taking other than `[0]` alone;
    taking the trailing bytes; and taking the leading bytes of `H(ss)` rather than of this
    separate digest.
    """
    return hashlib.sha256(DS_VIEWTAG + ss).digest()[:VIEW_TAG_BYTES]
