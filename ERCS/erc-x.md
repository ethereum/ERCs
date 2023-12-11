---
eip: TODO
title: Partial and Extended ERC-4626 Vaults
description: Modular ERC-4626 Interface enabling Multi-Vault, Pipes, Partial and Alternative Vaults
author: Jeroen Offerijns (@hieronx), Alina Sinelnikova (@ilinzweilin), Vikram Arun (@vikramarun), Joey Santoro (@joeysantoro), Farhaan Ali (@0xfarhaan)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: TODO
requires: 20, 2771, 4626
---

## Abstract

The following standard adapts [ERC-4626](./eip-4626.md) into several modular components which can be used in isolation or combination to unlock new use cases. 

New functionality includes multiple assets or entry points for the same share token, conversions between arbitrary tokens, and implementations which use a partial or distinct entry/exit flows.

This standard adds nomenclature for the different components of the base ERC-4626 standard, and adds a new `share` method to allow the [ERC-20](./eip-20.md) dependency to be externalized.


## Motivation

[ERC-4626](./eip-4626.md) represents a "complete" and symmetrical standard for a Tokenized Vault pattern. Certain use cases may want to borrow functionality from 4626 to maintain some interface compatibility without wanting the entire standard. 

One major use case are Vaults which have multiple assets or entry points such as LP Tokens. These are generally unwieldy or non-compliant due to the requirement of ERC-4626 to itself be an ERC-20.

Another are Vaults which don't have a true share token but rather convert between two arbitrary external tokens.

Some Vaults always have a 1:1 conversion rate between `assets` and `shares` and would benefit from being able to implement only one entry or exit function from the Vault rather than both.

There are so many customizeable use cases that it is beneficial to modularize the Vault standard.

## Specification

### Definitions:

The existing definitions from [ERC-4626](./eip-4626.md) apply.

- Multi-Vault: A Vault which has multiple assets/entry points
- Pipe: A converter from one token to another (unidirectional or bidirectional)
- Entry Function: A Vault function which converts `asset` to `shares`. Either `deposit` or `mint` in ERC-4626
- Exit Function: A Vault function which converts `shares` to `assets`. Either `withdraw` or `redeem` in ERC-4626
- Alternative Vault: A Vault which implements a different exit/entry flow from ERC-4626
- Partial Vault: A Vault which implements only one Entry or Exit function from ERC-4626

First the standard defines a new `share` function which is useful for many configurable use cases, and then goes into detail on the requirements for different configurations.

### Methods

#### share

The address of the underlying `share` received on deposit into the Vault. MUST return an address of an ERC-20 share representation of the Vault.

`share` MAY return the address of the Vault itself.

If the `share` returns an external token i.e. `share != address(this)`:
* entry functions MUST increase the `share` balance of the `receiver` by the `shares` amount. i.e. `share.balanceOf(receiver) += shares`
* exit functions MUST decrease the `share` balance of the `owner` by the `shares` amount. i.e. `share.balanceOf(owner) -= shares`

MUST _NOT_ revert.

```yaml
- name: share
  type: function
  stateMutability: view

  inputs: []
  outputs:
    - name: shareTokenAddress
      type: address
```

### Multi-Vaults
Multi-vaults share a single `share` token with multiple entry points denominated in different `asset` tokens.

Multi-vaults MUST implement the `share` method on each entry point. The entry points SHOULD NOT be ERC-20.

### Partial Vaults
A Partial Vault implements only one of the entry or exit functions.

A Partial Vault SHOULD implement both the `preview*` and `max*` methods associated with any implemented functions.

Partial Vaults SHOULD prefer implementing `deposit` and `redeem` over `mint` and `withdraw`, respectively.

### Pipes
Pipes convert between a single `asset` and `share` which are both ERC-20 tokens outside the Vault.

A Pipe MAY be either unidirectional or bidirectional.

If the exchange rate is fixed, the Pipe SHOULD be a Partial Vault implementing only `deposit` and/or `redeem`.

A unidirectional Pipe SHOULD implement only the entry function(s) `deposit` and/or `mint`.

### Alternative Vaults
Alternative Vaults do not implement any of the entry or exit functions of ERC-4626, nor their corresponding `preview*` and `max*` functions.

Alternative Vaults MUST implement the following ERC-4626 methods:
- `asset`
- `share`
- `convertToAssets`
- `convertToShares`
- `totalAssets`

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
