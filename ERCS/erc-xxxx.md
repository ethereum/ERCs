---
eip: XXXX
title: Permanent Locks for Lockable Tokens
description: Extends default lockable tokens with permanent locks, multi-token support, and mint and burn rules
author: Ryan Ghods (@ryanio)
discussions-to: https://ethereum-magicians.org/t/erc-draft-permanent-locks-for-lockable-tokens-erc-6982-extension/30030
status: Draft
type: Standards Track
category: ERC
created: 2026-10-19
requires: 165, 721, 1155, 6982
---

## Abstract

This proposal extends [ERC-6982](./eip-6982.md) so that a lock can be marked permanent, so that the same interface applies to [ERC-1155](./eip-1155.md) contracts as well as [ERC-721](./eip-721.md) contracts, and so that minting and burning are defined while tokens are locked. Contracts keep using ERC-6982's `DefaultLocked` and `Locked` events to lock and unlock tokens. This proposal adds two events, two view functions, and one custom error. Marketplaces, wallets, and indexers can then tell a temporary trading pause, such as one during a public mint, from a collection that will never be transferable.

## Motivation

Creators often disable secondary transfers for a period: while a public mint is running, before a reveal, or during a migration. Other collections are non-transferable for good, such as credentials, memberships, and achievement badges. In both cases marketplaces need to stop offering listings, offers, and sales that the contract would reject.

ERC-6982 already gives contracts a way to lock or unlock every token with one `DefaultLocked` event, and to override single tokens with `Locked` events. It leaves three gaps:

1. A consumer cannot tell a lock that will lift from one that never will. A wallet cannot label a token as non-transferable, and a marketplace cannot tell whether to keep orders for when trading resumes.
2. ERC-6982 requires ERC-721, so ERC-1155 contracts have no equivalent signal.
3. ERC-6982 does not say whether minting and burning continue while tokens are locked. Pausing trading during a mint depends on minting continuing.

[ERC-5192](./eip-5192.md) covers permanent locks, but only with one event per token, so a 10,000 token collection needs 10,000 logs at deployment.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

- A *holder transfer* is a transfer of a token where both the sender (`from`) and the recipient (`to`) are not the zero address. Mints (`from` is the zero address) and burns (`to` is the zero address) are not holder transfers.
- A token is *locked* when ERC-6982's `locked(tokenId)` returns `true`.
- A token is *permanently locked* when `permanentlyLocked(tokenId)` returns `true`.
- For an ERC-1155 contract, `tokenId` is the token type ID, and a token ID *exists* once at least one unit of it has been minted.

### Interface

A compliant contract MUST implement ERC-721 or ERC-1155, MUST implement ERC-6982, and MUST implement the following interface:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

/// @dev The ERC-165 identifier for this interface is 0x752cf662.
interface IERCXXXX /* is IERC165, IERC6982 */ {
    /// @notice Emitted when every token in the contract becomes permanently locked.
    event DefaultPermanentlyLocked();

    /// @notice Emitted when `tokenId` becomes permanently locked.
    event PermanentlyLocked(uint256 indexed tokenId);

    /// @notice Thrown when a holder transfer of a locked token is attempted.
    error TokenLocked(uint256 tokenId);

    /// @notice Returns true if every token in the contract is permanently locked.
    function defaultPermanentlyLocked() external view returns (bool);

