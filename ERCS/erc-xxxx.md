---
eip: XXXX
title: Token Transfer Pause Signal
description: Lets NFT contracts signal that holder transfers are paused, temporarily or permanently, for all or a range of token IDs
author: Ryan Ghods (@ryanio)
discussions-to: https://ethereum-magicians.org/t/erc-draft-token-transfer-pause-signal/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2026-10-19
requires: 165, 721, 1155
---

## Abstract

This proposal defines a minimal interface for [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md) contracts to report that transfers between holders are paused, either for every token in the contract or for a range of token IDs, while minting and burning may continue. A pause can be temporary or permanent, so the same interface covers both a trading pause during a mint and a non-transferable (soulbound) collection. It adds two view functions, one event that covers a token ID range in a single log, and one custom error. Marketplaces, wallets, and indexers can use it to stop offering listings, offers, and sales that the contract would reject.

## Motivation

Creators often disable secondary transfers for a period: while a public mint is running, before a reveal, during a migration, or permanently for non-transferable credentials. Today a marketplace learns this only when a fulfillment reverts, or when the creator contacts each marketplace to flag the collection by hand. Users create listings and offers that cannot fill, and buyers pay gas for failed transactions.

[ERC-5192](./eip-5192.md) signals a permanent lock per token. It has no way to cover a whole collection in one event, so a 10,000 token collection needs 10,000 logs to lock, and again to unlock. Its semantics are also those of soulbound tokens, not of a temporary pause. [ERC-6454](./eip-6454.md) exposes a transferability view, but has no event, so indexers have to poll every token to notice a change.

A pause that covers the whole contract and lifts later is the common case in practice. This proposal makes that case one event in each direction, and leaves per-token and per-range pauses possible with the same event. A collection that is non-transferable for good uses the same event once, marked permanent, so consumers can tell it apart from a pause that will lift.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

- A *holder transfer* is a transfer of a token where both the sender (`from`) and the recipient (`to`) are not the zero address. Mints (`from` is the zero address) and burns (`to` is the zero address) are not holder transfers.
- A token is *paused* when `transfersPaused(tokenId)` returns `true`.
- A token is *permanently paused* when `transfersPausedPermanently(tokenId)` returns `true`.

### Interface

A compliant contract MUST implement [ERC-721](./eip-721.md) or [ERC-1155](./eip-1155.md), and MUST implement the following interface:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

/// @dev The ERC-165 identifier for this interface is 0x8035b47e.
interface IERCXXXX /* is IERC165 */ {
    /// @notice Emitted when the paused status of every token ID in the
    ///  inclusive range [fromTokenId, toTokenId] is set to `paused`.
    ///  `permanent` is true when the pause can never be lifted.
    event TransferPauseUpdated(uint256 fromTokenId, uint256 toTokenId, bool paused, bool permanent);

    /// @notice Thrown when a holder transfer of a paused token is attempted.
    error TokenTransferPaused(uint256 tokenId);

    /// @notice Returns true if holder transfers of `tokenId` are paused.
    function transfersPaused(uint256 tokenId) external view returns (bool);

