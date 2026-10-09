# Conformance vector plan — schemeId 3, and what it shares

## 1. Each test vector is explainable

Every vector is a JSON object with six fields, e.g.

```json
{
  "id":       "V1-03",
  "spec":     "Section 1",
  "claim":    "the range check MUST reject base = 0",
  "given":    { "base": "0x0000…0000" },
  "expect":   { "outcome": "fail" },
  "wrong":    "offset = 0 accepted — an implementation that does not range-check base makes
               the stealth address the address of spending_pk itself"
}
```

### Two tiers of test vectors

| tier | covers | oracle | who generates it |
|---|---|---|---|
| 1 | ML-KEM-768 itself | **FIPS 203 / NIST ACVP** | nobody — vendored at a pinned commit |
| 2 | **everything below** | the specification text | a standalone generator, no project code |

---

## 2. Section1 — common to every schemeId

| id | claim | given | expect | wrong |
|---|---|---|---|---|
| V1-01 | `H(ss) = SHA256(DS_offset ‖ ss)`, range-checked | a fixed `ss` | `base`, and `offset = base` | — |
| V1-02 | **every digest is big-endian** | an `ss` whose digest starts `0x01` and ends `0x80` | the integer, MSB first | little-endian read gives a different scalar, therefore a different address, therefore **funds the recipient cannot spend**. Silent and total |
| V1-03 | the range check MUST reject `base = 0` | `base = 0x00…00` | failure | `offset = 0` — no range check, and the stealth address is then the address of `spending_pk` itself |
| V1-04 | the range check MUST reject `base = n` | `base = n_secp256k1` | failure | reduced mod n to 0, which some libraries do silently |
| V1-05 | `base = n − 1` is **valid** | `base = n − 1` | `offset = n − 1` | rejected — an off-by-one in the bound loses a legitimate payment |
| V1-06 | ~~the counter byte is a single byte appended~~ WITHDRAWN: Section 1 no longer retries with a counter | — | — | — |
| V1-07 | `view_tag = SHA256(DS_viewtag ‖ ss)[0]` | a fixed `ss` | one byte | **the superseded eight-byte width**, `[0..8]`, which matches nothing a conforming sender emits; taking `[31]` instead of `[0]`; or the leading byte of `H(ss)` instead of a separate digest |

## 3. Section2 — schemeId 3

