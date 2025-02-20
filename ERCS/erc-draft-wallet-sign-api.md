---
eip: XXXX
title: Wallet Signing API
description: Adds a JSON-RPC method for requesting a signature from a wallet
author: Lukas Rosario (@lukasrosario), Jake Moxey (@jxom), Cody Crozier (@wcrozier12), Conner Swenberg (@ilikesymmetry)
discussions-to: https://ethereum-magicians.org/t/new-erc-wallet-signing-api/22718
status: Draft
type: Standards Track
category: Interface
created: 2024-01-29
requires: 191, 712, 5792
---

## Abstract

Defines a new JSON-RPC method which enables apps to ask a wallet to sign [EIP-191](./eip-191.md) messages.

Applications can use this JSON-RPC method to request a signature over any version of `signed_data` as defined by [EIP-191](./eip-191.md). The new JSON-RPC method allows for support of future [EIP-191](./eip-191.md) `signed_data` versions.

The new JSON-RPC method also supports [EIP-5792](./eip-5792.md)-style `capabilities`, and support for signing capabilities can be discovered using `wallet_getCapabilities` as defined in [EIP-5792](./eip-5792.md).

## Motivation

Wallets and developer tools currently support multiple JSON-RPC methods for handling offchain signature requests. This proposal simplifies wallet & tooling implementations by consolidating these requests under a single `wallet_sign` JSON-RPC method. This also leaves room for new [EIP-191](./eip-191.md) `signed_data` versions without needing to introduce a new corresponding JSON-RPC method.

Furthermore, this new `wallet_sign` method introduces new functionalities via [EIP-5792](./eip-5792.md)-style `capabilities`.

## Specification

One new JSON-RPC method is introduced.

### `wallet_sign`

Requests a signature over [EIP-191](./eip-191.md) `signed_data` from a wallet.

The top-level `version` parameter is for specifying the version of `wallet_sign` should the top-level interface change.

The `request.type` parameter is for specifying the [EIP-191](./eip-191.md) `signed_data` `version` (e.g. `0x01` for structured data, `0x45` for `personal_sign` messaged). The `request.data` parameter is the corresponding data according to the `signed_data` `version`.

The optional `address` parameter is for requesting a signature from a specified address. If included, the wallet MUST respect it and only respond with a signature from that address.

The capabilities field is how an app can communicate with a wallet about capabilities that a wallet supports.

This proposal defines `request` schemas for the three `signed_data` versions currently in [EIP-191](./eip-191.md) (`0x00`, `0x01`, `0x45`). Any future `signed_data` versions can be supported by `wallet_sign`, and their `request` interfaces SHOULD be defined in their own ERCs.

#### `wallet_sign` RPC Specification

```typescript
type Capability = {
  [key: string]: unknown;
  optional?: boolean;
}

type SignParams = {
  version: string;
  address?: `0x${string}`;
  request: {
    type: `0x${string}`; // 1-byte EIP-191 version
    data: any; // data corresponding to the above version
  };
  capabilities?: Record<string, Capability>;
};

type SignResult = {
  signature: `0x${string}`;
  capabilities?: Record<string, any>;
};
```

##### Request Interfaces

Below are `request` interfaces for the `signed_data` `version`s specified in [EIP-191](./eip-191.md) at time of writing. These include:
* `0x00` - Data with intended validator
* `0x01` - [EIP-712](./eip-712.md) Typed Data
* `0x45` - Personal Sign

Any new `request` interfaces corresponding to new `signed_data` `version`s SHOULD be defined in their own ERCs.

```typescript
type ValidatorRequest = {
  type: '0x00';
  data: {
    validator: `0x${string}`; // Intended validator address
    data: `0x${string}`; // Data to sign
  };
}

type TypedDataRequest = {
  type: '0x01';
  data: {
    ...TypedData // TypedData as defined by EIP-712
  }
}

type PersonalSignRequest = {
  type: '0x45';
  data: {
    message: string; // UTF-8 message string
  }
}
```

##### `wallet_sign` Example Parameters

```json
{
  "version": "1.0",
  "request": {
    "type": "0x45",
    "data": {
      "message": "Hello world"
    }
  }
}
```

##### `wallet_sign` Example Return Value

```json
{
  "signature": "0x00000000000000000000000000000000000000000000000000000000000000000e670ec64341771606e55d6b4ca35a1a6b75ee3d5145a99d05921026d1527331",
}
```

## Rationale

TODO

## Backwards Compatibility

TODO

## Security Considerations

TODO

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).