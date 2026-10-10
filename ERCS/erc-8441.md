---
eip: 8441
title: Hybrid post-quantum stealth address scheme
description: ERC-5564 schemeId 3, announcing with ML-KEM-768 combined with secp256k1 ECDH while spending stays on secp256k1
author: Nam Ngo (@namnc), Pierre Daix-Moreux (@dmpierre), kassandra.eth (@kassandraoftroy)
discussions-to: https://ethereum-magicians.org/t/erc-8441-hybrid-post-quantum-stealth-address-scheme/29923
status: Draft
type: Standards Track
category: ERC
created: 2026-08-28
requires: 5564, 6538
---

## Abstract

[ERC-5564](./eip-5564.md) defines stealth addresses and a `schemeId` namespace, and specifies `schemeId` 1, on secp256k1. 
This ERC specifies `schemeId` 3. Its payment secret combines an ML-KEM-768 encapsulation with a secp256k1 ECDH secret. 
As long as ML-KEM-768 holds, an adversary who later gains access to a quantum computer still cannot tell from the public announcement log who was the receiver.

The scheme protects the announcement layer only. Spending stays vulnerable to quantum attacker. 
Each stealth address is still an ordinary EOA controlled by a secp256k1 key,
and a quantum adversary can break those keys as it can break any EOA's. 
It uses the deployed ERC-5564 announcer and [ERC-6538](./eip-6538.md) registry as is, 
with no protocol change and no new contract.

| | schemeId 3 |
|---|---|
| payment secret | ML-KEM-768 shared secret combined with a secp256k1 ECDH secret |
| announcement | 1 122 B per payment: an ephemeral public key, an ML-KEM ciphertext and a view tag |
| meta-address | 1 250 B, registered once via ERC-6538 |
| spending | secp256k1 ECDSA from a plain EOA |

## Motivation

As defined in ERC-5564, 
stealth-address announcement is public, permanent, and centralized in one contract. 
Under `schemeId` 1, an announcement's privacy relies on secp256k1 ECDH. 
Anyone who can compute discrete logarithms (i.e., with a cryptographically relevant quantum computer (CRQC) built in the future) 
can take each registered viewing key, 
recompute the shared secret for every announcement, 
and thus learn which recipient each payment went to. 
As such privacy loss is retroactive, 
post-quantum migration for the anonymity layer matters now.

Spending is a different problem with a later deadline,
as theft needs the CRQC to exist while the funds are still in the account.
Beside, moving accounts off secp256k1 may also need account or protocol changes that are not yet available. 

Conveniently, ERC-5564's `announce()` and ERC-6538's `registerKeys` both take unbounded `bytes`, 
hence the announcement layer can move to a post-quantum KEM now, with no new contract. 
And spending can stay on secp256k1 until a later and separate migration.

The ECDH half yields no protection against a quantum adversary
but a hedge for the extreme case 
where ML-KEM-768, or an implementation of it, is broken classically.
In such case, the payment secret still has the protection `schemeId` 1 has today.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in RFC 2119 and RFC 8174.

### 1. Common definitions

Notation:

- `a || b` is byte concatenation, and `x[i..j]` is bytes `i` (inclusive) to `j` (exclusive) of `x`.
- `u256be(b)` reads 32 bytes as an unsigned integer, most significant byte first.
- `n` is the order of the secp256k1 group and `G` is its generator. 
A valid scalar is an integer `k` with `0 < k < n`. 
A 32-byte secret's `u256be` value must be a valid scalar.
- Points use SEC1-compressed encoding: 33 bytes with tag `0x02` or `0x03`. 
`uncompressed(P)` is the 65-byte SEC1 form `0x04 || x || y`.
- `ECDH(k, P).x` is the 32-byte big-endian x-coordinate of `k·P`.
- `SHA256` is SHA-256 (FIPS 180-4) and `SHA3-256` is SHA3-256 (FIPS 202). 
`keccak256` is Ethereum's original Keccak-256.
- Domain separators are ASCII strings used as written, with no length prefix and no terminator.

ML-KEM-768 is as specified in FIPS 203. We use it as follows:

