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

This ERC specifies how a wallet derives the secret seeds of hash-based post-quantum keys, such as leanSPHINCS, from a BIP-39 recovery phrase. The derivation uses only PBKDF2-HMAC-SHA512 (as in BIP-39) and Keccak-256. It never passes through BIP-32 or any elliptic-curve operation, so a quantum adversary who breaks every ECDSA key made from the same phrase learns nothing about the hash-based keys.

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
- `keccak256` is Ethereum's Keccak-256: FIPS 202's 256-bit hash with first padding byte `0x01` instead of `0x06`.
- `be32(x)` is the 4-byte big-endian encoding of an integer `0 <= x < 2^32`.
- `ascii(s)` is the ASCII encoding of a string `s`, without terminator or length prefix.
- `TH(tag, data) = keccak256(keccak256(ascii(tag)) || data)` is a tagged hash.

### Root secret

A root secret `R` is 32 bytes. It comes from one of two sources.

**From a BIP-39 phrase.** With mnemonic sentence `M` and BIP-39 passphrase `P` (the empty string if the user sets none):

```
S = BIP39-Seed(M, P)          64 bytes: PBKDF2-HMAC-SHA512, 2048 iterations, as BIP-39 specifies
R = TH("HBKD/root/v1", S)
```

`M` is the phrase's words exactly as they appear in the BIP-39 wordlist it was made with, separated by single spaces. Wallets MAY support only the English wordlist. A wallet MUST bring what the user types (other letter case, other spacing, abbreviated words) into this form. It MUST reject a mnemonic with a word outside the wordlist or a failed BIP-39 checksum. BIP-39 only asks for a warning, but a mistyped word that passes would restore different keys.

**Random.** For a key holder without a phrase, such as a device that a phrase-derived key certifies, `R` is 32 bytes from a cryptographically secure random number generator.

A wallet MUST NOT derive `R`, or any value in this ERC, through BIP-32 or any other step that involves elliptic-curve arithmetic.

### Accounts

