---
title: Interest Rate Swaps
description: This interface defines a specification by which two parties enter a financial derivative contract to exchange interest rate cash flows over a specified period
author: Samuel Gwlanold Edoumou (@Edoumou)
discussions-to: https://ethereum-magicians.org/t/interest-rate-swaps/17777
status: Draft
type: Standards Track
category: ERC
created: 2023-12-31
---

## Abstract

This proposal introduces a standardized framework for on-chain interest rate swaps. The proposed standard aims to facilitate the seamless exchange of fixed and floating interest rate cash flows between parties, providing a foundation for decentralized finance (DeFi) applications. 

## Motivation

Interest Rate Swapping (IRS) denotes a derivative contract wherein two parties mutually consent to exchange a series of forthcoming interest payments based on a specified notional amount. This financial instrument serves as a strategic tool for hedging against interest rate fluctuations. The mechanism entails the utilization of a benchmark index to facilitate the exchange between a variable interest rate and a fixed rate. Despite its widespread use, there is currently an absence of a standardized framework that enables the representation of IRS contracts on blockchain platforms.

The formulation of a standardized protocol is imperative to address this gap. This standard would establish a consistent and transparent methodology for depicting IRS contracts within the blockchain environment. By doing so, it would enhance the interoperability, security, and efficiency of interest rate swap transactions on distributed ledger technology.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

```solidity
pragma solidity ^0.8.0;

/**
* @title ERC-xxxx Interest Rate Swaps
*/
interface IERCxxxx {
    /**
    *  @notice Returns the fixed rate payer. The party who aggreed to pay fixed interest
    */
    function fixedRatePayer() external view returns(address);

    /**
    *  @notice Returns the floating rate payer. The party who aggreed to pay floating interest
    */
    function floatingRatePayer() external view returns(address);

    /**
    *  @notice Returns the fixed interest rate. It is RECOMMENDED to express the interest rate in basis point unit
    *          1 basis point = 0.01% = 0.0001
    *          ex: if interest rate = 5%, then coupon() => 500 basis points
    */
    function fixedRate() external view returns(uint256);

    /**
    *  @notice Returns the floating rate spread. It is RECOMMENDED to express the spread in basis point unit
    *          1 basis point = 0.01% = 0.0001
    *          ex: if interest rate = 5%, then coupon() => 500 basis points
    */
    function floatingRateSpread() external view returns(uint256);

    /**
    *  @notice Returns the notional amount. This amount serves as the basis for calculating the interest payments, and may not be exchanged
    */
    function notionalAmount() external view returns(uint256);

    /**
    *  @notice Returns the currency contract address of the national
    */
    function notionalCurrency() external view returns(address);

    /**
    *  @notice Returns the interest payment frequency
    */
    function frequency() external view returns(uint256);

    /**
    *  @notice Returns the starting date of the contract
    */
    function startingDate() external view returns(uint256);

    /**
    *  @notice Returns the maturity date of the swap contract
    */
    function maturityDate() external view returns(uint256);

    /**
    *  @notice Returns the benchmark rate used for the floating rate
    *          Ex: 0: EURIBOR, 1: SOFR, 2: SONIA, 3: TONA, etc.
    */
    function benchmark() external view returns(uint8);

    /**
    *  @notice Returns true if an account is allowed to make payment of interest difference 
    */
    function isAllowedToMakePayment(address _account) external view returns(bool);

    /**
    *  @notice Allows an account to make payment of interest difference 
    */
    function allowToMakePayment(address _account) external returns(bool);

    /**
    *  @notice Pays the difference between the floating and fixed interests 
    */
    function pay() external returns(bool);
}
```

## Rationale

TBD

## Backwards Compatibility

TBD

## Test Cases

TBD

## Reference Implementation

TBD

## Security Considerations

TBD

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