- Key generation starts from the 64-byte seed `(d, z)`: `(ek, dk) = ML-KEM.KeyGen_internal(d, z)` (FIPS 203 Algorithm 16). 
The seed can be stored in place of the decapsulation key and only expanded when needed.
- Encapsulation is FIPS 203 `ML-KEM.Encaps(ek)` (Algorithm 20). 
We use the deterministic `ML-KEM.Encaps_internal(ek, m)` (Algorithm 17) only in the test vectors (Test Cases).
- Decapsulation is FIPS 203 `ML-KEM.Decaps(dk, ct)`, 
or `ML-KEM.Decaps_internal` on a `dk` expanded from `(d, z)`. 
Note that ML-KEM rejects implicitly: 
a well-formed ciphertext that was not intended for `dk` decapsulates to a pseudorandom value, not to an error.

**Offset and view tag.** From the 32-byte payment secret `ss` of Section 1.1:

```
base = SHA256("pq-stealth/offset/v1" || ss)
if 0 < u256be(base) < n:  H(ss) = u256be(base)
else:                     fail

view_tag = SHA256("pq-stealth/view-tag/v1" || ss)[0..1]                       1 B
```

Sender and recipient MUST both run exactly this procedure. 
An implementation MUST NOT reduce `base` mod `n` or derive another candidate. 
On failure, the sender discards the announcement's randomness and draws again (Section 2.4), 
and a scanner skips the announcement (Section 2.7).
`base` is out of range with probability below 2^-127. 
Test vectors reach the failure by supplying `base` directly (Test Cases).

The stealth key pair and its address keep ERC-5564's structure:

```
stealth_pk = spending_pk + H(ss)·G
stealth_sk = (spending_sk + H(ss)) mod n
address    = keccak256(uncompressed(stealth_pk)[1..65])[12..32]
```

These derivations differ from ERC-5564's `schemeId` 1 in four ways:

1. The hashed secret is the hybrid `ss` of Section 1.1, not the ECDH shared point.
2. ERC-5564's hash function `h` is made explicit SHA-256 under the domain separator `"pq-stealth/offset/v1"`.
3. ERC-5564 takes the view tag from the first byte of the digest that also becomes the scalar.
Here the view tag is a separate digest under its own domain separator.
4. ERC-5564 uses the digest as the scalar with no range check. 
Here we make explicit that the range check above yields a valid scalar or fails.

#### 1.1 The hybrid combiner

```
hybrid_combine(DS, ss_ec, ss_pq, epk, ct, viewing_pk_ec, ek)
    = SHA3-256(DS || ss_ec || ss_pq || epk || ct || viewing_pk_ec || ek)               32 B
```

`schemeId` 3 uses `DS = "pq-stealth/hybrid-payment/v1"` (28 bytes) and output `ss` (Section 2.4).

1. `ss_ec` MUST be the 32-byte x-coordinate alone.
2. `epk` and `viewing_pk_ec` MUST be their 33-byte compressed encodings. 
`ct` MUST be the 1 088-byte ML-KEM ciphertext as announced, 
and `ek` the 1 184-byte encapsulation key as registered.
3. The input order MUST be exactly as shown, 
with `DS` first, 
and the output MUST be the full 32-byte digest.

Every field has a fixed length, so plain concatenation encodes the inputs unambiguously.

Our combiner has the shape of `KeyCombineCCA_H` in NIST SP 800-227 §4.6.3 (an instance of Eq. (15)):

| SP 800-227 input | here | role |
|---|---|---|
| `K1`, `K2` | `ss_ec`, `ss_pq` | the two shared secrets |
| `c1` | `epk` | the ECDH "ciphertext": the sender's ephemeral public key |
| `c2` | `ct` | the ML-KEM ciphertext |
| `ek1` | `viewing_pk_ec` | the ECDH "encapsulation key": the recipient's viewing key |
| `ek2` | `ek` | the ML-KEM encapsulation key |
| `domain_sep` | `DS` | names this scheme and this combiner |

It departs from the exact shape in three ways:

- `DS` comes first rather than last.
- The inputs are concatenated rather than given as a list. 
SP 800-227 §4.6.2 allows plain concatenation when the encoding is unambiguous, as it is here.
- We use a bare hash, not SP 800-56C's one-step KDF, which prefixes a 32-bit counter.

Note that security is still kept: i.e.,
with the hash modelled as a random oracle, 
hashing both shared secrets together with both ciphertexts yields an IND-CCA KEM if either component KEM is IND-CCA.
The two encapsulation keys are not needed 
but as SP 800-227 notes, 
including them binds the secret to the recipient's identity.

### 2. schemeId 3

Each payment carries one ML-KEM encapsulation and one ephemeral secp256k1 key. 
Spending stays secp256k1 ECDSA on an ordinary EOA, 
so it needs no new verifier and no consensus change.

