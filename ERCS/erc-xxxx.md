---
eip: xxxx
title: Expirable NFTs and SBTs
description: A extended for creating non-fungible tokens (NFTs) and soulbound tokens (SBTs) with expiration, supporting time-limited use cases.
author: sirawt (@MASDXI), ADISAKBOONMARK (@ADISAKBOONMARK), parametprame (@parametprame), Nacharoen (@najaroen)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-expirable-nft-sbt/22406
status: Draft
type: Standards Track
category: ERC
created: 2024-01-04
requires: 165
---

## Abstract

Introduces an extension for [ERC-721](./eip-721.md) Non-Fungible Tokens (NFTs) and Soulbound Tokens (SBTs) that adds an expiration mechanism, allowing tokens to become invalid after a predefined period. This additional layer of functionality ensures that the expiration mechanism does not interfere with existing NFTs or SBTs, preserving transferability for NFTs and compatibility with current DApps such as NFT Marketplace. Expiration can be defined using either block height or timestamp, offering flexibility for various use cases.

## Motivation

Introduces an extension for [ERC-721](./eip-721.md) Non-Fungible Tokens (NFTs) and Soulbound Tokens (SBTs), which facilitates the implementation of an expiration mechanism.

Use cases include:

* Access and Authentication
  * Authentication for Identity and Access Management (IAM)
  * Membership for Membership Management System (MMS)
  * Ticket and Press for Meetings, Incentive Travel, Conventions, and Exhibitions (MICE)
  * Subscription-based access for digital platforms.
* Digital Certifications, Contracts, Copyrights, Documents, Licenses, Policies, etc.
* Loyalty Program voucher or coupon
* Governance and Voting Rights
* Financial Product
  * Bonds, Loans, Hedge, and Options Contract

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-XXXX: Expirable NFTs and SBTs
 * @notice unique/granular expiry
 */

// import "./IERC721.sol";
// import "./IERC5007.sol";

interface IERCXXXX /**is IERC5007, IERC721 */ {
    enum EXPIRY_TYPE {
        BLOCK_BASED, // block.number
        TIME_BASED // block.timestamp
    }
    
    /**
     * @dev Emitted when the expiration date of a token is set or updated.
     * @param tokenId The identifier of the token ERC721 `tokenId`.
     * @param startTime The start time of the token (block number or timestamp based on `expiryType()`).
     * @param endTime The end time of the token (block number or timestamp based on `expiryType()`).
     */
    event TokenExpiryUpdated(
        uint256 indexed tokenId,
        uint256 indexed startTime,
        uint256 indexed endTime,
    );

    /**
     * @dev Returns the type of the expiry.
     * @return EXPIRY_TYPE  Enum value indicating the unit of an expiry.
     */
    function expiryType() external view returns (EXPIRY_TYPE);

    /**
     * @dev Checks whether a specific token is expired.
     * @param Id The identifier representing the `tokenId` (ERC721).
     * @return bool True if the token is expired, false otherwise.
     */
    function isTokenValid(uint256 Id) external view returns (bool);

