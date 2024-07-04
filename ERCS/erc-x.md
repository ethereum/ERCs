---
eip: x
title: Authorize Operator
description: Set Operator via EIP-712 secp256k1 signatures
author: Jeroen Offerijns (@hieronx), João Martins (@0xTimepunk)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2024-06-03
requires: 712, 1271
---

## Simple Summary

A contract interface that enables setting operators via a signed authorization.

## Abstract

A set of functions to enable meta-transactions and atomic interactions with contracts implementing an operator model, via signatures conforming to the [EIP-712](./eip-712.md) typed message signing specification.

## Motivation

TODO

## Specification

### Operator-compatible contracts

This signed authorization scheme applies to any contracts implementing the following interface:

```solidity
  interface IOperator {
    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    function setOperator(address operator, bool approved) external returns (bool);
    function isOperator(address owner, address operator) external returns (bool status);
  }
```

[EIP-6909](./eip-6909.md) and [EIP-7540](./eip-7540.md) already implement this interface.

The naming of the arguments is interchangeable, e.g. [EIP-6909](./eip-6909.md) uses `spender` instead of `operator`.

### Methods

#### `authorizeOperator`

Grants or revokes permissions for `operator` to manage Requests on behalf of the `msg.sender`, using an [EIP-712](./eip-712.md) signature.

MUST revert if the `deadline` has passed.

MUST invalidate the nonce of the signature to prevent message replay.

MUST revert if the `signature` is not a valid [EIP-712](./eip-712.md) signature, with the given input parameters.

MUST set the operator status to the `approved` value.

MUST log the `OperatorSet` event.

MUST return `true`.

```yaml
- name: authorizeOperator
  type: function
  stateMutability: nonpayable

  inputs:
    - name: owner
      type: address
    - name: operator
      type: address
    - name: approved
      type: bool
    - name: deadline
      type: uint256
    - name: nonce
      type: bytes32
    - name: signature
      type: bytes

  outputs:
    - name: success
      type: bool
```

#### `invalidateNonce`

Revokes the given `nonce` for `msg.sender` as the `owner`.

```yaml
- name: invalidateNonce
  type: function
  stateMutability: nonpayable

  inputs:
    - name: nonce
      type: bytes32
```

### [ERC-165](./eip-165.md) support

Smart contracts implementing this standard MUST implement the [ERC-165](./eip-165.md) `supportsInterface` function.

Contracts MUST return the constant value `true` if `0x7a7911eb` is passed through the `interfaceID` argument.

## Rationale

TODO

## Backwards Compatibility

TODO 

## Reference Implementation

```solidity
    // This code snippet is incomplete pseudocode used for example only and is no way intended to be used in production or guaranteed to be secure

    bytes32 public constant AUTHORIZE_OPERATOR_TYPEHASH = keccak256(
        "AuthorizeOperator(address owner,address operator,bool approved,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    mapping(address owner => mapping(bytes32 nonce => bool used)) authorizations;

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
      // ERC-712 implementation 
    }

    function isValidSignature(address signer, bytes32 digest, bytes memory signature) internal view returns (bool valid) {
      // ERC-1271 implementation 
    }

    function authorizeOperator(
        address owner,
        address operator,
        bool approved,
        uint256 deadline,
        bytes32 nonce,
        bytes memory signature
    ) external view returns (bool) {
        require(block.timestamp <= deadline, "authorization-expired");
        require(owner != address(0), "invalid-owner");
        require(!authorizations[owner][nonce], "authorization-used");

        authorizations[owner][nonce] = true;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(AUTHORIZE_OPERATOR_TYPEHASH, owner, operator, approved, deadline, nonce))
            )
        );

        require(isValidSignature(owner, digest, signature), "invalid-authorization");

        isOperator[owner][operator] = approved;
        emit OperatorSet(owner, operator, approved);

        return true;
    }
    
    function invalidateNonce(bytes32 nonce) external {
        authorizations[msg.sender][nonce] = true;
    }
```

## Security Considerations

TODO

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
