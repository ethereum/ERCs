---
title: ERC-721 Lineage Registry
description: An ERC-721 extension for authorized parentage records with immutable chronology and optional genealogy operations.
author: Henrique L. Alvim (@henriquelalvim)
discussions-to: https://ethereum-magicians.org/t/lineage-registry-an-erc-721-extension-for-on-chain-genealogical-trees/29441
status: Draft
type: Standards Track
category: ERC
created: 2026-09-25
requires: 165, 721
---

## Abstract

This proposal extends [ERC-721](./eip-721.md) with genealogical records containing immutable sex and birth timestamps and up to two independently optional parent references. Owner authorization governs the creation of parentage assertions. Strict chronology makes the graph acyclic without requiring token IDs to follow genealogical order. Optional interfaces provide offspring queries, late parent attachment, duplicate reconciliation and leaf burning.

## Motivation

Pedigree applications need common semantics for reading ancestry, distinguishing missing parents and determining permission to record a relationship. Application-specific token metadata does not provide interoperable validation or authorization rules. A shared interface allows registries, wallets and indexers to exchange and inspect records without adopting the same storage implementation or breed-specific policy.

The initial use case is pedigree animals with male and female parental roles. The registry records authorized assertions; it does not establish biological truth or uniquely identify a physical animal.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Conformance and scope

A conforming registry MUST implement [ERC-721](./eip-721.md), [ERC-165](./eip-165.md) and `ILineageRegistry`. The four extension interfaces below are OPTIONAL. Their requirements apply only when the corresponding extension is implemented. Supporting an extension MUST NOT weaken the core invariants.

All parent references identify tokens in the same contract. Cross-contract and cross-chain parent references, evidence certification, unknown sex and alternative reproductive models are outside this specification. Registration access policy and the registration function's signature are implementation-defined. Breed data, animal names, death records and metadata formats are not specified.

### Core interface

```solidity
interface ILineageRegistry {

    struct Node {
        uint256 sireId;
        uint256 damId;
        int64 birthTimestamp;
        bool isMale;
    }

    event NodeRegistered(uint256 indexed tokenId, address indexed to, bool isMale, int64 birthTimestamp);

    event ParentageLinked(uint256 indexed tokenId, uint256 indexed sireId, uint256 indexed damId);

    event ParentageLinkageApproved(uint256 indexed parentTokenId, address indexed linker, bool approved);
    event GeneralParentageLinkageApprovalSet(address indexed owner, address indexed linker, bool approved);

    function approveParentageLinkage(uint256 parentTokenId, address linker, bool approved) external;

    function approveParentageLinkageBatch(uint256[] calldata parentTokenIds, address linker, bool approved)
        external;

    function setGeneralParentageLinkageApproval(address linker, bool approved) external;

    function canUseAsParent(uint256 parentTokenId, address caller) external view returns (bool);

    function parentageLinkageApproval(uint256 parentTokenId, address linker) external view returns (bool);

    function generalParentageLinkageApproval(address ownerAddr, address linker) external view returns (bool);

    function isMale(uint256 tokenId) external view returns (bool);

    function birthTimestampOf(uint256 tokenId) external view returns (int64);

    function getParents(uint256 tokenId) external view returns (uint256 sireId, uint256 damId);

    function getNode(uint256 tokenId) external view returns (Node memory);

    function nodeExists(uint256 tokenId) external view returns (bool);

    function getNodesBatch(uint256[] calldata tokenIds)
        external view returns (Node[] memory nodes, bool[] memory found);
}
```

### Records and invariants

A live record is a token with an existing ERC-721 owner. Token ID zero MUST NOT be minted. IDs MUST NOT be reused after burning or merging. Sequential allocation and a `nextTokenId` getter are not required.

Each record MUST have immutable `isMale` and `birthTimestamp` values. `isMale == true` denotes male; false denotes female. Birth timestamps MUST use signed `int64` Unix seconds: negative values precede 1970-01-01T00:00:00Z, and zero denotes that instant. No timestamp is reserved for absence. Calendar conversion is off-chain using UTC and the proleptic Gregorian calendar. Only exact timestamps are represented; incomplete or estimated dates are outside scope.

