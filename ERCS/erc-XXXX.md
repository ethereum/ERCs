---
eip: XXXX
title: Quote Oracle Standard
description: Standard API for data feeds providing the relative value of assets in the Ethereum and EVM-compatible blockchains.
author: alcueca (@alcueca), ruvaag (@ruvaag), totomanov (@totomanov), r0ohafza (@r0ohafza)
discussions-to: https://ethereum-magicians.org/t/erc-for-oracle-value-feeds/20351
status: Draft
type: Standards Track
category: ERC
created: 2024-06-20
---

## Abstract

The following standard allows for the implementation of a standard API for data feeds providing the relative value of
assets in the Ethereum and EVM-compatible blockchains.

## Motivation

The information required to value assets is scattered over a number of major and minor sources, each one with their own
integration API and security considerations. Many protocols over the years have implemented oracle adapter layers for
their own use to abstract this complexity away from their core implementations, leading to much duplicated effort.

This specification provides a standard API aimed to serve the majority of use cases. Preference is given to ease of
integration and serving the needs of product teams with less knowledge, requirements and resources.

## Specification

### Definitions

- base asset: The asset that the user needs to know the value for (e.g: USDC as in "I need to know the value of 1e6 USDC
  in ETH terms").
- quote asset: The asset in which the user needs to value the `base` (e.g: ETH as in "I need to know the value of 1e6
  USDC in ETH terms").
- value: An amount of `base` in `quote` terms (e.g. The `value` of 1000e6 USDC in ETH terms is 283,969,794,427,307,000
  ETH, and the `value` of 1000e18 ETH in USDC terms is 3,521,501,299,000 USDC). Note that this is an asset amount, and
  not a decimal factor.

### Methods

#### getQuote

Returns the value of `baseAmount` of `base` in `quote` terms.

MUST round down towards 0.

MUST revert with `OracleUnsupportedPair` if not capable to provide data for the specified `base` and `quote` pair.

MUST revert with `OracleUntrustedData` if not capable to provide data within a degree of confidence publicly specified.

```yaml
- name: getQuote
  type: function
  stateMutability: view

  inputs:
    - name: baseAmount
      type: uint256
    - name: base
      type: address
    - name: quote
      type: address

  outputs:
    - name: quoteAmount
      type: uint256
```

### Special Addresses

Some assets under the scope of this specification don't have an address, such as ETH, BTC and national currencies.

For ETH, ERC-7535 will be applied, using `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` as its address.

For BTC, the address will be `0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB`.

For assets without an address, but with an ISO 4217 code, the code will be used (e.g. `address(840)` for USD).

### Events

There are no events defined in this specification

### Errors

#### OracleUnsupportedPair

```yaml
- name: OracleUnsupportedPair
  type: error

  inputs:
    - name: base
      type: address
    - name: quote
      type: address
```

#### OracleUntrustedData

```yaml
- name: OracleUntrustedData
  type: error

  inputs:
    - name: base
      type: address
    - name: quote
      type: address
```

## Rationale

The use of `getQuote` doesn't require the consumer to be aware of any decimal partitions that might have been defined
for the `base` or `quote` and should be preferred in most data processing cases.

The spec doesn't include a `getPrice` function because it is rarely needed on-chain, and it would be a decimal number of
difficult representation. The popular option for representing prices can be implemented for ERC20 with decimals as
`oracle.quoteOf(base, quote, 10\*\*base.decimals()) and will give the value of a whole unit of base in quote terms.

## Backwards Compatibility

Most existing data feeds related to the relative value of pairs of assets should be representable using this standard.

## Reference Implementation

TBA

## Security Considerations

This specification purposefully provides no methods for data consumers to assess the validity of the data they receive.
It is expected of individual implementations using this specification to decide and publish the quality of the data that
they provide, including the conditions in which they will stop providing it.

Consumers should review these guarantees and use them to decide whether to integrate or not with a data provider.

## Acknowledgements

* [Getting Prices Right](https://hackernoon.com/getting-prices-right)

* [Euler Price Oracles](https://github.com/euler-xyz/euler-price-oracle/blob/73a51ca5a830ed03e4a3ef9e6c699c55a32211b8/docs/whitepaper.md)

## Copyright

Copyright and related rights waived via [CC0](https://eips.ethereum.org/LICENSE).