```
sender    : esk, epk    <- a fresh secp256k1 key pair                         (2.4)
            (ct, ss_pq) <- ML-KEM-768.Encaps(ek)
            ss          <- hybrid_combine(DS, ECDH(esk, viewing_pk_ec).x, ss_pq,
                                          epk, ct, viewing_pk_ec, ek)
            announce(3, address(stealth_pk), epk, view_tag(ss) || ct); pay the address
scanner   : ss_ec <- ECDH(viewing_ec, epk).x;  ss_pq <- ML-KEM-768.Decaps(dk, ct)
            ss    <- the same hybrid_combine call; compare the view tag, then the address
recipient : stealth_sk = (spending_sk + H(ss)) mod n
```

#### 2.1 Keys and seeds

Key generation takes a 128-byte seed and MUST be deterministic: 
i.e., the same seed MUST produce the same three outputs.

```
seed     = spending_seed(32) || viewing_ec_seed(32) || kem_seed(64)
kem_seed = d(32) || z(32)
```

An implementation MUST reject a seed of any other length rather than pad or truncate it.

- `spending_seed` is the master spending key `spending_sk`. 
It MUST be a valid scalar, and key generation MUST fail otherwise.
- `viewing_ec_seed` is the viewing scalar `viewing_ec`. 
It MUST be a valid scalar, and key generation MUST fail otherwise.
- `kem_seed` is ML-KEM's `(d, z)`. 
Key generation computes `(ek, dk) = ML-KEM.KeyGen_internal(d, z)`, 
and the tracking key is `(d, z)`.

The three components MUST be generated independently of one another. 
Each MUST be either drawn from a cryptographically secure random number generator (CSPRNG) 
or derived from a master secret by a PRF in a way that gives each component an independent output. 
In particular, a wallet MUST NOT use the spending key as the viewing key. 
The tracking key is meant to be handed to a scanning service, so it must not carry the spending key.
Key generation MUST fail if `spending_seed` equals `viewing_ec_seed`, `d`, or `z`. 

Key generation has three outputs:

| output | contents | size | disposition |
|---|---|---|---|
| meta-address | `spending_pk || viewing_pk_ec || ek` | 1 250 B | published via ERC-6538 (Section 2.2) |
| master key | `spending_sk` | 32 B | never leaves the owner |
| tracking key | `viewing_ec || d || z` | 96 B | MAY be delegated to a scanning service |

Here `spending_pk = spending_sk·G` and `viewing_pk_ec = viewing_ec·G`.

#### 2.2 Meta-address encoding

```
meta = spending_pk(33) || viewing_pk_ec(33) || ek(1184)                       1 250 B
```

A decoder MUST reject any length other than 1 250 bytes. 
Before the meta-address is used for anything, 
the decoder MUST check that both 33-byte fields carry tag `0x02` or `0x03` 
and decode to points on secp256k1. 
It MUST NOT accept other SEC1 forms. 
`ek` MUST pass FIPS 203's encapsulation input check (§7.2) before its first use.

#### 2.3 Registration and scheme selection

A recipient MUST register the encoded meta-address with ERC-6538 `registerKeys(3, meta)`.

A recipient MAY register under several `schemeId`s. 
A scanner MUST process each announcement only under the rules of the `schemeId` it carries, 
with the recipient's keys for that `schemeId`. 
A recipient who clears a `schemeId` (below) SHOULD keep scanning it for payments made before the change.

A sender that implements `schemeId` 3 and finds the recipient registered under it 
MUST use `schemeId` 3, even if the recipient is also registered under another scheme such as `schemeId` 1.
A recipient who wants post-quantum announcement privacy SHOULD register only `schemeId` 3. 
They SHOULD clear an existing `schemeId` 1 entry by registering an empty value under it, 
and a sender MUST treat an empty entry as unregistered.

#### 2.4 Sender

Each announcement needs a fresh ephemeral scalar `esk` and fresh encapsulation randomness.
Freshness is per announcement, not per `schemeId`: 
it holds across recipients, across `schemeId`s, and across payments to the same recipient. 
Reusing `esk` repeats `epk`, which links the two announcements to one sender. 
Reusing both against the same recipient also repeats `ss`,
and ends up the same stealth address, which merges two payments onto one key.

A sender MUST draw this randomness from a cryptographically secure random number generator.
For `esk` it draws 32 bytes, and if they are not a valid scalar, discards them and draws again.
For the encapsulation it calls `ML-KEM.Encaps(ek)`, 
whose randomness FIPS 203 §3.3 requires to come from an approved RBG 
with a security strength of at least 192 bits for ML-KEM-768. 
If `H(ss)` below fails (Section 1), the sender discards both and draws again.