At creation, the birth timestamp MUST be no later than the current block timestamp. Signed comparisons MUST preserve negative values and MUST NOT narrow the block timestamp to `int64` before comparison.

A zero parent ID means that no parent is recorded in that slot. Each slot is independently optional. For every nonzero parent reference:

- The referenced token MUST be live in the same registry.
- A sire MUST have `isMale == true`; a dam MUST have `isMale == false`.
- The parent's birth timestamp MUST be strictly less than the child's birth timestamp.

These requirements MUST hold after every completed graph mutation. Every operation MUST revert atomically when a required check fails. Equal parent and child timestamps and self-parentage MUST be rejected.

Ordinary parentage writes MUST NOT clear, replace or repeat a recorded slot. Only the Late Parentage extension may fill slots after registration. Duplicate reconciliation is the sole exception permitting the reference changes specified under Mergeable. No correction or supersession operation is defined, and administrative privileges MUST NOT permit replacement of an incorrect assertion.

A token MUST NOT be destroyed while a live child references it. Removal is permitted through leaf burning or completed duplicate reconciliation as defined below. Historical events remain available after removal.

### Parent authorization

Registration and late attachment MUST require authorization for each newly supplied parent. The authorized actor is the address calling the registration or attachment function. For a live parent, authorization is true if and only if at least one condition holds:

- The actor is the parent's current owner.
- The actor has a current per-token parentage grant.
- The parent's current owner has granted that actor blanket parentage permission.

ERC-721 token approvals and operator approvals MUST NOT themselves confer parentage permission. Revoking a grant MUST NOT delete existing relationships. Filling the other slot MUST NOT require renewed consent for an already recorded parent.

`approveParentageLinkage` MUST require ownership of the live parent token, set the requested per-token grant and emit `ParentageLinkageApproved`. `approveParentageLinkageBatch` MUST apply the same operation in input order and atomically require ownership of every supplied token. Repeated IDs MUST be processed as repeated approvals; empty input MUST be a no-op.

`setGeneralParentageLinkageApproval` MUST set the caller's blanket grant and emit `GeneralParentageLinkageApprovalSet`. These setters MUST accept any linker address, including the caller and the zero address. A grant to the zero address does not establish a transaction-sending capability.

Per-token grants MUST expire on an ownership change or burn and MUST NOT revive after transfer back to a previous owner. Self-transfers MUST preserve lineage grants. Blanket grants MUST remain associated with their granting owner and apply only to that owner's current holdings, including subsequent acquisitions. A standing blanket grant can therefore apply again after reacquisition.

`canUseAsParent` MUST return effective authorization according to these rules and MUST revert for an absent token. `parentageLinkageApproval` MUST return only the current per-token grant, excluding ownership and blanket permission, and MUST return false for absent tokens. `generalParentageLinkageApproval` MUST return the specified owner's blanket grant regardless of that owner's current token holdings. Unset grants MUST read as false.

Ownership-changing ERC-721 `Transfer` events signal per-token grant invalidation. Separate revocation events for each grantee are not required.

### Reading records

`isMale`, `birthTimestampOf`, `getParents` and `getNode` MUST return the corresponding live record fields and MUST revert for absent tokens. `nodeExists` MUST return true exactly for live tokens; zero, never-minted, burned and merged-away IDs MUST return false.

`getNodesBatch` MUST return two arrays with the input length and preserve input order, including repeated IDs. For a live ID, `nodes[i]` MUST equal its `getNode` result and `found[i]` MUST be true. For an absent ID, `nodes[i]` MUST contain zeroed fields and `found[i]` MUST be false. Empty input MUST return two empty arrays.

A female founder born at the epoch has zeroed node fields but `found == true`. Consumers MUST NOT infer existence from a timestamp or from the node's field values.

### Events and indexing

Creation MUST emit `NodeRegistered` with the initial owner, sex and birth timestamp. When creation records at least one parent, it MUST also emit `ParentageLinked`. A founder with no recorded parents does not require a `ParentageLinked` event.

