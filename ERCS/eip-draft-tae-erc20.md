---
eip: 7674
title: Transient Approval Extension for ERC-20
description: An interface for ERC-20 approvals via EIP-1153 transient storage
author: Xenia Shape (@byshape), Mikhail Melnik (@ZumZoom)
discussions-to: # TODO: update
status: Draft
type: Standards Track
category: ERC
created: 2024-04-02
requires: 20, 1153
---

## Abstract

This specification defines the minimum interface required to transiently approve `ERC-20` tokens for spending within a single transaction.

## Motivation

`EIP-1153` allows to use a cheaper way to transiently store allowances.

## Specification

The key words "MUST", "SHOULD", "MAY" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Compliant contracts MUST implement 1 new function in addition to `ERC-20`:
```solidity
function transientApprove(address spender, uint256 value) public returns (bool success)
```
Call to `transientApprove(spender, value)` allows `spender` to withdraw within the same transaction from `msg.sender` multiple times, up to the `value` amount.

Compliant contracts MUST use the transient storage `EIP-1153` to keep the temporary allowance. For each `owner` and `spender`, the slot MUST be uniquely selected to avoid slot collision. Each slot index SHOULD be derived from the base slot index for transient allowances, `owner` and `spender` addresses. Slot MAY be derived as `keccak256(spender . keccak256(owner . p))` where `.` is concatenation and `p` is `keccak256` from the string uniquely defining transient allowances in the namespace of the implementing contract.

Compliant contracts MUST add a transient allowance check to the `transferFrom` function. The permanent allowance can only be spent after the temporary allowance has been exhausted.

Compliant contracts MUST add a transient allowance to the permanent one when returning the allowed amount to spend in the `allowance` function.

## Rationale

The main goal of this standard is to make it cheaper to approve `ERC-20` tokens for a single transaction with minimal interface extension to allow easier integration of a compliant contract into existing infrastructure. This affects the backward compatibility of the `allowance` and `transferFrom` functions.

## Backwards Compatibility

All functionality of the `ERC-20` standard is backward compatible except for the `allowance` and `transferFrom` functions.

## Reference Implementation

The reference implementation can be found [here](https://github.com/byshape/transient-token/blob/main/contracts/TransientToken.sol).

## Security Considerations

The method of deriving slot identifiers to store temporary allowances must avoid collision with other transient storage slots.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).