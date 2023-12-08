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
requires: 20, 2771, 4626
---

## Abstract

The following standard adapts [ERC-4626](./eip-4626.md) by removing the extension of [ERC-20](./eip-20.md), and adding a share method in its place that links the Vault to the share.

## Motivation

[ERC-4626](./eip-4626.md) Vaults are specified to extend [ERC-20](./eip-20.md). This limits them to a one-to-one relationship between asset and share.

There are use cases where multiple assets can be deposited to receive the same share. This standard accomplishes that by indirectly linking the share to the Vault.

## Specification

### Definitions:

The existing definitions from [ERC-4626](./eip-4626.md) apply.

- [ERC-20](./eip-20.md) compliant Vault: Vault that implements the [ERC-20](./eip-20.md) specification including the optional metadata extension
- [ERC-20](./eip-20.md) non-compliant Vault: Vault that do not implement the [ERC-20](./eip-20.md) specification

### [ERC-20](./eip-20.md) non-compliant Vaults

ERC-x Vaults MAY implement [ERC-20](./eip-20.md) to represent shares. If they do not, there needs to be a separate share token contract, that is minted on entering the vault and burned on exiting the vault.

### Methods

#### share

The address of the underlying share received on deposit into the Vault.

For [ERC-20](./eip-20.md) compliant Vaults, the `share` method SHOULD return the address of the Vault.

For [ERC-20](./eip-20.md) non-compliant Vaults, the `share` method SHOULD NOT return the address of the Vault.

```yaml
- name: share
  type: function
  stateMutability: view

  inputs: []
  outputs:
    - name: shareTokenAddress
      type: address
```

## Rationale

This standard is intentionally flexible to support both existing [ERC-4626](./eip-4626.md) Vaults easily by the introduction of a single new method, but also flexible to support new use cases by allowing separate share tokens.

## Reference Implementation

N/A

## Backwards Compatibility

Existing [ERC-4626](./eip-4626.md) Vaults can be made compatible with ERC-x by adding a single `share` method that returns the address of the Vault.

## Security Considerations

[ERC-20](./eip-20.md) non-compliant Vaults must take care with supporting a redeem flow where `owner` is not `msg.sender`, since the [ERC-20](./eip-20.md) approval flow does not by itself work if the Vault and share are separate contracts. It can work by setting up the Vault as a Trusted Forwarder of the share token, using [ERC-2771](./eip-2771.md).

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
