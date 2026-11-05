#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Reference checker for the ERC-8481 `address.on-list` list document vectors.

Python 3.9+, standard library only (keccak256, RFC 8785 JCS, bech32 and base58 are
implemented below, so nothing needs installing).

    python3 onlist_vectors.py           # check every vector file against this implementation
    python3 onlist_vectors.py --write   # regenerate the vector files (deterministic)

Cases marked "basis": "spec" follow the draft text as of d21f46e. Cases marked "basis": "reference"
are choices this implementation makes where the draft is silent (see README.md). Cases under "open"
carry no expected result and are not checked; as of d21f46e there are none.
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- keccak256 (original Keccak padding, not SHA3-256)
_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _M if n else x


def _keccak_f(a):
    for rc in _RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        a = [[a[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y], _ROT[x][y])
        a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
        a[0][0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    msg = bytearray(data) + b"\x01"
    msg += b"\x00" * ((-len(msg)) % rate)
    msg[-1] |= 0x80
    a = [[0] * 5 for _ in range(5)]
    for off in range(0, len(msg), rate):
        block = msg[off:off + rate]
        for i in range(rate // 8):
            a[i % 5][i // 5] ^= int.from_bytes(block[8 * i:8 * i + 8], "little")
        a = _keccak_f(a)
    out = b"".join(a[i % 5][i // 5].to_bytes(8, "little") for i in range(4))
    return out


def hx(b: bytes) -> str:
    return "0x" + b.hex()


# ---------------------------------------------------------------- RFC 8785 JCS (subset: no floats)
def jcs(v) -> str:
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        if abs(v) > 2 ** 53 - 1:
            raise ValueError("integer outside the I-JSON range; the draft uses decimal strings")
        return str(v)
    if isinstance(v, float):
        raise ValueError("floats are not used by these vectors")
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)  # same escapes as ECMAScript JSON.stringify
    if isinstance(v, list):
        return "[" + ",".join(jcs(x) for x in v) + "]"
    if isinstance(v, dict):
        keys = sorted(v.keys(), key=lambda k: k.encode("utf-16-be"))  # UTF-16 code unit order
        return "{" + ",".join(jcs(k) + ":" + jcs(v[k]) for k in keys) + "}"
    raise TypeError(type(v))


def digest(v) -> str:
    return hx(keccak256(jcs(v).encode("utf-8")))


# ---------------------------------------------------------------- address encodings
_B32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_B32M = 0x2BC830A3


def _polymod(values):
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= gen[i] if ((top >> i) & 1) else 0
    return chk


def _hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def _convertbits(data, frombits, tobits, pad):
    acc, bits, ret, maxv = 0, 0, [], (1 << tobits) - 1
    for v in data:
        acc = (acc << frombits) | v
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad and bits:
        ret.append((acc << (tobits - bits)) & maxv)
    elif not pad and (bits >= frombits or ((acc << (tobits - bits)) & maxv)):
        return None
    return ret


def segwit_encode(hrp, ver, prog):
    data = [ver] + _convertbits(prog, 8, 5, True)
    const = 1 if ver == 0 else _B32M
    pm = _polymod(_hrp_expand(hrp) + data + [0] * 6) ^ const
    return hrp + "1" + "".join(_B32[d] for d in data + [(pm >> 5 * (5 - i)) & 31 for i in range(6)])


def segwit_valid(addr: str) -> bool:
    """BIP-173 / BIP-350 segwit address check. Single case only, as BIP-173 requires."""
    if addr != addr.lower() and addr != addr.upper():
        return False
    a = addr.lower()
    pos = a.rfind("1")
    if pos < 1 or pos + 7 > len(a) or len(a) > 90:
        return False
    hrp, rest = a[:pos], a[pos + 1:]
    if any(c not in _B32 for c in rest):
        return False
    data = [_B32.find(c) for c in rest]
    const = _polymod(_hrp_expand(hrp) + data)
    if const not in (1, _B32M):
        return False
    ver, prog = data[0], _convertbits(data[1:-6], 5, 8, False)
    if prog is None or ver > 16 or not 2 <= len(prog) <= 40:
        return False
    if ver == 0 and (len(prog) not in (20, 32) or const != 1):
        return False
    if ver != 0 and const != _B32M:
        return False
    return True


_B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58encode(b: bytes) -> str:
    n = int.from_bytes(b, "big")
    s = ""
    while n:
        n, r = divmod(n, 58)
        s = _B58[r] + s
    return "1" * (len(b) - len(b.lstrip(b"\x00"))) + s


def b58decode(s: str):
    if not s or any(c not in _B58 for c in s):
        return None
    n = 0
    for c in s:
        n = n * 58 + _B58.index(c)
    body = n.to_bytes((n.bit_length() + 7) // 8, "big") if n else b""
    return b"\x00" * (len(s) - len(s.lstrip("1"))) + body


def b58check_encode(payload: bytes) -> str:
    return b58encode(payload + hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4])


def b58check_valid(s: str) -> bool:
    raw = b58decode(s)
    if raw is None or len(raw) < 5:
        return False
    return hashlib.sha256(hashlib.sha256(raw[:-4]).digest()).digest()[:4] == raw[-4:]


def eip55(addr: str) -> str:
    a = addr.lower()[2:]
    h = keccak256(a.encode()).hex()
    return "0x" + "".join(c.upper() if int(h[i], 16) >= 8 else c for i, c in enumerate(a))


# ---------------------------------------------------------------- CAIP-10 and the draft's normalization
_CAIP10 = re.compile(r"([-a-z0-9]{3,8}):([-_a-zA-Z0-9]{1,32}|\*):([-.%a-zA-Z0-9]{1,128})")


def bip122_encoding(addr: str) -> str:
    """d21f46e: inside bip122 an address is bech32 when it is a valid BIP-173 or BIP-350 address, base58 otherwise."""
    return "bech32" if segwit_valid(addr) else "base58"


def normalize_account(account: str, allow_wildcard=True):
    """Returns {"ok": True, "account", "encoding"} or {"ok": False, "error"}.

    Spec (9abaacf): EVM (eip155) lowercase hex, bech32 lowercase, base58 as written. An account that is not
    valid CAIP-10 for its namespace makes a list non-conforming: a mixed-case EVM address that is not a valid
    EIP-55 checksum, a mixed-case bech32 address, an eip155 chain reference with a leading zero.
    Spec (d21f46e): inside bip122, bech32 when a valid BIP-173/350 address, base58 otherwise; namespaces other
    than eip155, bip122 and solana are compared exactly as written unless their CAIP-10 profile defines a
    normalization (this implementation knows of none, so it keeps them as written).
    Reference choices (README): a bip122 string that is classified base58 but is not valid base58check (for
    example a bech32 address with a bad checksum) is treated as not valid, so the list does not conform.
    """
    if not isinstance(account, str):
        return {"ok": False, "error": "not a string"}
    m = _CAIP10.fullmatch(account)
    if not m:
        return {"ok": False, "error": "not CAIP-10"}
    ns, ref, addr = m.groups()
    if ref == "*" and not allow_wildcard:
        return {"ok": False, "error": "wildcard chain reference outside a list entry"}
    if ns == "eip155":
        if re.fullmatch(r"0[0-9]+", ref):
            return {"ok": False, "error": "eip155 chain reference with a leading zero"}
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", addr):
            return {"ok": False, "error": "eip155 address is not 0x + 40 hex"}
        hexpart = addr[2:]
        if hexpart != hexpart.lower() and hexpart != hexpart.upper() and eip55(addr) != addr:
            return {"ok": False, "error": "mixed-case EVM address that is not a valid EIP-55 checksum"}
        return {"ok": True, "account": f"{ns}:{ref}:{addr.lower()}", "encoding": "hex"}
    if ns == "bip122":
        if bip122_encoding(addr) == "bech32":
            return {"ok": True, "account": f"{ns}:{ref}:{addr.lower()}", "encoding": "bech32"}
        if addr != addr.lower() and addr != addr.upper() and segwit_valid(addr.lower()):
            return {"ok": False, "error": "mixed-case bech32 (BIP-173 forbids it)"}
        if b58check_valid(addr):
            return {"ok": True, "account": account, "encoding": "base58"}
        return {"ok": False, "error": "classified base58 (d21f46e) but not valid base58check (reference choice)"}
    if ns == "solana":
        raw = b58decode(addr)
        if raw is None or len(raw) != 32:
            return {"ok": False, "error": "solana address is not base58 of 32 bytes"}
        return {"ok": True, "account": account, "encoding": "base58"}
    # d21f46e: other namespaces compared exactly as written (no CAIP-10 profile normalization is applied here)
    return {"ok": True, "account": account, "encoding": "as-written"}


def canonical_list(doc):
    """Normalize, sort and dedupe entries. Returns (document, None) or (None, error)."""
    out = dict(doc)
    by_acct = {}
    for e in doc.get("entries", []):
        n = normalize_account(e.get("account"))
        if not n["ok"]:
            return None, f"entry {e.get('account')!r}: {n['error']}"
        ne = dict(e)
        ne["account"] = n["account"]
        prev = by_acct.get(ne["account"])
        if prev is not None and jcs(prev) != jcs(ne):
            return None, f"duplicate account {ne['account']} with different entry content"
        by_acct[ne["account"]] = ne
    out["entries"] = [by_acct[k] for k in sorted(by_acct)]  # Python str order = code point order
    return out, None


def list_hash(doc):
    c, err = canonical_list(doc)
    return (None, err) if err else (digest(c), None)


def conforms(doc):
    if doc.get("version") != "erc-presign-list/1":
        return False, "version is not erc-presign-list/1"
    for f in ("source", "criteria"):
        if not isinstance(doc.get(f), str):
            return False, f"missing {f}"
    if "attestation" not in doc:
        for e in doc.get("entries", []):
            if not e.get("evidence"):
                return False, f"entry {e['account']} has no evidence and the list has no attestation"
    c, err = canonical_list(doc)
    if err:
        return False, err
    return True, None


def match_value(doc, address):
    """The entry `value` names: the exact chain reference wins over `*` (9abaacf); None when nothing matches,
    including against a list with no entries (d21f46e)."""
    m = matches(doc, address)
    if not m:
        return None
    exact = [e for e in m if e["account"].split(":")[1] != "*"]
    return (exact or m)[0]


def matches(doc, address):
    """Entries of the canonical list that match a concrete CAIP-10 address."""
    c, err = canonical_list(doc)
    if err:
        raise ValueError(err)
    n = normalize_account(address, allow_wildcard=False)
    if not n["ok"]:
        raise ValueError(n["error"])
    ns, ref, a = n["account"].split(":")
    out = []
    for e in c["entries"]:
        ens, eref, ea = e["account"].split(":")
        if ens == ns and (eref == ref or eref == "*") and ea == a:
            out.append(e)
    return out


KIND = "erc.presign.address.on-list"


def on_list_findings(scenario):
    """Builds the on-list findings for one scenario (status, value or reason only; no evidence or `at`)."""
    lists = scenario["lists"]  # uri -> {"published": doc} | {"fetch": "fails"} | {"source-reads": False}
    out = []
    for i, ent in enumerate(scenario["entities"]):
        for p in scenario["params"]:
            f = {"kind": KIND, "entity": {"address": ent, "role": "recipient"}, "param": p}
            l = lists.get(p["uri"], {"source-reads": False})
            if l.get("source-reads") is False:
                f.update(status="not-read", reason="unsupported")
            elif l.get("fetch") == "fails":
                f.update(status="not-read", reason="unavailable")
            else:
                h, err = list_hash(l["published"])
                if err or h != p["hash"] or not conforms(l["published"])[0]:
                    # fetch failed, normalized digest differs, or the list does not conform (9abaacf)
                    f.update(status="not-read", reason="unavailable")
                else:
                    f.update(status="read", value=match_value(l["published"], ent))
            out.append(f)
    return out


def diff(a, b):
    ca, ea = canonical_list(a)
    cb, eb = canonical_list(b)
    if ea or eb:
        raise ValueError(ea or eb)
    ma = {e["account"]: e for e in ca["entries"]}
    mb = {e["account"]: e for e in cb["entries"]}
    meta = sorted(k for k in set(ca) | set(cb) if k != "entries" and jcs(ca.get(k)) != jcs(cb.get(k)))
    return {
        "fromHash": digest(ca),
        "toHash": digest(cb),
        "sameHash": digest(ca) == digest(cb),
        "added": sorted(set(mb) - set(ma)),
        "removed": sorted(set(ma) - set(mb)),
        "changed": sorted(k for k in set(ma) & set(mb) if jcs(ma[k]) != jcs(mb[k])),
        "metadataChanged": meta,
    }


# ---------------------------------------------------------------- fixtures
FBI_URL = "https://www.fbi.gov/investigate/cyber/alerts/2026/north-korea-responsible-for-6-billion-binance-attack"
FBI_CRITERIA = ("The following addresses are holding or have held assets from the theft, and are operated by or "
                "closely connected to North Korean TraderTraitor actors")
FBI_ATTESTATION = ("FBI, USSS, and IRS-CI are urging private sector entities including THORNode operators, RPC node "
                   "operators, instant exchanges, DeFi services, blockchain analytics firms, and other virtual asset "
                   "service providers to block transactions with or derived from addresses TraderTraitor actors are "
                   "using to launder these stolen assets. See the full list of addresses below.")
BTC = "bip122:000000000019d6689c085ae165831e93"      # CAIP-2 Bitcoin mainnet
SOL = "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"      # CAIP-2 Solana mainnet

OTHER_NS = "xmpl:testnet"   # hypothetical CAIP-2 namespace with no CAIP-10 profile, so no normalization is defined
OTHER_ADDR = "AbCdEf0123XyZ"

FBI_EVM = "0x8532FA14ACAf483729C449b8458aedDb900543D4"   # first ETH address of the FBI alert (EIP-55 as published)
FBI_BTC = "bc1qxrxujwxfnvz040jw76d26zhjdg5jura7hs968s"
FBI_SOL = "AffzFDKZbyMiU11zmVBoAqD25ugpr7xoWWyRyGigBEaU"


def _seed(tag, n=32):
    return keccak256(f"erc-8481 on-list vector {tag}".encode())[:n]


def synth_evm(i):
    return eip55(hx(_seed(f"evm {i}")[12:32]))


def synth_p2wpkh(i):
    return segwit_encode("bc", 0, _seed(f"p2wpkh {i}", 20))


def synth_p2tr(i):
    return segwit_encode("bc", 1, _seed(f"p2tr {i}", 32))


def synth_p2pkh(i):
    return b58check_encode(b"\x00" + _seed(f"p2pkh {i}", 20))


def synth_p2sh(i):
    return b58check_encode(b"\x05" + _seed(f"p2sh {i}", 20))


def segwit_encode_const(hrp, ver, prog, const):
    """Like segwit_encode, but with the checksum constant chosen by the caller (1 = bech32, _B32M = bech32m)."""
    data = [ver] + _convertbits(prog, 8, 5, True)
    pm = _polymod(_hrp_expand(hrp) + data + [0] * 6) ^ const
    return hrp + "1" + "".join(_B32[d] for d in data + [(pm >> 5 * (5 - i)) & 31 for i in range(6)])


def synth_sol(i):
    return b58encode(_seed(f"sol {i}", 32))


def swap_one_case(s):
    """Swap the case of the first letter whose swapped form is still in the base58 alphabet."""
    for i, c in enumerate(s):
        if c.isalpha() and c.swapcase() in _B58 and c.swapcase() != c:
            t = s[:i] + c.swapcase() + s[i + 1:]
            if len(b58decode(t)) == len(b58decode(s)):  # still a valid address of the same length
                return t
    raise ValueError(s)


def bad_eip55(a):
    """Swap the case of the first hex letter of an EIP-55 address: still mixed case, checksum no longer valid."""
    for i, c in enumerate(a[2:], 2):
        if c.isalpha():
            t = a[:i] + c.swapcase() + a[i + 1:]
            assert eip55(t) != t
            return t
    raise ValueError(a)


def mixed_case(s):
    """Upper-case every other letter after the prefix (an invalid mixed-case bech32 string)."""
    out, flip = [], False
    for c in s:
        if c.isalpha():
            flip = not flip
            out.append(c.upper() if flip else c)
        else:
            out.append(c)
    return "".join(out)


def synth_list(accounts, **kw):
    d = {"version": "erc-presign-list/1", "source": "https://example.org/upstream/synthetic-list",
         "criteria": "Synthetic addresses for test vectors; not a real list.",
         "attestation": "Synthetic attestation covering every entry.", "entries": [{"account": a} for a in accounts]}
    d.update(kw)
    return d


def fbi_list():
    """The FBI alert of 31 Oct 2026 as one attested list document, in the alert's own order and case."""
    rows = open(os.path.join(HERE, "fbi-tradertraitor-2026-10-31.published.txt")).read().split("\n")
    entries = []
    for r in rows:
        if not r.strip():
            continue
        chain, addr = r.split(" ")
        pre = {"evm": "eip155:*", "btc": BTC, "sol": SOL}[chain]
        entries.append({"account": f"{pre}:{addr}"})
    return {"version": "erc-presign-list/1", "source": FBI_URL, "criteria": FBI_CRITERIA,
            "attestation": FBI_ATTESTATION, "entries": entries}


# ---------------------------------------------------------------- vector builders
def build_normalize():
    e1, e2 = synth_evm(1), synth_evm(2)
    cases = [
        ("evm-eip55-to-lower", f"eip155:1:{FBI_EVM}", "spec", "EIP-55 checksummed input, FBI alert address"),
        ("evm-already-lower", f"eip155:1:{FBI_EVM.lower()}", "spec", "already normalized"),
        ("evm-upper-hex", f"eip155:1:0x{FBI_EVM[2:].upper()}", "spec", "all upper-case hex digits"),
        ("evm-wildcard-chain", f"eip155:*:{FBI_EVM}", "spec", "chain reference * kept, address lowercased"),
        ("evm-synthetic-eip55", f"eip155:8453:{e1}", "spec", "synthetic address, EIP-55 form"),
        ("evm-synthetic-wildcard", f"eip155:*:{e2}", "spec", "synthetic address, wildcard"),
        ("bech32-upper-to-lower", f"{BTC}:{FBI_BTC.upper()}", "spec", "bech32 upper-case, FBI alert address"),
        ("bech32-lower", f"{BTC}:{FBI_BTC}", "spec", "bech32 already lower"),
        ("bech32m-taproot-upper", f"{BTC}:{synth_p2tr(1).upper()}", "spec", "synthetic bech32m (witness v1)"),
        ("base58-btc-legacy", f"{BTC}:{synth_p2pkh(1)}", "spec", "base58check kept as written"),
        ("base58-solana", f"{SOL}:{FBI_SOL}", "spec", "Solana base58 kept as written, FBI alert address"),
        ("base58-solana-synthetic", f"{SOL}:{synth_sol(1)}", "spec", "synthetic Solana address"),
        ("reject-leading-space", f" eip155:1:{FBI_EVM}", "spec", "CAIP-10 has no whitespace"),
        ("reject-trailing-newline", f"eip155:1:{FBI_EVM}\n", "spec", "CAIP-10 has no whitespace"),
        ("reject-upper-namespace", f"EIP155:1:{FBI_EVM}", "spec", "CAIP-2 namespace is [-a-z0-9]{3,8}"),
        ("reject-bare-address", FBI_EVM, "spec", "entries are CAIP-10, not bare addresses"),
        ("reject-short-hex", f"eip155:1:{FBI_EVM[:-1]}", "reference", "39 hex digits"),
        ("reject-mixed-case-bech32", f"{BTC}:{mixed_case(FBI_BTC)}", "spec",
         "BIP-173 forbids mixed case; the list does not conform (9abaacf)"),
        ("reject-bad-bech32-checksum", f"{BTC}:{FBI_BTC[:-1]}{'q' if FBI_BTC[-1] != 'q' else 'p'}", "reference",
         "last character changed: base58 by the d21f46e rule, but not valid base58check, so treated as not valid "
         "(our call, see README open question)"),
        ("reject-evm-bad-checksum", f"eip155:1:{bad_eip55(FBI_EVM)}",
         "spec", "mixed case that is not a valid EIP-55 checksum: the list does not conform (9abaacf; was open Q2)"),
        ("reject-evm-0X-prefix", f"eip155:1:0X{FBI_EVM[2:]}", "spec",
         "upper-case 0X prefix is not a valid CAIP-10 eip155 address (9abaacf; was open Q2)"),
        ("reject-chain-ref-leading-zero", f"eip155:01:{FBI_EVM}", "spec",
         "eip155 chain reference with a leading zero: the list does not conform (9abaacf; was open Q4)"),
        ("base58-btc-p2sh", f"{BTC}:{synth_p2sh(1)}", "spec",
         "not a valid BIP-173/350 address, so base58, kept as written (d21f46e)"),
        ("other-namespace-as-written", f"{OTHER_NS}:{OTHER_ADDR}", "spec",
         "a namespace other than eip155, bip122 and solana: kept exactly as written, case included (d21f46e)"),
        ("other-namespace-lower-variant", f"{OTHER_NS}:{OTHER_ADDR.lower()}", "spec",
         "the lowercase variant is also kept as written: a different account (d21f46e)"),
    ]
    vec = []
    for cid, inp, basis, note in cases:
        r = normalize_account(inp)
        exp = {"ok": True, "account": r["account"], "encoding": r["encoding"]} if r["ok"] else {"ok": False}
        vec.append({"id": cid, "basis": basis, "note": note, "input": inp, "expected": exp})
    p2wpkh, p2tr = synth_p2wpkh(1), synth_p2tr(1)
    prog32 = _seed("p2tr 1", 32)
    v1_bech32 = segwit_encode_const("bc", 1, prog32, 1)
    v0_bech32m = segwit_encode_const("bc", 0, _seed("p2wpkh 1", 20), _B32M)
    bad_ck = f"{FBI_BTC[:-1]}{'q' if FBI_BTC[-1] != 'q' else 'p'}"
    cls = [
        ("bech32-p2wpkh-lower", FBI_BTC, "valid BIP-173 (witness v0, bech32 checksum)"),
        ("bech32-p2wpkh-upper", FBI_BTC.upper(), "all upper case is valid BIP-173, so bech32 (normalized to lowercase)"),
        ("bech32-synthetic-p2wpkh", p2wpkh, "valid BIP-173"),
        ("bech32m-p2tr", p2tr, "valid BIP-350 (witness v1, bech32m checksum)"),
        ("base58-p2pkh", synth_p2pkh(1), "not BIP-173/350: base58"),
        ("base58-p2sh", synth_p2sh(1), "not BIP-173/350: base58"),
        ("bad-bech32-checksum-is-base58", bad_ck,
         "last character changed: not a valid BIP-173 address, so base58 by the text. It is not valid base58check "
         "either; whether the list conforms is a reference choice (normalize.json reject-bad-bech32-checksum)"),
        ("v1-with-bech32-checksum-is-base58", v1_bech32,
         "witness v1 with the BIP-173 checksum: BIP-350 makes it invalid, so base58 by the text"),
        ("v0-with-bech32m-checksum-is-base58", v0_bech32m,
         "witness v0 with the BIP-350 checksum: invalid, so base58 by the text"),
        ("mixed-case-bech32-is-base58", mixed_case(FBI_BTC),
         "mixed case is not valid BIP-173, so the encoding rule gives base58; the list still does not conform, "
         "since a mixed-case bech32 account is named as invalid (9abaacf, normalize.json reject-mixed-case-bech32)"),
    ]
    classification = [{"id": cid, "basis": "spec", "note": note, "namespace": "bip122", "address": a,
                       "expected": {"encoding": bip122_encoding(a)}} for cid, a, note in cls]
    assert [c["expected"]["encoding"] for c in classification] == ["bech32"] * 4 + ["base58"] * 6
    return {"description": "account normalization (draft: EVM lowercase hex, bech32 lowercase, base58 as written, "
                           "other namespaces as written) and the bip122 encoding rule of d21f46e",
            "vectors": vec, "classification": classification, "open": []}


def build_list_hash():
    e1, e2, e3 = synth_evm(1), synth_evm(2), synth_evm(3)
    sol = synth_sol(1)
    vec = []

    def add(cid, basis, note, docs, same):
        hashes, canon = [], []
        for d in docs:
            c, err = canonical_list(d)
            hashes.append(digest(c))
            canon.append(jcs(c))
        assert (len(set(hashes)) == 1) == same, cid
        v = {"id": cid, "basis": basis, "note": note, "documents": docs,
             "expected": {"hashes": hashes, "sameHash": same}}
        if all(len(x) < 2000 for x in canon):
            v["expected"]["canonical"] = canon
        vec.append(v)

    # the draft's own test case (Test Cases: "eip155:*:0xAbC... and eip155:*:0xabc...")
    add("spec-case-duplicate-case-variants", "spec", "two case variants of one address hash as the single lowercase entry",
        [synth_list([f"eip155:*:{e1}", f"eip155:*:{e1.lower()}"]), synth_list([f"eip155:*:{e1.lower()}"])], True)
    add("order-independent", "spec", "entries sorted by account (code points) before hashing",
        [synth_list([f"eip155:*:{e1}", f"eip155:*:{e2}", f"eip155:*:{e3}"]),
         synth_list([f"eip155:*:{e3}", f"eip155:*:{e1}", f"eip155:*:{e2}"])], True)
    add("sort-wildcard-before-digits", "spec", "'*' (U+002A) sorts before '1' (U+0031); both entries are kept",
        [synth_list([f"eip155:1:{e1}", f"eip155:*:{e1}"]), synth_list([f"eip155:*:{e1}", f"eip155:1:{e1}"])], True)
    add("chain-scope-changes-hash", "spec", "eip155:1 and eip155:* are different accounts",
        [synth_list([f"eip155:1:{e1}"]), synth_list([f"eip155:*:{e1}"])], False)
    add("bech32-case-same-hash", "spec", "bech32 upper and lower hash the same",
        [synth_list([f"{BTC}:{FBI_BTC.upper()}"]), synth_list([f"{BTC}:{FBI_BTC}"])], True)
    add("base58-case-different-hash", "spec", "base58 is exact: one swapped letter is a different account",
        [synth_list([f"{SOL}:{sol}"]), synth_list([f"{SOL}:{swap_one_case(sol)}"])], False)
    add("attestation-is-hashed", "spec", "adding or removing attestation changes the hash",
        [synth_list([f"eip155:*:{e1}"]),
         {k: v for k, v in synth_list([f"eip155:*:{e1}"], entries=[{"account": f"eip155:*:{e1}", "evidence": [
             {"type": "tx", "chainId": "eip155:1", "hash": hx(_seed("tx 1"))}]}]).items() if k != "attestation"}],
        False)
    add("two-sources-same-upstream", "spec",
        "two sources pin the same upstream list at different times: retrieval time is not in the document, so the "
        "hash is the same (retrievedAt goes in the finding's document evidence, see match.json)",
        [synth_list([f"eip155:*:{e2}", f"eip155:*:{e1}"]), synth_list([f"eip155:*:{e1.lower()}", f"eip155:*:{e2}"])],
        True)
    add("retrieval-time-inside-document", "spec",
        "extra top-level fields are allowed, are part of the hash and are ignored by readers (9abaacf), so a "
        "document that carries retrievedAt hashes differently, which is why the draft keeps it out",
        [synth_list([f"eip155:*:{e1}"]), synth_list([f"eip155:*:{e1}"], retrievedAt="2026-11-01T15:50:13Z")], False)

    # published bytes vs canonical bytes (Q1)
    d = synth_list([f"eip155:*:{e1.lower()}"])
    pretty = json.dumps(d, indent=2)
    compact = json.dumps(d, separators=(",", ":"))
    vec.append({"id": "published-bytes-vs-jcs", "basis": "spec",
                "note": "hash is digest() of the normalized form over the parsed JSON value, so whitespace and key "
                        "order in the published bytes do not matter; keccak256 of the raw bytes differs (9abaacf)",
                "publishedBytes": [pretty, compact],
                "expected": {"digest": digest(json.loads(pretty)),
                             "rawKeccak": [hx(keccak256(pretty.encode())), hx(keccak256(compact.encode()))]}})

    fbi = fbi_list()
    c, err = canonical_list(fbi)
    assert not err, err
    counts = {}
    for e in c["entries"]:
        counts[e["account"].split(":")[0]] = counts.get(e["account"].split(":")[0], 0) + 1
    vec.append({"id": "fbi-tradertraitor-2026-10-31", "basis": "spec",
                "note": "the FBI alert of 31 Oct 2026 as one attested list (ETH addresses as eip155:*). "
                        "published order and case in fbi-tradertraitor-2026-10-31.published.txt; canonical document "
                        "in fbi-tradertraitor-2026-10-31.list.json",
                "expected": {"hash": digest(c), "entries": len(c["entries"]), "byNamespace": counts,
                             "conforms": conforms(fbi)[0]}})
    dup = synth_list([], entries=[
        {"account": f"eip155:*:{e1}", "evidence": [{"type": "tx", "chainId": "eip155:1", "hash": hx(_seed('tx 1'))}]},
        {"account": f"eip155:*:{e1.lower()}", "evidence": [{"type": "tx", "chainId": "eip155:1", "hash": hx(_seed('tx 2'))}]}])
    c, err = canonical_list(dup)
    vec.append({"id": "duplicate-different-evidence-nonconforming", "basis": "spec",
                "note": "one account twice with different content: the list does not conform and has no hash a "
                        "reader can use (9abaacf; was open Q5)",
                "documents": [dup], "expected": {"conforms": conforms(dup)[0], "hash": None if err else digest(c)}})
    add("other-namespace-case-different-hash", "spec",
        "a namespace other than eip155, bip122 and solana is compared as written: a case variant is a different "
        "account (d21f46e)",
        [synth_list([f"{OTHER_NS}:{OTHER_ADDR}"]), synth_list([f"{OTHER_NS}:{OTHER_ADDR.lower()}"])], False)
    both = synth_list([f"{OTHER_NS}:{OTHER_ADDR.lower()}", f"{OTHER_NS}:{OTHER_ADDR}"])
    c, err = canonical_list(both)
    assert not err and len(c["entries"]) == 2
    vec.append({"id": "other-namespace-case-variants-both-kept", "basis": "spec",
                "note": "both case variants are kept as two entries, not merged, and the list conforms (d21f46e)",
                "documents": [both], "expected": {"conforms": conforms(both)[0], "entries": len(c["entries"]),
                                                  "hash": digest(c), "canonical": jcs(c)}})
    empty = synth_list([])
    vec.append({"id": "empty-entries", "basis": "spec",
                "note": "a list with no entries conforms; on-list against it reads null for every address "
                        "(d21f46e; was open Q7, see match.json empty-list-reads-null)",
                "documents": [empty], "expected": {"conforms": conforms(empty)[0], "hash": list_hash(empty)[0]}})
    return {"description": "list document hash: hash = keccak256(JCS(document)) after entries are normalized, "
                           "sorted by account and deduplicated", "vectors": vec, "open": []}


def build_match():
    e1, e2 = synth_evm(1), synth_evm(2)
    sol = synth_sol(1)
    L = synth_list([f"eip155:*:{e1}", f"eip155:1:{e2}", f"{BTC}:{FBI_BTC}", f"{SOL}:{sol}"])
    vec = []
    cases = [
        ("wildcard-matches-any-evm-chain", f"eip155:4663:{e1.upper().replace('0X', '0x')}", "spec",
         "the draft's case: eip155:4663:0xABC... matches eip155:*:0xabc..."),
        ("wildcard-matches-base", f"eip155:8453:{e1}", "spec", "EIP-55 candidate, wildcard entry"),
        ("exact-chain-matches", f"eip155:1:{e2.lower()}", "spec", "same chain reference"),
        ("other-chain-no-match", f"eip155:10:{e2}", "spec", "entry is eip155:1 only"),
        ("bech32-upper-candidate", f"{BTC}:{FBI_BTC.upper()}", "spec", "bech32 compared lowercase"),
        ("base58-exact", f"{SOL}:{sol}", "spec", "base58 exact"),
        ("base58-case-swapped", f"{SOL}:{swap_one_case(sol)}", "spec", "one letter's case differs: no match"),
        ("not-on-list", f"eip155:1:{synth_evm(9)}", "spec", "value is null, not false"),
        ("namespace-must-equal", f"{BTC}:{synth_p2wpkh(1)}", "spec", "other bip122 address: null"),
    ]
    for cid, cand, basis, note in cases:
        vec.append({"id": cid, "basis": basis, "note": note, "list": "L", "candidate": cand,
                    "expected": {"value": match_value(L, cand)}})
    L2 = synth_list([f"eip155:*:{e1}", f"eip155:1:{e1}"])
    L3 = synth_list([f"{OTHER_NS}:{OTHER_ADDR}", f"eip155:*:{e1}"])
    for cid, cand, note in [
            ("other-namespace-exact", f"{OTHER_NS}:{OTHER_ADDR}",
             "a namespace other than eip155, bip122 and solana, same string: match (d21f46e)"),
            ("other-namespace-case-differs", f"{OTHER_NS}:{OTHER_ADDR.lower()}",
             "same namespace, case differs: compared exactly as written, no match (d21f46e)"),
            ("other-namespace-upper-differs", f"{OTHER_NS}:{OTHER_ADDR.upper()}",
             "all upper case: also no match, there is no case folding outside eip155 and bech32 (d21f46e)"),
            ("other-namespace-other-chain", f"xmpl:mainnet:{OTHER_ADDR}",
             "same address, other chain reference, entry is not *: no match")]:
        vec.append({"id": cid, "basis": "spec", "note": note, "list": "L3", "candidate": cand,
                    "expected": {"value": match_value(L3, cand)}})
    for cid, cand, note in [
            ("two-entries-exact-chain-wins", f"eip155:1:{e1}",
             "eip155:1:X and eip155:*:X both match: value is the exact chain reference entry (9abaacf; was open Q5)"),
            ("two-entries-other-chain-wildcard", f"eip155:10:{e1}", "only eip155:*:X matches on another chain")]:
        vec.append({"id": cid, "basis": "spec", "note": note, "list": "L2", "candidate": cand,
                    "expected": {"value": match_value(L2, cand)}})
    h, _ = list_hash(L)
    uri = "https://example.org/lists/L.json"
    uri_x = "https://example.org/lists/consumer-choice.json"
    bad = synth_list([f"eip155:*:{e1}"])
    noatt = {k: v for k, v in synth_list([f"eip155:*:{e1}"]).items() if k != "attestation"}
    h_noatt, _ = list_hash(noatt)
    uri_n = "https://example.org/lists/no-attestation.json"
    extra = dict(L, publisherNote="extra top-level field")
    h_extra, _ = list_hash(extra)
    uri_e = "https://example.org/lists/L-extra.json"
    empty = synth_list([])
    h_empty, _ = list_hash(empty)
    uri_0 = "https://example.org/lists/empty.json"
    findings = [
        {"id": "read-value-and-null", "basis": "spec",
         "scenario": {"entities": [f"eip155:42161:{e1}", f"eip155:42161:{synth_evm(9)}"],
                      "params": [{"uri": uri, "hash": h}], "lists": {uri: {"published": L}}}},
        {"id": "hash-mismatch-unavailable", "basis": "spec",
         "scenario": {"entities": [f"eip155:1:{e1}"], "params": [{"uri": uri, "hash": h}],
                      "lists": {uri: {"published": bad}}}},
        {"id": "fetch-failed-unavailable", "basis": "spec",
         "scenario": {"entities": [f"eip155:1:{e1}"], "params": [{"uri": uri, "hash": h}],
                      "lists": {uri: {"fetch": "fails"}}}},
        {"id": "consumer-list-unsupported", "basis": "spec",
         "note": "kinds holds { kind: on-list, param: { uri, hash } } for a list the source will not read: not read "
                 "/ unsupported for each address, and no finding with a param of the source's own",
         "request": {"kinds": [{"kind": KIND, "param": {"uri": uri_x, "hash": h}}]},
         "scenario": {"entities": [f"eip155:1:{e1}", f"eip155:1:{e2}"], "params": [{"uri": uri_x, "hash": h}],
                      "lists": {uri_x: {"source-reads": False}, uri: {"published": L}}}},
        {"id": "nonconforming-hash-match-unavailable", "basis": "spec",
         "note": "the normalized digest matches hash, but the list has no attestation and an entry without "
                 "evidence: not read / unavailable (9abaacf; was open Q7)",
         "scenario": {"entities": [f"eip155:1:{e1}"], "params": [{"uri": uri_n, "hash": h_noatt}],
                      "lists": {uri_n: {"published": noatt}}}},
        {"id": "extra-top-level-field-ignored", "basis": "spec",
         "note": "an extra top-level field is hashed (h_extra differs from L_hash) and ignored: same value as L",
         "scenario": {"entities": [f"eip155:42161:{e1}"], "params": [{"uri": uri_e, "hash": h_extra}],
                      "lists": {uri_e: {"published": extra}}}},
        {"id": "empty-list-reads-null", "basis": "spec",
         "note": "a list with no entries conforms; on-list against it reads null for every address (d21f46e)",
         "scenario": {"entities": [f"eip155:1:{e1}", f"{BTC}:{FBI_BTC}", f"{SOL}:{sol}", f"{OTHER_NS}:{OTHER_ADDR}"],
                      "params": [{"uri": uri_0, "hash": h_empty}], "lists": {uri_0: {"published": empty}}}},
    ]
    for f in findings:
        f["expected"] = on_list_findings(f["scenario"])
    assert all(x["status"] == "read" and x["value"] is None for x in findings[-1]["expected"])
    conf = []
    part = dict(noatt, entries=[{"account": f"eip155:*:{e1}", "evidence": [
        {"type": "tx", "chainId": "eip155:1", "hash": hx(_seed("tx 1"))}]}, {"account": f"eip155:*:{e2}"}])
    for cid, doc, note in [("attested-no-evidence-conforms", synth_list([f"eip155:*:{e1}"]), "draft test case"),
                           ("no-attestation-no-evidence-fails", noatt, "draft test case"),
                           ("no-attestation-partial-evidence-fails", part, "one entry without evidence"),
                           ("extra-top-level-field-conforms", extra, "extra top-level fields are allowed (9abaacf)"),
                           ("empty-list-conforms", empty, "a list with no entries conforms (d21f46e)"),
                           ("empty-list-without-attestation-conforms",
                            {k: v for k, v in empty.items() if k != "attestation"},
                            "no entries, so no entry lacks evidence; conforms (d21f46e)"),
                           ("bad-eip55-entry-fails", synth_list([f"eip155:*:{bad_eip55(e1)}"]),
                            "an entry with a mixed-case EVM address that is not a valid EIP-55 checksum (9abaacf)")]:
        ok, why = conforms(doc)
        conf.append({"id": cid, "basis": "spec", "note": note, "document": doc, "expected": {"conforms": ok}})
    document_evidence = build_document_evidence()
    return {"description": "matching, value as the matching entry or null, not-read reasons, conformance",
            "lists": {"L": L, "L_hash": h, "L2": L2, "L2_hash": list_hash(L2)[0], "L3": L3,
                      "L3_hash": list_hash(L3)[0]}, "vectors": vec,
            "findings": findings, "conformance": conf, "documentEvidence": document_evidence, "open": []}


UPSTREAM_URI = "https://example.org/upstream/synthetic-advisory"
UPSTREAM_FETCHES = (("2026-11-01T15:50:13Z", "a1f3"), ("2026-11-03T09:00:00Z", "7c09"))


def upstream_page(retrieved_at, nonce):
    """Synthetic upstream page: the same two addresses, re-rendered with a per-fetch timestamp and nonce."""
    e1, e2 = synth_evm(1), synth_evm(2)
    return ("<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>Synthetic advisory</title>"
            f"<meta name=\"render-nonce\" content=\"{nonce}\"></head>\n<body>\n"
            f"<p>Rendered {retrieved_at}. Synthetic addresses for test vectors; not a real list.</p>\n"
            f"<ul>\n<li>{e1}</li>\n<li>{e2}</li>\n</ul>\n</body></html>\n").encode("utf-8")


def upstream_fixture_name(i):
    return f"upstream-page.fetch{i + 1}.html"


def build_document_evidence():
    """d21f46e: the document evidence hash is keccak256 of the bytes the source read at retrievedAt."""
    e1, e2 = synth_evm(1), synth_evm(2)
    lst = synth_list([f"eip155:*:{e1}", f"eip155:*:{e2}"], source=UPSTREAM_URI)
    h_list, _ = list_hash(lst)
    vec = []
    for i, (t, nonce) in enumerate(UPSTREAM_FETCHES):
        raw = upstream_page(t, nonce)
        vec.append({"id": f"fetch{i + 1}", "basis": "spec",
                    "note": "hash = keccak256 of the raw bytes in the fixture file, as read; no parsing, no "
                            "re-encoding (d21f46e)",
                    "fixture": upstream_fixture_name(i), "bytesLength": len(raw),
                    "expected": {"evidence": {"type": "document", "uri": UPSTREAM_URI, "hash": hx(keccak256(raw)),
                                              "retrievedAt": t},
                                 "notSha3_256": "0x" + hashlib.sha3_256(raw).hexdigest()}})
    raw1 = upstream_page(*UPSTREAM_FETCHES[0])
    crlf = raw1.replace(b"\n", b"\r\n")
    vec.append({"id": "same-text-crlf-different-hash", "basis": "spec",
                "note": "fetch1 with CRLF line endings: the same text, other bytes, so another hash; the hash is "
                        "over bytes as read (d21f46e)",
                "bytesHex": crlf.hex(), "expected": {"hash": hx(keccak256(crlf))}})
    assert len({v["expected"]["evidence"]["hash"] for v in vec[:2]} | {vec[2]["expected"]["hash"]}) == 3
    return {"note": "the upstream publication goes in a document evidence entry of the finding, with retrievedAt. "
                    "Its hash is keccak256 of the bytes the source read and records what was read; a page that "
                    "re-renders on each fetch gives a different hash each time and a third party cannot recompute "
                    "it, which is why the list (one hash for both fetches) is the pinned document (d21f46e).",
            "list": lst, "listHash": h_list, "vectors": vec}


def build_diff():
    E = [synth_evm(i) for i in range(1, 7)]
    v1 = synth_list([f"eip155:*:{E[0]}", f"eip155:*:{E[1]}", f"eip155:*:{E[2]}", f"{BTC}:{synth_p2wpkh(1)}"])
    cases = [
        ("added", synth_list([f"eip155:*:{E[0]}", f"eip155:*:{E[1]}", f"eip155:*:{E[2]}", f"{BTC}:{synth_p2wpkh(1)}",
                              f"eip155:*:{E[3]}", f"{SOL}:{synth_sol(2)}"]), "two entries added"),
        ("removed", synth_list([f"eip155:*:{E[0]}", f"{BTC}:{synth_p2wpkh(1)}"]), "two entries removed"),
        ("added-and-removed", synth_list([f"eip155:*:{E[0]}", f"eip155:*:{E[1]}", f"eip155:*:{E[4]}",
                                          f"{BTC}:{synth_p2wpkh(1)}"]), "one swapped for another, same count"),
        ("recase-and-reorder-only", synth_list([f"{BTC}:{synth_p2wpkh(1).upper()}", f"eip155:*:{E[2].lower()}",
                                                f"eip155:*:{E[0].lower()}", f"eip155:*:{E[1]}"]),
         "same list re-cased and reordered: same hash, empty diff"),
        ("duplicate-added", synth_list([f"eip155:*:{E[0]}", f"eip155:*:{E[0].lower()}", f"eip155:*:{E[1]}",
                                        f"eip155:*:{E[2]}", f"{BTC}:{synth_p2wpkh(1)}"]), "a duplicate is not an addition"),
        ("scope-narrowed", synth_list([f"eip155:1:{E[0]}", f"eip155:*:{E[1]}", f"eip155:*:{E[2]}",
                                       f"{BTC}:{synth_p2wpkh(1)}"]), "eip155:* to eip155:1 is a removal plus an addition"),
        ("criteria-changed", dict(v1, criteria="Synthetic addresses for test vectors, second wording."),
         "same entries, new criteria: hash changes, entry diff empty"),
        ("evidence-added", dict(v1, entries=[{"account": f"eip155:*:{E[0]}", "evidence": [
            {"type": "tx", "chainId": "eip155:1", "hash": hx(_seed("tx 3"))}]}] + v1["entries"][1:]),
         "one entry gains evidence: changed, not added"),
    ]
    vec = []
    for cid, v2, note in cases:
        vec.append({"id": cid, "basis": "reference", "note": note, "from": "v1", "to": v2,
                    "expected": diff(v1, v2)})
    return {"description": "list version diffs: added / removed / changed by normalized account, and the hash "
                           "change. The draft does not define a diff; this format is informative (9abaacf).",
            "v1": v1, "vectors": vec, "open": []}


def primitive_selftest():
    assert hx(keccak256(b"")) == "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    assert hx(keccak256(b"abc")) == "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
    assert hx(keccak256(b"a" * 200)) == hx(keccak256(b"a" * 200))
    for a in ("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
              "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB", "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"):
        assert eip55(a) == a, a  # EIP-55 examples
    assert segwit_valid(FBI_BTC) and segwit_valid(FBI_BTC.upper()) and not segwit_valid(mixed_case(FBI_BTC))
    assert segwit_valid(synth_p2wpkh(1)) and segwit_valid(synth_p2tr(1)) and b58check_valid(synth_p2pkh(1))
    assert len(b58decode(FBI_SOL)) == 32 and b58encode(b58decode(FBI_SOL)) == FBI_SOL
    assert jcs({"b": 1, "a": [True, None, "\u20ac\n"]}) == '{"a":[true,null,"\u20ac\\n"],"b":1}'
    # RFC 8785 3.2.3: keys in UTF-16 code unit order (U+1F600 before U+FB33, unlike code point order)
    assert jcs({"\ufb33": 4, "\u20ac": 1, "\U0001F600": 2, "\r": 3}) == '{"\\r":3,"\u20ac":1,"\U0001F600":2,"\ufb33":4}'


FILES = {"normalize.json": build_normalize, "list-hash.json": build_list_hash, "match.json": build_match,
         "diff.json": build_diff}


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def main():
    write = "--write" in sys.argv[1:]
    primitive_selftest()
    ok = True
    for name, fn in FILES.items():
        text = dump(fn())
        p = os.path.join(HERE, name)
        if write:
            open(p, "w", encoding="utf-8").write(text)
        else:
            cur = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
            if cur != text:
                ok = False
                print(f"FAIL {name}: differs from what this implementation computes")
        d = json.loads(text)
        n = sum(len(d.get(k, [])) for k in ('vectors', 'findings', 'conformance', 'classification'))
        n += len(d.get("documentEvidence", {}).get("vectors", []))
        print(f"{'wrote' if write else 'ok  '} {name}: {n}"
              f" checked, {len(d.get('open', []))} open")
    de = build_document_evidence()
    for i, (t, nonce) in enumerate(UPSTREAM_FETCHES):
        raw = upstream_page(t, nonce)
        p = os.path.join(HERE, upstream_fixture_name(i))
        if write:
            open(p, "wb").write(raw)
        else:
            cur = open(p, "rb").read() if os.path.exists(p) else b""
            if cur != raw or hx(keccak256(cur)) != de["vectors"][i]["expected"]["evidence"]["hash"]:
                ok = False
                print(f"FAIL {upstream_fixture_name(i)}")
        print(("wrote" if write else "ok  ") + f" {upstream_fixture_name(i)}: keccak256 {hx(keccak256(raw))}")
    c, _ = canonical_list(fbi_list())
    p = os.path.join(HERE, "fbi-tradertraitor-2026-10-31.list.json")
    text = jcs(c) + "\n"
    if write:
        open(p, "w", encoding="utf-8").write(text)
    elif open(p, encoding="utf-8").read() != text or digest(json.loads(text)) != digest(c):
        ok = False
        print("FAIL fbi-tradertraitor-2026-10-31.list.json")
    print(("wrote" if write else "ok  ") + f" fbi-tradertraitor-2026-10-31.list.json: hash {digest(c)}")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
