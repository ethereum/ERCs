---
title: Intrinsic RevShare Token
description: An ERC-20 extension that integrates a revenue-sharing mechanism, ensuring tokens intrinsically represent a share of a communal revenue pool
author: Conway (@0x1cc), Cathie So (@socathie), Xiaohang Yu (@xhyumiracle), Suning Yao (@fewwwww), Kartin <kartin@hyperoracle.io>
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2024-02-28
requires: 20
---

## Abstract

This proposal outlines an extension of the prevailing ERC-20 token standard, introducing a seamlessly integrated revenue-sharing mechanism. It incorporates a suite of interfaces designed to foster fair distribution of revenue among token holders while preserving the essential attributes of ERC-20. Central to this design is the establishment of a communal revenue pool, aggregating revenues from diverse sources. The token, in essence, embodies shares, affording holders the ability to burn their tokens and redeem a proportionate share from the revenue pool. This innovative burning mechanism guarantees that, when the revenue pool is non-empty, the token's value remains at least commensurate with the share of the revenue pool. Additionally, in periodic intervals, token holders can claim a portion of the reward, enriching their engagement and further enhancing the token's utility.

## Motivation

<!--
  This section is optional.

  The motivation section should include a description of any nontrivial problems the EIP solves. It should not describe how the EIP solves those problems, unless it is not immediately obvious. It should not describe why the EIP should be made into a standard, unless it is not immediately obvious.

  With a few exceptions, external links are not allowed. If you feel that a particular resource would demonstrate a compelling case for your EIP, then save it as a printer-friendly PDF, put it in the assets folder, and link to that copy.

  TODO: Remove this comment before submitting
-->

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

**Every compliant contract must implement the `IERCXXXX`, and [ERC-20](./eip-20.md) interfaces.**

The Intrinsic RevShare Token standard includes the following interfaces:

`IERCXXXX`:
- Defines a `claimableRevenue` view function to calculate the amount of ETH claimable by a token holder at a certain snapshot.
- Defines a `claim` function for token holder to claim ETH based on the token balance at certain snapshot.
- Defines a `snapshot` function to snapshot the token balance and the claimable revenue token balance.
- Defines a `redeemableOnBurn` view function to calculate the amount of ETH redeemable by a token holder upon burn.
- Defines a `burn` function for token holder to burn tokens and redeem the corresponding amount of revenue token.

```solidity
pragma solidity ^0.8.24;

/**
 * @dev An interface for ERCXXXX, an ERC-20 extension that integrates a revenue-sharing mechanism, ensuring tokens intrinsically represent a share of a communal revenue pool
 */
interface IERCXXXX is IERC20 {
    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return The amount of revenue token claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) external view returns (uint256);

    /**
     * @dev A function for token holder to claim ETH based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id
     */
    function claim(uint256 snapshotId) external;

    /**
     * @dev A function to snapshot the token balance and the claimable revenue token balance
     * @return The snapshot id
     * @notice Should have `require` to avoid ddos attack
     */
    function snapshot() external returns (uint256);

    /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint256 amount) external view returns (uint256);

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(uint256 amount) external;
}
```

### Optional Extension: AltRevToken

The **AltRevToken extension** is OPTIONAL for this standard. This allows accept other [ERC-20](./eip-20.md) revenue tokens (more than ETH) into the revenue sharing pool.

The AltRevToken extension
- Defines a `claimableERC20` function to calculate the amount of [ERC-20](./eip-20.md) claimable by a token holder at certain snapshot.
- Defines a `redeemableERC20OnBurn` function to calculate the amount of [ERC-20](./eip-20.md) redeemable by a token holder upon burn.

```solidity
pragma solidity ^0.8.24;

/**
 * @dev An optional extension of the ERCXXXX standard that accepts other ERC-20 revenue tokens into the contract with corresponding claim function
 */
interface IERCXXXXAltRevToken is IERCXXXX {
    /**
     * @dev A function to calculate the amount of ERC-20 claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @param token The address of the revenue token
     * @return The amount of revenue token claimable
     */
    function claimableERC20(address account, uint256 snapshotId, address token) external view returns (uint256);

    /**
     * @dev A function to calculate the amount of ERC-20 redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @param token The address of the revenue token
     * @return The amount of revenue token redeemable
     */
    function redeemableERC20OnBurn(uint256 amount, address token) external view returns (uint256);
}
```

## Rationale

<!--
  The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

TBD

## Backwards Compatibility

This standard is backward compatible with the ERC-20 as it extends the existing functionality with new interfaces.

## Test Cases

The reference implementation includes sample implementations of the interfaces in this standard under `contracts/` and corresponding unit tests under `test/`.

## Reference Implementation

* [ERC-XXXX](../assets/eip-XXXX/contracts/ERCXXXX.sol)

## Security Considerations

<!--
  All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life cycle of the proposal. For example, include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
