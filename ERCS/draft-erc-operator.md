---
title: Operator contract for non delegated EOAs
description: A standard for operating batch executions on behalf of non delegated EOAs
author: Marcelo Morgado (@marcelomorgado), Manoj Patidar (@patidarmanoj10)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2025-07-02
requires: EIP-1153, ERC-2771
---

## Abstract

A singleton contract which allows standard EOAs to perform batch calls to compatible contracts.

## Motivation

The ERC-7702 allows EOAs to became powerful smart contract accounts (SCA) which address many UX issues we've faced so far like the usual double `approve` + `transferFrom` transactions.
This new possibility that will probably reach wider adoption over time, meanwhile, we need a way to improve UX for the EOAs that don't have code attached to them.
The `Operator` approach brings new possibilities for contracts which support it. For instance, it improves usage of pull oracles (where the price data must be update on-chain before the actual call).

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

- Operator: The singleton contract that execute calls on the sender's behalf.
- Operated: The contract that supports calls throught the Operator.

### Operator

```solidity
pragma solidity ^0.8.24;

interface IOperator {
    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @notice Execute calls
    /// @param calls An array of Call structs
    /// @return returnData An array of bytes containing the responses
    function execute(Call[] calldata calls) external payable returns (bytes[] memory returnData);

    /// @notice The address which initiated the executions
    /// @return sender The actual sender of the calls
    function onBehalfOf() external view returns (address sender);
}
```

### Methods

`execute`
Execute the calls sent by the actual sender.

MUST revert if any of the calls fail.
MUST return data from the calls.

`onBehalfOf`
Used by the target contract to get the actual caller.

MUST return the actual `msg.sender` when called in the context of a call.
MUST revert when called outside of the context of a call.

### Operated

The target contract when checking who the sender is, let's assume the sender is the `operator.onBehalfOf()` when `msg.sender == operator`. This behavior fits well with the usage of the `_msgSender()` function from the `ERC-2771`.

## Reference Implementation

### Operator

```solidity
pragma solidity ^0.8.24;

import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IOperator} from "./interfaces/IOperator.sol";

/// @title Operator contract
/// @dev Allows standard EOAs to perform batch calls
contract Operator is IOperator, ReentrancyGuardTransient {
    using TransientSlot for *;
    using Address for address;

    // keccak256(abi.encode(uint256(keccak256("operator.actual.sender")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MSG_SENDER_STORAGE = 0x0de195ebe01a7763c35bcc87968c4e65e5a5ea50f2d7c33bed46c98755a66000;

    modifier setMsgSender() {
        MSG_SENDER_STORAGE.asAddress().tstore(msg.sender);
        _;
        MSG_SENDER_STORAGE.asAddress().tstore(address(0));
    }

    /// @inheritdoc IOperator
    function onBehalfOf() external view returns (address _actualMsgSender) {
        _actualMsgSender = MSG_SENDER_STORAGE.asAddress().tload();
        require(_actualMsgSender != address(0), "outside-call-context");
    }

    /// @inheritdoc IOperator
    function execute(
        Call[] calldata calls_
    ) external payable override nonReentrant setMsgSender returns (bytes[] memory _returnData) {
        uint256 _length = calls_.length;
        _returnData = new bytes[](_length);

        uint256 _sumOfValues;
        Call calldata _call;
        for (uint256 i; i < _length; ) {
            _call = calls_[i];
            uint256 _value = _call.value;
            unchecked {
                _sumOfValues += _value;
            }
            _returnData[i] = _call.target.functionCallWithValue(_call.callData, _value);
            unchecked {
                ++i;
            }
        }

        require(msg.value == _sumOfValues, "value-mismatch");
    }
}
```

Worth noting that the usage of transient storage (EIP-1153) for storing msg.sender is highly RECOMMENDED.

### Operated

```solidity
pragma solidity ^0.8.24;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IOperator} from "../interfaces/IOperator.sol";

abstract contract Operated is Context {
    IOperator public immutable operator;

    constructor(address operator_) {
        operator = IOperator(operator_);
    }

    /// @inheritdoc Context
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(operator)) {
            return operator.onBehalfOf();
        }

        return msg.sender;
    }
}
```

## Limitations

The main limitation of this ERC is that only contracts that implements the `Operated` logic will be able to receive calls thorught the `Operator`. This means that non-upgradeable contracts (like most of the tokens) will never be compatible.
As consequence this ERC will only be able to address `approve`+`transferFrom` UX for tokens that became compatible with the `Operator` contract.

## Security Considerations

- The `execute` function MUST implement reentracy control to avoid having a callback call overriding the `msg.sender` storage.
- The `Operated` contract MUST only add trusted `Operator` contract. That's the reason of having a trusted singleton contract deployed across EVM chains.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
