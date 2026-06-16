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

[EIP-8130](./eip-8130.md) adds an optional, opaque `metadata` field to its transaction type but leaves the byte layout to a companion specification. This proposal defines that layout: `metadata` is a single deterministic [CBOR](https://www.rfc-editor.org/rfc/rfc8949) value — a **text string** (memo), a **byte string** (commitment digest), a **map** of reserved keys (attribution, memo, commitment, scope), or an **array** of any of these. The map keys are interoperable with [ERC-8021](./eip-8021.md) schema 2, extended with keys for off-chain commitments and call scoping. This proposal also defines an [ERC-5792](./eip-5792.md) `metadata` capability superseding `dataSuffix`. Because the protocol never interprets `metadata`, the encoding is self-identifying through strict deterministic decoding rather than any protocol enforcement.

## Motivation

[EIP-8130](./eip-8130.md) provides a top-level `metadata` field as the home for data that legacy wallets appended to `tx.input` as a **data suffix**. That field is opaque bytes: without a shared structure, every producer invents its own framing and no indexer can read across them. Batching also broadens what metadata is useful for:

- **Attribution**: identifying the wallet builder and applications whose calls the transaction contains.
- **Multi-application batching**: per-application attribution lets analytics and revenue be split correctly when several applications share one transaction.
- **Payments and remittance**: a memo or reference attached to the transaction or to a specific transfer in a batch.
- **Intents and routing**: tagging a group of calls as one intent or solver route.
- **Commitments to off-chain data**: a digest binding the transaction to an off-chain document so the content stays private.

A shared, self-describing encoding lets producers attach independently scoped annotations into the one signed field, and lets any indexer recover all of them with a single parser.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Value forms

The `metadata` field, when non-empty and structured per this proposal, is a single CBOR value. A consumer branches on the CBOR major type of the first byte:

| Form | CBOR type | Meaning |
| --- | --- | --- |
| Text string | major type 3 | A memo. Equivalent to a map `{t: <text>}` at whole-transaction scope. |
| Byte string | major type 2 | A commitment digest. Equivalent to a map `{h: <digest>}` at whole-transaction scope. |
| Map | major type 5 | A single annotation record; see [Keys](#keys). |
| Array | major type 4 | Multiple independent annotations, each element a text string, byte string, or map. An array MUST NOT contain a nested array. |

The text-string and byte-string forms are shorthands for their single-key map equivalents; a parser MAY normalize them to maps before processing.

`metadata` is part of the signed [EIP-8130](./eip-8130.md) transaction and is charged per byte; the wallet that assembles the transaction is responsible for producing the final encoding from the contributions of each party.

### Keys

A map uses text-string keys. All keys are OPTIONAL; unrecognized keys MUST be ignored.

| Key | Name | Value | Description |
| --- | --- | --- | --- |
| `a` | application | text | Application attribution code. |
| `w` | wallet | text | Wallet attribution code. |
| `s` | services | array of text | Service attribution codes (block builders, relayers, solvers). |
| `r` | registries | map | Custom registry overrides, keyed by entity type. |
| `m` | metadata | map | A sub-map of arbitrary application key-value pairs. |
| `t` | text | text | A text memo. |
| `h` | commitment | byte string | A digest committing to off-chain data; length follows from the hash algorithm (typically 32 bytes). See [Commitments](#commitments). |
| `p` | phase | uint | Phase scope (0-based index into `calls`). See [Scope](#scope). |
| `c` | call | uint | Call scope (0-based index within phase `p`). See [Scope](#scope). |

The `a`, `w`, `s`, `r`, and `m` keys are [ERC-8021](./eip-8021.md) schema 2; this proposal reuses that vocabulary and registry without re-specifying it. The ERC-8021 calldata `ercMarker`, `schemaId` byte, and `cborLength` prefix are not used: the value is self-delimiting and length-known from the RLP field.

The `t`, `h`, `p`, and `c` keys extend schema 2.

### Scope

`p` and `c` associate a map with part of the `calls` array:

| Keys present | Meaning |
| --- | --- |
| neither | The whole transaction. |
| `p` only | Phase `p` (0-based). |
| `p` and `c` | Call `c` (0-based) within phase `p`. |

A `c` key without `p` is treated as `p = 0`. A consumer SHOULD ignore a scope whose index does not exist in `calls`, treating the map as whole-transaction.

Wallets MUST encode `p` and `c` only after `calls` is finalized. All parties must have determined their calls before scope is encoded, since a payer prepending a phase shifts the app's calls to a later index.

> **Note (non-normative):** In [ERC-8168](./erc-8168.md) sponsored flows: (1) app sends `wallet_sendCalls`; (2) payer may prepend a phase; (3) wallet resolves each annotation's final phase index; (4) wallet encodes `metadata` and signs.

### Commitments

A commitment (the `h` key, or a bare byte string) binds the transaction to off-chain data without revealing it. Its value is a digest; the hash algorithm, document format, and digest computation are defined by the off-chain document and its application. The document is resolved through an application side channel; applications that need an on-chain locator MAY carry it in `m` alongside `h`.

A commitment's scope ties the digest to its subject: whole-transaction, `p` for one phase, or `p`+`c` for a single call.

**Batches (RECOMMENDED).** When a batch commits to one off-chain document per call, a producer SHOULD aggregate per-call digests into a single Merkle root and carry one commitment scoped to the phase, rather than one commitment per call. Each call's document is a leaf — which may itself be a Merkle root, since this proposal does not constrain off-chain document structure. To prove a single call's data, a verifier is shown that document with a Merkle proof (sibling hashes) and recomputes the root. A Merkle proof discloses sibling hashes; producers SHOULD give each document a high-entropy salt so disclosing one leaf does not reveal information about siblings (see [Security Considerations](#security-considerations)).

**Recommended Merkle tree construction.** Producers SHOULD use the following construction for interoperable proofs:

- Leaves are ordered by call index.
- `leaf[i] = keccak256(0x00 || salt[i] || document[i])` where `salt[i]` is 32 random bytes and `0x00` is a leaf domain separator.
- `node = keccak256(0x01 || min(left, right) || max(left, right))` where `0x01` is an internal-node separator and siblings are sorted so a verifier needs only sibling hashes, not directions.
- If the leaf count is odd, the last leaf is duplicated.
- A proof for leaf `i` is the ordered array of sibling hashes from leaf to root.

### Determinism

Producers MUST encode `metadata` using CBOR core deterministic encoding ([RFC 8949 §4.2](https://www.rfc-editor.org/rfc/rfc8949#section-4.2)): definite-length items only, shortest-form integers and lengths, map keys sorted in bytewise lexicographic order.

### Identification and strict decoding

`metadata` is recognized as structured per this proposal if and only if:

1. The bytes decode as a single CBOR value (text, byte string, map, or array of those) that **consumes the entire field** with no trailing bytes.
2. The encoding is canonically deterministic per [Determinism](#determinism).

A consumer MUST treat the field as opaque if either condition fails. A consumer MUST NOT use a lax decoder that accepts a complete item with trailing bytes.

A future revision MAY introduce a CBOR semantic tag for explicit versioning; consumers that do not recognize a future tag fall back to opaque.

**Foreign encodings.** A producer using a different encoding SHOULD begin the field with `0xFF` (the CBOR break code, never a valid first byte of a well-formed item) to ensure a strict decoder immediately identifies it as non-standard.

### Consumer behavior

For a `metadata` field that passes [Identification and strict decoding](#identification-and-strict-decoding), a consumer:

1. Branches on the value form, normalizing bare text and byte strings to their map equivalents.
2. For each map, resolves scope from `p`/`c` against `calls`, ignoring out-of-range indices, and reads recognized keys, ignoring unrecognized ones.

`metadata` is an inert annotation; a consumer MUST NOT infer any execution effect from it.

### Application and wallet integration ([ERC-5792](./eip-5792.md))

Applications contribute metadata through a `metadata` capability on [ERC-5792](./eip-5792.md) `wallet_sendCalls`, superseding `dataSuffix`.

```typescript
/** A single annotation value. */
type MetadataValue =
  | string      // bare memo (t shorthand)
  | Uint8Array  // bare commitment digest (h shorthand)
  | {
      a?: string;      // application code
      w?: string;      // wallet code
      s?: string[];    // service codes
      r?: object;      // registry overrides (ERC-8021 format)
      m?: object;      // arbitrary application metadata
      t?: string;      // text memo
      h?: Uint8Array;  // commitment digest
      p?: number;      // phase scope (0-based); refers to calls in THIS request
      c?: number;      // call scope within phase p (0-based)
    };

interface MetadataCapability {
  metadata: {
    value: MetadataValue | MetadataValue[];
    optional?: boolean; // default false; if false, wallet MUST reject if it cannot honor
  };
}
```

Any `p`/`c` scope in the app's value refers to the calls in this request. The wallet MUST:

1. Map each annotation's scope to the corresponding index in the finalized `calls`.
2. Append its wallet code `w` as a separate map; MUST NOT merge it into an app-contributed map.
3. When batching multiple requests, treat each request's annotations independently.
4. Encode the result (single value or array) deterministically and sign.

A wallet receiving a legacy `dataSuffix` MAY carry a recognized [ERC-8021](./eip-8021.md) attribution suffix as the corresponding attribution map, or other bytes as a foreign encoding.

## Examples

Byte counts assume short ASCII codes.

**1. Bare memo (13 bytes).**
```
metadata = "invoice 4471"
hex      = 6c696e766f6963652034343731
```

**2. Attribution (22 bytes).**
```
metadata = { a: "baseapp", w: "mywallet" }
hex      = a2 6161 6762617365617070 6177 686d7977616c6c6574
```

**3. Bare commitment (34 bytes).**
```
metadata = h'<digest>'
hex      = 5820 <32 bytes>
```

**4. Attribution + memo (37 bytes).**
```
metadata = { a: "baseapp", w: "mywallet", t: "invoice 4471" }
```

**5. Attribution + memo + commitment (73 bytes).**
```
metadata = { a: "baseapp", w: "mywallet", t: "invoice 4471", h: h'<digest>' }
```

**6. Sponsored tx: whole-tx attribution + phase-scoped memo (42 bytes).** Payer prepends phase 0; app transfer is phase 1.
```
metadata = [
  { a: "baseapp", w: "mywallet" },
  { t: "invoice 4471", p: 1 }
]
```

**7. Remittance batch as one Merkle root (40 bytes).** Five transfers in phase 0, one root over five salted documents.
```
metadata = { p: 0, h: h'<Merkle root>' }
```

**8. Intent / solver tag (46 bytes).**
```
metadata = { a: "myapp", m: { intent: "swap-eth-usdc", solver: "1inch" } }
```

**9. Multi-app batch with per-phase attribution (42 bytes).**
```
metadata = [
  { a: "defi-app", p: 0 },
  { a: "nft-app",  p: 1 },
  { w: "mywallet" }
]
```

**10. Compliance commitment scoped to one call (43 bytes).**
```
metadata = { h: h'<digest>', p: 0, c: 0 }
```

## Rationale

### One value, four forms

The most common case is a single small annotation. Bare CBOR primitives (text or byte string) cost only a couple of bytes over the raw data with no envelope. A map holds multiple keys when needed; an array holds independently scoped maps when multiple parties are involved. Bare forms are shorthands for single-key maps, so a parser normalizes and treats everything uniformly. Branching on CBOR major type avoids a leading type tag.

### Reusing ERC-8021 keys

[ERC-8021](./eip-8021.md) schema 2 (`a`, `w`, `s`, `r`, `m`) is a well-specified, registry-backed attribution vocabulary. Reusing it means existing registries and parsers apply without translation. This proposal adds only `t`, `h`, `p`, and `c` — what schema 2 lacks for [EIP-8130](./eip-8130.md).

### CBOR

CBOR is compact, widely implemented, and has a specified deterministic profile that matters for signed data. Structural overhead is a few bytes per map, dominated by the payload, and on rollups the repeated keys compress across a batch. A bespoke format would forfeit the tooling, the deterministic profile, and ERC-8021 compatibility.

### No type byte

The field is never interpreted by the protocol and its length is always known from RLP. Full-consume canonical decoding identifies the format without a tag byte. A tag is reserved for a future version if explicit versioning is needed.

### Encoding the top-level field versus a sink address

An alternative carries metadata as a no-op call to a reserved address inside `calls`, using call position to express scope. The top-level `metadata` field is preferred: it keeps metadata out of execution, makes scope explicit rather than inferred from placement, and requires one parser rather than address filtering across phases.

### Scope mirrors the calls structure

Encoding scope as a phase or `[phase, call]` index reuses [EIP-8130](./eip-8130.md)'s two-level `calls` structure directly. Absolute indices are safe because the wallet assembles the final `calls` and resolves scope after the structure is known.

### Commitments for privacy

A digest keeps sensitive detail off-chain while binding the transaction to it. Only the digest is on-chain; the document is resolved out-of-band, keeping the locator and format registry out of signed consensus-adjacent data.

## Backwards Compatibility

This proposal applies only to the [EIP-8130](./eip-8130.md) `metadata` field. Indexers SHOULD continue parsing trailing-bytes data suffixes on legacy transactions. An [ERC-8021](./eip-8021.md) schema 2 map previously carried as a calldata suffix becomes the `metadata` value directly, with the `ercMarker`, `schemaId`, and length prefix dropped.

## Security Considerations

### Unverified metadata

Metadata is an attestation by the signer only. Consumers MUST NOT grant trust or privileges based on content without independent verification, MUST sanitize untrusted bytes, and MUST treat scope as a producer claim with no protocol authority.

### Commitments reveal information about existence

A commitment and its scope are disclosed to anyone who can read the transaction. Producers MUST place only an opaque digest in `h` — no recoverable fragment of the document. Low-entropy documents are guessable; producers SHOULD salt each document.

When a batch uses a Merkle root, a proof for one leaf discloses the tree shape, leaf count, and sibling hashes. Producers MUST salt each leaf independently to prevent confirming guesses about siblings. Where the leaf count is sensitive, producers MAY pad the tree with decoy leaves.

### Malformed and adversarial encodings

Consumers MUST bound decoding work (array length, nesting, map size) and MUST NOT fail transaction processing on a malformed or non-deterministic encoding; treat such input as opaque.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