The sender then computes:

```
epk         = SEC1-compressed(esk·G)                                          33 B
ss_ec       = ECDH(esk, viewing_pk_ec).x                                      32 B
(ct, ss_pq) = ML-KEM-768.Encaps(ek)                                 1 088 B / 32 B
ss          = hybrid_combine("pq-stealth/hybrid-payment/v1",
                             ss_ec, ss_pq, epk, ct, viewing_pk_ec, ek)        32 B
stealth_pk  = spending_pk + H(ss)·G                                    (Section 1)
address     = keccak256(uncompressed(stealth_pk)[1..65])[12..32]              20 B
```

It calls ERC-5564 `announce(3, address, epk || ct, view_tag(ss))` (Section 3) 
and pays `address`. 
The `stealthAddress` argument MUST be `address`, 
because scanners compare against it.
The sender MAY append ERC-5564's token metadata after the view tag. 
The sender learns `stealth_pk` but not `stealth_sk`.

#### 2.5 Scanner

Given a tracking key `viewing_ec || d || z`, the recipient's meta-address, 
and an announcement under `schemeId` 3 whose fields have the lengths of Section 3:

```
epk   <- ephemeralPubKey[0..33]
ct    <- ephemeralPubKey[33..1121]
ss_ec <- ECDH(viewing_ec, epk).x
ss_pq <- ML-KEM-768.Decaps(dk, ct)                       dk expanded from (d, z)
ss    <- hybrid_combine("pq-stealth/hybrid-payment/v1",
                        ss_ec, ss_pq, epk, ct, viewing_pk_ec, ek)
if view_tag(ss) != metadata[0]:                 skip
stealth_pk <- spending_pk + H(ss)·G
if address(stealth_pk) != stealthAddress:       skip
match (stealthAddress, ss)
```

The combiner takes `viewing_pk_ec` and `ek` from the registered meta-address. 
Before scanning, a scanner SHOULD recompute `viewing_ec·G` and `ek` from the tracking key 
and compare them with the registered values. 
Otherwise a corrupted tracking key fails silently.

The address comparison decides correctness of matching. 
The one-byte view tag only lets a scanner skip the offset, 
the point arithmetic and the address hash for 255 of 256 foreign announcements.
Decapsulation never fails, so a scanner MUST NOT treat a successful decapsulation as a match.

The view tag is a function of `ss`, 
so it cannot be checked before both the ECDH and the decapsulation. 
Every `schemeId` 3 announcement therefore costs a scanner 
at least one ECDH and one ML-KEM-768 decapsulation, 
and there is no cheaper prefilter (see also Rationale).

`announce()` is permissionless, so anyone can replay a real announcement. 
A scanner SHOULD deduplicate matches by stealth address.

#### 2.6 Recipient

```
stealth_sk = (spending_sk + H(ss)) mod n
```

The recipient SHOULD check that `stealth_sk·G` gives the matched address before using the key.

A one-time key and its `ss` together give the master spending key:
`spending_sk = (stealth_sk - H(ss)) mod n`. 
Implementations MUST NOT disclose both for the same payment. 
A scanning service already holds every `ss`, 
so handing it any one-time key hands it the master key.

#### 2.7 Errors and skips

| condition | behaviour |
|---|---|
| `schemeId` other than 3 | not processed under this scheme's rules (Section 2.3) |
| `ephemeralPubKey` not 1 121 bytes, or `metadata` empty | skip |
| `epk` not a valid compressed point | skip |
| view tag mismatch | skip |
| `H(ss)` fails its range check (Section 1) | skip |
| announced `stealthAddress` differs from the derived address | skip |
| decapsulation "fails" | cannot happen, because ML-KEM rejects implicitly |
| keygen seed not 128 bytes | error, at key generation |
| `spending_seed` or `viewing_ec_seed` not a valid scalar | error, at key generation |
| `spending_seed` equal to `viewing_ec_seed`, `d` or `z` | error, at key generation |
| meta-address not 1 250 bytes, or either point invalid | error, at decoding |
| `ek` fails FIPS 203's encapsulation input check | error, at encapsulation |

#### 2.8 ERC-5564 methods

Per ERC-5564 our scheme also defines `generateStealthAddress`, `checkStealthAddress` and `computeStealthKey`. 
`schemeId` 3 uses ERC-5564's signatures unchanged. 
`ct` is carried in `ephemeralPubKey` (Section 3).

