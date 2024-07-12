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

The primary motivation for this standard is to enhance the flexibility, security, and efficiency of operator management. By leveraging EIP-712 signatures, this standard allows users to authorize operators without the need for on-chain transactions, reducing gas costs and improving user experience. This is particularly beneficial whenever frequent operator changes and cross-chain interactions are required.

Additionally, this standard aims to:

1. **Enable Meta-Transactions**: Allow users to delegate the execution of transactions to operators, enabling meta-transactions where the user does not need to hold native tokens to pay for gas fees on each chain.
2. **Improve Security**: Utilize the EIP-712 standard for typed data signing, which provides a more secure and user-friendly way to sign messages compared to raw data signing.
3. **Facilitate Interoperability**: Provide a standardized interface for operator management that can be adopted across various vault protocols, promoting interoperability and reducing integration complexity for developers.
4. **Streamline Cross-Chain Operations**: Simplify the process of managing operators across different chains, making it easier for protocols to maintain consistent operator permissions and interactions in a multi-chain environment.

By addressing these needs, the `Authorize Operator` standard aims to streamline the process of managing operators in decentralized vault protocols, making it easier for users and developers to interact with smart contracts in a secure, cost-effective, and interoperable manner across multiple blockchain networks.

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

### Similarity to ERC-2612

The specification is intentionally designed to closely match ERC-2612. This should simplify new integrations of the standard.

The main difference is using `bytes32` vs `uint256`, which enables unordered nonces. 

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
