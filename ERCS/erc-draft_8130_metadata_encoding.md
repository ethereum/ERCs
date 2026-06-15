---
title: Transaction Metadata Encoding for EIP-8130
description: A structured encoding for the EIP-8130 metadata field, scoping records to a transaction, phase, or call and supporting commitments to off-chain data
author: Chris Hunter (@chunter-cb) <chris.hunter@coinbase.com>
discussions-to: https://ethereum-magicians.org/t/erc-transaction-metadata-encoding-for-eip-8130
status: Draft
type: Standards Track
category: ERC
created: 2026-06-11
requires: 5792, 8021, 8130, 8168
---

## Abstract

[EIP-8130](./eip-8130.md) adds an optional, opaque `metadata` field to its transaction type for attribution and annotation data, but leaves the byte layout to a companion specification. This proposal defines that layout: `metadata` is a deterministic [CBOR](https://www.rfc-editor.org/rfc/rfc8949) array of **records**, where each record carries a **type** (how its payload is interpreted), an optional **scope** (the whole transaction, a phase, or a single call), and a **payload**. It defines an initial set of record types, including native **attribution** (whose vocabulary is interoperable with [ERC-8021](./eip-8021.md) schema 2), **commitments** to off-chain data, and arbitrary application **metadata** maps, and an [ERC-5792](./eip-5792.md) `metadata` capability that lets applications contribute records through `wallet_sendCalls`, superseding the `dataSuffix` capability. The encoding lets multiple independent parties attach metadata to one transaction, scope each annotation to the relevant calls, and commit to off-chain data without revealing it on-chain. Because the protocol never interprets `metadata`, the encoding is self-identifying through strict deterministic decoding rather than any protocol enforcement.

## Motivation

[EIP-8130](./eip-8130.md) replaces the single `tx.input` byte string of legacy transactions with a structured `calls` array of execution phases, and provides a top-level `metadata` field as the home for the data that legacy wallets appended to `tx.input` as a **data suffix**. That field is opaque bytes: useful as a signed, charged location, but with no shared structure, every producer would invent its own framing and no indexer could read across them.

Batching also broadens what metadata is useful for beyond a single transaction-level suffix:

- **Builder and application attribution**: identifying the wallet builder or the applications whose calls the transaction contains.
- **Multi-application batching**: per-application metadata lets analytics and revenue be split correctly across contributors when several applications share one transaction.
- **Payments and remittance**: an invoice number, reference, or memo attached to a specific transfer in a batch.
- **Intents and routing**: a tag marking a group of calls as one intent or solver route for indexers and portfolio tools.
- **Commitments to off-chain data**: a hash of an off-chain document (for example a receipt with line-item detail), so the transaction is provably tied to that document while the content stays private.

These differ in *scope* (whole transaction vs. a phase vs. a single call) and in *who* produces them. A shared, self-describing encoding lets each producer append an independently typed and scoped record into the one signed `metadata` field, and lets any indexer recover all of them with a single parser.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Container

The [EIP-8130](./eip-8130.md) `metadata` field, when non-empty and structured per this proposal, MUST decode as a CBOR array. Each element of the array is a **record** (see [Record](#record)). An empty `metadata` field carries no records.

The entire `metadata` byte string is part of the signed [EIP-8130](./eip-8130.md) transaction (covered by the sender signature, and the payer signature when present) and is charged per byte at the transaction's calldata rate. Because the bytes are signed as a unit, the wallet that assembles the transaction is responsible for producing the final encoding from the records contributed by each party.

### Record

A record is a CBOR map with unsigned-integer keys:

| Key | Name | Type | Required | Description |
| --- | --- | --- | --- | --- |
| `0` | `type` | uint | No (default `0`) | Selects how `payload` is interpreted. See [Record types](#record-types). |
| `1` | `scope` | see [Scope](#scope) | No (default: whole transaction) | Which calls the record describes. |
| `2` | `payload` | per `type` | Yes | The record's content. For `type 0` an opaque byte string; other types define their own payload. |

A record with no recognized keys, or missing `payload`, is malformed and SHOULD be ignored.

### Scope

`scope` associates a record with part of the transaction's [EIP-8130](./eip-8130.md) `calls` (an ordered array of phases, each an ordered array of calls). It is encoded as:

| `scope` value | Meaning |
| --- | --- |
| absent | The whole transaction. |
| unsigned integer `p` | Phase `p` (0-based) of `calls`. |
| two-element array `[p, c]` | Call `c` (0-based) within phase `p`. |

A consumer SHOULD ignore the `scope` (treating the record as whole-transaction) of any record whose `scope` references a phase or call index that does not exist in `calls`. Multiple records MAY share the same scope, and a single call MAY be described by records at call, phase, and transaction scope simultaneously.

Wallets MUST encode `scope` values only after the `calls` array is finalized. The final phase structure is not known until all parties — sender, payer, and any other contributors — have determined their calls. Encoding scope before that point risks pointing at the wrong phase if a payer prepends a payment phase or if calls are otherwise reordered during construction.

> **Note (non-normative):** In [ERC-8168](./erc-8168.md) sponsored flows, the typical construction order is: (1) app sends `wallet_sendCalls` with its calls and attribution intent; (2) wallet contacts the payer service, which may prepend a payment phase via `payer_fillTransaction`; (3) wallet resolves each call's final phase index in the assembled `calls`; (4) wallet encodes `metadata` with correct absolute indices and signs. The app's original calls may shift from phase 0 to phase 1 when a payer prepends — the wallet holds both the original intent and the final structure, so it resolves the correct index before encoding.

> **Note (non-normative):** When a wallet assembles calls from multiple independent `wallet_sendCalls` requests (multi-app batching), it SHOULD track which metadata contributions came with which calls, then resolve each contribution's scope to the phase those calls occupy in the final `calls`. Each app's attribution record ends up scoped to its own phase independently.

### Record types

This proposal defines an initial registry of record types. The `type` value is a hint: a consumer that does not recognize a `type`, or whose `payload` does not validate against the named format, MUST treat that record's `payload` as opaque rather than rejecting the transaction.

| `type` | Name | `payload` |
| --- | --- | --- |
| `0` | Opaque | A CBOR byte string of application-defined bytes. |
| `1` | Attribution | A CBOR map of attribution codes. See [Attribution records](#attribution-records). |
| `2` | Commitment | A commitment to off-chain data. See [Commitment records](#commitment-records). |
| `3` | Metadata | A CBOR map of arbitrary application-defined key-value pairs. See [Metadata records](#metadata-records). |

These types are independent: a single transaction MAY carry an attribution record, a commitment record, and a metadata record (and more), each as its own element of the array with its own `scope`.

Future ERCs MAY define additional `type` values. A defined `type` SHOULD be self-validating (structurally checkable) so a coincidental match on opaque bytes is rejected.

### Attribution records

An **attribution record** (`type 1`) identifies the parties responsible for a transaction or a part of it. Its `payload` is a CBOR map with the following keys, all OPTIONAL:

| Key | Description |
| --- | --- |
| `a` | Application code (string) |
| `w` | Wallet code (string) |
| `s` | Service codes (array of strings: block builders, relayers, solvers) |
| `r` | Custom registries (sub-map keyed by entity type, each with a chain id and registry address override) |
| `m` | Arbitrary application metadata (sub-map of key-value pairs) |

These keys are intentionally **identical to [ERC-8021](./eip-8021.md) schema 2**, so that ERC-8021 code registries, payout resolution, and existing schema-2 parsers apply to an attribution payload unchanged, and an ERC-8021 schema-2 map drops in as the payload without modification. The `a`, `w`, and `s` values are ERC-8021 codes resolved through the code registry mechanism that ERC-8021 defines; this proposal reuses that vocabulary and registry rather than re-specifying it, and references ERC-8021 only for the *meaning* of the codes, not for byte framing.

The payload is the map itself. The ERC-8021 calldata `ercMarker`, `schemaId` byte, and `cborLength` prefix are not used: the record envelope already provides the type tag, and the CBOR map is self-delimiting and length-known from the RLP `metadata` field. The `m` key carries per-party application metadata without requiring a separate record, mirroring schema 2.

### Commitment records

A **commitment record** (`type 2`) binds the transaction to off-chain data without revealing it. Its `payload` is a CBOR byte string: the **digest** of the off-chain document (for example a `keccak256` hash, or a Merkle root for selectively-disclosable documents). Only the digest appears on-chain, so the document's contents (for example receipt line items) stay private until revealed.

The off-chain document is **self-describing**: the hash algorithm, the document format or schema, and how the digest was computed are defined by the document and the application that produces it, not by this proposal. A verifier recomputes the digest over a presented document (per that document's own rules) and compares it to the on-chain value.

This proposal deliberately does not carry a **locator** for the off-chain document. Following the model of off-chain attestations in systems like the [Ethereum Attestation Service](https://attest.org), the digest is the only on-chain artifact; the document is resolved through an application side channel (a shared URL, a content-addressed store such as IPFS, or peer-to-peer delivery) rather than a pointer embedded in the transaction. Applications that do need an on-chain locator can carry it as their own opaque (`type 0`) record alongside the commitment.

A commitment record's `scope` ties the off-chain data to its subject: absent for a receipt covering the whole transaction, or `[p, c]` for a document describing one call (for example one transfer in a batch).

**Batches (RECOMMENDED).** When a batch commits to one off-chain document per call, a producer SHOULD aggregate the per-call digests into a single Merkle root and carry **one** commitment record scoped to the phase (or the whole transaction), rather than one record per call. Each call's document is a leaf; to prove a single call's data, a verifier is shown that document together with a Merkle proof (the sibling hashes) and recomputes the root for comparison with the on-chain value. This collapses `N` on-chain digests into one 32-byte root while still binding every document, and disclosing one leaf reveals only sibling hashes, not the contents of the other documents. The tree construction (leaf hashing, ordering, domain separation, and proof format) is part of the self-describing off-chain document set, not this proposal; producers SHOULD salt leaves so that undisclosed leaves cannot be guessed (see [Security Considerations](#security-considerations)).

### Metadata records

A **metadata record** (`type 3`) carries arbitrary application-defined annotation as a CBOR map of key-value pairs that is *not* attribution: a memo, an invoice or order reference, routing or intent tags, analytics parameters, and similar. None of its keys are reserved by this proposal; the producing application defines them.

A metadata record differs from the two adjacent types:

- Unlike an **attribution record** (`type 1`), it carries no attribution codes and reserves no keys, so it is the right home for application data that is not about *who* produced the transaction.
- Unlike an **opaque record** (`type 0`), its payload is a structured, introspectable CBOR map rather than a raw byte string, so indexers can read its fields directly.

Application metadata that is specifically about an attributed party MAY instead be carried in the `m` key of that party's attribution record; a standalone metadata record is preferred when the annotation is not tied to a particular attributed entity.

For example, a single `metadata` field MAY carry an attribution, a commitment, and a standalone metadata map as three independent records:

```
metadata = [
  { 0: 1, 2: { a: "baseapp", w: "mywallet" } },          // attribution (type 1), whole transaction
  { 0: 3, 2: { memo: "invoice 4471", ref: "PO-22" } },   // arbitrary metadata (type 3), whole transaction
  { 0: 2, 1: [0, 0], 2: h'…32-byte digest…' }            // commitment (type 2), scoped to call [0,0]
]
```

### Determinism

Producers MUST encode `metadata` using CBOR core deterministic encoding ([RFC 8949 §4.2](https://www.rfc-editor.org/rfc/rfc8949#section-4.2)): definite-length items only, integers and lengths in their shortest form, and map keys sorted in bytewise lexicographic order of their encodings. Determinism ensures the signed bytes are reproducible by any party validating the transaction and that a digest computed over a record is stable.

### Identification and strict decoding

The protocol never parses `metadata`, so this proposal is not identified by any protocol tag or magic prefix; a `metadata` field is recognized as structured per this proposal purely by whether it decodes under the strict rules below. A consumer MUST treat the field as structured **only if all** of the following hold, and MUST otherwise treat the entire field as opaque bytes:

1. The bytes decode as a single CBOR array that **consumes the entire `metadata` field** with no trailing bytes. The field length is known from RLP, so this check is always available.
2. The encoding is canonically deterministic per [Determinism](#determinism); a non-canonical encoding (indefinite-length items, non-shortest integers, unsorted or duplicate map keys) MUST be rejected as opaque.
3. Every array element is a CBOR map whose keys are a subset of the defined record keys (`0`, `1`, `2`).

These rules make accidental or adversarial collision negligible: an arbitrary byte string essentially never forms a canonical CBOR array of well-formed record maps that exactly fills the field. A consumer MUST NOT use a lax decoder that accepts a complete item followed by trailing bytes, because many unrelated byte strings begin with a parseable CBOR item.

This proposal does not reserve a CBOR semantic tag or version prefix. A future revision MAY introduce one for explicit versioning; consumers that do not recognize a future tag fall back to opaque per the rules above.

**Foreign encodings.** A producer MAY treat `metadata` as wholly opaque to this proposal and use a different encoding. The strict rules above already route any field that is not a canonical array of record maps to opaque, so no action is strictly required. To eliminate even an accidental match and give consumers a fast reject, such a producer SHOULD either make its encoding self-describing, or begin the field with the byte `0xFF`. `0xFF` is the CBOR "break" code and can never begin a well-formed CBOR data item, so a strict decoder rejects it immediately. A structured `metadata` field under this proposal always begins with a CBOR array header (`0x80`–`0x9F`) and never with `0xFF`, so the two coexist without ambiguity.

### Consumer behavior

For an [EIP-8130](./eip-8130.md) transaction whose `metadata` satisfies [Identification and strict decoding](#identification-and-strict-decoding), a consumer:

1. For each record, reads `type` (default `0`), `scope` (default whole transaction), and `payload`.
2. Resolves `scope` against `calls` per [Scope](#scope), ignoring out-of-range scopes.
3. Interprets `payload` per `type`, falling back to opaque for unknown or non-validating types.

A consumer MUST treat metadata as describing only the transaction it appears in, and MUST NOT infer any execution effect from it: records are inert annotations, never dispatched or executed.

### Application and wallet integration ([ERC-5792](./eip-5792.md))

Applications contribute metadata through a `metadata` capability on [ERC-5792](./eip-5792.md) `wallet_sendCalls`. This capability supersedes the `dataSuffix` capability: where `dataSuffix` passed opaque bytes for the wallet to append blindly, `metadata` passes typed, scoped records that the wallet places in the signed [EIP-8130](./eip-8130.md) `metadata` field.

```typescript
interface MetadataCapability {
  metadata: {
    records: Array<{
      type: number; // record type (0 opaque, 1 attribution, 2 commitment, ...)
      scope?: number | [number, number]; // index into THIS request's calls; omit for whole transaction
      payload: unknown; // per type; e.g. an attribution map, a digest, or opaque bytes
    }>;
    optional?: boolean; // if true, wallet MAY proceed without honoring; if false (default), wallet MUST reject when it cannot
  };
}
```

The application provides records describing its own calls; any `scope` index refers to the call array the application submits in this request. The wallet is the final assembler and MUST:

1. Map each contributed record's `scope` to the corresponding phase or call index in the finalized `calls` (which MAY differ from the request, for example when a payer prepends a phase under [ERC-8168](./erc-8168.md), or when calls from several requests are batched).
2. Add its own attribution as appropriate (for example its wallet code `w` in an attribution record).
3. Encode all records into the `metadata` field per this proposal, deterministically, and sign.

If the wallet cannot honor the capability and `optional` is not `true`, it MUST reject the request. A wallet that still receives a legacy `dataSuffix` capability MAY carry those bytes as an opaque (`type 0`) record, or as an attribution (`type 1`) record if it recognizes them as [ERC-8021](./eip-8021.md) attribution.

## Examples

### ERC-8021 attribution on a sponsored USDC transfer

**Scenario.** An app (code `"baseapp"`) sends a USDC transfer via `wallet_sendCalls`. The wallet (code `"mywallet"`) contacts a payer service via [ERC-8168](./erc-8168.md), which prepends a payment phase. The final `calls` structure is:

```
calls:
  phase 0: [{to: payerContract, data: <pay 0.01 USDC to payer>}]
  phase 1: [{to: usdcContract,  data: <transfer 100 USDC to Alice>}]
```

The wallet attaches attribution scoped to the whole transaction, encoding `metadata` after `calls` is finalized and signing.

**Step 1 — attribution payload (CBOR map).**

The attribution payload is the CBOR map `{"a":"baseapp","w":"mywallet"}` directly. There is no schema-id byte, `cborLength` prefix, or `ercMarker`: the record envelope carries the type and the map is self-delimiting.

```
a2                          CBOR map(2)
  61 61                       text "a"  (key)
  67 62 61 73 65 61 70 70     text "baseapp"
  61 77                       text "w"  (key)
  68 6d 79 77 61 6c 6c 65 74  text "mywallet"

= a2616167626173656170706177686d7977616c6c6574  (22 bytes)
```

**Step 2 — record (type 1, whole-transaction scope).**

Scope is absent (whole transaction), so the record map has two pairs: `type` and `payload`. The payload value is the attribution map nested directly.

```
a2                          map(2)          ← record
  00  01                      key 0 (type) = 1 (attribution)
  02                          key 2 (payload) =
    a2 ...                       the attribution map (22 bytes)
```

Key/value layout at a glance:

```
a2 | 00 01 | 02 | a2616167626173656170706177686d7977616c6c6574
└┘   └──┘   └┘   └──────────────── map(2) ─────────────────────┘
 │    type   payload
map(2)
```

**Step 3 — metadata field (array of one record).**

```
81                          array(1)
  a2 00 01 02              record (26 bytes)
  a2616167626173656170706177686d7977616c6c6574

metadata = 0x81a2000102a2616167626173656170706177686d7977616c6c6574
         = 27 bytes total
```

**Construction flow (non-normative).** The wallet receives the filled transaction (including the payer's prepended phase 0) from `payer_fillTransaction`, assembles the above `metadata` bytes, and signs `sender_auth` over the complete RLP including `metadata`. The payer co-signs the same bytes via `payer_auth`. Both signatures commit to the attribution.

### Self-paid remittance batch with per-payment commitments

**Scenario.** A self-paid transaction sends five USDC remittances (10,000 / 15,000 / 27,000 / 20,000 / 17,000 USDC) as five calls in a single phase. Each transfer is tagged with a commitment to an off-chain receipt (line items, payer/payee reference, compliance memo) scoped to that specific call, so each payment is provably bound to its own document while the contents stay private.

Because the transaction is self-paid there is no payer phase; the sender signs `metadata` directly.

```
calls:
  phase 0:
    call 0: {to: usdcContract, data: <transfer 10,000 USDC to recipient 1>}
    call 1: {to: usdcContract, data: <transfer 15,000 USDC to recipient 2>}
    call 2: {to: usdcContract, data: <transfer 27,000 USDC to recipient 3>}
    call 3: {to: usdcContract, data: <transfer 20,000 USDC to recipient 4>}
    call 4: {to: usdcContract, data: <transfer 17,000 USDC to recipient 5>}
```

**Per-payment record (type 2, call scope).** Each record is a commitment scoped to `[0, c]` (phase 0, call `c`). The payload is the 32-byte digest of that payment's receipt; the document is self-describing about its own hash algorithm (here, an example `sha256`).

```
a3                          map(3)              ← record for call c
  00  02                      key 0 (type)    = 2 (commitment)
  01  82 00 0c                key 1 (scope)   = [0, c]
  02  58 20 <32-byte digest>  key 2 (payload) = bstr(32)
```

Each record is 42 bytes. For example, the third payment (27,000 USDC, `c = 2`) has scope `82 00 02` and payload `5820e6cb...4b80`.

**Metadata field (array of five records).**

```
85                          array(5)
  a3 0002 01 820000 02 5820 e3a7bf1e2fe58d753137cce3595bd6ab1d97556559ae88b48e47d0628ce1321f
  a3 0002 01 820001 02 5820 8a77a55b25c4c7b982116fa5c585757c2ca4fcf36266f03e79ac4197610e9e70
  a3 0002 01 820002 02 5820 e6cb354d860108ebf74e31e1c51c68e8a791907de571e26f1e6cf5431c204b80
  a3 0002 01 820003 02 5820 defedc040caaa126ef3f71f2f3cc04281088da46f887cba2b6387ad6b2727a25
  a3 0002 01 820004 02 5820 eac1f983fb2102dc75539d3b40c510d19bd2ff091eff630c083211fbfca82451

metadata = 211 bytes total
```

| Call | Amount (USDC) | Scope | Receipt digest |
| --- | --- | --- | --- |
| 0 | 10,000 | `[0,0]` | `0xe3a7bf1e2fe58d753137cce3595bd6ab1d97556559ae88b48e47d0628ce1321f` |
| 1 | 15,000 | `[0,1]` | `0x8a77a55b25c4c7b982116fa5c585757c2ca4fcf36266f03e79ac4197610e9e70` |
| 2 | 27,000 | `[0,2]` | `0xe6cb354d860108ebf74e31e1c51c68e8a791907de571e26f1e6cf5431c204b80` |
| 3 | 20,000 | `[0,3]` | `0xdefedc040caaa126ef3f71f2f3cc04281088da46f887cba2b6387ad6b2727a25` |
| 4 | 17,000 | `[0,4]` | `0xeac1f983fb2102dc75539d3b40c510d19bd2ff091eff630c083211fbfca82451` |

A consumer reading this transaction recovers five commitment records, each bound to one transfer: anyone later shown a receipt document can verify it against the on-chain digest for the matching payment, while the transaction alone reveals only that each transfer has an associated receipt.

**Variant: one Merkle root for the batch (recommended).** Instead of five per-call records, the wallet builds a Merkle tree over the five receipt digests and carries a single commitment scoped to phase 0. The five leaves are the per-payment digests above; the root is `0x5baa2525c7f452de3a0be045ced4e883886f935d64701d23a486be826e6f3bc0`.

```
81                          array(1)
  a3                          map(3)            ← single commitment
    00 02                       type    = 2
    01 00                       scope   = 0 (phase 0, all calls)
    02 5820 5baa2525…6f3bc0     payload = bstr(32) Merkle root

metadata = 0x81a3000201000258205baa2525c7f452de3a0be045ced4e883886f935d64701d23a486be826e6f3bc0
         = 41 bytes total
```

This is 41 bytes versus 211 for the five per-call records. Each payment's receipt is still individually provable: a verifier is shown that receipt plus a Merkle proof (the sibling digests) and recomputes the root, and disclosing one receipt reveals only the other leaves' hashes, not their contents.

## Rationale

### A typed, self-describing container

The [EIP-8130](./eip-8130.md) `metadata` field is one signed byte string shared by every producer. Without structure, builder attribution, an application memo, and an off-chain commitment cannot coexist without a private agreement on framing. A CBOR array of typed records gives each producer an independent slot: records are appended, not merged, and each carries its own `type` and `scope`. CBOR is compact, self-describing, widely implemented, and has a specified deterministic profile, which matters because the bytes are signed.

### Why CBOR, and why no type byte

CBOR was chosen over a bespoke binary format because the structural overhead is small (a few bytes per record) and dominated by the payload itself, while CBOR brings a mature tooling ecosystem, a specified deterministic profile for signed data, and byte-level interoperability with [ERC-8021](./eip-8021.md) schema 2, whose attribution map is reused verbatim as the attribution payload. A custom format could save a handful of bytes per record but would forfeit all three, and on rollups the repeated structural bytes compress to near-nothing across a batch.

No leading magic or version byte is required because the field is never interpreted by the protocol and its length is always known from RLP. That length lets a consumer demand the CBOR decode to consume the field exactly, with no trailing bytes, under canonical-deterministic rules. A field that is not structured per this proposal essentially never satisfies "a canonical array of well-formed record maps that exactly fills the field," so strict decoding identifies the format without spending a byte on every transaction or breaking direct compatibility with a bare schema-2 attribution map. The danger is a *lax* decoder: a large fraction of unrelated byte strings begin with some parseable CBOR item, so accepting a leading item with trailing bytes would cause false positives. The strict full-consume rule, not a tag, is what makes identification safe; a tag is left to a future version for explicit versioning if needed.

### Encoding the top-level field versus a sink address

An alternative transport carries metadata as a no-op call to a reserved sink address inside the `calls` array, using the call's position to express scope. This proposal instead encodes the top-level `metadata` field, for three reasons. First, it keeps metadata out of `calls`, so it can never interact with execution, gas estimation, or phase atomicity. Second, scope is explicit data (`scope`) rather than an emergent property of call placement, so producers do not have to add empty phases to scope a record and consumers do not infer scope from layout. Third, a single signed field with one parser is simpler for wallets and indexers than recognizing and filtering a reserved address across phases. The trade-off is that this design depends on [EIP-8130](./eip-8130.md) defining the `metadata` field, whereas a sink address needs no new transaction field.

### Scope mirrors the calls structure

Metadata is useful at different granularities: a builder code describes the whole transaction, while a remittance memo describes one transfer in a batch. Encoding `scope` as a phase index or `[phase, call]` pair reuses [EIP-8130](./eip-8130.md)'s existing two-level `calls` structure rather than inventing a parallel addressing scheme, so a record points directly at the calls it annotates.

### Scope stability under construction reordering

Using absolute phase indices is safe in practice because the wallet — which both receives the app's attribution intent and assembles the final `calls` — is the sole encoder of `metadata`. When a payer prepends a phase, the wallet observes the final structure and maps the app's calls to their correct index before encoding. The requirement that scope be resolved only after `calls` is finalized makes this explicit. An alternative using relative indices (e.g. offset from end) was considered but adds consumer complexity without solving a real problem: the wallet's position as final assembler already ensures correctness with absolute indices.

### Commitments for privacy

Publishing a digest instead of the document keeps sensitive detail (receipt contents, invoice line items, KYC references) off-chain while still binding the transaction to it: anyone later shown the document can verify it against the on-chain digest, but nothing is revealed by the transaction alone. The record carries only the digest; the document is self-describing about its own hashing and format, and is resolved out-of-band. This mirrors how off-chain attestation systems keep the on-chain footprint to a commitment (a hash or Merkle root) and leave storage and delivery to the application, which avoids baking a storage locator or format registry into consensus-adjacent signed data.

### Type as a hint, not a gate

Treating `type` as advisory (with a mandatory opaque fallback) means an unrecognized or future record type never causes a consumer to reject an otherwise valid transaction, and a coincidental byte pattern cannot be mistaken for a structured payload as long as defined types are self-validating.

## Backwards Compatibility

This proposal applies only to the [EIP-8130](./eip-8130.md) `metadata` field and changes nothing on legacy transaction types. During transition, indexers SHOULD continue to parse trailing-bytes data suffixes on legacy transactions while reading structured `metadata` on [EIP-8130](./eip-8130.md) transactions. An [ERC-8021](./eip-8021.md) schema-2 attribution previously carried as a trailing calldata suffix maps directly onto an attribution record: the schema-2 CBOR map becomes the record `payload` unchanged, with the legacy `ercMarker`, `schemaId` byte, and length prefix dropped.

## Security Considerations

### Unverified metadata

Metadata is an attestation by the signer only: it asserts that the signer committed to those bytes, not that the content is true. Consumers MUST NOT grant trust or privileges based on payload content without independent verification, and MUST sanitize untrusted bytes before use.

### Commitments reveal metadata about existence

A commitment record proves that *some* off-chain document existed and was bound to the transaction at signing time, and its scope reveals which calls that document concerns. Producers SHOULD treat the presence and scope of a commitment as themselves disclosed, and MUST place only an opaque digest, not any recoverable fragment of the document, in the payload. A single hash of a small or low-entropy document is guessable; producers SHOULD salt the document (or use a Merkle tree of salted leaves) so the digest does not leak its preimage.

### Malformed and adversarial encodings

Because `metadata` is attacker-influenced bytes, consumers MUST bound decoding work (array length, nesting, record count) and MUST NOT fail transaction processing on a malformed or non-deterministic encoding; such input is treated as opaque. A record whose `scope` references calls it did not produce carries no authority: scope is a producer's claim, not a protocol guarantee.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