`account` is an integer `0 <= account < 2^32`. Different values give independent sets of keys from one root, like the account level of [BIP-44](https://github.com/bitcoin/bips/blob/a34f044bb8d5cd684d7a742d2f6483c14b719046/bip-0044.mediawiki). Wallets SHOULD use `account = 0` unless the user creates more.

### Key types

A key type is a non-empty string of printable ASCII characters other than the space, that is of bytes `0x21` to `0x7e`. It identifies:

- the signature scheme;
- its parameter set and hash function;
- the deterministic procedure that makes a key pair from a 32-byte seed, including every option that changes the public key, such as pruning the key's top tree.

The specification of a scheme or of an application defines its key types. A key type string MUST change whenever the map from seed to public key changes. Two different procedures MUST NOT share a key type string.

`kt(t) = keccak256(ascii(t))` for a key type `t`.

### Stateless keys

The seed of the stateless key of type `t` for `account` is:

```
seed = TH("HBKD/stateless/v1", R || be32(account) || kt(t))
```

The key pair is the key type's key generation applied to `seed`. Restoring `R` MUST restore the same key pair.

### Stateful keys

A stateful key (one-time, few-time or many-time with an index, such as WOTS, FORS or XMSS) MUST NOT be reproducible from the root alone. Each instance has:

- `context`: 32 bytes the application defines, for example a hash of the chain, the account and the purpose;
- `instance`: 32 bytes from a cryptographically secure random number generator, generated when the instance is created.

```
seed = TH("HBKD/stateful/v1", R || be32(account) || kt(t) || context || instance)
```

The wallet MUST store `instance` with the instance's state, such as which indices have signed, and MUST NOT derive `instance` deterministically. A wallet restored from its root MUST create new instances. It MUST NOT recreate an instance from a backup of `instance` unless that backup also restores the instance's state, and the state is the latest.

### Application secrets

An application that needs its own secret derives it as:

```
secret = TH("HBKD/app/v1", R || be32(account) || keccak256(utf8(label)))
```

where `label` is a string the application chooses and `utf8` its UTF-8 encoding, without Unicode normalization. Labels SHOULD be ASCII, and SHOULD be namespaced with a domain or project name the application controls. An application secret MUST NOT be used as the seed of a key type; stateless and stateful keys have their own derivations above. It MAY be used as other key material, for example as the private key of an ECDSA account that pays an application's gas. A quantum adversary who breaks such a key learns that secret only, not `R`.

### Restoring

After restoring `R` from a phrase, a wallet SHOULD show a fingerprint of a stateless public key, or an address derived from it, before the user relies on the keys. A mistyped BIP-39 passphrase gives a valid but different root, and comparing the fingerprint with a known one is how the user notices.

## Rationale

**Hash functions only.** BIP-32 mixes elliptic-curve arithmetic into derivation. A quantum adversary who holds an extended public key at any hardened level can compute that node's private key and chain code, and then every hardened child below it. Extended public keys at the account level are routinely exported to watch-only software. Keys derived from the BIP-39 seed by hashing alone are protected by the preimage resistance of HMAC-SHA512 and Keccak-256: breaking every elliptic-curve key in the phrase's BIP-32 tree yields at most the BIP-32 master key and chain code, and neither reveals the BIP-39 seed.

**The BIP-39 seed, not the entropy.** Deriving from the seed keeps BIP-39 passphrases meaningful: each passphrase, including a hidden-wallet passphrase, gets its own hash-based keys. It also works for hardware wallets and libraries that keep only the seed. Deriving from the entropy avoids a second secret whose typos give valid keys, and at least one implementation chose it for that reason. This ERC keeps passphrases because users with existing phrases rely on them, and asks wallets to show a fingerprint after a restore instead.

**One PBKDF2, not two.** A second PBKDF2 over the phrase with its own salt also gives a secret independent of the BIP-32 tree, but it needs the words themselves: a wallet that keeps only the BIP-39 seed cannot compute it. It adds no protection against a quantum adversary either, since the BIP-32 tree already sits behind HMAC-SHA512, which hides the seed.

**Other derivations.** [ERC-2333](./eip-2333.md) also routes derivation through hashes, so that a broken curve does not expose child keys, but it derives BLS12-381 keys and ties its tree to that curve. BIP-85 and SLIP-0010 derive through BIP-32-style trees, whose nodes have elliptic-curve public keys.

**A tagged root.** `R` compresses the 64-byte seed to 32 bytes under a fixed tag. A random 32-byte root fits the same derivations, so a device key without a phrase is made the same way as a phrase key.

**Keccak-256.** Every Ethereum wallet already has it, and contracts can recompute it. The derivation hash is independent of the signature scheme's hash, so a scheme that settles on another hash still uses this derivation.

**The key type in every seed.** A seed is never shared between two parameter sets or key-generation procedures, so a weakness in one cannot carry over to the other through a shared seed. When a protocol upgrade fixes a new parameter set, the wallet derives a new key from the same phrase under the new key type. An application can then link the new key to the old one by signing it with the old key, without a new backup.

**Random instances for stateful keys.** Stateful keys fail when an index signs twice. A deterministic stream of keys indexed by a counter repeats keys whenever a wallet is restored from an old backup, copied, or run on two devices. A per-device identifier only moves the problem: the same device restored twice repeats its stream. A phrase backs up an identity, not state, so this ERC restores stateless keys and makes fresh stateful instances. `context` binds an instance to its use, and an application can certify a new instance with its stateless key. Because the seed also depends on `R`, a stored `instance` and its state are not secret: whoever copies them still cannot sign without the root.

**Random roots for devices.** A device key derived from the phrase would require the phrase on the device. A device with its own random root holds no phrase, and the phrase's stateless key can certify and revoke its keys.

## Backwards Compatibility

No standard derivation exists for hash-based keys, so nothing breaks. Keys made by earlier, implementation-specific derivations, such as derivation from BIP-39 entropy or through BIP-32 paths under `m/44'/60'`, are not keys of this ERC. A wallet can derive keys of this ERC from the same phrase and have the earlier key sign them.

The BIP-39 seed this ERC uses is the same one BIP-32 wallets use, so a phrase can hold ECDSA and hash-based keys at once.

## Test Cases

Key type `leanSphincs-keccak/wambsgans-keccak/b10` is an example. It names leanSPHINCS over Keccak-256 at the parameters of the `keccak` branch of the leanSphincs reference crate (16-byte hashes, one XMSS layer of height 26, FORS with 24 trees of 1,024 leaves, WOTS+C with 64 chains of `w = 4` and target sum 120), with a pruned top tree that keeps a subtree of height 10. The vectors use it only as a string and do not depend on its key generation. `context` is the bytes `0x00` to `0x1f`, and `instance` is 32 bytes of `0xa5`. The application label is `example.app.gas`.

```
mnemonic   abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon
           abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art
passphrase (empty)
S          408b285c123836004f4b8842c89324c1f01382450c0d439af345ba7fc49acf70
           5489c6fc77dbd4e3dc1dd8cc6bc9f043db8ada1e243c4a0eafb290d399480840
R          3e6cf3c3a1af758759e9337eed8a7d4723e23a378c1e471a28baf4db10569e01
stateless, account 0  373d01c6fca9738080cf1f4186fd517ad450d134d31bcb3aecb3bb4dd340d419
stateless, account 1  8fc21bcff345bc88b412b2d4a3a8c2a0637d3ea05e187969d3ce0aa195ca2e7b
stateful, account 0   e8e1e2bc45a1a0785011021d34b601833c4e1f0fcfabb19daa53d0ffd1a47939
app secret            fcec37951685415d996fb166633bce4891ffb650ef121354129c1fe8b6d850c7

mnemonic   (as above)
passphrase TREZOR
S          bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd30971
           70af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8
R          04ed2bcdefde1aad10dc37dd64ef968d3229c9b468a8407d76b1f969a2d6b335
stateless, account 0  d4438a8e081bd7cf04b632dc763fcff549eeb1f1fbea78e759d22041aa0ef295
stateless, account 1  44a8d35e0d3010c16f5256426c2c0c6b267f5a121928adcb21e6f934de5711b7
stateful, account 0   9e65891f41a97f6235a55233a3117095a86fc831b3bfc72eb429ba5c77e2160e
app secret            1da8fa73176e364da9784eeff604937153bf9565acff932d558e678c9aca6eff

mnemonic   legal winner thank year wave sausage worth useful legal winner thank yellow
passphrase TREZOR
S          2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6f
           a457fe1296106559a3c80937a1c1069be3a3a5bd381ee6260e8d9739fce1f607
R          fed41ed04e47cf6b7cebabb5fce9f214fc6a5e5b8ddddb38c50cbc7feaa7dee4
stateless, account 0  55b86642971ca5d137f1ce48ad68d0c79310aff96ae70b5b061dc696e5a7dd03
stateless, account 1  3347fbb9f4f0adaf77a518ccd4ff34d47247120a8b32ecf7d13b5b5575170d7e
stateful, account 0   37306d29c12f6f5490989ce516eada140d00038ec48979584aaec7a42c00b37a
app secret            85c53633bb07dddb69b8cabe0f883410574b5db9bf90775b93b45620120227b4

R (random)                      202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
stateless, account 4294967295   08ab99f47191e6cda022959b2081b705c6c8ad7c621bbf5dc2dc3eb25d1f8618
stateful, account 4294967295    6f7916cfa6ddcc290922eb98746847c8b9b3eb863df42715a28e5e0432371ef4
app secret, account 4294967295  3f19d5ebb8a58e748762da7038cf705835fd88b62b7c2b93aa9cacb3e3223529
```

The two values of `S` with passphrase `TREZOR` are BIP-39's published test vectors.

An implementation rejects each of these inputs: the mnemonic `abandon` repeated 24 times, whose checksum fails; the key types `""` and `leanSphincs keccak`, one empty and one with a space; and account `2^32`.

## Reference Implementation

```python
import hashlib
import unicodedata

from Crypto.Hash import keccak  # pycryptodome
from mnemonic import Mnemonic  # the BIP-39 reference implementation

ENGLISH = Mnemonic("english")
ENGLISH_WORDS = frozenset(ENGLISH.wordlist)


def keccak256(data: bytes) -> bytes:
    return keccak.new(digest_bits=256, data=data).digest()


def tagged_hash(tag: str, data: bytes) -> bytes:
    return keccak256(keccak256(tag.encode("ascii")) + data)


def _require(ok: bool, what: str) -> None:
    if not ok:
        raise ValueError(what)


def bip39_seed(words: list, passphrase: str = "") -> bytes:
    # words: the mnemonic's words as they appear in the wordlist, here the English one
    _require(all(w in ENGLISH_WORDS for w in words), "mnemonic: a word outside the wordlist")
    sentence = " ".join(words)
    _require(ENGLISH.check(sentence), "mnemonic: a wrong number of words, or a failed checksum")
    m = unicodedata.normalize("NFKD", sentence).encode("utf-8")
    salt = unicodedata.normalize("NFKD", "mnemonic" + passphrase).encode("utf-8")
    return hashlib.pbkdf2_hmac("sha512", m, salt, 2048)


def root_from_seed(seed: bytes) -> bytes:
    _require(isinstance(seed, bytes) and len(seed) == 64, "seed: 64 bytes")
    return tagged_hash("HBKD/root/v1", seed)


def _bytes32(value: bytes, what: str) -> bytes:
    _require(isinstance(value, bytes) and len(value) == 32, what + ": 32 bytes")
    return value


def _account(account: int) -> bytes:
    _require(type(account) is int and 0 <= account < 2**32, "account: an integer from 0 to 2^32 - 1")
    return account.to_bytes(4, "big")


def _key_type(key_type: str) -> bytes:
    _require(isinstance(key_type, str) and key_type != "" and all("!" <= c <= "~" for c in key_type),
             "key type: a non-empty string of bytes 0x21 to 0x7e")
    return keccak256(key_type.encode("ascii"))


def stateless_seed(root: bytes, key_type: str, account: int = 0) -> bytes:
    return tagged_hash("HBKD/stateless/v1", _bytes32(root, "root") + _account(account) + _key_type(key_type))


def stateful_seed(root: bytes, key_type: str, context: bytes, instance: bytes, account: int = 0) -> bytes:
    # instance: 32 fresh random bytes, stored with the instance's state
    return tagged_hash("HBKD/stateful/v1", _bytes32(root, "root") + _account(account) + _key_type(key_type)
                       + _bytes32(context, "context") + _bytes32(instance, "instance"))


def app_secret(root: bytes, label: str, account: int = 0) -> bytes:
    _require(isinstance(label, str), "label: a string")
    return tagged_hash("HBKD/app/v1", _bytes32(root, "root") + _account(account) + keccak256(label.encode("utf-8")))
```

## Security Considerations

**The phrase holds every key.** Whoever learns the phrase, and the passphrase if there is one, holds every stateless key and application secret of every account it derives. Stateful instances also depend on `instance`, but an adversary with the phrase can use the stateless keys instead.

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