Every subsequent parent-pointer mutation MUST emit `ParentageLinked` containing the complete resulting pair, including unchanged slots. This includes late attachment, adopted survivor parentage and redirected children during reconciliation. Consumers reconstruct ancestry by replacing the previous pair and omitting zero references.

An ERC-721 burn removes the node and its links to its parents from the live graph. It does not require an additional `ParentageLinked` event clearing the burned record. Forwarding information created by merging MUST persist independently of token existence.

### Interface discovery

`supportsInterface` MUST return true for the core interface ID and for each implemented extension's ID, in addition to the required ERC-721 and ERC-165 IDs. The identifiers below are calculated from each interface's own functions; the interfaces do not inherit one another.

| Interface | ID | Required interfaces |
| --- | --- | --- |
| `ILineageRegistry` | `0x63add18e` | ERC-721, ERC-165 |
| `ILineageRegistryOffspring` | `0x698afb25` | Core |
| `ILineageRegistryLateParentage` | `0x311f6e23` | Core |
| `ILineageRegistryMergeable` | `0x4205c309` | Offspring |
| `ILineageRegistryBurnable` | `0x42966c68` | Offspring |

### Offspring extension

```solidity
interface ILineageRegistryOffspring {

    function getOffspring(uint256 tokenId) external view returns (uint256[] memory);

    function offspringCount(uint256 tokenId) external view returns (uint256);
}
```

`getOffspring` MUST return every live token directly naming the queried token as sire or dam, exactly once, and no other tokens. Ordering is unspecified. `offspringCount` MUST return the number of those tokens. Both functions MUST revert when the queried token is absent.

The reverse index MUST remain consistent with current parent pointers after registration, attachment, reconciliation and burning. Zero parent slots MUST NOT produce reverse-index entries. This interface does not specify pagination.

### Late Parentage extension

```solidity
interface ILineageRegistryLateParentage {

    event ChildParentageLinkageApproved(uint256 indexed childTokenId, address indexed linker, bool approved);

    function attachParentage(uint256 tokenId, uint256 sireId, uint256 damId) external;

    function approveChildParentageLinkage(uint256 childTokenId, address linker, bool approved) external;

    function childParentageLinkageApproval(uint256 childTokenId, address linker) external view returns (bool);
}
```

`attachParentage` MUST require a live child and a caller who owns that child or has a current child-side grant. ERC-721 approvals and blanket parent grants MUST NOT themselves confer child-side permission.

A zero argument leaves its slot unchanged. At least one supplied parent ID MUST be nonzero. Each nonzero argument MUST target an empty slot; supplying an already recorded parent, even with the same ID, MUST revert. Each supplied parent MUST satisfy the core existence, sex, chronology and authorization checks. Both slot updates MUST be atomic, and the operation MUST emit the complete resulting pair.

`approveChildParentageLinkage` MUST require ownership of the live child, set the requested grant and emit `ChildParentageLinkageApproved`. It MUST accept any linker address. Child grants MUST expire under the same ownership-change, burn and reacquisition rules as per-token parent grants. Self-transfers MUST preserve them.

`childParentageLinkageApproval` MUST return only the current child grant and MUST return false for absent tokens, revoked grants and grants from prior ownership periods. Unset grants MUST read as false.

### Mergeable extension

```solidity
interface ILineageRegistryMergeable {

    event NodesMerged(uint256 indexed survivorId, uint256 indexed duplicateId);

    function mergedInto(uint256 duplicateId) external view returns (uint256 survivorId);
}
```

This extension defines reconciliation outcomes and forwarding queries. Initiation, consent entry points and execution scheduling are implementation-defined. An implementation MUST define and enforce a merge authorization policy; ERC-165 support does not identify that policy. Merge authorization replaces individual parent-grant checks for the reconciliation itself.

A reconciliation MUST reject identical or absent candidates, different sexes and candidates in an ancestor/descendant relationship. The survivor's immutable birth timestamp MUST be no later than the duplicate's timestamp.

