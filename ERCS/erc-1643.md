---
eip: 1643
title: Document Management for Security Tokens
description: Interface to attach, update, remove, and enumerate legal or operational documents for token contracts.
author: Adam Dossa (@adamdossa), Pablo Ruiz (@pabloruiz55), Fabian Vogelsteller (@frozeman), Stephane Gosselin (@thegostep), Ryan Sauge (@rya-sge)
discussions-to: https://ethereum-magicians.org/t/erc-1643-document-management-standard-erc-1400/27437
status: Draft
type: Standards Track
category: ERC
created: 2018-09-09
---

## Abstract

This ERC defines a standard interface for associating documents with a token contract and for notifying off-chain systems when those documents change. Documents can represent legal agreements, offering materials, disclosures, or other issuer-provided references needed for security token operations.

## Motivation

Security tokens commonly represent assets with legal rights and obligations that depend on external documents. Wallets, exchanges, custodians, and compliance tools need a predictable way to discover those documents and track updates.

Without a standard, each implementation exposes different storage and retrieval methods, increasing integration cost and operational risk. A common interface allows ecosystem participants to read and monitor document metadata consistently.

Within security token frameworks, the document management component highlights that security tokens usually have associated documentation such as offering documents and legend details. The ability to set, remove, and retrieve these documents, with events emitted on those actions, allows investors and integrators to remain up to date.

This ERC intentionally does not define an on-chain mechanism for investors to attest they have read or agreed to any document.

Historically, this proposal was authored as part of a broader security token standards suite called ERC‑1400, and that parent suite had not yet been merged in this repository when this proposal was added.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHOULD", and "MAY" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Implementations MUST support querying and subscribing to updates on any relevant documentation for the security.

A document entry is identified by a name (`bytes32`) and stores:

- A URI (`string`) pointing to the document location.
- A content hash (`bytes32`) for integrity checks.
- A last-modified timestamp (`uint256`) set when the entry is written.

### Interface

```solidity
/// @title IERC1643 Document Management
interface IERC1643 {
    /// @notice Returns metadata for a document identified by `name`.
    /// @return uri Document location.
    /// @return documentHash Hash of the document contents.
    /// @return lastModified Last update timestamp.
    function getDocument(bytes32 name) external view returns (string memory uri, bytes32 documentHash, uint256 lastModified);

    /// @notice Creates or updates a document entry.
    /// @dev MUST emit `DocumentUpdated` on success.
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external;

    /// @notice Removes an existing document entry.
    /// @dev MUST emit `DocumentRemoved` on success.
    function removeDocument(bytes32 name) external;

    /// @notice Returns all document names currently tracked by the contract.
    function getAllDocuments() external view returns (bytes32[] memory documentNames);

    /// @notice Emitted when a document is created or updated.
    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);

    /// @notice Emitted when a document is removed.
    event DocumentRemoved(bytes32 indexed name, string uri, bytes32 documentHash);
}
```

### Function Requirements

- `getDocument`:
  - MUST return the latest values for the provided document name.
  - MUST return empty values when the entry does not exist (`""`, `bytes32(0)`, `0`).
  - MUST NOT revert solely because the entry does not exist.

- `setDocument`:
  - MUST create a new entry when `name` is not present.
  - MUST overwrite the existing entry when `name` already exists.
  - MUST update the stored last-modified timestamp.
  - MUST emit `DocumentUpdated` after state changes.
  - MUST revert if the update cannot be persisted.

- `removeDocument`:
  - MUST remove the entry identified by `name`.
  - MUST emit `DocumentRemoved` with the removed metadata.
  - MUST revert if removal cannot be completed.

- `getAllDocuments`:
  - MUST include every document name added by `setDocument` and not removed by `removeDocument`.
  - MUST NOT include removed document names.

## Rationale

The standard uses `bytes32` names to keep keys compact and deterministic, while leaving naming conventions to implementations. A URI-based pointer is used instead of on-chain document storage to avoid high gas costs and to support existing off-chain document systems.

Including a document hash enables clients to verify that fetched off-chain content matches issuer-published metadata. Emitting update and removal events supports indexing and near-real-time monitoring without repeated full-state polling.

While a human-readable document title cannot always be represented directly in `bytes32` without hashing or canonicalization, `bytes32` remains practical for on-chain identifiers because fixed-size values can be compared directly (`a == b`). By contrast, `string` comparisons generally require hashing (for example, `keccak256(bytes(s))`), which increases contract code size and gas usage when repeated comparisons are needed on-chain, such as locating and removing a document name from an array.

## Backwards Compatibility

This ERC is additive and does not alter base token transfer semantics. It can be implemented alongside existing token standards and permissioning systems without changing their core behavior.

## Test Cases

Implementations should verify at least the following:

- Adding a new document and reading it through `getDocument`.
- Updating an existing document and validating changed URI/hash/timestamp.
- Removing a document and ensuring it is no longer returned by `getAllDocuments`.
- Emission of `DocumentUpdated` on create/update and `DocumentRemoved` on delete.
- Enumeration consistency after multiple add/update/remove operations.

## Reference Implementation

A minimal implementation maintains:

- Mapping from `bytes32` name to document metadata.
- Array/set for enumeration of active names.
- Index tracking to support O(1) removals from the enumeration set.

Implementers can add access control to restrict document mutation operations (for example, issuer or agent-only updates).

## Security Considerations

Document URIs may reference mutable off-chain content. Consumers are strongly encouraged to verify content using the published `documentHash` and trusted retrieval channels.

Implementations should protect `setDocument` and `removeDocument` with appropriate authorization, otherwise unauthorized actors can modify legal or operational references.

Applications should treat event streams as advisory and reconcile against on-chain state when correctness is critical.

Document names may not always fit cleanly into `bytes32`, especially for long legal titles. Implementations should avoid lossy truncation of human-readable names; using a deterministic hash-based identifier (for example, the document content hash or a hash of a canonical full title) as the `bytes32` name is a safer alternative.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