- `generateStealthAddress(stealthMetaAddress)` implements Section 2.4 and returns `address`,
  `epk || ct` as `ephemeralPubKey`, and `view_tag(ss)` as `viewTag`. 
  `stealthMetaAddress` is the 1 250-byte `meta` of Section 2.2.
- `checkStealthAddress(stealthAddress, ephemeralPubKey, viewingKey, spendingPubKey)` implements Section 2.5. 
It takes no view tag, so it compares addresses only, 
and it returns `false` wherever Section 2.7 says skip.
- `computeStealthKey(stealthAddress, ephemeralPubKey, viewingKey, spendingKey)` implements Section 2.6.
- `viewingKey` is the 96-byte tracking key, from which `viewing_pk_ec` and `ek` are recomputed.
  `spendingPubKey` is `spending_pk`, and `spendingKey` is `spending_sk`.

### 3. Wire format

Announcements use ERC-5564's `announce(schemeId, stealthAddress, ephemeralPubKey, metadata)` unchanged:

| argument | value | length |
|---|---|---|
| `schemeId` | 3 | |
| `stealthAddress` | `address` from Section 2.4 | 20 B |
| `ephemeralPubKey` | `epk || ct` | exactly 1 121 B |
| `metadata` | `view_tag`, then optional ERC-5564 token metadata | at least 1 B |

1. `ephemeralPubKey` MUST be exactly `epk || ct`, in that order: `epk` in bytes 0 to 32 and
   `ct` in bytes 33 to 1 120.
2. The view tag MUST be the first byte of `metadata`, as ERC-5564 requires.
3. A sender MAY follow the view tag with the 56 bytes of token metadata ERC-5564 recommends.
   `schemeId` 3 gives no meaning to any byte after the first. 
   A scanner MUST read only `metadata[0]`, 
   and MUST NOT skip an announcement because `metadata` is longer than one byte.
   These bytes are not bound into `ss`, 
   so, as under `schemeId` 1, they are the sender's unauthenticated claim.

A scanner MUST skip a `schemeId` 3 announcement whose `ephemeralPubKey` is not 1 121 bytes 
or whose `metadata` is empty (Section 2.7). 
Meta-addresses are registered with ERC-6538 `registerKeys(3, meta)` (Section 2.3).

## Rationale

### Why a hybrid

ML-KEM is new, and so are its implementations. 
Combining it with ECDH means that recovering `ss` needs both secrets, 
so `ss` is at least as hard to recover as the harder of the two. 
Against a classical adversary that is today's ECDH. 
Against a quantum adversary it is ML-KEM-768 alone.
The ECDH half costs a 33-byte `epk` per announcement, 
a 33-byte viewing key in the meta-address,
and one ECDH on each side.

### Why ML-KEM-768

ML-KEM is NIST's standardised KEM (FIPS 203). 
ML-KEM-768 is its security category 3 parameter set, 
and it is also used by the hybrid key exchange deployed in TLS.

### Why these hash functions

We make explicit the hash function for consistent independent implementations.
The combiner is only run off-chain thus it can use SHA3-256 
as SP 800-227's `KeyCombineCCA_H` takes a SHA-3 hash and X-Wing uses SHA3-256. 
The offset and the view tag use domain-separated SHA-256, which every wallet stack provides.

### Why the offset and view tag differ from schemeId 1

- **A separate view-tag digest.** 
In ERC-5564 the view tag is the first byte of the digest that is used as the scalar, 
so publishing it gives away 8 bits of that digest. 
ERC-5564 notes the reduction from 128 to 124 bits. 
Here the tag comes from its own digest and says nothing about `H(ss)`.
- **A range check instead of none.** 
A digest equal to 0 or at least `n` is not a valid scalar. 
Reducing mod `n` would turn a digest equal to `n` into offset 0, 
which makes the stealth address the address of `spending_pk` itself 
and links the payment to the registered key in public. 
Failing instead avoids this and keeps the offset uniform. 
Upon failure, the sender can draw fresh randomness and gets a new `ss`.

### Why the view tag comes after the KEM

A view tag derived from `ss_ec` alone would let scanners skip the decapsulation for 255 of 256 announcements. 
But a quantum adversary can compute `ss_ec` for every registered viewing key, 
so such a tag would let it rule out about 255 of 256 candidate recipients for each announcement,
which is enough to deanonymise. 
A tag derived from `ss` is visible only to someone who can decapsulate.