    /// @notice Returns true if holder transfers of `tokenId` are paused and
    ///  the pause can never be lifted.
    function transfersPausedPermanently(uint256 tokenId) external view returns (bool);
}
```

### Behavior

1. The contract MUST return `true` from `supportsInterface(0x8035b47e)`, as defined by [ERC-165](./eip-165.md).
2. `transfersPaused` and `transfersPausedPermanently` MUST NOT revert for any `tokenId`, including token IDs that have not been minted.
3. While a token is paused, the contract MUST revert every holder transfer of that token. This includes transfers made by the holder and by any approved operator.
4. While a token is paused, the contract MAY allow that token ID to be minted and burned.
5. A holder transfer that reverts because the token is paused SHOULD revert with `TokenTransferPaused(tokenId)`.
6. Every change to the value returned by `transfersPaused` or `transfersPausedPermanently` for any token ID MUST happen in a transaction that emits `TransferPauseUpdated` with a range containing that token ID and the new values as `paused` and `permanent`. The return values MUST NOT change as a function of block number, timestamp, or any other state that changes without such a transaction.
7. `fromTokenId` MUST be less than or equal to `toTokenId`. The range is inclusive and applies to token IDs that have not yet been minted.
8. To pause or unpause every token in the contract, the contract SHOULD emit `TransferPauseUpdated(0, type(uint256).max, paused, permanent)`.
9. The contract MUST NOT emit `TransferPauseUpdated` with `permanent` set to `true` and `paused` set to `false`.
10. If `transfersPausedPermanently(tokenId)` returns `true`, then `transfersPaused(tokenId)` MUST also return `true`, and both MUST keep returning `true` for that token ID for the life of the contract. The contract MUST NOT emit `TransferPauseUpdated` with `permanent` set to `false` for a range that contains a permanently paused token ID.
11. The contract MAY emit `TransferPauseUpdated` for a range whose status did not change.
12. The contract SHOULD NOT revert `approve` or `setApprovalForAll` solely because a token is paused and not permanently paused.

### Consumers

1. When a later `TransferPauseUpdated` log overlaps an earlier one, consumers MUST apply them in log order, so that the latest log decides the status of each token ID in the overlap.
2. Consumers SHOULD NOT create, display, or fulfill listings, offers, or sales of a paused token. Consumers MAY keep existing orders and show them again when the token is unpaused.
3. Consumers SHOULD store ranges as ranges and SHOULD NOT expand a range into per-token records.
4. Consumers MAY call `transfersPaused` and `transfersPausedPermanently` to confirm the current status, for example after processing logs out of order.
5. Consumers MAY present a permanently paused token as non-transferable, and a paused token that is not permanently paused as temporarily unavailable for trading.

## Rationale

### Range event

A single log that covers a range lets a contract pause or unpause a whole collection for the cost of one event, whatever its supply. The `fromTokenId`/`toTokenId` shape follows the `BatchMetadataUpdate` event of [ERC-4906](./eip-4906.md), which indexers already handle. A contract that pauses a single token emits a range where both bounds are that token ID.

The range covers token IDs that do not exist yet. This is the case a mint needs: a creator pauses the full range at deployment, mints proceed while every new token is already paused, and one unpause event opens trading for all of them.

### Status in the event

An earlier draft of this proposal emitted only the range and required consumers to call the view function to learn the new status. For a contract-wide range, a consumer could not learn the status of each token without one call per token. Including `paused` and `permanent` in the event lets a consumer update its state from logs alone. Behavior rule 6 keeps the logs and the view in agreement, and the view stays available as a check.

### Permanent pauses

Non-transferable collections, such as credentials, memberships, and achievement badges, need the same signal as a mint-time pause: marketplaces should stop offering trades. They also need consumers to know the pause will never lift, so that a wallet can label the token as non-transferable instead of "trading paused", and a marketplace can stop holding orders in case trading resumes.

A separate proposal for collection-wide soulbound tokens would give indexers two event shapes for the same question. Folding permanence into this event keeps one log type, and one contract-wide log at deployment covers an entire non-transferable collection. Behavior rule 10 makes permanence one way: a contract can move a token from temporarily paused to permanently paused, but never back. A consumer that has seen `permanent` set for a token ID can rely on it.

A permanent pause still allows burning, so holders of a non-transferable token can dispose of it if the contract supports burns.

### No time-based changes

Some pauses have a known end, such as the close of a public mint. Allowing `transfersPaused` to flip at a timestamp would make the logs stale with no event to notice, which defeats the purpose of the event. Contracts with a scheduled end need one transaction to lift the pause. This proposal also leaves out a field for the expected end time. Pauses often end early or late, and a consumer that trusted a stale end time would offer orders that revert.

### Mints and burns

Pausing secondary trading during a mint is the main use case, so the pause applies only to holder transfers. A contract that also needs to block mints or burns can do so on its own; this proposal does not describe it.

### Approvals

Blocking `approve` and `setApprovalForAll` during a temporary pause would stop holders from preparing listings and would add no protection, since the transfer itself already reverts. Consumers already decide whether to show an order based on the pause status.

### Function and error names

`transfersPaused` is a question about holder transfers only, which is why it is not named `isTransferable` or `locked`. The error is named `TokenTransferPaused` because Solidity does not allow an error and a function to share a name in one contract.

### Relationship to ERC-5192 and ERC-6454

This proposal does not replace either. [ERC-5192](./eip-5192.md) is Final, so a range event cannot be added to it. A contract can implement ERC-5192 alongside this interface. When it does, `transfersPaused(tokenId)` should return `true` for every token where `locked(tokenId)` returns `true`, so that consumers reading either signal agree. A permanently non-transferable collection can emit one contract-wide `TransferPauseUpdated(0, type(uint256).max, true, true)` event at deployment instead of one `Locked` event per token.

## Backwards Compatibility

This proposal adds a new interface and does not change [ERC-721](./eip-721.md) or [ERC-1155](./eip-1155.md) behavior when tokens are not paused. Contracts deployed before this proposal do not implement it, and consumers continue to handle them as they do today.

## Reference Implementation

The following [ERC-721](./eip-721.md) contract pauses holder transfers for the whole collection at deployment. The owner can unpause, pause again, or make the pause permanent, after which it can no longer be changed. It uses the `_update` hook of OpenZeppelin Contracts 5.x, which runs for mints, burns, and transfers.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PausableDrop is ERC721, Ownable, IERCXXXX {
    error TransferPauseIsPermanent();

    bool private _transfersPaused;
    bool private _permanent;

    constructor() ERC721("Pausable Drop", "DROP") Ownable(msg.sender) {
        _setTransfersPaused(true);
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _mint(to, tokenId);
    }

    function setTransfersPaused(bool paused) external onlyOwner {
        _setTransfersPaused(paused);
    }

    function pauseTransfersPermanently() external onlyOwner {
        _transfersPaused = true;
        _permanent = true;
        emit TransferPauseUpdated(0, type(uint256).max, true, true);
    }

    function transfersPaused(uint256 /* tokenId */) public view returns (bool) {
        return _transfersPaused;
    }

    function transfersPausedPermanently(uint256 /* tokenId */) public view returns (bool) {
        return _permanent;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERCXXXX).interfaceId || super.supportsInterface(interfaceId);
    }

    function _setTransfersPaused(bool paused) internal {
        if (_permanent) revert TransferPauseIsPermanent();
        _transfersPaused = paused;
        emit TransferPauseUpdated(0, type(uint256).max, paused, false);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0) && transfersPaused(tokenId)) {
            revert TokenTransferPaused(tokenId);
        }
        return super._update(to, tokenId, auth);
    }
}
```

An [ERC-1155](./eip-1155.md) contract applies the same check to each ID in `_update(from, to, ids, values)`.

## Security Considerations

The pause status is reported by the token contract itself. A contract can report `false` and still revert transfers, or report `true` and allow them. Consumers should treat the signal as a way to hide orders that will fail, and should keep simulating fulfillments rather than trusting the signal to approve them.

Whoever controls the pause controls the secondary market for the affected tokens. A creator can make a pause permanent at any time, which removes the secondary market for good. A creator can also pause transfers indefinitely without marking the pause permanent, or pause just before a sale to make outstanding orders unfillable. Holders and buyers should be able to see who can change the pause and whether it can be lifted. Consumers may want to show that information alongside the token.

The pause status can change between the time an order is created and the time it is filled. A buyer's transaction can revert if the creator pauses in the same block. Consumers should check the status close to fulfillment.

A malicious or careless contract can emit many overlapping ranges, or ranges that cover token IDs it will never mint. Consumers that store ranges as ranges, and merge or cap them per contract, avoid unbounded storage growth. Consumers calling `transfersPaused` should bound the gas they pass to the call, since the function runs arbitrary contract code.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
