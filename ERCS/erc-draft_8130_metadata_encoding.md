---
title: Transaction Metadata Encoding for EIP-8130
description: CBOR encoding for the EIP-8130 metadata field, covering attribution, memos, and offchain-data commitments with selective disclosure.
author: Chris Hunter (@chunter-cb) <chris.hunter@coinbase.com>
discussions-to: https://ethereum-magicians.org/t/erc-transaction-metadata-encoding-for-eip-8130
status: Draft
type: Standards Track
category: ERC
created: 2026-06-11
requires: 5792, 8130
---

## Abstract

[EIP-8130](./eip-8130.md) adds an optional, opaque `metadata` field to its transaction type but leaves the byte layout to a companion specification. This proposal defines that layout: `metadata` is a single deterministic [CBOR](https://www.rfc-editor.org/rfc/rfc8949) value: a **text string** (memo), a **byte string** (commitment digest), a **map** of reserved keys (attribution, memo, commitment, scope), or an **array** of any of these. The map keys are interoperable with [ERC-8021](./eip-8021.md) schema 2, extended with keys for offchain commitments and call scoping. Any value MAY be replaced by a salted commitment to it, recursively, so a producer conceals a single field, a record, or the whole map with one primitive and discloses it selectively offchain; this proposal also defines that disclosure and delivery protocol and an [ERC-5792](./eip-5792.md) `metadata` capability superseding `dataSuffix`. Because the protocol never interprets `metadata`, the encoding is self-identifying through strict deterministic decoding rather than any protocol enforcement.

## Motivation

[EIP-8130](./eip-8130.md) provides a top-level `metadata` field as the home for data that legacy wallets appended to `tx.input` as a **data suffix**. That field is opaque bytes: without a shared structure, every producer invents its own framing and no indexer can read across them. Batching also broadens what metadata is useful for:

- **Attribution**: identifying the wallet builder and applications whose calls the transaction contains.
- **Multi-application batching**: per-application attribution lets analytics and revenue be split correctly when several applications share one transaction.
- **Payments and remittance**: a memo or reference attached to the transaction or to a specific transfer in a batch.
- **Intents and routing**: tagging a group of calls as one intent or solver route.
- **Commitments to offchain data**: a digest binding the transaction to an offchain document so the content stays private.

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
| `m` | metadata | map | A sub-map of arbitrary application key-value pairs. See [Keys in `m`](#keys-in-m). |
| `t` | text | text | A text memo. |
| `h` | commitment | byte string | A digest committing to offchain data; length follows from the hash algorithm (typically 32 bytes). See [Commitments](#commitments). |
| `p` | phase | uint | Phase scope (0-based index into `calls`). See [Scope](#scope). |
| `c` | call | uint | Call scope (0-based index within phase `p`). See [Scope](#scope). |

The `a`, `w`, `s`, `r`, and `m` keys are [ERC-8021](./eip-8021.md) schema 2; this proposal reuses that vocabulary and registry without re-specifying it. The ERC-8021 calldata `ercMarker`, `schemaId` byte, and `cborLength` prefix are not used: the value is self-delimiting and length-known from the RLP field.

The `t`, `h`, `p`, and `c` keys extend schema 2.

#### Keys in `m`

`m` is signed by the sender and charged per byte, so its size is the producer's economic choice: a producer willing to pay for a large `m` MAY include one, and this proposal sets no maximum. Two conventions keep `m` interoperable:

- Keys SHOULD be short, stable ASCII identifiers so consumers can recognize them across transactions.
- Data that does not need to be onchain (large, private, or per-call application state) is usually better committed through `h` and delivered offchain (see [Concealment](#concealment-recursive) and [Concealed values](#concealed-values)) than inlined into `m`. This is a suggestion, not a requirement.

A consumer MAY apply its own size limit when decoding untrusted input (see [Security Considerations](#security-considerations)), so a producer relying on a very large `m` round-tripping through every consumer SHOULD confirm those consumers accept it.

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

A commitment (the `h` key, or a bare byte string) binds the transaction to offchain data without revealing it. Its value is a digest; the hash algorithm, document format, and digest computation are defined by the offchain document and its application. The document is resolved through an application side channel; applications that need an onchain locator MAY carry it in `m` alongside `h`.

A commitment's scope ties the digest to its subject: whole-transaction, `p` for one phase, or `p`+`c` for a single call.

#### Concealment (recursive)

Any value in `metadata` MAY be replaced by a salted commitment to it, keeping the value offchain while still binding the transaction to it:

```
commit(value) = keccak256(0x00 || salt || cbor(value))   // salt: 32 random bytes
```

The bare byte-string form commits to the whole field, and the `h` key commits to a record. For any other key whose cleartext type is not a byte string (`a`, `w`, `s`, `r`, `m`, `t`), a byte-string value is a commitment to that key's value; `p` and `c` are always cleartext so a consumer can place the annotation. Concealment is recursive: a concealed value MAY itself be a map whose values are concealed. The preimage (salt and value) is disclosed offchain and verified per [Selective Disclosure and Delivery](#selective-disclosure-and-delivery); a consumer that does not hold the preimage treats the field as opaque and ignores it for interpretation.

Standardized keys (`a`, `w`, `s`, `r`, `t`, `h`) are resolved **only** at the top-level map (or, for a whole-field commitment, its preimage map). A consumer MUST NOT scan the contents of `m`, or of any commitment preimage, for standardized keys. `m` is therefore the home for application-private data that carries no standardized meaning, and concealing data under `m` cannot be used to smuggle a second attribution or other reserved field.

**Batches (RECOMMENDED).** When a batch commits to one offchain document per call, a producer SHOULD aggregate per-call digests into a single Merkle root and carry one commitment scoped to the phase, rather than one commitment per call. Each call's document is a leaf, which may itself be a Merkle root, since this proposal does not constrain offchain document structure. To prove a single call's data, a verifier is shown that document with a Merkle proof (sibling hashes) and recomputes the root. A Merkle proof discloses sibling hashes; producers SHOULD give each document a high-entropy salt so disclosing one leaf does not reveal information about siblings (see [Security Considerations](#security-considerations)).

**Recommended Merkle tree construction.** Producers SHOULD use the following construction for interoperable proofs:

- Leaves are ordered by call index.
- `leaf[i] = keccak256(0x00 || salt[i] || document[i])` where `salt[i]` is 32 random bytes and `0x00` is a leaf domain separator.
- `node = keccak256(0x01 || min(left, right) || max(left, right))` where `0x01` is an internal-node separator and siblings are sorted so a verifier needs only sibling hashes, not directions.
- If the leaf count is odd, the last leaf is duplicated.
- A proof for leaf `i` is the ordered array of sibling hashes from leaf to root.

**Positional proofs (non-normative).** Sorting siblings makes proofs symmetric: a verifier needs only the sibling hashes (no direction bits), at the cost of being unable to prove a leaf's index. The recommended construction is appropriate for unordered membership ("this document is in the batch"), which covers the typical remittance and digest-commitment cases this proposal targets, but cannot prove "this is leaf 3 of 5". Producers whose use case requires positional proofs (ordered receipts, anti-replay against an indexed log) SHOULD use an unsorted construction that carries explicit direction bits in the proof; such a construction is out of scope of this proposal.

### Determinism

Producers MUST encode `metadata` using CBOR core deterministic encoding ([RFC 8949 §4.2](https://www.rfc-editor.org/rfc/rfc8949#section-4.2)): definite-length items only, shortest-form integers and lengths, map keys sorted in bytewise lexicographic order.

### Identification and strict decoding

`metadata` is recognized as structured per this proposal if and only if:

1. The bytes decode as a single CBOR value (text, byte string, map, or array of those) that **consumes the entire field** with no trailing bytes.
2. The encoding is canonically deterministic per [Determinism](#determinism).

A consumer MUST treat the field as opaque if either condition fails. A consumer MUST NOT use a lax decoder that accepts a complete item with trailing bytes.

A future revision MAY introduce a CBOR semantic tag for explicit versioning; consumers that do not recognize a future tag MUST treat the field as opaque, which is the proposal's upgrade lane.

**Foreign encodings.** A producer that writes a non-CBOR payload to `metadata` MUST begin the field with `0xFF` (the CBOR break code, never a valid first byte of a well-formed CBOR item) so that a strict decoder immediately classifies the field as non-standard. This proposal can bind only producers that read it; a non-conforming producer that omits the `0xFF` prefix risks being misidentified as structured under the bare form, with the consumer recovering arbitrary keys or text from foreign bytes.

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

/** A value the wallet should commit onchain (as an `h` digest) and disclose
    offchain rather than inline. See Selective Disclosure and Delivery. */
interface ConcealedValue {
  value: object | string; // cleartext to commit, e.g. a receipt
  p?: number;             // phase scope; refers to calls in THIS request
  c?: number;             // call scope within phase p
  deliver?: string[];     // servers that receive THIS disclosure
}

interface MetadataCapability {
  metadata: {
    value?: MetadataValue | MetadataValue[]; // public, inline metadata
    conceal?: ConcealedValue[];              // values committed onchain, disclosed offchain
    deliver?: string[];                      // default disclosure endpoints
    required?: boolean; // default false (best-effort): the wallet MAY drop or transform metadata it cannot honor. When true, the wallet MUST reject the request if it cannot honor the metadata as written.
  };
}
```

Any `p`/`c` scope in the app's value refers to the calls in this request. The wallet MUST:

1. Map each annotation's scope to the corresponding index in the finalized `calls`.
2. Append its wallet code `w` as a separate map; MUST NOT merge it into an app-contributed map.
3. When batching multiple requests, treat each request's annotations independently.
4. Encode the result (single value or array) deterministically and sign.

A wallet receiving a legacy `dataSuffix` MAY carry a recognized [ERC-8021](./eip-8021.md) attribution suffix as the corresponding attribution map, or other bytes as a foreign encoding.

#### Concealed values

When the capability carries `conceal`, the app is asking the wallet to keep those values offchain and anchor only a commitment. For each `ConcealedValue` the wallet MUST:

1. Compute `commit(value)` per [Concealment](#concealment-recursive) with a fresh salt.
2. Place the resulting digest as an `h`, at the item's scope (`p`/`c`), in the encoded `metadata`.
3. After the transaction confirms, deliver the disclosure (salt, value, scope, and any Merkle proof) to the endpoints in the item's `deliver` (falling back to the top-level `deliver`), per [Selective Disclosure and Delivery](#selective-disclosure-and-delivery).

The `deliver` endpoints are how an **application** names a server it has negotiated with: a receipt service it is settling with, or a private attribution endpoint (for example an advertising attribution server). Only the application knows these, so they MUST be passed through the capability for the wallet to honor them.

A **wallet's own** server is separate and out of scope of this capability. A wallet MAY, by its own policy, deliver every disclosure (and the full preimage) to an endpoint it controls, such as the user's receipt inbox or private metadata server, without the application requesting or observing it. The wallet MAY likewise add its own attribution as a separate map rather than concealing it. A wallet that cannot honor a requested `deliver` endpoint MUST reject the request when `required` is true.

### Selective Disclosure and Delivery

A concealed value (see [Concealment](#concealment-recursive)) is opened to a chosen consumer offchain: the producer hands over the preimage and its location, and the consumer checks it against the onchain transaction. This section defines that proof package, its verification, and delivery. It is an offchain protocol and adds no consensus rules; producers that publish metadata in cleartext do not need it.

#### Locating a commitment

A disclosure points at one commitment inside one transaction's `metadata`, identified by its **path**: the sequence of CBOR map keys and array indices from the top of the `metadata` value to the byte string being opened. A whole-field commitment (bare byte string) has the empty path; `{ h: <digest> }` has path `["h"]`; the third array element's `h` has path `[2, "h"]`.

#### Replay binding

The salt stops a third party from *opening* a commitment they did not author, but a party that has legitimately received a preimage could re-present it against a different transaction (for example replaying an attribution disclosure as if it described the replayer's own transaction). A **verification-grade** disclosure MUST therefore bind to the transaction: the committed value (or a sibling value disclosed alongside it) MUST include the transaction's identifying fields:

- `chain` (CAIP-2),
- `sender` (the resolved [EIP-8130](./eip-8130.md) sender),
- the sender's transaction selector: `nonce_key` and `nonce_sequence` for keyed nonces, or `expiry` (and the [EIP-8130](./eip-8130.md) `replay_id` where exactness is required) for nonce-free transactions.

`sender` is load-bearing: it cannot be forged, so a commitment copied into another account's transaction will not match a `sender`-bound disclosure. The transaction hash cannot be used, because `metadata` is part of the hash preimage. A disclosure that omits a transaction binding is **signal only** (it shows a commitment exists) and MUST NOT be treated as verification-grade.

#### Proof package

A disclosure is transported as a deterministic CBOR (or equivalent JSON) object; one package MAY carry several disclosures for the same transaction.

```jsonc
{
  "anchor": {
    "chain": "eip155:8453",        // CAIP-2; untrusted routing hint
    "tx": "0x...",                 // transaction hash (or userOpHash)
    "where": "metadata"
  },
  "disclosures": [
    {
      "path": ["h"],               // location within the metadata value
      "salt": "0x... (32 bytes)",
      "value": { "type": "receipt", "items": [/* ... */] },  // the opened cleartext
      "merkleProof": {             // present only when the commitment is a batch root
        "leaf": "0x...",           // commit() of THIS document
        "siblings": ["0x...", "0x..."]
      }
    }
  ]
}
```

`anchor` is an **untrusted routing hint**. To verify a disclosure, a consumer MUST:

1. Fetch the transaction at `anchor.tx`, confirm finality, and decode its `metadata`.
2. Read the byte string at `path`; call it `D`.
3. If `merkleProof` is absent, check `D == commit(value)`.
4. If `merkleProof` is present, check `merkleProof.leaf == commit(value)`, fold `siblings` with the [Merkle construction](#commitments), and check the result equals `D`.
5. For a verification-grade claim, read the [transaction binding](#replay-binding) from `value` (or a sibling disclosure) and check `chain`, `sender`, and the nonce selector against the fetched transaction.

A claim is verification-grade only if steps 1-5 pass; otherwise the disclosure is signal only.

#### Delivery

After the transaction confirms, the producer (typically the wallet) sends each disclosure to the consumers that need it by HTTP POST:

```
POST <endpoint>
Content-Type: application/cbor   // or application/json
body: <proof package>
```

A disclosure MAY go to several servers; each server receives only the disclosures intended for it (an attribution server gets only the attribution disclosure, a merchant only its receipt). A server MUST run the verification steps before accepting a disclosure and SHOULD be idempotent on `(chain, tx, path)`. Endpoints come from the two sources defined in [Concealed values](#concealed-values): application-supplied (`conceal[].deliver` / `deliver`) and wallet-owned. Transport beyond "an authenticated HTTP endpoint that verifies before accepting" is out of scope.

### Examples

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

**11. Migrating from a legacy ERC-8021 schema 2 calldata suffix.** A producer that previously appended `0xabcd02 || cborLength || { a: "baseapp", w: "mywallet" }` to `tx.input` (with some illustrative `ercMarker` `0xabcd`, `schemaId` byte `0x02`, and a length prefix) writes the inner CBOR map straight into `metadata`. The `ercMarker`, `schemaId`, and length prefix are not used because the field is self-delimiting:
```
legacy suffix     = abcd 02 16 a2 6161 6762617365617070 6177 686d7977616c6c6574
                    └───┘ └┘ └┘ └────────── inner CBOR map ─────────────────┘
                    marker  │  length-prefix
                            schemaId

metadata (this spec) = a2 6161 6762617365617070 6177 686d7977616c6c6574
                       └────────── same CBOR map, directly ──────────┘
```
**12. Non-conforming foreign payload (`0xFF` prefix).** A producer that intends to write a non-CBOR payload (for example a bespoke binary tagging format) into `metadata` MUST begin the field with `0xFF` so consumers immediately classify it as opaque rather than attempting bare-form CBOR decoding against it:
```
metadata = ff <producer-defined bytes>
```
A consumer that sees a leading `0xFF` MUST treat the entire field as opaque and skip CBOR decoding.

**13. In-place concealment: public attribution, hidden memo (39 bytes).** The `t` memo is concealed as a commitment (a byte string where text is expected), while attribution stays public. The memo's salt and text are delivered offchain per [Selective Disclosure and Delivery](#selective-disclosure-and-delivery).
```
metadata = { a: "baseapp", t: commit("invoice 4471") }
hex      = a2 6161 6762617365617070 6174 5820 <32 bytes>
           └┬┘ └─┬┘ └──────┬──────┘ └─┬┘ └─┬┘ └───┬───┘
        map(2) "a"   "baseapp"      "t"  bstr(32)  digest
```
A consumer with the preimage substitutes `t = "invoice 4471"`; a consumer without it sees attribution and an opaque memo commitment.

**14. Batch payment, three hidden receipts, per call (113 bytes).** Phase 0 makes three payments (calls 0, 1, 2); each is tagged with its own concealed receipt using `[p, c]` scope. Only the three digests are onchain; each receipt's salt and contents are delivered offchain to the merchant or the user's inbox, and each is provable on its own.
```
metadata = [
  { h: commit(receipt0), p: 0, c: 0 },
  { h: commit(receipt1), p: 0, c: 1 },
  { h: commit(receipt2), p: 0, c: 2 }
]
```
To instead bind all three under one digest, aggregate them into a Merkle root and carry a single phase-scoped commitment `{ p: 0, h: <root> }` (see [Batches](#commitments)); each receipt stays individually provable with a Merkle proof.

**15. Disclosing a receipt to a merchant.** For the payment `metadata = { h: commit(receipt), p: 0, c: 0 }`, the wallet POSTs this proof package (see [Selective Disclosure and Delivery](#selective-disclosure-and-delivery)) to the merchant after confirmation:
```jsonc
{
  "anchor": { "chain": "eip155:8453", "tx": "0x...", "where": "metadata" },
  "disclosures": [{
    "path": ["h"],
    "salt": "0x...",
    "value": {
      "type": "receipt",
      "chain": "eip155:8453", "sender": "0x...", "nonce_key": "0", "nonce_sequence": "42",
      "items": [{ "sku": "A1", "qty": 2, "price": "9.99" }], "total": "19.98"
    }
  }]
}
```
The merchant fetches the transaction, checks `metadata.h == commit(value)`, then checks `chain`/`sender`/`nonce` inside `value` against the transaction: verification-grade.

**16. Disclosing one of three batched receipts.** From example 14, to open only the second payment the producer discloses path `[1, "h"]` with `receipt1`'s salt and value; the other two digests reveal nothing. Under a single Merkle root `{ p: 0, h: <root> }` instead, the disclosure carries a `merkleProof` for `receipt1` and the verifier folds the siblings to the onchain root.

**17. Private attribution to an ad server.** `metadata = { h: commit(attr) }` with `attr = { a: "baseapp", w: "mywallet", chain: "eip155:8453", sender: "0x...", nonce_key: "0", nonce_sequence: "42" }`. The wallet POSTs the disclosure only to the attribution server, which credits the builder; onchain, only the 32-byte commitment's existence is visible, never the attribution contents.

## Rationale

### One value, four forms

The most common case is a single small annotation. Bare CBOR primitives (text or byte string) cost only a couple of bytes over the raw data with no envelope. A map holds multiple keys when needed; an array holds independently scoped maps when multiple parties are involved. Bare forms are shorthands for single-key maps, so a parser normalizes and treats everything uniformly. Branching on CBOR major type avoids a leading type tag.

### Reusing ERC-8021 keys

[ERC-8021](./eip-8021.md) schema 2 (`a`, `w`, `s`, `r`, `m`) is a well-specified, registry-backed attribution vocabulary. Reusing it means existing registries and parsers apply without translation. This proposal adds only `t`, `h`, `p`, and `c`, the keys schema 2 lacks for [EIP-8130](./eip-8130.md).

### CBOR

CBOR is compact, widely implemented, and has a specified deterministic profile that matters for signed data. Structural overhead is a few bytes per map, dominated by the payload, and on rollups the repeated keys compress across a batch. A bespoke format would forfeit the tooling, the deterministic profile, and ERC-8021 compatibility.

### No type byte

The field is never interpreted by the protocol and its length is always known from RLP. Full-consume canonical decoding identifies the format without a tag byte, which is where the bare-form shorthand saves the bytes that otherwise dominate a short field. Foreign content is kept out of the way by the `0xFF` prefix rule, and a CBOR semantic tag is reserved for a future version if explicit versioning is ever needed.

### Encoding the top-level field versus a sink address

An alternative carries metadata as a no-op call to a reserved address inside `calls`, using call position to express scope. The top-level `metadata` field is preferred: it keeps metadata out of execution, makes scope explicit rather than inferred from placement, and requires one parser rather than address filtering across phases.

### Scope mirrors the calls structure

Encoding scope as a phase or `[phase, call]` index reuses [EIP-8130](./eip-8130.md)'s two-level `calls` structure directly. Absolute indices are safe because the wallet assembles the final `calls` and resolves scope after the structure is known.

### Commitments for privacy

A digest keeps sensitive detail offchain while binding the transaction to it. Only the digest is onchain; the document is resolved out-of-band, keeping the locator and format registry out of signed consensus-adjacent data.

### Recursive concealment instead of a separate structure

Because any value MAY be a commitment, a producer conceals a single field, a whole record, or the whole map with the same primitive, and a concealed value MAY itself be a map of concealed values. This makes the metadata map its own selective-disclosure structure: the map's keys already give each reserved field one canonical location (deterministic CBOR forbids a duplicate key), so a disclosed `a` is *the* attribution, not merely *an* attribution, with no positional tree, slot index, or direction bits. A consumer never scans `m` or a commitment preimage for reserved keys, so concealed application data cannot smuggle a reserved field. Only batches that disclose one of many siblings need a Merkle root; everything else is plain map nesting.

### Disclosure addresses commitments by path, binds by sender

Because the map is its own disclosure structure, the offchain protocol needs only a package format and a transport, not a new onchain tree. A disclosure locates its commitment by CBOR path so it is self-locating against the exact value the transaction signed and one package can open several fields independently. It binds to `sender` (unforgeable) plus the nonce selector rather than the transaction hash, since `metadata` is inside the hash preimage and so cannot contain its own hash; this also defeats copying a commitment into another account's transaction. A Merkle proof is used only to open one of many sibling documents; every other case is a direct `commit(value)` check.

## Backwards Compatibility

This proposal applies only to the [EIP-8130](./eip-8130.md) `metadata` field. Indexers SHOULD continue parsing trailing-bytes data suffixes on legacy transactions. An [ERC-8021](./eip-8021.md) schema 2 map previously carried as a calldata suffix becomes the `metadata` value directly, with the `ercMarker`, `schemaId`, and length prefix dropped.

**Indexer migration.** The practical cost of this proposal falls on tooling, not contracts. Indexers that recover attribution today by scanning trailing `tx.input` bytes for an ERC-8021 suffix MUST add a new code path for EIP-8130 transactions: read the EIP-8130 `metadata` field directly and decode per this proposal, rather than scanning calldata. The trailing-suffix path remains for pre-8130 transactions. An indexer that fails to add the new path will silently miss all attribution and annotation on EIP-8130 transactions, including transactions where the equivalent data would previously have been carried in `tx.input`.

**Producer migration.** A producer that previously emitted an ERC-8021 schema 2 calldata suffix migrates by dropping the `ercMarker` + `schemaId` + `cborLength` prefix and writing the inner CBOR map directly into the `metadata` field; see [Examples](#examples) for a worked migration. A producer that emits a different (non-CBOR) payload into `metadata` and has not migrated MUST prefix the field with `0xFF` per [Foreign encodings](#identification-and-strict-decoding).

## Security Considerations

### Unverified metadata

Metadata is an attestation by the signer only. Consumers MUST NOT grant trust or privileges based on content without independent verification, MUST sanitize untrusted bytes, and MUST treat scope as a producer claim with no protocol authority.

### Commitments reveal information about existence

A commitment and its scope are disclosed to anyone who can read the transaction. Producers MUST place only an opaque digest in `h`, with no recoverable fragment of the document. Low-entropy documents are guessable; producers SHOULD salt each document.

When a batch uses a Merkle root, a proof for one leaf discloses the tree shape, leaf count, and sibling hashes. Producers MUST salt each leaf independently to prevent confirming guesses about siblings. Where the leaf count is sensitive, producers MAY pad the tree with decoy leaves.

### Disclosure replay and trust

A disclosure without a verified transaction binding is signal only: a verifier MUST check `sender` (and `chain` and the nonce selector) from the committed value against the onchain transaction before treating a claim as verification-grade, or an attacker can re-present a preimage against an unrelated transaction (see [Replay binding](#replay-binding)). The `anchor` in a proof package is an untrusted routing hint; a verifier MUST fetch the transaction and verify rather than accept `anchor` at face value. A delivery server learns exactly the disclosures sent to it: producers MUST send a server only the disclosures it is authorized to see, and MUST NOT place recoverable secrets in a value they are unwilling to reveal to that server. Verifiers MUST bound proof length, disclosure count, and payload size, treating a malformed package as unverified rather than failing open.

### Malformed and adversarial encodings

A consumer decoding untrusted `metadata` MUST bound its own work (array length, map size, total bytes) to avoid resource exhaustion, and MUST NOT fail transaction processing on a malformed, non-deterministic, or over-limit encoding; it treats such input as opaque rather than attempting partial recovery. The choice of limit is consumer policy: gas already bounds `metadata` size economically because the producer pays per byte, so a large field is self-limiting rather than free, and this proposal sets no maximum size. The structure is inherently shallow: the top-level array MUST NOT contain a nested array, and maps carry only scalars, the `m` sub-map, and registry overrides, so nesting does not exceed two levels.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