### Why `ct` is carried in `ephemeralPubKey`

ERC-5564 describes `ephemeralPubKey` as the ephemeral public key used by the sender with no bounded size. 
An ML-KEM ciphertext is the sender's per-payment contribution to the shared secret, the KEM counterpart of an ephemeral public key.
Putting `epk || ct` in `ephemeralPubKey` leaves `metadata` as ERC-5564 lays it out, 
so the token metadata convention and ERC-5564's method signatures apply unchanged. 
While putting `ct` in `metadata` instead would displace the token metadata 
and would need extra method parameters to reach `ct`.

### Why the tracking key holds the seed `(d, z)`

The seed is 64 bytes. The expanded decapsulation key is 2 400 bytes. 
FIPS 203 §3.3 allows the seed to be stored and expanded with `ML-KEM.KeyGen_internal`, 
and seed-form keys are now common in ML-KEM libraries. 
`ek` commits to `d` but not to `z`. 
A scanner holding a wrong `z` still finds every payment, 
because `z` only selects the implicit-rejection output for unintended ciphertexts.

### Why the sender's randomness is drawn, not derived

The scanner only decapsulates, so the sender's source of randomness does not affect interoperability, 
and we can pick the simplest safe source. 
Determinism is only needed in the test vectors, to pin `ct`.

### Cost

These figures are Prague figures. 
They come from real transactions on a local anvil node with `--hardfork prague`, 
and `gasUsed` is read from each receipt. 
Both contracts run their canonical deployed runtime bytecode, 
installed at their mainnet addresses 
and pinned by hash in each benchmark's `measured.json`: 
the ERC-5564 announcer at `0x55649E01B5Df198D18D95b5cc5051630cfD45564` 
and the ERC-6538 registry at `0x6538E6bf4B0eBd30A8Ea093027Ac2422ce5d6538`. 
The `schemeId` 3 rows use the real fixture
announcement and meta-address, identified by `fixture.sha256` in `measured.json`. 
`schemeId` 1 has no fixture, so its rows use constructed payloads of the same lengths with no zero byte.

**Announcement**, a standalone `announce()` call:

| schemeId | `ephemeralPubKey` + `metadata` | calldata | gas | pricing rule | vs classical |
|---|---|---|---|---|---|
| 1 (classical) | 34 B | 292 B | 28 313 | standard | 1.00x |
| 3 | 1 122 B | 1 380 B | 69 330 | [EIP-7623](./eip-7623.md) floor | 2.45x |
| 3, with token metadata | 1 178 B | 1 412 B | 70 550 | EIP-7623 floor | 2.49x |

The `schemeId` 3 receipt equals the EIP-7623 calldata floor exactly: 21 000 plus 10 per calldata token. 
So execution is not charged, and the figure is set by calldata size alone. 
The classical receipt is above its floor and pays the standard rate. 
The ratios therefore compare two pricing rules, and any calldata repricing will move them. 
The first `schemeId` 3 row carries the view tag alone in `metadata`. 
The second appends ERC-5564's 56-byte native-token metadata for 1 ETH, 
which Section 3 allows, and costs 1 220 gas more.

**Registration**, a first-time `registerKeys` call with a fresh registrant:

| schemeId | meta-address | vs schemeId 1's 66 B | gas |
|---|---|---|---|
| 1 (classical) | 66 B | 1.0x | 115 310 |
| 3 | 1 250 B | 18.9x | 964 737 |

ERC-6538 writes the meta-address to contract storage, one slot per 32 bytes. 
Storage writes make up most of this cost, and it is paid once per recipient.

**Payment end to end**, for native ETH only:

| | announce | fund | spend | total gas |
|---|---|---|---|---|
| schemeId 3 | 69 330 | 21 000 | 21 000 | 111 330 |

The run announces, funds the derived address, and spends from it with the derived key. 
A token payment adds the token transfer. 
Unless the sender sponsors gas, it also needs a transaction that funds the stealth EOA, 
which links addresses (Security Considerations).

## Backwards Compatibility

This ERC needs no consensus change, no new opcode and no new contract. 
It calls ERC-5564's `announce()` and ERC-6538's `registerKeys` as deployed. 
Existing `schemeId` 1 deployments are unaffected, 
and a recipient can register under both schemes without migrating (but see Section 2.3). 
ERC-5564 requires the ERC that standardises a scheme to declare its `schemeId`, 
and this ERC declares `schemeId` 3.

