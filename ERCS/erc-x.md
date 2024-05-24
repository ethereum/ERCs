---
eip: x
title: Simple Permissions Checks
description: Standardized interface for checking either contract-level or calldata-level permissions
author: TODO
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2024-05-24
requires: 165
---

## Abstract

The following standard provides two generic methods for checking whether a given account has permissions on either the contract level or to execute specific calldata.

This can be used for permissions such as token blacklists, minimum token holdings, vaults with allowlists built in, and any other permissions relevant to smart contract execution.

## Motivation

While there has been standards focused on defining permissions for ERC20 token transfers (e.g. ERC-1404), there is no standard that enables any permission for any arbitrary contract and calldata to be retrieved.

## Specification

### Definitions:

- contract-level permissions: an account with permissions is allowed to call any method with any calldata without permission restrictions
- calldata-level permissions: an account might have permissions to some but not all methods and/or some but not all specific inputs to the methods

Contracts MUST implement the calldata-level permission check, optionally ignoring the `calldata` argument in the implementation.

Contracts MAY implement the contract-level permission check.

### Methods

#### `isPermissioned(address)`

Returns `true` if the `user` is permissioned to interact with the contract.

```yaml
- name: isPermissioned
  type: function
  stateMutability: view

  inputs:
    - name: user
      type: address

  outputs:
    - name: status
      type: bool
```

#### `isPermissioned(address,bytes)`

Returns `true` if the `user` is permissioned to submit `calldata` to the contract.

```yaml
- name: isPermissioned
  type: function
  stateMutability: view

  inputs:
    - name: user
      type: address
    - name: calldata
      type: bytes

  outputs:
    - name: status
      type: bool
```

### [ERC-165](./eip-165.md) support

Smart contracts implementing this Vault standard MUST implement the [ERC-165](./eip-165.md) `supportsInterface` function.

Contracts supporting contract-level permissions MUST return the constant value `true` if `0xTODO` is passed through the `interfaceID` argument.

Contracts supporting calldata-level permissions MUST return the constant value `true` if `0xTODO` is passed through the `interfaceID` argument.

## Rationale

### Including calldata-level permissions check

Contract-level permissions apply to many use cases, such as tokens with blacklists. But there are also many use cases where this does not suffice, including but not limited to:
* ERC-4626 Vaults where a user that has their permissions removed can still call exit their position but cannot increase their existing position.
* ERC-20 tokens with a minimum amount to be transferred.
* Contract methods with multiple accounts being passed as arguments, where both need to have permissions.

### Mandated Support for [ERC-165](./eip-165.md)

Implementing support for [ERC-165](./eip-165.md) is mandated because this enables integrations to know whether they need to call the more complex calldata-level permission check, or can call the simpler contract-level permission check.

## Security Considerations

Users should not assume having a permission ensures their calls will be guaranteed to succeed.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
