---
title: Holding-Time Auto Staking for NFTs
description: Accrue staking time on ERC-721 tokens while they are held, without staking transactions or custody transfers.
author: Kiwoong Kim (@helloing0119), Jeff Rhie (@jeff-rhie), Jay B (@DalecB)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-holding-time-auto-staking-for-nfts/29787
status: Draft
type: Standards Track
category: ERC
created: 2024-09-24
requires: 165, 721
---

## Abstract

This proposal defines an extension of [ERC-721](./eip-721.md) in which every token accrues "staking time" simply by being held. Holders do not send a staking transaction, do not move the token into a staking pool, and do not receive a receipt token. Instead, the token contract records a timestamp whenever a token is transferred, and derives each token's accumulated staking time on demand from that timestamp and a contract-wide staking policy (a season with a start time, an end time, and a break period during which a recently transferred token does not accrue time). Other contracts and off-chain services can read the accumulated time through a common interface to grant rewards, unlock content, or change metadata.

## Motivation

Many NFT projects reward long-term holders. The usual pattern requires the holder to call a staking function, transfer the token into a separate staking contract, and later call another function to withdraw it. This costs gas on every step, removes the token from the holder's wallet (breaking wallet-based utilities such as token-gated access and profile pictures), and adds a separate contract with its own custody risk.

What these systems actually measure is how long a token has been held without being traded. That quantity can be derived from data the token contract already touches on each transfer. Recording it in the token contract itself removes the extra transactions and the custody transfer, and a shared interface lets marketplaces, reward contracts, and indexers read staking status from any compliant collection in the same way.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- A **staking season** is a period defined by a season identifier (`stakingId`), a start time (`stakingBegin`), an end time (`stakingEnd`), and a `breaktime` in seconds. At most one season is active in a contract at a time.
- A token's **status change time** (`stakingTimestamp`) is the most recent block timestamp at which the token's staking record was updated.
- A token is **taking a break** when the current season has begun, the token's status change time is not earlier than the season start, and less than `breaktime` seconds have passed since that status change time.

### Interface

Compliant contracts MUST implement [ERC-721](./eip-721.md) and the following interface:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

interface IERC721AutoStaking /* is IERC721 */ {
    /// @notice Returns the accumulated staking time of `tokenId`, in seconds,
    ///         within the current staking season.
    /// @dev MUST revert if `tokenId` does not exist.
    function stakingTotal(uint256 tokenId) external view returns (uint256);

    /// @notice Returns the most recent time at which the staking record of
    ///         `tokenId` was updated, as a Unix timestamp. Returns 0 if the
    ///         record has never been updated.
    /// @dev MUST revert if `tokenId` does not exist.
    function stakingTimestamp(uint256 tokenId) external view returns (uint256);

    /// @notice Returns true if `tokenId` is currently taking a break and
    ///         therefore not accruing staking time.
    /// @dev MUST revert if `tokenId` does not exist.
    function isTakingBreak(uint256 tokenId) external view returns (bool);

    /// @notice Returns the start time of the current staking season, as a Unix
    ///         timestamp. Returns 0 if no season has been configured.
    function stakingBegin() external view returns (uint256);

    /// @notice Returns the end time of the current staking season, as a Unix
    ///         timestamp.
    function stakingEnd() external view returns (uint256);

    /// @notice Returns the identifier of the current staking season.
    function stakingId() external view returns (uint256);

    /// @notice Returns the breaktime of the current staking season, in seconds.
    function stakingBreaktime() external view returns (uint256);
}
```

### Behavior

1. When a token is transferred between two non-zero addresses, the contract MUST first add the staking time the token has accrued since its previous status change to its stored total, and then set its status change time to the current block timestamp.
2. While a season is active, `stakingTotal` MUST increase by one for every second in which the token exists and is not taking a break.
3. `stakingTotal` MUST NOT increase before `stakingBegin` or after `stakingEnd`.
4. When a new season with a different `stakingId` begins, the accumulated total of every token MUST be treated as zero for that season.
5. The staking record MUST follow the token, not the owner: the accrued total is not reset by a transfer, but the new holder does not accrue time until the break period has elapsed.
6. Staking policy parameters MAY be changed by the contract deployer or another authorized party. The mechanism for doing so is not specified by this proposal.
7. The `supportsInterface` function defined in [ERC-165](./eip-165.md) MUST return `true` when called with the interface identifier of `IERC721AutoStaking`.

## Rationale

**Accrual derived from transfers.** Every ERC-721 transfer already writes to storage for the token being moved. Updating a timestamp and a running total in the same write adds little gas to a transfer and requires no extra transaction from the holder. Staking time for tokens that are never transferred is computed lazily in view functions, so holding costs nothing.

**Break period instead of a lock.** Traditional staking locks tokens to prevent a single token from being used to claim rewards across many wallets in quick succession. This proposal keeps tokens freely transferable and instead suspends accrual for `breaktime` seconds after each transfer. Projects choose how strongly to discourage rapid trading by choosing the length of `breaktime`.

**Seasons.** Projects often run staking campaigns in phases. A season identifier lets a contract start a fresh campaign without iterating over every token: tokens whose stored season identifier differs from the current one are treated as having a zero total.

**Record follows the token.** Binding the total to the token rather than the owner keeps the storage layout to one record per token and lets secondary buyers see how long a token has been held. Reward systems that need per-owner accounting can combine `stakingTimestamp` with transfer events.

**Minimal interface.** Batch minting, burning, metadata that changes with staking time, and per-season history are useful in practice but are not required for interoperability, so they are left to implementations and possible future extensions.

## Backwards Compatibility

This proposal is fully compatible with ERC-721. It does not change the signature or observable behavior of any ERC-721 function; it only adds read functions and additional bookkeeping inside transfers. Transfers of compliant tokens cost slightly more gas than transfers of a plain ERC-721 token because of the extra bookkeeping.

## Reference Implementation

An implementation, including optional extensions for staking-dependent metadata, burning, and per-season history, was originally developed in 2022 for the authors' NFT project and deployed on Ethereum mainnet for that collection. It will be added to the assets directory of this proposal once a number is assigned.

## Security Considerations

**Timestamp dependence.** Accrual relies on `block.timestamp`, which block proposers can influence within a small range. The effect on totals measured in days or weeks is negligible, but reward systems SHOULD NOT depend on second-level precision.

**Escrow-based marketplaces and custody services.** Listing a token on a marketplace or service that takes custody of the token is a transfer and therefore starts a new break period. Holders should be informed of this. Approval-based listings do not affect staking status.

**Tokens minted during a season.** Implementations need to define how tokens minted after a season has begun are credited. An implementation that does not record a status change at mint time will credit such tokens from the season start. Implementations SHOULD record a status change at mint if this is not intended.

**Policy changes.** Because the deployer or another authorized party can change the staking policy, holders depend on that party not to alter seasons unfairly. Implementations SHOULD restrict policy changes with access control and SHOULD make changes observable, for example by emitting an event.

**Rewards based on the record following the token.** Because accrued time is attached to the token, a buyer acquires the accrued total of the seller. Reward contracts that pay out based on `stakingTotal` SHOULD account for this, for example by recording claims per token and season.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
