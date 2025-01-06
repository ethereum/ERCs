---
eip: xxxx
title: Expirable NFT/SBT
description: Represents an extended interface that enables non-fungible tokens (NFTs) and soulbound tokens (SBTs) with expiration functionality, supporting time-limited use cases.
author: sirawt (@MASDXI), ADISAKBOONMARK (@ADISAKBOONMARK), parametprame (@parametprame)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-expirable-nft-sbt/22406
status: Draft
type: Standards Track
category: ERC
created: 2024-01-04
requires: 165
---

## Abstract

Introduces an extension for [ERC-721](./eip-721.md) Non-Fungible Tokens (NFTs) and Soulbound Tokens (SBTs), Through this extension, tokens have a predetermined validity period, after which they become invalid and cannot be used in the smart contract that checks their validity. This functionality is essential for various applications where token expiration is necessary such as access and authentication, contracts, governance, licenses, and policies.

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

**Every contract compliant with this ERC MUST implement the following Token Interface as well as the [ERC-165](./eip-165.md) interface:**

### Interface

```solidity

// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-XXXX: Expirable NFT/SBT
 * @notice unique/granular expiry
 */

// import "./IERC1155.sol";
// import "./IERC721.sol";

import "IERC5007.sol";

interface IERC5007Ext is IERC5007 /** IERC721 or IERC1155 */ {
    enum EXPIRY_TYPE {
        BLOCK_BASED, // block.number
        TIME_BASED // block.timestamp
    }
    
    /**
     * @dev Returns the type of the expiry.
     * @return EXPIRY_TYPE  Enum value indicating the unit of an expiry.
     */
    function expiryType() external view returns (EXPIRY_TYPE);

    /**
     * @dev Checks whether a specific token is expired.
     * @param Id The identifier representing the token type `Id` (ERC1155) or `tokenId` (ERC721).
     * @return bool True if the token is expired, false otherwise.
     */
    function isTokenExpired(uint256 Id) external view returns (bool);

    // inherit from ERC-5007 return depends on the type `block.timestamp` or `block.number`
    // {ERC-5007} return in uint64 MAY not suitable for `block.number` based.
    // function startTime(uint256 tokenId) external view returns (uint64);
    // function endTime(uint256 tokenId) external view returns (uint64);
}

```

### Behavior specification

* `balanceOf` or `balanceOfBatch` that inherited from [ERC-721](./eip-721.md) or [ERC-1155](./eip-1155.md) **MUST** return all tokens even if expired it still exists but unusable due to limitation to tracking expire token on-chain.

* For Non-SBTs `transferFrom`, `safeTransferFrom`, and `safeBatchTransferFrom` **MUST** allow transferring tokens even if they expired. This ensures that expired tokens remain transferable and tradable, preserving compatibility with existing applications already deployed. However, expired tokens **MUST** be considered invalid and unusable in contracts that check for token validity.

* `expiryType` **MUST** return the type of expiry used by the contract, which can be either `BLOCK` or `TIME`.

* `startTime` and `endTime` of `tokenId` or `tokenType`, can be `block.number` or `block.timestamp` depending on `expiryType`. The `startTime` **MUST** less than `endTime` and **SHOULD** except when both are set to 0. A `startTime` and `endTime` of 0 indicates that the `tokenId` or `tokenType` has no time-limited.

* `isTokenValid` is used for retrieving the status of the given `tokenId` or `tokenType` the function **MUST** return `true` if the token is still valid otherwise `false`.

* `supportInterface` for `IERC5007Ext` is `<0x00000000> // TODO`  for `IERC5007ExtEpoch` is `0x11111111 // TODO`

### Extension

**Epochs** represent a specific period or block range during which certain tokens are valid borrowing concepts from [ERC-7818](./eip-7818.md), tokens are grouped under an `epoch` and share the same `validityDuration`.

```solidity

// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-XXXX: Expirable ERC1155 or ERC721
 * @notice epoch expiry
 */

// import "./IERC1155.sol";
// import "./IERC721.sol";

import "./IERC5007Ext.sol";

interface IERC5007ExtEpoch is IERC5007Ext {
    /**
     * @dev Retrieves the balance of a specific `epoch` owned by an account.
     * @param epoch The `epoch for which the balance is checked.
     * @param Id  The identifier representing the token type `Id` (ERC1155) or `tokenId` (ERC721).
     * @param account The address of the account.
     * @return uint256 The balance of the specified `epoch`.
     * @notice "MUST" return 0 if the specified `epoch` is expired.
     */
    function balanceOfAtEpoch(
        uint256 epoch,
        uint256 Id,
        address account
    ) external view returns (uint256);

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
     * @param Id The identifier representing the token type `Id` (ERC1155) or `tokenId` (ERC721).
     * @return uint256 The validity duration of the token in `epoch` unit.
     */
    function validityDuration(uint256 Id) external view returns (uint256);
    
     /**
     * @dev Checks whether a specific `epoch` is expired.
     * @param epoch The `epoch` to check.
     * @return bool True if the token is expired, false otherwise.
     * @notice Implementing contracts "MUST" define and document the logic for determining expiration,
     * typically by comparing the latest epoch with the given `epoch` value,
     * based on the `EPOCH_TYPE` measurement (e.g., block count or time duration).
     */
    function isEpochExpired(uint256 epoch) external view returns (bool);

    // inherit from ERC-5007 return but return it in `epoch`
    // and `epoch` depends on the  type `block.timestamp` or `block.number`
    // {ERC-5007} return in uint64 MAY not suitable for `epoch` due to `epoch` is abstract 
    // it's can be short or long depend on implementation.
    // function startTime(uint256 tokenId) external view returns (uint64);
    // function endTime(uint256 tokenId) external view returns (uint64);
}
```

* `balanceOfAtEpoch` **MUST** returns the balance of tokens held by an account at the specified `epoch`, even if the `epoch` has expired.

* `currentEpoch` **MUST** return the current `epoch` of the contract.

* `epochLength` **MUST** return duration between `epoch` in blocks or time in seconds.

* `epochType` **MUST** return the type of epoch used by the contract, which can be either `BLOCKS_BASED` or `TIME_BASED`.

* `validityDuration` **MUST** return the validity duration of tokens in terms of `epoch` counts.

* `isEpochExpired` **MUST** return true if the given `epoch` is expired, otherwise `false`.

## Rationale

### First, do no harm

Introducing **expirability** as a token behavior in a way that doesn’t interfere with existing use cases or applications. For non-SBT tokens, transferability remains intact, ensuring compatibility with current systems, while expired tokens are simply flagged as unusable when validity checks are needed

## Backwards Compatibility

This standard fully [ERC-721](./eip-721.md), [ERC-1155](./eip-1155.md), [ERC-5484](./eip-5484.md) and SBTs compatible.

## Reference Implementation

TODO

## Security Considerations

No security considerations were found.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
