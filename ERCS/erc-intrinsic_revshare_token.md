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

### Revenue Sharing Mechanism

We implement a revenue sharing mechanism wherein any token holder can claim a proportional share from the revenue pool. To ensure regular and transparent revenue distribution, we have incorporated the snapshot method, capturing both the token balance and the associated claimable revenue token balance. Periodic invocation of the snapshot method, corresponding to distinct revenue-sharing processes, is required. During each snapshot, token holders are empowered to claim a proportionate share from the revenue pool, creating a systematic and equitable distribution mechanism for participants.

### `snapshot` interface

We specify a `snapshot` interface to snapshot the token balance and the claimable revenue token balance. This functionality ensures correctness in tracking token holdings, facilitating a transparent record of each token portfolio. Regular invocation of the snapshot function is essential to maintain up-to-date records. The `snapshot` interface returns a unique `snapshotId`, allowing access to the corresponding token balance and claimable revenue token balance associated with that specific snapshot. This systematic approach enhances the correctness and reliability of historical data retrieval, providing users with comprehensive insights into their token and revenue token balances at different points in time.

### `claimableRevenue` interface

We specify a `claimableRevenue` interface to calculate the amount of ETH claimable by a token holder at a certain snapshot. We will share the revenue between two consecutive snapshots. Specifically, assuming that the revenue between two snapshots is `R`, we will specify a revenue sharing ratio `p`, ranging from 0%-100%, and we will share the revenue of `pR` to different token holders according to the token ratio. Specifically,  the amount of ETH claimable by a token holder with `amount` tokens at a certain snapshot is `pR * amount / totalAmount` , where `totalAmount`  denotes the total amount of ERCXXXX token. Noted that the remaining revenue of `(1-p)R` will be retained in the revenue pool, and we can take out this part of revenue through burning.

### `claim` interface

We specify a `claim` interface for token holder to claim ETH based on the token balance at certain snapshot. Each token holder can only claim revenue at a certain snapshot once, ensuring a fair and transparent distribution mechanism.

### Burning Mechanism

We implement a burning mechanism wherein any token holder can burn their tokens to redeem a proportional share from the revenue pool. This mechanism serves as a guarantee, ensuring that the value of the token is consistently greater than or equal to the share of the revenue pool, promoting a fair and balanced system.

### `redeemableOnBurn` interface

We specify `**redeemableOnBurn`** interface to calculate the amount of ETH redeemable by a token holder upon burn. It is defined as a view function to reduce gas cost. Specifically, the amount of ETH redeemable, i.e., `redeemableETH` by a token holder with `amount` of token to burn is

```jsx
redeemableETH = amount / totalSupply * totalRedeemableETH
```

where `totalSupply` denotes the total supply of ERCXXXX token, and `totalRedeemableETH` denotes the total amount of ETH in the burning pool.

### `burn`  interface:

We specify `burn` interface for token holder to burn tokens and redeem the corresponding amount of revenue token. A token holder can burn at most all tokens it holds. This burning process leads to a reduction in the total token supply, establishing a deflationary economic model. Furthermore, it is important to note that tokens once burned are excluded from participating in any subsequent revenue sharing.

## Backwards Compatibility

This standard is backward compatible with the [ERC-20](./eip-20.md) as it extends the existing functionality with new interfaces.

## Test Cases

The reference implementation includes sample implementations of the interfaces in this standard under `contracts/` and corresponding unit tests under `test/`.

## Reference Implementation

* [ERC-XXXX](../assets/eip-XXXX/contracts/ERCXXXX.sol)

## Security Considerations

### Deflationary Economic Model

The introduction of the burning mechanism in this standard signifies a shift towards a deflationary economic model, which introduces unique considerations regarding security. One prominent concern involves the potential impact on token liquidity and market dynamics. The continuous reduction in token supply through burning has the potential to affect liquidity levels, potentially leading to increased volatility and susceptibility to price manipulation. It is essential to conduct thorough stress testing and market simulations to assess the resilience of the system under various scenarios.

### Spam Revenue Tokens

The extension of AltRevToken with the ability to set up different revenue tokens introduces specific security considerations, primarily centered around the prevention of adding numerous, potentially worthless tokens. The addition of too many spam (worthless) tokens may lead to an increase in gas fees associated with burning and claiming processes. This can result in inefficiencies and higher transaction costs for users, potentially discouraging participation in revenue-sharing activities. 

A robust governance model is crucial for the approval and addition of new revenue tokens. Implementing a transparent and community-driven decision-making process ensures that only reputable and valuable tokens are introduced, preventing the inclusion of tokens with little to no utility. This governance process should involve community voting, security audits, and careful consideration of the potential impact on gas fees.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
