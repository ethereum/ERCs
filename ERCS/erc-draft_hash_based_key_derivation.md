---
eip: XXXX
title: Hash-Based Key Derivation from BIP-39
description: Derives hash-based post-quantum keys from a BIP-39 phrase using hash functions only.
author: Johann Barbie (@johba37)
discussions-to: https://ethereum-magicians.org/t/TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-11-08
---

## Abstract

This ERC specifies how a wallet derives the secret seeds of hash-based post-quantum keys, such as leanSPHINCS, from a BIP-39 recovery phrase. The derivation uses one primitive, HMAC-SHA512: in BIP-39's own PBKDF2, and then in HKDF. It never passes through BIP-32 or any elliptic-curve operation, so a quantum adversary who breaks every ECDSA key made from the same phrase learns nothing about the hash-based keys.

The ERC defines a root secret, a seed for each stateless key, a seed for each instance of a stateful key, and a secret for each application. Stateless keys are restored from the phrase. Stateful keys never are: each instance takes fresh randomness, so a restored wallet cannot reuse one-time keys.

The ERC is independent of the signature scheme and its parameters. A key type string names the scheme, its parameter set and its key generation, so a new parameter set gives a new key from the same phrase.

## Motivation

Hash-based signatures are the most conservative post-quantum option for Ethereum accounts. Accounts can already verify them in contracts through [ERC-1271](./eip-1271.md) and account abstraction, and protocol proposals would aggregate them. Users, however, back up their accounts with [BIP-39](https://github.com/bitcoin/bips/blob/a34f044bb8d5cd684d7a742d2f6483c14b719046/bip-0039.mediawiki) phrases, and no standard says how a phrase becomes a hash-based key.

Implementations have diverged:

- One derives keys from the phrase's BIP-39 entropy, with Keccak-256 over application-specific labels.
- Another derives them through hardened [BIP-32](https://github.com/bitcoin/bips/blob/a34f044bb8d5cd684d7a742d2f6483c14b719046/bip-0032.mediawiki) paths under `m/44'/60'/a'`.
- A third runs BIP-39's PBKDF2 over the phrase a second time, with its own salt in place of `"mnemonic"`.

The same phrase therefore gives different keys in different wallets, and a phrase restored elsewhere does not restore the account.

A standard derivation lets a user:

- restore hash-based keys in any conforming wallet, hardware wallet or recovery tool;
- add hash-based keys to an existing phrase without a new backup;
- move to a new parameter set, for example the one a future protocol upgrade fixes, by deriving a new key from the same phrase.

Derivations through BIP-32 have a further problem. Every BIP-32 node has an elliptic-curve public key. Given an extended public key, a quantum adversary can compute the node's private key, and with its chain code every hardened child. Hardened derivation protects against classical leaks, not quantum ones. Hash-based keys should not depend on any value that an elliptic-curve public key can reveal.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Notation

- `||` is byte concatenation.
- `be16(x)` and `be32(x)` are the 2-byte and 4-byte big-endian encodings of a non-negative integer below `2^16` and `2^32`.
- `len8(b)` is the length of the byte string `b` as one byte. `b` is at most 255 bytes long.
- `ascii(s)` and `utf8(s)` are the ASCII and UTF-8 encodings of a string `s`, without terminator or length prefix.
- `HKDF-Extract(salt, IKM)` and `HKDF-Expand(PRK, info, L)` are the two steps of HKDF as [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869) defines them, with SHA-512 as the hash. `HKDF-Extract` returns 64 bytes, and `HKDF-Expand` returns `L` bytes.

### Root secret

A root secret `R` is 64 bytes:

```
R = HKDF-Extract(salt = ascii("HBKD/v1"), IKM)
```

The input key material `IKM` comes from one of two sources.

**From a BIP-39 phrase.** With mnemonic sentence `M` and BIP-39 passphrase `P` (the empty string if the user sets none):

```
IKM = S = BIP39-Seed(M, P)          64 bytes: PBKDF2-HMAC-SHA512, 2048 iterations, as BIP-39 specifies
```

`M` is the phrase's words exactly as they appear in the BIP-39 wordlist it was made with, separated by single spaces. Wallets MAY support only the English wordlist. A wallet MUST bring what the user types (other letter case, other spacing, abbreviated words) into this form. It MUST reject a mnemonic with a word outside the wordlist or a failed BIP-39 checksum. BIP-39 only asks for a warning, but a mistyped word that passes would restore different keys.

**Random.** For a key holder without a phrase, such as a device that a phrase-derived key certifies, `IKM` is at least 32 bytes from a cryptographically secure random number generator.

A wallet MUST NOT derive `R`, or any value in this ERC, through BIP-32 or any other step that involves elliptic-curve arithmetic.

### Derived values

Every seed and secret of this ERC is an output of `HKDF-Expand(R, info, L)`:

```
info = purpose || be32(account) || be16(L) || len8(name) || name || tail
```

| Field | Bytes | Value |
|---|---|---|
| `purpose` | 1 | `0x01` for a stateless key, `0x02` for a stateful key, `0x03` for an application secret |
| `account` | 4 | the account, below |
| `L` | 2 | the number of bytes derived, `32 <= L <= 16320` |
| `len8(name)` | 1 | the length of `name`, from 1 to 255 |
| `name` | 1 to 255 | the key type, or the application's label |
| `tail` | 0 or 64 | empty, or `context \|\| instance` for a stateful key |

### Accounts

`account` is an integer `0 <= account < 2^32`. Different values give independent sets of keys from one root, like the account level of [BIP-44](https://github.com/bitcoin/bips/blob/a34f044bb8d5cd684d7a742d2f6483c14b719046/bip-0044.mediawiki). Wallets SHOULD use `account = 0` unless the user creates more.

### Key types

A key type is a string of 1 to 255 printable ASCII characters other than the space, that is of bytes `0x21` to `0x7e`. It identifies:

- the signature scheme;
- its parameter set and hash function;
- the length `L` of its seed, at least 32 bytes;
- the deterministic procedure that makes a key pair from that seed, including every option that changes the public key, such as pruning the key's top tree.

The specification of a scheme or of an application defines its key types. A key type string MUST change whenever the map from seed to public key changes. Two different procedures MUST NOT share a key type string. A scheme whose key generation takes several secret values, or more than 32 bytes, sets `L` to what it needs and says how the seed is cut up.

### Stateless keys

The seed of the stateless key of type `t` for `account` is:

```
seed = HKDF-Expand(R, 0x01 || be32(account) || be16(L) || len8(ascii(t)) || ascii(t), L)
```

The key pair is the key type's key generation applied to `seed`. Restoring `R` MUST restore the same key pair.

### Stateful keys

A stateful key (one-time, few-time or many-time with an index, such as WOTS, FORS or XMSS) MUST NOT be reproducible from the root alone. Each instance has:

- `context`: 32 bytes the application defines, for example a hash of the chain, the account and the purpose;
- `instance`: 32 bytes from a cryptographically secure random number generator, generated when the instance is created.

```
seed = HKDF-Expand(R, 0x02 || be32(account) || be16(L) || len8(ascii(t)) || ascii(t) || context || instance, L)
```

The wallet MUST store `instance` with the instance's state, such as which indices have signed, and MUST NOT derive `instance` deterministically. A wallet restored from its root MUST create new instances. It MUST NOT recreate an instance from a backup of `instance` unless that backup also restores the instance's state, and the state is the latest.

### Application secrets

An application that needs its own secret derives it as:

```
secret = HKDF-Expand(R, 0x03 || be32(account) || be16(L) || len8(utf8(label)) || utf8(label), L)
```

where `label` is a string the application chooses, of 1 to 255 bytes in UTF-8 without Unicode normalization, and `L` is the length the application needs, 32 unless it says otherwise. Labels SHOULD be ASCII, and SHOULD be namespaced with a domain or project name the application controls. An application secret MUST NOT be used as the seed of a key type; stateless and stateful keys have their own derivations above. It MAY be used as other key material, for example as the private key of an ECDSA account that pays an application's gas. A quantum adversary who breaks such a key learns that secret only, not `R`.

### Restoring

After restoring `R` from a phrase, a wallet SHOULD show a fingerprint of a stateless public key, or an address derived from it, before the user relies on the keys. A mistyped BIP-39 passphrase gives a valid but different root, and comparing the fingerprint with a known one is how the user notices.

## Rationale

**Hash functions only.** BIP-32 mixes elliptic-curve arithmetic into derivation. A quantum adversary who holds an extended public key at any hardened level can compute that node's private key and chain code, and then every hardened child below it. Extended public keys at the account level are routinely exported to watch-only software. Keys derived from the BIP-39 seed by hashing alone are protected by HMAC-SHA512 alone: breaking every elliptic-curve key in the phrase's BIP-32 tree yields at most the BIP-32 master key and chain code, and neither reveals the BIP-39 seed.

**The BIP-39 seed, not the entropy.** Deriving from the seed keeps BIP-39 passphrases meaningful: each passphrase, including a hidden-wallet passphrase, gets its own hash-based keys. It also works for hardware wallets and libraries that keep only the seed. Deriving from the entropy avoids a second secret whose typos give valid keys, and at least one implementation chose it for that reason. This ERC keeps passphrases because users with existing phrases rely on them, and asks wallets to show a fingerprint after a restore instead.

**One PBKDF2, not two.** A second PBKDF2 over the phrase with its own salt also gives a secret independent of the BIP-32 tree, but it needs the words themselves: a wallet that keeps only the BIP-39 seed cannot compute it. It adds no protection against a quantum adversary either, since the BIP-32 tree already sits behind HMAC-SHA512, which hides the seed.

**Other derivations.** [ERC-2333](./eip-2333.md) also routes derivation through hashes, so that a broken curve does not expose child keys, but it derives BLS12-381 keys and ties its tree to that curve. BIP-85 and SLIP-0010 derive through BIP-32-style trees, whose nodes have elliptic-curve public keys.

**HKDF-SHA512.** HKDF is the standard way to turn one secret into many, and reviewers and libraries know it. With SHA-512 it runs on HMAC-SHA512, which every BIP-39 wallet and hardware wallet already has for PBKDF2 and BIP-32, so the whole derivation needs one primitive. The derivation's hash is independent of the signature scheme's hash, so a scheme that settles on another hash still uses this derivation.

**Extract under a fixed salt.** `HKDF-Extract` is `HMAC-SHA512(key = salt, message = IKM)`. BIP-32 makes its master key the same way under the key `"Bitcoin seed"`, and SLIP-0010 separates curves by changing that string. The salt `"HBKD/v1"` separates this ERC's root from all of them. The version sits in the salt and nowhere else, so a later version changes every derived value at once. Random input takes the same step, so a device key without a phrase is made the same way as a phrase key.

**The layout of `info`.** RFC 5869 leaves `info` to the application. Five choices shape it:

- **Every field has a fixed width or a length byte.** Two different sets of inputs therefore never encode to the same bytes, which is the property a derivation needs. Without the length byte, the key type `ab` followed by a context starting with `c` could equal the key type `abc`.
- **The purpose comes first, as one byte.** A stateless seed, a stateful seed and an application secret can then never coincide, whatever follows. A byte is enough, since the salt already carries the name and the version.
- **The key type and the label go in as they are.** Hashing them to a fixed width first would also work. But HKDF takes `info` of any length, so the hash would only add a step and a second place for implementations to differ. 255 bytes is ample for a name.
- **`L` is part of `info`.** `HKDF-Expand` produces its output block by block, so without `L` in `info` a 32-byte seed would be the first 32 bytes of a 48-byte seed for the same inputs. With it, the two are unrelated. TLS 1.3 puts the length into its HKDF labels for the same reason.
- **Fixed-width fields first, big-endian.** The order is: what kind, which account, how long, which name, then the stateful key's two 32-byte values. Integers are big-endian, as in BIP-32.

**Seed lengths per key type.** Schemes need different amounts of secret input. SLH-DSA takes three values of 16 to 32 bytes each. With one fixed seed length, every such scheme would have to invent its own expansion. Here the key type asks for the bytes it needs. The floor of 32 bytes keeps a careless key type from deriving a short seed.

**The key type in every seed.** A seed is never shared between two parameter sets or key-generation procedures, so a weakness in one cannot carry over to the other through a shared seed. When a protocol upgrade fixes a new parameter set, the wallet derives a new key from the same phrase under the new key type. An application can then link the new key to the old one by signing it with the old key, without a new backup.

**Random instances for stateful keys.** Stateful keys fail when an index signs twice. A deterministic stream of keys indexed by a counter repeats keys whenever a wallet is restored from an old backup, copied, or run on two devices. A per-device identifier only moves the problem: the same device restored twice repeats its stream. A phrase backs up an identity, not state, so this ERC restores stateless keys and makes fresh stateful instances. `context` binds an instance to its use, and an application can certify a new instance with its stateless key. Because the seed also depends on `R`, a stored `instance` and its state are not secret: whoever copies them still cannot sign without the root.

**Random roots for devices.** A device key derived from the phrase would require the phrase on the device. A device with its own random root holds no phrase, and the phrase's stateless key can certify and revoke its keys.

## Backwards Compatibility

No standard derivation exists for hash-based keys, so nothing breaks. Keys made by earlier, implementation-specific derivations, such as derivation from BIP-39 entropy or through BIP-32 paths under `m/44'/60'`, are not keys of this ERC. A wallet can derive keys of this ERC from the same phrase and have the earlier key sign them.

The BIP-39 seed this ERC uses is the same one BIP-32 wallets use, so a phrase can hold ECDSA and hash-based keys at once.

## Test Cases

Key type `leanSphincs-keccak/wambsgans-keccak/b10` is an example with a 32-byte seed. It names leanSPHINCS over Keccak-256 at the parameters of the `keccak` branch of the leanSphincs reference crate (16-byte hashes, one XMSS layer of height 26, FORS with 24 trees of 1,024 leaves, WOTS+C with 64 chains of `w = 4` and target sum 120), with a pruned top tree that keeps a subtree of height 10. The vectors use it only as a string and do not depend on its key generation.

Unless a line says otherwise, `L` is 32, `context` is the bytes `0x00` to `0x1f`, `instance` is 32 bytes of `0xa5`, and the application label is `example.app.gas`. "max account" is account `2^32 - 1`.

```
mnemonic                 abandon (23 times) art
passphrase               (empty)
S                        408b285c123836004f4b8842c89324c1f01382450c0d439af345ba7fc49acf70
                         5489c6fc77dbd4e3dc1dd8cc6bc9f043db8ada1e243c4a0eafb290d399480840
R                        31a48aa502c800ed2e98d6ea19e8121861876ac755601b53f3772c4c910cc292
                         e8f1650268f6df3f7b7f030536b6b4e55a13b0d673b24e7e6a8fdecb9c5854ed
stateless, account 0     fe1de5038bcc56fc434f8cba07eb53ab972de18ec0779c7465fd0d789a966879
stateless, account 1     dae839ce92eb35bdd99718114d73d0b1ef6a2c66ad0bdd41b1fc7e99ee36ff82
stateless, L = 48        da22b68be432f40bc516b7f4633ac9238970b93fe22e198438f32750cb42c45a
                         7eaa9c32c1bc6a3fb120d9d3e3cd9d51
stateful, account 0      675a2390347bd7f57af7086cd3596929701d22f554100304555a946403542c9f
app secret, account 0    4a50286a3a17be26017002484f0e99f10b6a19bc6202fbc3f079760fd9b1c000

mnemonic                 abandon (23 times) art
passphrase               TREZOR
S                        bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd30971
                         70af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8
R                        36115dbd5c9909f705901905fdfcd5b59af8a03773b107a4cbc01de190810425
                         edabf87db6ceaebf3684dbfaf5ea46ec34d2b91a0d7661310b03b4ec1b5202bf
stateless, account 0     3d5ad9f82a782c1578db5b40443cfba75c151167312a133d4c90457f6a98179d
stateless, account 1     e5fa8baf57d6a7fecf5cdd9b7e1d1714cfbbdd4c86e7de882d4494d02fe65433
stateful, account 0      20023fe84a406e7f050108053e586d5741db708b721554c6a9e1e1cb16bd6b6b
app secret, account 0    63cf757802534428b39551535e5560831be70a5996f1eab6240d399a0798c151

mnemonic                 legal winner thank year wave sausage worth useful legal winner thank yellow
passphrase               TREZOR
S                        2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6f
                         a457fe1296106559a3c80937a1c1069be3a3a5bd381ee6260e8d9739fce1f607
R                        c9f92a198541dcb5caf89f801827ef3baa8aafadcd3cee67d973ddbced8edad2
                         30dd8e77b5d30e60650c5d6ac22328a701b0e87ef959ea6a78c7e170354c3fbf
stateless, account 0     601ae30e33d5058eed33e0cc0ec25cb5bf8659481104a7bd0f10c0ebdd30b967
stateless, account 1     7d3b358bf3d671dc6eb66dcfc58f7d91e6bb06bfe4cf92da9c19051a44516943
stateful, account 0      52f7f43010563686fa971066e92e0e389d1caddf2c14a1dbb27f589a5f90dfee
app secret, account 0    27ed4acb2aed9f052692619b763f96da377a3f96f2b242d8d636d19e1d06a3be

random input             202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
R                        719bbea6f6e3bec595afff3dccc8558972a4aa4893a654ce6b793616eab6f3d5
                         c18887c81e3a4009c5488c1070b86a65e6bb32279473b8d8a21548e8d02fc07a
stateless, max account   6a0989ffde23947e80f0dfe22f5c9f7df46b79403db776b90fdd127b84f76ceb
stateful, max account    0faee1dc2f4f8cdb4cd3fb634429c53d2305644fcc3903f5507ce05a64c6f5e8
app secret, max account  dadb75da4b8194cfac6575b65705b93e5343172e4c2ed271e2e3627ffadfa950
```

The two values of `S` with passphrase `TREZOR` are BIP-39's published test vectors. The line with `L = 48` shows that a longer seed does not start with the shorter one.

The `info` of the first stateless seed (account 0, `L = 32`) is these 47 bytes:

```
01 00000000 0020 27
6c65616e537068696e63732d6b656363616b2f77616d627367616e732d6b656363616b2f623130
```

An implementation rejects each of these inputs: the mnemonic `abandon` repeated 24 times, whose checksum fails; the key types `""` and `leanSphincs keccak`, one empty and one with a space; a key type of 256 bytes; account `2^32`; and the lengths 31 and 16321.

## Reference Implementation

```python
import hashlib
import hmac
import unicodedata

from mnemonic import Mnemonic  # the BIP-39 reference implementation

ENGLISH = Mnemonic("english")
ENGLISH_WORDS = frozenset(ENGLISH.wordlist)
SALT = b"HBKD/v1"
STATELESS, STATEFUL, APPLICATION = 1, 2, 3


def _require(ok: bool, what: str) -> None:
    if not ok:
        raise ValueError(what)


def hkdf_extract(salt: bytes, ikm: bytes) -> bytes:
    return hmac.new(salt, ikm, hashlib.sha512).digest()


def hkdf_expand(prk: bytes, info: bytes, length: int) -> bytes:
    out, block, counter = b"", b"", 1
    while len(out) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha512).digest()
        out += block
        counter += 1
    return out[:length]


def bip39_seed(words: list, passphrase: str = "") -> bytes:
    # words: the mnemonic's words as they appear in the wordlist, here the English one
    _require(all(w in ENGLISH_WORDS for w in words), "mnemonic: a word outside the wordlist")
    sentence = " ".join(words)
    _require(ENGLISH.check(sentence), "mnemonic: a wrong number of words, or a failed checksum")
    m = unicodedata.normalize("NFKD", sentence).encode("utf-8")
    salt = unicodedata.normalize("NFKD", "mnemonic" + passphrase).encode("utf-8")
    return hashlib.pbkdf2_hmac("sha512", m, salt, 2048)


def root(ikm: bytes) -> bytes:
    # ikm: a BIP-39 seed, or at least 32 fresh random bytes
    _require(isinstance(ikm, bytes) and len(ikm) >= 32, "input key material: at least 32 bytes")
    return hkdf_extract(SALT, ikm)


def _info(purpose: int, account: int, length: int, name: bytes, tail: bytes = b"") -> bytes:
    _require(type(account) is int and 0 <= account < 2**32, "account: an integer from 0 to 2^32 - 1")
    _require(type(length) is int and 32 <= length <= 16320, "length: an integer from 32 to 16320")
    _require(1 <= len(name) <= 255, "key type or label: 1 to 255 bytes")
    return bytes([purpose]) + account.to_bytes(4, "big") + length.to_bytes(2, "big") + bytes([len(name)]) + name + tail


def _root(value: bytes) -> bytes:
    _require(isinstance(value, bytes) and len(value) == 64, "root: 64 bytes")
    return value


def _bytes32(value: bytes, what: str) -> bytes:
    _require(isinstance(value, bytes) and len(value) == 32, what + ": 32 bytes")
    return value


def _key_type(key_type: str) -> bytes:
    _require(isinstance(key_type, str) and all("!" <= c <= "~" for c in key_type), "key type: bytes 0x21 to 0x7e")
    return key_type.encode("ascii")


def stateless_seed(root: bytes, key_type: str, length: int, account: int = 0) -> bytes:
    # length: the seed length that the key type defines
    return hkdf_expand(_root(root), _info(STATELESS, account, length, _key_type(key_type)), length)


def stateful_seed(root: bytes, key_type: str, length: int, context: bytes, instance: bytes, account: int = 0) -> bytes:
    # instance: 32 fresh random bytes, stored with the instance's state
    tail = _bytes32(context, "context") + _bytes32(instance, "instance")
    return hkdf_expand(_root(root), _info(STATEFUL, account, length, _key_type(key_type), tail), length)


def app_secret(root: bytes, label: str, length: int = 32, account: int = 0) -> bytes:
    _require(isinstance(label, str), "label: a string")
    return hkdf_expand(_root(root), _info(APPLICATION, account, length, label.encode("utf-8")), length)
```

## Security Considerations

**The phrase holds every key.** Whoever learns the phrase, and the passphrase if there is one, holds every stateless key and application secret of every account it derives. Stateful instances also depend on `instance`, but an adversary with the phrase can use the stateless keys instead.

**The root.** `R` is as secret as the phrase: whoever holds it can derive every key without the phrase. A wallet that stores `R` instead of the phrase protects it the same way.

**Sharing a phrase with ECDSA wallets.** The derivation keeps hash-based keys safe from a quantum adversary who breaks the phrase's ECDSA keys. It does not keep them safe from the phrase itself: every wallet that has seen the phrase can derive them, including a hot wallet that was compromised years ago. Hash-based keys from a shared phrase are only as safe as the weakest wallet that ever held it. Wallets SHOULD create a new phrase for a new hash-based account, and SHOULD warn the user before deriving hash-based keys from an existing phrase.

**Stateful keys.** Signing twice at one index of a one-time key reveals enough to forge. Wallets MUST save an instance's state before releasing a signature, MUST NOT restore an instance from stale state, and MUST create new instances after a restore. Applications SHOULD bind each instance to its use through `context`.

**Phrase length.** A 12-word phrase has 128 bits of entropy, and a 24-word phrase 256. Grover's algorithm searches 128 bits in about 2^64 sequential steps, each a PBKDF2 of 2048 iterations and a check against a known public key or address of the phrase, which matches parameter sets with 16-byte hashes. Wallets SHOULD use 24-word phrases for key types that target a higher level.

**Signature budgets.** A stateless key is secure only up to the number of signatures its parameter set allows. Wallets SHOULD count signatures per key, and move to a new `account` or key type before the budget runs out.

**Key types.** A key type string that names two procedures would let two implementations derive different keys from one seed. Implementers of a scheme SHOULD publish its key type strings with test vectors.

**Passphrases.** A mistyped passphrase gives valid keys that nobody else knows, so funds sent to them are lost. Wallets SHOULD show a fingerprint after a restore, as the Specification says.

**Random roots.** A random root has no backup. Losing it loses its keys, so its keys SHOULD only hold authority that a phrase-derived key can revoke.

**Side channels.** Key generation for hash-based schemes computes many hashes of secret values. Implementations on hardware SHOULD use constant-time hash implementations.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