For each parent slot, the survivor MUST retain its known parent or adopt the duplicate's parent if its own slot is empty. Different nonzero IDs in the same slot MUST cause rejection. Adopted parents MUST satisfy the survivor's sex-role and chronology requirements. Parent IDs are compared directly; this operation MUST NOT substitute a different known parent to correct an assertion.

On completion:

- Every live child of the duplicate MUST instead reference the survivor in the same slot.
- The reverse index MUST reflect all adopted, redirected and removed edges.
- The duplicate MUST be burned and the survivor MUST remain live.
- `mergedInto(duplicateId)` MUST be set to the survivor ID and `NodesMerged` MUST be emitted in the transaction that burns the duplicate.
- Every modified live node MUST have emitted its complete resulting parent pair.

`mergedInto` MUST return zero for IDs that have never been merged, including zero, never-minted IDs and ordinarily burned leaves. Once set, a forwarding entry MUST persist unchanged after burning or later merging of the survivor. Forwarding chains are permitted. A terminal forwarding target need not remain live; consumers MUST check existence after resolution.

If an implementation supports pending consent offers, a change of ownership or removal of either candidate MUST invalidate prior offers, including transfers away and back. Self-transfers do not constitute an ownership change.

No common batching or pending-operation API is defined by this interface. An implementation that performs work across transactions MUST maintain the core invariants and accurate query results at every transaction boundary. It MUST keep the duplicate live while any child still references it and MUST NOT publish completion before all completion conditions hold. Implementations MAY reject operations that cannot complete within their supported resource limits.

### Burnable extension

```solidity
interface ILineageRegistryBurnable {

    event NodeBurned(uint256 indexed tokenId);

    function burn(uint256 tokenId) external;
}
```

`burn` MUST require a live token and a caller authorized to transfer it under ERC-721 ownership or approval rules. It MUST reject a token with any live offspring. On success it MUST destroy the token, remove its entries from its parents' offspring lists and emit `NodeBurned` and the ERC-721 burn `Transfer` event. Token-specific lineage grants MUST cease to apply, and the token ID MUST remain unavailable for reuse.

## Rationale

### Chronology and acyclicity

Every child-to-parent edge strictly decreases an immutable timestamp. A directed cycle would require a timestamp to be strictly less than itself. The graph is therefore acyclic regardless of numeric token IDs or registration order, including when an older animal is registered after a descendant and attached later.

The proof applies to all mutations. For merges, keeping a survivor no younger than the duplicate preserves chronology for redirected children; checking adopted parents against the survivor preserves chronology above it. Refusing ancestor/descendant reconciliation is an additional identity policy.

### Partial records and permanent assertions

Independent zero slots distinguish unknown ancestry from recorded ancestry without inventing placeholder animals. Boolean sex describes the two parental roles in scope; explicit existence queries distinguish absent tokens from female records.

Write-once assertions give consumers stable historical commitments. Late attachment adds missing knowledge. Reconciliation identifies duplicate records subject to conflict checks. Neither operation provides a general correction mechanism.

Signed timestamps support historical records before 1970 while retaining a compact representation. Approximate dates would require different chronology semantics and are outside this proposal.

### Optional capabilities

Storing parent references on children is sufficient to traverse ancestry. A reverse index imposes additional write costs and is optional because indexers can reconstruct it from events. Late attachment, reconciliation and burning also remain optional so applications can support the core without exposing these mutations.

Large reconciliations are intended to use bounded, resumable batches. The shared progress and locking protocol remains extension work; the current Mergeable interface standardizes completion and forwarding only. A loop over every child is not a scalability guarantee, and bounding child rewrites does not bound ancestor checks or reverse-index maintenance.

### Local references

Local references let one contract enforce existence, immutable chronology and consistent reads. Foreign records would require additional identity, availability and trust rules. Identifying nodes from separate acyclic graphs can introduce cycles in their combined graph. Federation is deferred.

## Backwards Compatibility

ERC-721 ownership, transfers and approvals retain their existing meanings. Generic ERC-721 applications can interact with tokens without interpreting lineage; lineage consumers discover this extension through ERC-165. Existing ERC-721 contracts do not automatically acquire genealogy support.