| id | claim | given | expect | wrong |
|---|---|---|---|---|
| V3-01 | keygen seed is 128 B | 128 B; then 96 B and 127 B | outputs; then errors | accepting a legacy 96-byte seed |
| V3-02 | keygen MUST reject a seed whose `spending_seed` equals **any** 32-byte component of the delegated object: `viewing_ec_seed`, `d` or `z` | `spending_seed` copied into each component in turn — offsets 0, 32 and 64 of `viewing_ec ‖ dk` | error, all three times | **comparing against `viewing_ec_seed` alone.** That catches a port of ERC-5564's single-key meta-address and misses the same 32 bytes copied into the KEM seed, which a scanning service receives verbatim |
| V3-02a | a keygen with no equal component is accepted | a seed whose delegated object contains no component equal to `spending_seed` | outputs, no error | rejecting valid keygens — the positive control, without which V3-02 passes on an implementation that rejects everything |
| V3-03 | meta is 1 250 B and **both** points are validated | a `0x05`-tagged `viewing_pk_ec`, `spending_pk` well-formed | error at decode | validating only `spending_pk`, which is the natural port of a decoder for a meta-address that carries one point |
| V3-04 | `ss_ec` is the **x-coordinate alone** | `esk`, `viewing_pk_ec` | 32 bytes | the full 65-byte point, or the 33-byte compressed form → a different `ss`, silently |
| V3-05 | the domain separator is the **first** input, neither appended nor length-prefixed | the IKM above | 32-byte `ss` | appending it, or length-prefixing it → a different `ss`, silently. This is the parameter that replaced the absent-salt requirement when the derivation became a direct hash, and no other vector pinned it |
| V3-06 | IKM is exactly `ss_ec ‖ ss_pq ‖ epk ‖ ct ‖ viewing_pk_ec ‖ ek`, in that order | the six parts | 32-byte `ss` | any other order, and **any omission** → a different `ss`. The historical three-field form `ss_ec ‖ ss_pq ‖ epk` is the likeliest omission |
| V3-06a | `ct` is bound in | two announcements with the same `epk` and `ss_ec` but different `ct` | different `ss` | the same `ss`. Hashing both ciphertexts in is what keeps the combiner IND-CCA when only one component KEM is (Giacon–Heuer–Poettering; SP 800-227 §4.6.3's `KeyCombineCCA_H`) |
| V3-06b | `viewing_pk_ec` is bound in | the same `ss_ec` reached against two recipients' registered keys | different `ss` | the same `ss`, which is the identity binding absent from the old IKM |
| V3-07 | `epk` MUST be bound in | the same first contact with the parity byte flipped `0x02`↔`0x03` | a **different** `ss` | the same `ss` — the flipped point has the same x-coordinate, so without `epk` in the IKM this is a replay with a different-looking announcement |
| V3-08 | wire shape | the sender above | **`epk ‖ ct`** 1 121 in `ephemeralPubKey`, `view_tag` 1 in `metadata`, 1 122 B | `ct ‖ epk`, the same length as the right answer, so no length check distinguishes it; and the superseded layout with `ct` in `metadata`, which a conforming scanner skips on the `ephemeralPubKey` length |
| V3-08a | the view tag is `metadata[0]`, and later bytes are ignored | the same `ephemeralPubKey` with `metadata` = the view tag alone, then the view tag followed by ERC-5564's 56-byte native-token block | both parse, to the same view tag | **requiring `metadata` to be exactly one byte**, which skips every payment from a sender following ERC-5564's token-metadata recommendation; or reading the tag off the end of `metadata`, which is the amount's low byte once the token block is there |
| V3-09 | **keygen MUST be deterministic in the seed** | a 128-byte seed whose `kem_seed` is ACVP keygen `(d, z)`, so `ek` is NIST's value | the 1 250-byte meta-address, the 96-byte tracking key, the 32-byte master | calling the KEM's randomness-taking keygen and ignoring `kem_seed` — the entry point most ML-KEM APIs offer first. The meta-address is well formed and registration succeeds; nothing fails until the owner restores from seed, gets a different `dk`, and can decapsulate no payment ever made to the registered `ek` |
| V3-10 | `spending_seed` and `viewing_ec_seed` MUST each be a valid secp256k1 scalar | 128-byte seeds differing only in one 32-byte half: `0`, `n`, `n − 1`, and `viewing_ec_seed = 0` | error, error, **accepted**, error | reducing the seed mod n rather than rejecting it. Nothing in this document reduces mod n: `spending_seed = n` becomes `0`, and every payment to the resulting meta-address is spendable by anyone. `n − 1` is the positive control |
| V3-11 | decoding MUST reject a meta-address length other than 1 250 | 1 249, 1 250, 1 251 | error, accepted, error | slicing `[0:33]`, `[33:66]`, `[66:]` with no length check: 1 251 decodes with a trailing byte ignored, 1 249 yields a 1 183-byte `ek` the KEM rejects at the first payment rather than at decode |
| V3-12 | 33 bytes of the right length can still be a **non-point** | `0x02 ‖ x` for `x = 5`, the smallest `x` with no `y` on the curve; then a valid key | error at decode, then accepted | checking the length and the `0x02`/`0x03` tag byte and storing the bytes. The ECDH that follows throws from inside a curve library, far from the meta-address that caused it — or, in a library that does not validate, returns a value on the wrong curve |
| V3-13 | `address = keccak256(uncompressed(pk)[1..])[12..32]` | a derived `stealth_pk`, both encodings | the 20-byte address and its EIP-55 form | keccak of the *compressed* form; keccak *with* the `0x04` prefix; `[0..20]` rather than `[12..32]`. Each is 20 well-formed bytes and each is a different address — the payment is lost to a chain address nobody holds a key for, not to an error |
| V3-14 | a view-tag mismatch is a skip — **and decapsulation does not fail** | ACVP decapsulation tcId 88, `reason: modified ciphertext`; `ek` read from `dk[1152:2336]` and checked against the `H(ek)` at `dk[2336:2368]` | 32 bytes and **no error**; a derived tag differing from the announced one; **skip** | scanning on whether `Decaps` errored — it never does, so such an implementation matches every announcement ever published. Raising on the mismatch is the other error: `announce()` is permissionless, so an error path there is a scanner denial of service (Section2.7) |
| V3-15 | a malformed announcement is a **skip at the entry point**, not an error | `ephemeralPubKey` of 33, 1 120, 1 121, 1 122 B; `metadata` of 0, 1, 57 B | skip unless `ephemeralPubKey` is 1 121 B and `metadata` is non-empty | raising, or propagating a library exception. Anyone can call `announce()` with any bytes, so a scanner that errors on shape stops at the first announcement an attacker publishes, for the price of one transaction. 1 121 / 1 and 1 121 / 57 are the positive controls |

## 7. Deliverables, in order

1. `tools/gen_vectors.py` — standalone, `hashlib` plus one secp256k1 library, **imports
   nothing from this repository.** Emits one JSON file per section plus a manifest with a
   sha256 per file.
2. `vectors/*.json` — the sets above, committed.
