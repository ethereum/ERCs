---
title: Transaction Metadata Encoding for EIP-8130
description: A structured CBOR encoding for the EIP-8130 metadata field covering attribution, memos, and commitments to off-chain data, scoped to a transaction, phase, or call
author: Chris Hunter (@chunter-cb) <chris.hunter@coinbase.com>
discussions-to: https://ethereum-magicians.org/t/erc-transaction-metadata-encoding-for-eip-8130
status: Draft
type: Standards Track
category: ERC
created: 2026-06-11
requires: 5792, 8130
---

## Abstract

[EIP-8130](./eip-8130.md) adds an optional, opaque `metadata` field to its transaction type for attribution and annotation data, but leaves the byte layout to a companion specification. This proposal defines that layout.

`metadata` is a single deterministic [CBOR](https://www.rfc-editor.org/rfc/rfc8949) value in one of four forms: a **text string** (a memo), a **byte string** (a commitment digest), a **map** of reserved keys (attribution, memo, commitment, and scope), or an **array** of any of these (multiple independent annotations). The map keys are interoperable with [ERC-8021](./eip-8021.md) schema 2, so existing attribution registries and parsers apply unchanged, extended here with keys for off-chain commitments and call scoping.

The encoding lets a single signed field carry a bare memo with no overhead, full multi-party attribution, a privacy-preserving commitment to off-chain data, or any combination, each optionally scoped to the whole transaction, a phase, or a single call. This proposal also defines an [ERC-5792](./eip-5792.md) `metadata` capability that lets applications contribute metadata through `wallet_sendCalls`, superseding the `dataSuffix` capability. Because the protocol never interprets `metadata`, the encoding is self-identifying through strict deterministic decoding rather than any protocol enforcement.

## Motivation

[EIP-8130](./eip-8130.md) replaces the single `tx.input` byte string of legacy transactions with a structured `calls` array of execution phases, and provides a top-level `metadata` field as the home for the data that legacy wallets appended to `tx.input` as a **data suffix**. That field is opaque bytes: useful as a signed, charged location, but with no shared structure, every producer would invent its own framing and no indexer could read across them.

Batching also broadens what metadata is useful for beyond a single transaction-level suffix:

- **Builder and application attribution**: identifying the wallet builder or the applications whose calls the transaction contains.
- **Multi-application batching**: per-application attribution lets analytics and revenue be split correctly across contributors when several applications share one transaction.
- **Payments and remittance**: an invoice number, reference, or memo attached to the transaction or to a specific transfer in a batch.
- **Intents and routing**: a tag marking a group of calls as one intent or solver route for indexers and portfolio tools.
- **Commitments to off-chain data**: a hash of an off-chain document (for example a receipt with line-item detail), so the transaction is provably tied to that document while the content stays private.

These differ in *scope* (whole transaction vs. a phase vs. a single call) and in *who* produces them. A shared, self-describing encoding lets producers attach independently scoped annotations into the one signed `metadata` field, and lets any indexer recover all of them with a single parser. The most common case, a single small annotation, costs only a few bytes more than the raw data itself.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Value forms

The [EIP-8130](./eip-8130.md) `metadata` field, when non-empty and structured per this proposal, is a single CBOR value in one of four forms. A consumer branches on the CBOR major type of the first byte:

| Form | CBOR type | Meaning |
| --- | --- | --- |
| Text string | major type 3 | A memo. Equivalent to a map `{t: <text>}` at whole-transaction scope. |
| Byte string | major type 2 | A commitment digest. Equivalent to a map `{h: <digest>}` at whole-transaction scope. |
| Map | major type 5 | A single annotation record; see [Keys](#keys). |
| Array | major type 4 | Multiple independent annotations, each element a text string, byte string, or map, interpreted as above. |

The text-string and byte-string forms are shorthands for the single-key map forms, so a parser MAY normalize them to maps before processing. An array MUST NOT contain a nested array.

An empty `metadata` field carries no annotation.

The entire `metadata` byte string is part of the signed [EIP-8130](./eip-8130.md) transaction (covered by the sender signature, and the payer signature when present) and is charged per byte at the transaction's calldata rate. Because the bytes are signed as a unit, the wallet that assembles the transaction is responsible for producing the final encoding from the contributions of each party.

### Keys

A map uses text-string keys. All keys are OPTIONAL; unrecognized keys MUST be ignored.

| Key | Name | Value | Description |
| --- | --- | --- | --- |
| `a` | application | text | Application attribution code. |
| `w` | wallet | text | Wallet attribution code. |
| `s` | services | array of text | Service attribution codes (block builders, relayers, solvers). |
| `r` | registries | map | Custom registry overrides, keyed by entity type. |
| `m` | metadata | map | A sub-map of arbitrary application key-value pairs. |
| `t` | text | text | A memo (human- or application-readable text). |
| `h` | commitment | byte string | A digest committing to off-chain data; its length follows from the hash algorithm (typically 32 bytes). See [Commitments](#commitments). |
| `p` | phase | uint | Phase scope (0-based index into `calls`). See [Scope](#scope). |
| `c` | call | uint | Call scope (0-based index within phase `p`). See [Scope](#scope). |

The `a`, `w`, `s`, `r`, and `m` keys are [ERC-8021](./eip-8021.md) schema 2; their values are ERC-8021 codes (and, for `m`, an arbitrary metadata sub-map) resolved through the registry mechanism that ERC-8021 defines. This proposal reuses that vocabulary and registry rather than re-specifying it, and references ERC-8021 only for the *meaning* of the codes, not for byte framing. The ERC-8021 calldata `ercMarker`, `schemaId` byte, and `cborLength` prefix are not used: the value is self-delimiting and length-known from the RLP `metadata` field. An ERC-8021 schema 2 map drops in as a `metadata` value without modification.

The `t`, `h`, `p`, and `c` keys extend schema 2: `t` is a plain-text memo, `h` is an off-chain commitment, and `p`/`c` carry scope.

### Scope

`scope` associates a map with part of the transaction's [EIP-8130](./eip-8130.md) `calls` (an ordered array of phases, each an ordered array of calls), using the `p` and `c` keys:

| Keys present | Meaning |
| --- | --- |
| neither `p` nor `c` | The whole transaction. |
| `p` only | Phase `p` (0-based) of `calls`. |
| `p` and `c` | Call `c` (0-based) within phase `p`. |

A `c` key without a `p` key is invalid; a consumer MUST treat such a map as whole-transaction scope. A consumer SHOULD ignore the scope (treating the map as whole-transaction) of any map whose `p` or `c` references an index that does not exist in `calls`. Bare text-string and byte-string values are always whole-transaction scope. Multiple maps MAY share the same scope, and a single call MAY be described at call, phase, and transaction scope simultaneously.

Wallets MUST set `p` and `c` only after the `calls` array is finalized. The final phase structure is not known until all parties (sender, payer, and any other contributors) have determined their calls; setting scope before that risks pointing at the wrong phase if a payer prepends a payment phase or if calls are otherwise reordered during construction.

> **Note (non-normative):** In [ERC-8168](./erc-8168.md) sponsored flows, the typical construction order is: (1) app sends `wallet_sendCalls` with its calls and metadata intent; (2) wallet contacts the payer service, which may prepend a payment phase; (3) wallet resolves each annotation's final phase index in the assembled `calls`; (4) wallet encodes `metadata` and signs. The app's original calls may shift from phase 0 to phase 1 when a payer prepends, so the wallet maps them to the correct index before encoding.

### Commitments

A commitment (the `h` key, or a bare byte string) binds the transaction to off-chain data without revealing it. Its value is the **digest** of the off-chain document (for example a `keccak256` hash, or a Merkle root for selectively-disclosable documents). The digest length follows from the hash algorithm and is typically 32 bytes; the algorithm is part of the self-describing off-chain document, not fixed by this proposal. Only the digest appears on-chain, so the document's contents (for example receipt line items) stay private until revealed.

The off-chain document is **self-describing**: the hash algorithm, the document format, and how the digest was computed are defined by the document and the application that produces it, not by this proposal. A verifier recomputes the digest over a presented document and compares it to the on-chain value.

This proposal deliberately does not carry a **locator** for the off-chain document. Following the model of off-chain attestations in systems like the [Ethereum Attestation Service](https://attest.org), the digest is the only on-chain artifact; the document is resolved through an application side channel (a shared URL, a content-addressed store such as IPFS, or peer-to-peer delivery). Applications that need an on-chain locator MAY carry it in an `m` field alongside the commitment.

A commitment's scope ties the off-chain data to its subject: whole-transaction for a receipt covering the transaction, `p` for one phase, or `p`+`c` for a document describing one call (for example one transfer in a batch).

**Batches (RECOMMENDED).** When a batch commits to one off-chain document per call, a producer SHOULD aggregate the per-call digests into a single Merkle root and carry one commitment scoped to the phase (or the whole transaction), rather than one commitment per call. Each call's document is a leaf; to prove a single call's data, a verifier is shown that document together with a Merkle proof (the sibling hashes) and recomputes the root. This collapses `N` on-chain digests into one 32-byte root while still binding every document, and disclosing one leaf reveals only sibling hashes, not the contents of the other documents.

Each leaf is typically a sizable but templated document (for example a JSON receipt), and a Merkle proof discloses the sibling hashes of any revealed leaf. Producers SHOULD therefore give each document a high-entropy salt so that disclosing one leaf does not let an observer confirm guesses about the sibling documents (see [Security Considerations](#security-considerations)).

**Recommended Merkle tree construction.** Producers SHOULD use the following construction so off-chain tooling can produce interoperable proofs:

- Leaves are ordered by call index (call 0, call 1, ...).
- Each leaf is `leaf[i] = keccak256(0x00 || salt[i] || document[i])`, where `salt[i]` is 32 random bytes unique to that document and `0x00` is a 1-byte domain separator for leaves.
- Internal nodes are `node = keccak256(0x01 || min(left, right) || max(left, right))`, where `0x01` is the internal-node domain separator and siblings are sorted so a verifier needs only the sibling hashes, not their left/right position.
- If the leaf count is odd, the last leaf is duplicated.
- A proof for leaf `i` is the ordered array of 32-byte sibling hashes from leaf level to the root.

Adherence to this construction is RECOMMENDED, not REQUIRED; the off-chain document set remains self-describing about its tree construction.

### Determinism

Producers MUST encode `metadata` using CBOR core deterministic encoding ([RFC 8949 §4.2](https://www.rfc-editor.org/rfc/rfc8949#section-4.2)): definite-length items only, integers and lengths in their shortest form, and map keys sorted in bytewise lexicographic order of their encodings. Determinism ensures the signed bytes are reproducible by any party validating the transaction and that a digest computed over the value is stable.

### Identification and strict decoding

The protocol never parses `metadata`, so this proposal is not identified by any protocol tag or magic prefix; a `metadata` field is recognized as structured per this proposal purely by whether it decodes under the strict rules below. A consumer MUST treat the field as structured **only if both** of the following hold, and MUST otherwise treat the entire field as opaque bytes:

1. The bytes decode as a single CBOR value (text string, byte string, map, or array of those) that **consumes the entire `metadata` field** with no trailing bytes. The field length is known from RLP, so this check is always available.
2. The encoding is canonically deterministic per [Determinism](#determinism); a non-canonical encoding (indefinite-length items, non-shortest integers, unsorted or duplicate map keys) MUST be rejected as opaque.

A consumer MUST NOT use a lax decoder that accepts a complete item followed by trailing bytes, because many unrelated byte strings begin with a parseable CBOR item.

This proposal does not reserve a CBOR semantic tag or version prefix. A future revision MAY introduce one for explicit versioning; consumers that do not recognize a future tag fall back to opaque per the rules above.

**Foreign encodings.** A producer MAY treat `metadata` as wholly opaque to this proposal and use a different encoding. To avoid being read as a memo or commitment, such a producer SHOULD make its encoding self-describing, or begin the field with the byte `0xFF`. `0xFF` is the CBOR "break" code and can never begin a well-formed CBOR data item, so a strict decoder rejects it immediately, and no value form under this proposal begins with `0xFF`.

### Consumer behavior

For an [EIP-8130](./eip-8130.md) transaction whose `metadata` satisfies [Identification and strict decoding](#identification-and-strict-decoding), a consumer:

1. Branches on the value form (text, byte string, map, or array), normalizing the bare forms to their single-key map equivalents.
2. For each map, resolves scope from `p`/`c` against `calls` per [Scope](#scope), ignoring out-of-range scopes, and reads the recognized keys, ignoring unrecognized ones.

A consumer MUST treat metadata as describing only the transaction it appears in, and MUST NOT infer any execution effect from it: it is an inert annotation, never dispatched or executed.

### Application and wallet integration ([ERC-5792](./eip-5792.md))

Applications contribute metadata through a `metadata` capability on [ERC-5792](./eip-5792.md) `wallet_sendCalls`. This capability supersedes the `dataSuffix` capability: where `dataSuffix` passed opaque bytes for the wallet to append blindly, `metadata` passes a structured value (or values) that the wallet places in the signed [EIP-8130](./eip-8130.md) `metadata` field.

```typescript
interface MetadataCapability {
  metadata: {
    // One or more annotations the app wants attached. Each is a memo string,
    // a commitment digest, or a map of the keys defined by this proposal.
    // Any p/c scope refers to the calls in THIS request.
    value: MetadataValue | MetadataValue[];
    optional?: boolean; // if true, wallet MAY proceed without it; if false (default), wallet MUST reject when it cannot
  };
}
```

The application provides values describing its own calls; any `p`/`c` scope refers to the call array the application submits in this request. The wallet is the final assembler and MUST:

1. Map each contributed annotation's scope to the corresponding phase or call index in the finalized `calls` (which MAY differ from the request, for example when a payer prepends a phase under [ERC-8168](./erc-8168.md), or when calls from several requests are batched).
2. Append its own attribution (its wallet code `w`) as a separate map; it MUST NOT merge its code into an app-contributed attribution map.
3. When batching multiple `wallet_sendCalls` requests, treat each request's annotations independently and resolve each to the phase its calls occupy in the final `calls`.
4. Encode the resulting value (a single value when only one annotation results, otherwise an array) into the `metadata` field per this proposal, deterministically, and sign.

If the wallet cannot honor the capability and `optional` is not `true`, it MUST reject the request. A wallet that still receives a legacy `dataSuffix` capability MAY carry an [ERC-8021](./eip-8021.md) attribution suffix as the corresponding attribution map, or other suffix bytes as a foreign encoding (see [Identification and strict decoding](#identification-and-strict-decoding)).

## Examples

Byte counts are for the encoded `metadata` field. Lengths assume short ASCII codes.

**1. Bare memo (13 bytes).** A payment reference, no attribution.

```
metadata = "invoice 4471"
hex      = 6c696e766f6963652034343731
```

**2. Attribution (22 bytes).** Wallet and application identify themselves.

```
metadata = { a: "baseapp", w: "mywallet" }
hex      = a2 6161 6762617365617070 6177 686d7977616c6c6574
```

**3. Bare commitment (34 bytes).** A 32-byte root binding the whole transaction to off-chain data.

```
metadata = h'<32-byte digest>'
hex      = 5820 <32 bytes>
```

**4. Attribution + memo (37 bytes).** Who sent it and why, in one map.

```
metadata = { a: "baseapp", w: "mywallet", t: "invoice 4471" }
```

**5. Attribution + memo + commitment (73 bytes).** Identity, reference, and a receipt hash in one signed map.

```
metadata = { a: "baseapp", w: "mywallet", t: "invoice 4471", h: h'<32-byte digest>' }
```

**6. Sponsored transaction: whole-tx attribution + phase-scoped memo (42 bytes).** The payer prepends phase 0; the app's transfer is phase 1.

```
metadata = [
  { a: "baseapp", w: "mywallet" },   // whole transaction
  { t: "invoice 4471", p: 1 }        // phase 1 only
]
```

**7. Remittance batch committed as one Merkle root (40 bytes).** Five transfers in phase 0, one root over five salted receipts.

```
metadata = { p: 0, h: h'<32-byte Merkle root>' }
```

**8. Intent / solver routing tag (46 bytes).**

```
metadata = { a: "myapp", m: { intent: "swap-eth-usdc", solver: "1inch" } }
```

**9. Multi-application batch with per-phase attribution (42 bytes).** Two apps share a transaction; the wallet's attribution covers the whole transaction.

```
metadata = [
  { a: "defi-app", p: 0 },
  { a: "nft-app",  p: 1 },
  { w: "mywallet" }          // whole transaction
]
```

**10. Compliance commitment scoped to one call (43 bytes).** A document bound to a specific transfer `[0, 0]`.

```
metadata = { h: h'<32-byte digest>', p: 0, c: 0 }
```

## Rationale

### One value, four forms

The most common annotation is a single small one: a memo, an attribution, or a commitment. Encoding these as bare CBOR primitives (a text string or a byte string) means the field costs only a couple of bytes more than the raw data, with no envelope overhead. A map carries the same primitives by key when more than one is needed, and an array carries several independently scoped maps when multiple parties or scopes are involved. The bare forms are exact shorthands for single-key maps, so a parser can normalize and then treat everything uniformly. Branching on CBOR major type, rather than a leading type tag, is what makes the cheap cases cheap.

### Reusing ERC-8021 keys

Attribution already has a well-specified, registry-backed vocabulary in [ERC-8021](./eip-8021.md) schema 2 (`a`, `w`, `s`, `r`, `m`). Reusing those keys verbatim means existing code registries, payout resolution, and parsers apply with no translation, and an ERC-8021 schema 2 map is a valid `metadata` value as-is. This proposal adds only what schema 2 lacks for [EIP-8130](./eip-8130.md): a plain-text memo key (`t`), a commitment key (`h`), and scope keys (`p`, `c`). Keeping one shared key space avoids a parallel attribution vocabulary.

### CBOR

CBOR is compact, self-describing, widely implemented, and has a specified deterministic profile, which matters because the bytes are signed. The structural overhead is a few bytes per map and dominated by the payload, and on rollups the repeated keys compress to near-nothing across a batch. A bespoke binary format could save a handful of bytes but would forfeit the tooling, the deterministic profile, and ERC-8021 compatibility.

### No type byte

The field is never interpreted by the protocol and its length is always known from RLP. That length lets a consumer require the CBOR to consume the field exactly, under canonical-deterministic rules, so a structured value is recognized without spending a byte on a tag. A lax decoder that accepted trailing bytes would mis-read unrelated data, so the strict full-consume rule, not a tag, is what makes identification safe; a tag is left to a future version for explicit versioning.

### Encoding the top-level field versus a sink address

An alternative transport carries metadata as a no-op call to a reserved sink address inside the `calls` array, using the call's position to express scope. This proposal instead encodes the top-level `metadata` field: it keeps metadata out of `calls` so it cannot interact with execution, gas estimation, or phase atomicity; scope is explicit data (`p`/`c`) rather than inferred from call placement, so producers need not add empty phases; and a single signed field with one parser is simpler than recognizing and filtering a reserved address across phases. The trade-off is a dependency on [EIP-8130](./eip-8130.md) defining the `metadata` field.

### Scope mirrors the calls structure

A builder code describes the whole transaction, while a remittance memo describes one transfer in a batch. Encoding scope as a phase index or `[phase, call]` pair reuses [EIP-8130](./eip-8130.md)'s existing two-level `calls` structure rather than inventing a parallel addressing scheme. Absolute indices are safe because the wallet, which both receives the app's intent and assembles the final `calls`, is the sole encoder of `metadata` and resolves indices after the structure is final.

### Commitments for privacy

Publishing a digest instead of the document keeps sensitive detail (receipt contents, invoice line items, compliance references) off-chain while still binding the transaction to it. The value carries only the digest; the document is self-describing about its own hashing and format and is resolved out-of-band. This mirrors how off-chain attestation systems keep the on-chain footprint to a commitment and leave storage and delivery to the application, avoiding a storage locator or format registry in signed data.

## Backwards Compatibility

This proposal applies only to the [EIP-8130](./eip-8130.md) `metadata` field and changes nothing on legacy transaction types. During transition, indexers SHOULD continue to parse trailing-bytes data suffixes on legacy transactions while reading structured `metadata` on [EIP-8130](./eip-8130.md) transactions. An [ERC-8021](./eip-8021.md) schema 2 attribution previously carried as a trailing calldata suffix maps directly onto the attribution map here: the schema 2 CBOR map becomes the `metadata` value (or an array element) unchanged, with the legacy `ercMarker`, `schemaId` byte, and length prefix dropped.

## Security Considerations

### Unverified metadata

Metadata is an attestation by the signer only: it asserts that the signer committed to those bytes, not that the content is true. Consumers MUST NOT grant trust or privileges based on the content without independent verification, and MUST sanitize untrusted bytes before use. A scope value is a producer's claim, not a protocol guarantee: a map whose `p`/`c` references calls the producer did not create carries no authority.

### Commitments reveal metadata about existence

A commitment proves that *some* off-chain document existed and was bound to the transaction at signing time, and its scope reveals which calls that document concerns. Producers SHOULD treat the presence and scope of a commitment as themselves disclosed, and MUST place only an opaque digest, not any recoverable fragment of the document, in the value. A single hash of a small or low-entropy document is guessable; producers SHOULD give each document a high-entropy salt so the digest does not leak its preimage.

When a batch is committed as a single Merkle root, a proof for one leaf additionally discloses the tree shape, the number of leaves (for example, how many payments a batch contained), and the sibling digests along the proof path. Producers SHOULD treat the leaf count and tree shape as disclosed whenever any proof is shared, and MUST salt each leaf document independently so that revealing one leaf does not let an observer confirm guesses about templated sibling documents. Where even the leaf count is sensitive, producers MAY pad the tree with random decoy leaves.

### Malformed and adversarial encodings

Because `metadata` is attacker-influenced bytes, consumers MUST bound decoding work (array length, nesting, map size) and MUST NOT fail transaction processing on a malformed or non-deterministic encoding; such input is treated as opaque.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
