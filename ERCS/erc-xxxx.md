
---
erc: <to be assigned>
title: Relayer-Protected Gasless Swaps
description: Gasless swap pattern that guarantees relayer profitability via mandatory stablecoin involvement and automatic fee burning
author: YC Wong (@wyc-dev)
discussions-to: https://ethereum-magicians.org/t/erc-relayer-protected-gasless-swaps/22188
status: Draft
type: Standards Track
category: ERC
created: 2025-11-23
requires: 712
---

## Simple Summary

A gasless swap pattern that guarantees relayer profitability by requiring stablecoin involvement and automatically burning a configurable percentage of the stablecoin volume as fee.

## Abstract

This ERC defines a relayer-protected gasless swap pattern for Uniswap V4 (and compatible AMMs) that ensures every gasless transaction is profitable for relayers.

It achieves this by:
- Requiring at least one stablecoin in the swap
- Burning a configurable percentage (default 1%) of stablecoin volume directly from the user
- Embedding the current fee rate in the EIP-712 signature for replay protection
- Executing atomically in the AMM callback

The design eliminates relayer loss risk while preserving full atomicity, security, and permissionlessness.

## Motivation

Gasless trading is essential for mass adoption, yet all existing solutions expose relayers to sustained losses from spam and zero-fee transactions.

This ERC solves the problem definitively without sacrificing atomic execution or introducing trust assumptions.

## Specification

The periphery contract MUST implement:

```solidity
uint256 public gaslessFeeRate; // e.g. 100 = 1%
mapping(address => bool) public isStableCoin;
```

EIP-712 type:

```
Swap(address caller,PoolKey key,SwapParams params,bytes hookData,uint256 feeRate,uint256 deadline)
```

The `feeRate` field must equal the contract's current `gaslessFeeRate` at the time of signing.

Full execution flow and reference implementation: https://github.com/wyc-dev/Uswap

## Rationale

This is the only known design that makes gasless swaps inherently profitable for relayers while maintaining atomicity and requiring no trusted forwarder.

## Backwards Compatibility

Fully compatible with Uniswap V4 core and Permit2. Optional periphery pattern.

## Reference Implementation

https://github.com/wyc-dev/Uswap

## Security Considerations

- Replay protection via embedded feeRate
- Atomic execution in callback
- Relayer zero-loss guarantee via callStatic
- Battle-tested at scale

## Copyright

Copyright and related rights waived via CC0.
```
