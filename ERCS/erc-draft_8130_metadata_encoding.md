---
title: Transaction Metadata Encoding for EIP-8130
description: A structured encoding for the EIP-8130 metadata field, scoping records to a transaction, phase, or call and supporting commitments to off-chain data
author: Chris Hunter (@chunter-cb) <chris.hunter@coinbase.com>
discussions-to: https://ethereum-magicians.org/t/erc-transaction-metadata-encoding-for-eip-8130
status: Draft
type: Standards Track
category: ERC
created: 2026-06-11
requires: 8130
---

## Abstract

[EIP-8130](./eip-8130.md) adds an optional, opaque `metadata` field to its transaction type for attribution and annotation data, but leaves the byte layout to a companion specification. This proposal defines that layout: `metadata` is a deterministic [CBOR](https://www.rfc-editor.org/rfc/rfc8949) array of **records**, where each record carries a **type** (how its payload is interpreted), an optional **scope** (the whole transaction, a phase, or a single call), and a **payload**. The encoding lets multiple independent parties attach metadata to one transaction, scope each annotation to the relevant calls, and commit to off-chain data without revealing it on-chain. This proposal defines the container, the record envelope, and an initial set of record types; payload formats for individual types MAY be defined by other specifications.

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

### Record types

This proposal defines an initial registry of record types. The `type` value is a hint: a consumer that does not recognize a `type`, or whose `payload` does not validate against the named format, MUST treat that record's `payload` as opaque rather than rejecting the transaction.

| `type` | Name | `payload` |
| --- | --- | --- |
| `0` | Opaque | A CBOR byte string of application-defined bytes. |
| `1` | Attribution | A byte string carrying [ERC-8021](./eip-8021.md) attribution (its `schemaId` and schema data), parsed per [ERC-8021](./eip-8021.md). |
| `2` | Commitment | A commitment to off-chain data. See [Commitment records](#commitment-records). |

Future ERCs MAY define additional `type` values. A defined `type` SHOULD be self-validating (structurally checkable) so a coincidental match on opaque bytes is rejected.

### Commitment records

A **commitment record** (`type 2`) binds the transaction to off-chain data without revealing it. Its `payload` is a CBOR byte string: the **digest** of the off-chain document (for example a `keccak256` hash, or a Merkle root for selectively-disclosable documents). Only the digest appears on-chain, so the document's contents (for example receipt line items) stay private until revealed.

The off-chain document is **self-describing**: the hash algorithm, the document format or schema, and how the digest was computed are defined by the document and the application that produces it, not by this proposal. A verifier recomputes the digest over a presented document (per that document's own rules) and compares it to the on-chain value.

This proposal deliberately does not carry a **locator** for the off-chain document. Following the model of off-chain attestations in systems like the [Ethereum Attestation Service](https://attest.org), the digest is the only on-chain artifact; the document is resolved through an application side channel (a shared URL, a content-addressed store such as IPFS, or peer-to-peer delivery) rather than a pointer embedded in the transaction. Applications that do need an on-chain locator can carry it as their own opaque (`type 0`) record alongside the commitment.

A commitment record's `scope` ties the off-chain data to its subject: absent for a receipt covering the whole transaction, or `[p, c]` for a document describing one call (for example one transfer in a batch).

### Determinism

Producers MUST encode `metadata` using CBOR core deterministic encoding ([RFC 8949 §4.2](https://www.rfc-editor.org/rfc/rfc8949#section-4.2)): definite-length items, integers and lengths in their shortest form, and map keys sorted in bytewise lexicographic order of their encodings. Determinism ensures the signed bytes are reproducible by any party validating the transaction and that a digest computed over a record is stable.

### Consumer behavior

For an [EIP-8130](./eip-8130.md) transaction whose `metadata` is structured per this proposal, a consumer:

1. Decodes `metadata` as a CBOR array; if decoding fails, treats `metadata` as wholly opaque.
2. For each record, reads `type` (default `0`), `scope` (default whole transaction), and `payload`.
3. Resolves `scope` against `calls` per [Scope](#scope), ignoring out-of-range scopes.
4. Interprets `payload` per `type`, falling back to opaque for unknown or non-validating types.

A consumer MUST treat metadata as describing only the transaction it appears in, and MUST NOT infer any execution effect from it: records are inert annotations, never dispatched or executed.

## Rationale

### A typed, self-describing container

The [EIP-8130](./eip-8130.md) `metadata` field is one signed byte string shared by every producer. Without structure, builder attribution, an application memo, and an off-chain commitment cannot coexist without a private agreement on framing. A CBOR array of typed records gives each producer an independent slot: records are appended, not merged, and each carries its own `type` and `scope`. CBOR is compact, self-describing, widely implemented, and has a specified deterministic profile, which matters because the bytes are signed.

### Encoding the top-level field versus a sink address

An alternative transport carries metadata as a no-op call to a reserved sink address inside the `calls` array, using the call's position to express scope. This proposal instead encodes the top-level `metadata` field, for three reasons. First, it keeps metadata out of `calls`, so it can never interact with execution, gas estimation, or phase atomicity. Second, scope is explicit data (`scope`) rather than an emergent property of call placement, so producers do not have to add empty phases to scope a record and consumers do not infer scope from layout. Third, a single signed field with one parser is simpler for wallets and indexers than recognizing and filtering a reserved address across phases. The trade-off is that this design depends on [EIP-8130](./eip-8130.md) defining the `metadata` field, whereas a sink address needs no new transaction field.

### Scope mirrors the calls structure

Metadata is useful at different granularities: a builder code describes the whole transaction, while a remittance memo describes one transfer in a batch. Encoding `scope` as a phase index or `[phase, call]` pair reuses [EIP-8130](./eip-8130.md)'s existing two-level `calls` structure rather than inventing a parallel addressing scheme, so a record points directly at the calls it annotates.

### Commitments for privacy

Publishing a digest instead of the document keeps sensitive detail (receipt contents, invoice line items, KYC references) off-chain while still binding the transaction to it: anyone later shown the document can verify it against the on-chain digest, but nothing is revealed by the transaction alone. The record carries only the digest; the document is self-describing about its own hashing and format, and is resolved out-of-band. This mirrors how off-chain attestation systems keep the on-chain footprint to a commitment (a hash or Merkle root) and leave storage and delivery to the application, which avoids baking a storage locator or format registry into consensus-adjacent signed data.

### Type as a hint, not a gate

Treating `type` as advisory (with a mandatory opaque fallback) means an unrecognized or future record type never causes a consumer to reject an otherwise valid transaction, and a coincidental byte pattern cannot be mistaken for a structured payload as long as defined types are self-validating.

## Backwards Compatibility

This proposal applies only to the [EIP-8130](./eip-8130.md) `metadata` field and changes nothing on legacy transaction types. During transition, indexers SHOULD continue to parse trailing-bytes data suffixes on legacy transactions while reading structured `metadata` on [EIP-8130](./eip-8130.md) transactions. A payload previously carried as a trailing suffix (for example an [ERC-8021](./eip-8021.md) attribution suffix) can be carried unchanged as the `payload` of an attribution record.

## Security Considerations

### Unverified metadata

Metadata is an attestation by the signer only: it asserts that the signer committed to those bytes, not that the content is true. Consumers MUST NOT grant trust or privileges based on payload content without independent verification, and MUST sanitize untrusted bytes before use.

### Commitments reveal metadata about existence

A commitment record proves that *some* off-chain document existed and was bound to the transaction at signing time, and its scope reveals which calls that document concerns. Producers SHOULD treat the presence and scope of a commitment as themselves disclosed, and MUST place only an opaque digest, not any recoverable fragment of the document, in the payload. A single hash of a small or low-entropy document is guessable; producers SHOULD salt the document (or use a Merkle tree of salted leaves) so the digest does not leak its preimage.

### Malformed and adversarial encodings

Because `metadata` is attacker-influenced bytes, consumers MUST bound decoding work (array length, nesting, record count) and MUST NOT fail transaction processing on a malformed or non-deterministic encoding; such input is treated as opaque. A record whose `scope` references calls it did not produce carries no authority: scope is a producer's claim, not a protocol guarantee.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