`schemeId` 3 departs from only one ERC-5564 convention, the meta-address length. 
ERC-5564 defines meta-addresses of length `n` or `2n` for a scheme whose public keys are `n` bytes long.
`schemeId` 3 has keys of two lengths, 33 and 1 184 bytes. 
Its 1 250-byte meta-address is not of that form.

It keeps ERC-5564's other conventions. 
The view tag is the first byte of `metadata`, 
which can carry ERC-5564's token metadata after it, 
and the methods of Section 2.8 have ERC-5564's signatures. 
Its `ephemeralPubKey` is 1 121 bytes rather than one 33-byte point, 
so a tool that assumes the length of `schemeId` 1's must check upon `schemeId` first.

## Test Cases

Conformance vectors are in the two files below, 
with a SHA-256 digest of each in
[`vectors/manifest.json`](../assets/erc-0/vectors/manifest.json).
[`vectors/PLAN.md`](../assets/erc-0/vectors/PLAN.md) 
states, 
for each row, the requirement it pins 
and the wrong output it distinguishes.

| file | rows | what it pins |
|---|---|---|
| [`vectors/section-1.json`](../assets/erc-0/vectors/section-1.json) | 6 | Section 1: the offset, its range check, byte order and the view tag |
| [`vectors/section-2.json`](../assets/erc-0/vectors/section-2.json) | 19 | Section 2: keys and seeds, the meta-address, the combiner and its bindings, the address, the wire mapping, and what counts as a skip |

The generator, [`tools/gen_vectors.py`](../assets/erc-0/tools/gen_vectors.py), 
does its arithmetic in [`tools/vecprim.py`](../assets/erc-0/tools/vecprim.py) 
and imports nothing from the reference implementation. 
ML-KEM values come from NIST's ACVP files, 
vendored at [`vectors/tier1/ml-kem-768-acvp.json`](../assets/erc-0/vectors/tier1/ml-kem-768-acvp.json). 
Running `python3 tools/gen_vectors.py --check` in the directory that holds `vectors/` and `tools/`
re-derives every vector and compares it with the files above. 
It needs only the Python standard library.

Three conventions apply to the vectors:

- **The range check's failure is tested synthetically.** 
No findable `ss` produces a `base` that is 0 or at least `n`, 
so V1-03 and V1-04 supply `base` directly.
- **Encapsulation is pinned through `Encaps_internal`.** 
The vectors fix `m` and use `ML-KEM.Encaps_internal(ek, m)`, 
so they pin `ct` and `ss_pq`. 
A sender using `ML-KEM.Encaps(ek)` produces different, 
equally valid announcements. 
Every scanner-side vector applies to it unchanged.
- **Decapsulation of a foreign ciphertext uses NIST's own case.** 
V3-14 takes an ACVP `modified ciphertext` case, 
so implicit rejection is checked against NIST's expected value.

Two vectors from `section-1.json`:

```
V1-01  ss       = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
       base     = d8b37e9fb5fd784cc30b719589811092fce202abc0f500d6609a2f69f78b171f
       H(ss)    = d8b37e9fb5fd784cc30b719589811092fce202abc0f500d6609a2f69f78b171f
V1-07  view_tag = fe                                                  (same ss)

V1-03  base     = 0000000000000000000000000000000000000000000000000000000000000000
       H(ss)    fails
```

## Reference Implementation

The reference implementation is a Rust workspace in the repository linked from the discussion thread. 
Its `per-payment` crate implements this scheme on three others: 
`kem` (ML-KEM-768, checked against NIST ACVP), 
`ec` (secp256k1) 
and `core` (the interface the scheme implements).
It passes every vector above.

Its sender, `announce_random`, draws `esk` and ML-KEM's `m` from the operating system's CSPRNG,
as Section 2.4 requires. 
A second, seeded `announce` takes that randomness as input instead. 
It exists so that the vectors, the demonstration and the gas harness are reproducible, 
and it is not a sender for real payments. 
The harness feeds it seeds from SHAKE256 over a fixed secret and a counter. 
Keygen seeds come from HKDF-SHA256, 
which is one instance of the requirements in Section 2.1 
and not part of the standard.

The gas figures under Rationale come from three harnesses in the same repository: 
one for the announcement, 
one for the registration 
and one for the whole payment. 
Each commits its receipts as `measured.json`.

The implementation has had no external cryptographic review.

## Security Considerations

### What this scheme protects, and what it does not

