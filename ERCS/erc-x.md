---
eip: TODO
title: Multi-vault support for ERC-4626 
description: Extension of ERC-4626 that enables multiple Vaults to mint a single ERC-20
author: Jeroen Offerijns (@hieronx), Alina Sinelnikova (@ilinzweilin), Vikram Arun (@vikramarun), Joey Santoro (@joeysantoro), Farhaan Ali (@0xfarhaan)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: TODO
requires: 20, 165, 4626
---

## Abstract

The following standard adapts [ERC-4626](./eip-4626.md) by removing the extension of [ERC-20](./eip-20.md), and adding a share method in its place that links the Vault to the share.

## Motivation

[ERC-4626](./eip-4626.md) Vaults are specified to extend [ERC-20](./eip-20.md). This limits them to a one-to-one relationship between asset and share.

There are use cases where multiple assets can be deposited to receive the same share. This standard accomplishes that by indirectly linking the share to the Vault.

## Specification

### Definitions:

The existing definitions from [ERC-4626](./eip-4626.md) apply.

### Deviation from [ERC-4626](./eip-4626.md)

ERC-x Vaults MAY implement [ERC-20](./eip-20.md) to represent shares. If an ERC-x Vault does implement [ERC-20](./eip-20.md), the `share` method SHOULD return the address of the Vault. If an ERC-x Vault does not implement [ERC-20](./eip-20.md), the `share` method SHOULD NOT return the address of the vault.

### Methods

#### share

The address of the underlying share received on deposit into the Vault.

```yaml
- name: share
  type: function
  stateMutability: view

  inputs: []
  outputs:
    - name: shareTokenAddress
      type: address
```

### [ERC-165](./eip-165.md) support

Smart contracts implementing this Vault standard MUST implement the [ERC-165](./eip-165.md) `supportsInterface` function.

Vaults MUST return the constant value `true` if `TODO` is passed through the `interfaceID` argument.

## Rationale

TODO
### Mandated Support for [ERC-165](./eip-165.md)

Implementing support for [ERC-165](./eip-165.md) is mandated because this enables differentiating [ERC-4626](./eip-4626.md) Vaults that use ERC-X from those that do not.

## Backwards Compatibility

TODO

## Reference Implementation

TODO

## Security Considerations

TODO

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