    /// @notice Returns true if `tokenId` is permanently locked.
    function permanentlyLocked(uint256 tokenId) external view returns (bool);
}
```

### Behavior

1. The contract MUST return `true` from `supportsInterface` for both `0x752cf662` and the ERC-6982 identifier `0x6b61a747`, as defined by [ERC-165](./eip-165.md).
2. The requirements of ERC-6982 apply to ERC-1155 contracts that implement this proposal, with `tokenId` read as the token type ID.
3. Locking restricts holder transfers only. A locked status MUST NOT by itself prevent minting. The contract MAY allow burning locked tokens.
4. While a token is permanently locked, the contract MUST revert every holder transfer of that token, including transfers made by the holder and by any approved operator.
5. A holder transfer that reverts because the token is locked SHOULD revert with `TokenLocked(tokenId)`.
6. When the contract emits `DefaultPermanentlyLocked`, `defaultLocked()` MUST already return `true`.
7. After the contract emits `DefaultPermanentlyLocked`:
   1. `defaultLocked()` and `defaultPermanentlyLocked()` MUST return `true` for the life of the contract.
   2. `locked(tokenId)` and `permanentlyLocked(tokenId)` MUST return `true` for every token ID that exists, regardless of any earlier `Locked` event.
   3. The contract MUST NOT emit `DefaultLocked(false)` or `Locked(tokenId, false)` for any token ID.
8. When the contract emits `PermanentlyLocked(tokenId)`, `locked(tokenId)` MUST already return `true`.
9. After the contract emits `PermanentlyLocked(tokenId)`, `locked(tokenId)` and `permanentlyLocked(tokenId)` MUST return `true` for as long as the token exists, and the contract MUST NOT emit `Locked(tokenId, false)`.
10. `permanentlyLocked(tokenId)` MUST return `true` if and only if `DefaultPermanentlyLocked` or `PermanentlyLocked(tokenId)` has been emitted. Like ERC-6982's `locked`, it MUST revert if the token does not exist.
11. The return values of `defaultPermanentlyLocked` and `permanentlyLocked` MUST NOT change except in a transaction that emits the corresponding event.
12. The contract SHOULD NOT revert `approve` or `setApprovalForAll` solely because a token is locked and not permanently locked.

### Consumers

1. Consumers SHOULD NOT create, display, or fulfill listings, offers, or sales of a locked token.
2. Consumers MAY keep existing orders for a token that is locked and not permanently locked, and show them again when the token is unlocked.
3. Consumers MAY present a permanently locked token as non-transferable, and a token that is locked and not permanently locked as temporarily unavailable for trading.
4. After a contract emits `DefaultPermanentlyLocked`, consumers SHOULD treat every token in the contract as permanently locked, including tokens minted later.

## Rationale

### Building on ERC-6982

An earlier draft of this proposal defined its own range event for pausing a whole collection. [ERC-6982](./eip-6982.md) already covers that case with `DefaultLocked`, and per-token exceptions with `Locked`. Reusing it means existing ERC-6982 contracts keep working, and indexers learn one base standard. This proposal adds only what ERC-6982 leaves open. A range event is not included: the default status covers a whole collection, `Locked` covers single tokens, and nothing in the motivating cases needs a partial range.

### Separate permanence events

ERC-6982 is Final, so its events cannot gain a field. Separate `DefaultPermanentlyLocked` and `PermanentlyLocked` events let a contract mark permanence without changing how ERC-6982 consumers read lock status. Behavior rules 6 and 8 require the lock to be in place before it is marked permanent, so a consumer that only understands ERC-6982 still sees the token as locked.

Permanence goes one way. A contract can move a token from locked to permanently locked, but never back. A consumer that has seen a permanence event can rely on it without polling.

### Strict reverts only for permanent locks

ERC-6982 notes that a locked token may still be transferable under some conditions, for example when a designated protector wallet starts the transfer. This proposal keeps that flexibility for temporary locks, since marketplaces only need to know not to offer the token. A permanent lock is a promise to holders that the token is non-transferable, so behavior rule 4 makes that promise binding on the contract.

### Mints and burns

Pausing secondary trading during a mint is the main temporary use case, so locking restricts holder transfers only. A permanently locked collection still allows burning, so holders of a non-transferable token can dispose of it if the contract supports burns.

### ERC-1155

ERC-6982's interface uses only a `tokenId`, which maps directly to an ERC-1155 token type ID. Applying the same events and functions to ERC-1155 gives multi-token contracts a lock signal without a parallel standard. Existence for ERC-1155 is defined by minting because ERC-6982 requires `locked` to revert for tokens that do not exist.

### No time-based changes

ERC-6982 requires `defaultLocked` to reflect the most recent `DefaultLocked` event, so lock status already changes only through events. Behavior rule 11 applies the same rule to permanence. Some pauses have a known end, such as the close of a public mint, but this proposal leaves out an end time field. Pauses often end early or late, and a consumer that trusted a stale end time would offer orders that revert.

### Approvals

Blocking `approve` and `setApprovalForAll` during a temporary lock would stop holders from preparing listings and would add no protection, since the transfer itself already reverts or is not offered.

### Relationship to ERC-5192

ERC-5192 and ERC-6982 share the `locked(uint256)` function, so a contract can implement both. A permanently locked token under this proposal is what ERC-5192 calls a soulbound token. A permanently non-transferable collection can emit `DefaultLocked(true)` and `DefaultPermanentlyLocked()` once at deployment instead of one ERC-5192 `Locked` event per token.

## Backwards Compatibility

Every contract that implements this proposal is also a valid ERC-6982 contract. Consumers that only understand ERC-6982 see permanently locked tokens as locked, which is the safe reading. Contracts deployed before this proposal do not implement it, and consumers continue to handle them as they do today.

## Reference Implementation

The following ERC-721 contract locks every token at deployment. The owner can unlock, lock again, or make the lock permanent, after which it can no longer change. It uses the `_update` hook of OpenZeppelin Contracts 5.x, which runs for mints, burns, and transfers. The `IERC6982` interface is copied from ERC-6982.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IERC6982 {
    event DefaultLocked(bool locked);
    event Locked(uint256 indexed tokenId, bool locked);
    function defaultLocked() external view returns (bool);
    function locked(uint256 tokenId) external view returns (bool);
}

contract LockableDrop is ERC721, Ownable, IERC6982, IERCXXXX {
    error LockIsPermanent();

    bool private _defaultLocked;
    bool private _defaultPermanentlyLocked;

    constructor() ERC721("Lockable Drop", "DROP") Ownable(msg.sender) {
        _setDefaultLocked(true);
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _mint(to, tokenId);
    }

    function setDefaultLocked(bool isLocked) external onlyOwner {
        _setDefaultLocked(isLocked);
    }

    function lockPermanently() external onlyOwner {
        if (!_defaultLocked) _setDefaultLocked(true);
        _defaultPermanentlyLocked = true;
        emit DefaultPermanentlyLocked();
    }

    function defaultLocked() external view returns (bool) {
        return _defaultLocked;
    }

    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return _defaultLocked;
    }

    function defaultPermanentlyLocked() external view returns (bool) {
        return _defaultPermanentlyLocked;
    }

    function permanentlyLocked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return _defaultPermanentlyLocked;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC6982).interfaceId
            || interfaceId == type(IERCXXXX).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _setDefaultLocked(bool isLocked) internal {
        if (_defaultPermanentlyLocked) revert LockIsPermanent();
        _defaultLocked = isLocked;
        emit DefaultLocked(isLocked);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0) && _defaultLocked) {
            revert TokenLocked(tokenId);
        }
        return super._update(to, tokenId, auth);
    }
}
```

An ERC-1155 contract applies the same check to each ID in `_update(from, to, ids, values)`.

## Security Considerations

The lock status is reported by the token contract itself. A contract can report a token as unlocked and still revert transfers, or report it as permanently locked and allow them. Consumers should treat the signal as a way to hide orders that will fail, and should keep simulating fulfillments rather than trusting the signal to approve them.

Whoever controls the lock controls the secondary market for the affected tokens. A creator can make a lock permanent at any time, which removes the secondary market for good. A creator can also keep a temporary lock in place indefinitely, or lock just before a sale to make outstanding orders unfillable. Holders and buyers should be able to see who can change the lock and whether it can still be lifted. Consumers may want to show that information alongside the token.

The lock status can change between the time an order is created and the time it is filled. A buyer's transaction can revert if the creator locks in the same block. Consumers should check the status close to fulfillment.

Consumers calling `locked` or `permanentlyLocked` should bound the gas they pass to the call, since the functions run arbitrary contract code, and should handle the revert these functions raise for tokens that do not exist.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