    // inherit from ERC-5007 return depends on the type `block.timestamp` or `block.number`
    // {ERC-5007} return in uint64 MAY not suitable for `block.number` based.
    function startTime(uint256 tokenId) external view returns (uint256);
    function endTime(uint256 tokenId) external view returns (uint256;
}

```

### Behavior specification

* `balanceOf` that inherited from [ERC-721](./eip-721.md) **MUST** return all tokens even if expired it still exists but unusable due to limitation to tracking expire token on-chain.

* For Non-SBTs `transferFrom`, and `safeTransferFrom` **MUST** allow transferring tokens even if they expired. This ensures that expired tokens remain transferable and tradable, preserving compatibility with existing applications already deployed. However, expired tokens **MUST** be considered invalid and unusable in contracts that check for token validity.

* `expiryType` **MUST** return the type of expiry used by the contract, which can be either `BLOCK` or `TIME`.

* `startTime` and `endTime` of `tokenId` or `tokenType`, can be `block.number` or `block.timestamp` depending on `expiryType`. The `startTime` **MUST** less than `endTime` and **SHOULD** except when both are set to 0. A `startTime` and `endTime` of 0 indicates that the `tokenId` or `tokenType` has no time-limited.

* `isTokenValid` is used for retrieving the status of the given `tokenId` or `tokenType` the function **MUST** return `true` if the token is still valid otherwise `false`.

* `supportInterface` for `IERCXXXX` is `0xAABBCCDD`  for `IERCXXXXEpoch` is `0xAABBCCDD`
* `TokenExpiryUpdated` **MUST** be emitted when the token is minted or when its expiration details (start time or end time) are updated.

### Extension Interface

**Epochs** represent a specific period or block range during which certain tokens are valid borrowing concepts from [ERC-7818](./eip-7818.md), tokens are grouped under an `epoch` and share the same `validityDuration`.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-XXXX: Expirable NFTs and SBTs
 * @notice epoch expiry extension
 */

import "./IERCXXXX.sol";

interface IERCXXXXEpoch is IERCXXXX {
    /**
     * @dev Retrieves the balance of a specific `epoch` owned by an account.
     * @param epoch The `epoch for which the balance is checked.
     * @param account The address of the account.
     * @return uint256 The balance of the specified `epoch`.
     * @notice "MUST" return 0 if the specified `epoch` is expired.
     */
    function balanceOfAtEpoch(uint256 epoch, address account) external view returns (uint256);

    /**
     * @dev Retrieves the current epoch of the contract.
     * @return uint256 The current epoch of the token contract,
     * often used for determining active/expired states.
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @dev Retrieves the duration of a single epoch.
     * @return uint256 The duration of a single epoch.
     * @notice The unit of the epoch length is determined by the `validityPeriodType()` function.
     */
    function epochLength() external view returns (uint256);
    
    /**
     * @dev Returns the type of the epoch.
     * @return EPOCH_TYPE  Enum value indicating the unit of an epoch.
     */
    function epochType() external view returns (EPOCH_TYPE);

    /**
     * @dev Retrieves the validity duration of a specific token.
     * @return uint256 The validity duration of the token in `epoch` unit.
     */
    function validityDuration() external view returns (uint256);
    
    /**
     * @dev Checks whether a specific `epoch` is expired.
     * @param epoch The `epoch` to check.
     * @return bool True if the token is expired, false otherwise.
     * @notice Implementing contracts "MUST" define and document the logic for determining expiration,
     * typically by comparing the latest epoch with the given `epoch` value,
     * based on the `EPOCH_TYPE` measurement (e.g., block count or time duration).
     */
    function isTokenValid(uint256 epoch) external view returns (bool);
}
```

* `balanceOfAtEpoch` **MUST** return the balance of tokens held by an account at the specified `epoch`, even if the `epoch` has expired.

* `currentEpoch` **MUST** return the current `epoch` of the contract.

* `epochLength` **MUST** return duration between `epoch` in blocks or time in seconds.

* `epochType` **MUST** return the type of epoch used by the contract, which can be either `BLOCKS_BASED` or `TIME_BASED`.

* `validityDuration` **MUST** return the validity duration of tokens in terms of `epoch` counts.

* `isEpochExpired` **MUST** return true if the given `epoch` is expired, otherwise `false`.

## Rationale

### First, do no harm

Introducing expirability as an additional layer of functionality ensures it doesn’t interfere with existing use cases or applications. For non-SBT tokens, transferability remains intact, maintaining compatibility with current systems. Expired tokens are simply flagged as unusable during validity checks, treating expiration as an enhancement rather than a fundamental change.

### Expiry Types

Defining expiration by either block height (`block.number`) or block timestamp (`block.timestamp`) offers flexibility for various use cases. Block-based expiration suits applications that rely on network activity and require precise consistency, while time-based expiration is ideal for networks with variable block intervals.

## Backwards Compatibility

This standard is fully compatible with [ERC-721](./eip-721.md), [ERC-5484](./eip-5484.md) and other SBTs.

## Reference Implementation

You can find our reference implementation [here](../assets/eip-XXXX/README.md).

## Security Considerations

No security considerations were found.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).