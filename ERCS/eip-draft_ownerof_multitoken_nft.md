---
eip: XXXX
title: Non-Fungible Multi-Token ownerOf
description: A canonical ownerOf interface for non-fungible ERC-1155 and ERC-6909 token IDs.
author: TBD
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-05-23
requires: 165, 721, 1155, 5615, 6909
---

## Abstract

This ERC defines a minimal `ownerOf(uint256 id)` interface for non-fungible token IDs managed by [ERC-1155](./eip-1155.md) and [ERC-6909](./eip-6909.md) multi-token contracts. A covered token ID has a maximum supply of one unit, and its current holder can be read with the same function selector used by [ERC-721](./eip-721.md). The interface lets wallets, marketplaces, delegation registries, indexers, token-bound integrations, and agent-binding integrations consume non-fungible multi-token IDs through a single-owner accessor without requiring the contract to implement ERC-721.

Implementations of this profile are informally referred to as ERC-1155F and ERC-6909F, where the `F` denotes the fixed-supply, single-unit non-fungible profile of the respective base standard.

## Motivation

ERC-1155 and ERC-6909 can both represent fungible and non-fungible token IDs within one contract. Their base interfaces expose balances by `(owner, id)`, but they do not expose a canonical single-owner read for IDs whose supply is fixed to one. Integrators that understand ERC-721 ownership through `ownerOf(uint256)` therefore need bespoke adapters, offchain indexing, or contract-specific logic for non-fungible multi-token IDs.

This gap already appears in production. The ENS NameWrapper represents wrapped names as ERC-1155 token IDs with at most one unit per ID and exposes `ownerOf(uint256)` for direct owner lookup. Standardizing that profile makes the pattern discoverable and reusable by delegate.xyz-style delegation tooling, marketplaces, indexers, Adapter8004, and agent-binding standards such as ERC-8217 that need to resolve a single controlling account for a token ID.