Lineage authorization is separate from transfer authorization. Earlier experimental interfaces with unsigned timestamps or batch reads lacking existence flags are not compatible with this specification. Return types are not part of function selectors, so clients must use the specified ABI and interface discovery rather than infer compatibility from a callable selector. This document specifies no storage migration or upgrade procedure.

## Test Cases

The following cases assume valid registration inputs and no additional domain restrictions. IDs are examples, not allocation requirements. Each row is an independent scenario unless otherwise stated.

| Setup and operation | Expected result |
| --- | --- |
| Register an authorized child with `(sire, 0)` and a strictly earlier male sire | One parent recorded; dam remains zero |
| Supply an absent, wrong-sex or unauthorized parent | Revert without partial writes |
| Supply a parent with the same or a later birth timestamp | Revert |
| Register parent at `-200` and child at `-100` | Chronology accepted |
| Read a live female founder born at `0` in a batch | Zeroed node fields with `found == true` |
| Batch-read `[liveId, absentId, liveId]` | Three aligned results; existence flags `[true, false, true]` |
| Batch-read an empty array | Two empty arrays |
| Transfer a token with a per-token grant away and back | Original per-token grant remains invalid |
| Self-transfer a token with a per-token grant | Grant remains valid |
| Give an actor only ERC-721 operator approval | Actor gains no parentage permission |
| Attach `(0, dam)` to a child with `(sire, 0)`, with all permissions and valid chronology | Result `(sire, dam)`; event contains both parents |
| Attach the already recorded sire again, or attach `(0, 0)` | Revert |
| Attach a valid older parent whose token ID is higher than the child's | Accept without an ID-order constraint |
| Merge compatible records whose known sire IDs differ | Revert |
| Complete an authorized, compatible reconciliation | Children reference survivor; duplicate absent; forwarding entry and completion event present |
| Transfer either candidate after a pending consent offer | Prior offer invalid |
| Burn an authorized leaf | Record absent; parent's reverse index updated; ID cannot be reused |
| Burn a token referenced by a live child | Revert |

## Security Considerations

### Assertions and authority

Authorization does not prove biological descent, birth evidence or physical identity. Duplicate and fraudulent registrations remain possible. Incorrect recorded parents are permanent and can compromise descendants' pedigrees. Applications must distinguish structural validity from certification and physical ownership.

Parent grants can authorize multiple future assertions; they are not restricted to one offspring or consumed after use. Blanket grants also cover future acquisitions. Applications should expose these scopes when requesting permission. Revocation cannot undo an assertion recorded before revocation.

Transfers must invalidate token-specific permissions even when a token later returns to the original owner. Implementations should use an ownership generation or equivalent mechanism rather than associate grants only with an owner address. Merge authorization policies need separate review, since this extension deliberately leaves their entry points to implementations.

### Graph integrity

All mutation paths, including privileged or upgrade paths, must preserve immutable chronology and valid references. Unsigned conversion of a negative birth timestamp, narrowing the block timestamp, or allowing date edits can invalidate the ordering argument.

Implementations using receiver callbacks or other external calls must preserve authorization and record consistency across reentrancy. Transfers during callbacks must not leave effective grants from a previous ownership period.

Multi-transaction reconciliation must prevent concurrent transfers, attachment, burning or other merges from invalidating its authorization and progress. Queries and events must describe the actual intermediate graph. An unfinished operation must not leave children pointing to a destroyed token.

### Resource limits and availability

Ancestor walks, rewriting all children and linearly searching reverse indexes can exceed transaction gas limits. A valid merge or leaf burn may therefore be unavailable in an implementation using unbounded operations. Bounded child batches alone do not resolve the other costs.

Batch getters and full offspring arrays can exceed execution or RPC response limits. Clients should bound their requests and use indexed event data where full-array reads are impractical. Long forwarding chains likewise require bounded client work and explicit handling of absent terminal targets.

Indexers must process complete parent-pair updates, burns, ownership changes and chain reorganizations. Treating every parent event as an append operation produces duplicate or stale edges. Burning removes live state but does not erase previously published information from chain history.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