`schemeId` 3 protects the announcement layer: 
the link between an announcement and its recipient, 
against an adversary who reads every announcement and every registered meta-address,
now or after building a CRQC. 
It does nothing for the rest of the on-chain transaction graph:

- The sender's funding transfer to the stealth address is public, 
as in any stealth-address scheme.
- A recipient who spends from or sweeps several stealth addresses into one account links them,
to each other and to that account.
- A stealth EOA that receives only tokens needs ETH for gas. 
Whoever funds it is linked to it,
so ERC-5564's discussion of recipients' transaction costs applies unchanged.
- Timing and amounts can correlate payments.

### KEM anonymity is required

The ERC-6538 registry gives an adversary every candidate encapsulation key. 
If an ML-KEM-768 ciphertext revealed which `ek` it was intended for, 
every payment could be linked to its recipient without decrypting anything. 
`schemeId` 3 therefore assumes that ML-KEM-768 is ANO-CCA
(anonymous under chosen-ciphertext attack) as well as IND-CCA. 
FIPS 203 does not claim anonymity.

CRYPTREC's evaluation of ML-KEM (PQShield, CRYPTREC-EX-3502-2025, Section 4) 
concludes that it yields anonymity in the quantum random-oracle model 
when ML-KEM is used with a symmetric scheme, 
provided ML-KEM is strongly collision-free CCA secure 
and its underlying K-PKE is strongly disjoint-simulatable and correct. 
Anonymity is stated here as an assumption rather than inherited.

The other announcement fields reveal nothing about the recipient, 
as long as `ss` stays secret.
`epk` is independent of the recipient's keys. 
The view tag and `stealthAddress` are functions of `ss`.

### Against a quantum adversary

A quantum adversary can compute `ss_ec` for every announcement and every registered viewing key,
hence `ss`'s security relies entirely through `ss_pq`, 
which relies on ML-KEM-768's IND-CCA security and the combiner of Section 1.1. 
Conversely, if ML-KEM-768 is broken classically, `ss_ec` keeps `ss` secret from a classical adversary.

### Spending once a CRQC exists

Spending is secp256k1, so a CRQC breaks it the way it breaks every EOA. 
A spend reveals the stealth address's public key, from which the private key can then be computed. 
A CRQC also recovers `spending_sk` from the registered `spending_pk`. 
From then on, anyone who holds a payment's `ss` can spend that payment, 
and that includes a delegated scanner or anyone who has obtained the tracking key. 
What survives a CRQC is the privacy of announcements already published, 
for as long as ML-KEM-768 holds. 
Funds need a separate migration before that point.

### Delegated scanning

A scanning service given the tracking key sees every payment to the recipient, with its timing and count. 
Before a CRQC it cannot spend them. 
Section 2.6 explains why a one-time key must never be disclosed to it, 
and the previous subsection explains why the tracking key becomes a spending capability after a CRQC.

### One-time key and `ss`

A leaked one-time key together with its `ss` yields the master spending key.
A leaked one-time key alone yields nothing. 
This follows from ERC-5564's additive derivation and is not new here.

### Sender randomness

Section 2.4 states the consequences of reusing an announcement's randomness: 
linked announcements, and payments merged onto one key. 
A sender's security therefore relies on its random number generator.

### Downgrade

A recipient registered under both `schemeId` 1 and `schemeId` 3 
can be paid under `schemeId` 1 by any sender, 
and that payment has no post-quantum announcement privacy. 
Section 2.3 is the mitigation: 
senders that implement `schemeId` 3 must prefer it, 
and recipients who need the protection should register only `schemeId` 3.

Scanners still find payments made under `schemeId` 1, 
including those made before a recipient already cleared that entry (Section 2.3), 
so a downgraded payment loses its post-quantum privacy 
but not its funds. 
A wallet can show which payments were announced under `schemeId` 1, 
since those are the ones a future quantum adversary can link to the recipient.

### Scanner cost and denial of service

Each `schemeId` 3 announcement costs a scanner 
one ECDH, one ML-KEM-768 decapsulation and one hash over about 2.4 kB, with no cheaper prefilter. 
Anyone can publish announcements, 
so an attacker can make scanning more expensive by paying calldata gas per announcement. 
Every malformed field is a skip (Section 2.7), 
so malformed input cannot halt a scan. 
ERC-5564's discussion of denial-of-service countermeasures applies.

### View tag

The view tag is one byte of a digest of `ss`, 
separate from the digest that yields the offset. 
It tells an observer without `ss` nothing, 
and unlike `schemeId` 1 it does not shorten the offset digest.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