This ERC generalizes the Stagnant [ERC-5409](./eip-5409.md) proposal for ERC-1155 by retaining the same `ownerOf(uint256)` selector and ERC-165 interface identifier while adding ERC-6909 support and specifying the relationship between `ownerOf`, supply, balances, and per-ID opt-in behavior.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
/// @title Non-fungible multi-token owner lookup
/// @dev The ERC-165 interface identifier is 0x6352211e.
interface IERC_NFMultiTokenOwnerOf {
    /// @notice Returns the owner of a non-fungible multi-token id.
    /// @dev Returns address(0) if the covered id has no current owner.
    /// @param id The token id to query.
    /// @return owner The current owner of id, or address(0) if unowned.
    function ownerOf(uint256 id) external view returns (address owner);
}
```

The ERC-165 interface identifier for `IERC_NFMultiTokenOwnerOf` is `0x6352211e`, calculated as `bytes4(keccak256("ownerOf(uint256)"))`. This is the same function selector used by ERC-721 `ownerOf(uint256)`.

An ERC-1155 or ERC-6909 contract that implements this ERC:

- MUST implement ERC-165 and return `true` for interface identifier `0x6352211e`.
- MUST implement either ERC-1155 or ERC-6909.
- MAY cover all token IDs or only a subset of token IDs.
- MUST ensure every covered token ID has total supply less than or equal to one at all times.
- MUST NOT allow a covered token ID to be owned by more than one address at the same time.
- MUST return the current owner from `ownerOf(id)` when `id` is covered, minted, and has supply one. The returned owner MUST hold a balance of exactly one for that id: whenever `ownerOf(id) != address(0)`, `balanceOf(ownerOf(id), id)` MUST equal `1`.
- MUST return `address(0)` from `ownerOf(id)` when `id` is covered and currently has supply zero, including before minting and after burning.
- MUST ensure that `ownerOf(id) == owner` if and only if `balanceOf(owner, id) == 1` for a covered token ID with supply one.
- MUST ensure that `balanceOf(account, id)` is either `0` or `1` for every account and every covered token ID.
- MUST emit the transfer events required by the underlying ERC-1155 or ERC-6909 standard when minting, transferring, or burning a covered token ID.

If an implementation exposes a total supply function for a covered token ID, such as [ERC-5615](./eip-5615.md) `totalSupply(uint256)`, the returned supply for that covered ID MUST be either `0` or `1`.

### Covered IDs

A covered ID is a token ID to which this ERC's non-fungible profile applies. A contract opts into this ERC by supporting `0x6352211e` through ERC-165. Individual IDs opt into the non-fungible profile according to the implementation's token design, such as a fixed ID range, a registry bit, immutable mint configuration, or another deterministic classification.

Implementations SHOULD document how covered IDs are identified. Implementations MAY treat an unknown or non-covered ID as unowned and return `address(0)` from `ownerOf(id)`. Implementations SHOULD NOT revert solely because an ID is covered but currently unminted or burned.

Consumers MUST NOT infer that every ID in a contract is covered only because the contract supports this interface. Consumers that need a positive per-ID classification SHOULD use application-specific metadata, contract documentation, known ID ranges, or another project-specific source of truth in addition to `ownerOf(id)`.

## Rationale

The interface is deliberately one function. ERC-721 `ownerOf(uint256)` is already the common single-owner read used by NFT tooling, so reusing the same selector avoids another adapter shape for multi-token standards. It also lets contracts such as ENS NameWrapper keep their existing owner lookup while making the behavior discoverable through ERC-165.

Returning `address(0)` for unminted or burned covered IDs follows ERC-5409 and avoids requiring callers to use revert handling to distinguish absent ownership. This differs from ERC-721, where `ownerOf` reverts for invalid token IDs, but it is better aligned with multi-token balance queries where absence is represented by a zero balance.

This ERC does not add a required `isNonFungible(uint256)` or `exists(uint256)` function. A per-ID classifier would make the interface more expressive, but it would also make existing contracts with only `ownerOf(uint256)` non-compliant. The minimal profile prioritizes compatibility with deployed practice and leaves richer classification to metadata, documented ID schemes, or optional extensions.

[ERC-8122](./eip-8122.md) is adjacent prior art for ERC-6909-based registries with single-owner token IDs and an `ownerOf(uint256)` method. This ERC extracts that ownership accessor into a reusable profile for any ERC-1155 or ERC-6909 contract, including registries that use metadata systems such as [ERC-8048](./eip-8048.md).

ERC-1155 and ERC-6909 are covered in one ERC because the ownership accessor, selector, ERC-165 identifier, balance invariant, and integration use cases are identical. Splitting them would duplicate the same interface and increase the risk that tooling supports one multi-token standard but not the other.

## Backwards Compatibility

This ERC is backward compatible with ERC-1155 and ERC-6909 because it only adds an optional read interface and does not change transfer, approval, balance, metadata, receiver, or event requirements of either base standard.

Existing ERC-1155 contracts that implement the ERC-5409 interface can be compatible with this ERC if their covered IDs satisfy the supply and balance invariants above and the contract supports `0x6352211e` through ERC-165. Existing ERC-721 integrations can reuse the `ownerOf(uint256)` selector, but they MUST NOT assume full ERC-721 compatibility unless the contract also supports ERC-721.

## Security Considerations

Implementations MUST keep `ownerOf(id)` synchronized with the balances and transfer events of the underlying ERC-1155 or ERC-6909 token. A stale owner value can cause delegation, marketplace, escrow, or binding systems to grant authority to the wrong account.

Implementations MUST enforce the supply invariant during minting, transferring, burning, batch transfers, bridging, wrapping, unwrapping, and administrative recovery flows. Any path that can create two units of a covered ID, or assign one unit to two accounts, breaks the non-fungible profile.

Consumers MUST treat `ownerOf(id) == address(0)` as no current owner, not as proof that the ID can never exist. Consumers also MUST NOT treat support for this interface as proof that every ID in the contract is non-fungible.

Contracts that use owner lookup for authorization SHOULD read ownership at the point of use and account for the same reentrancy and ordering concerns that apply to ERC-1155 and ERC-6909 transfers. If ownership is cached by another protocol, that cache SHOULD be updated from canonical transfer events and SHOULD handle burns and remints explicitly.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
