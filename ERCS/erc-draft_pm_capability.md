---
eip: 7677
title: Paymaster Web Service Capability
description: A standard for apps to communicate with smart wallets about paymaster web services
author: Lukas Rosario (@lukasrosario), Dror Tirosh (@drortirosh), Wilson Cusack (@wilsoncusack)
discussions-to: https://ethereum-magicians.org/t/add-erc-paymaster-web-service-capability/19530
status: Draft
type: Standards Track
category: ERC
created: 2024-04-03
requires: 4337, 5792
---

## Abstract

With [EIP-5792]('./eip-5792.md'), apps can communicate with wallets about advanced features via capabilities. This proposal defines a capability that allows apps to request that [ERC-4337]('./eip-4337.md') wallets communicate with a specified paymaster web service. To support this, we also define a standardized API for paymaster web services.

## Motivation

App developers want to start sponsoring their users' transactions using paymasters. Paymasters are commonly used via web services. However, there is currently no way for apps to tell wallets to communicate with a specific paymaster web service. Similarly, there is no standard for how wallets should communicate with these services. We need both a way for apps to tell wallets to communicate with a specific paymaster web service and a communication standard for wallets to do so.

## Specification

One new [EIP-5792]('eip-5792.md') wallet capability is defined. We also define a standard interface for paymaster web services as a prerequisite.

### Paymaster Web Service Interface

We define two JSON-RPC methods to be implemented by paymaster web services.

#### `pm_getPaymasterStubData`

Returns stub values to be used in paymaster-related fields of an unsigned user operation for gas estimation. Accepts an unsigned user operation, entrypoint address, chain id, and a context object. Paymaster service providers can define fields that app developers should use in the context object. 

##### `pm_getPaymasterStubData` RPC Specification

```typescript
// [userOp, entryPoint, chainId, context]
type GetPaymasterStubDataParams = [
  // Below is specific to Entrypoint v0.6 but this API can be used with other entrypoint versions too
  {
    sender: `0x${string}`;
    nonce: `0x${string}`;
    initCode: `0x${string}`;
    callData: `0x${string}`;
    callGasLimit: `0x${string}`;
    verificationGasLimit: `0x${string}`;
    preVerificationGas: `0x${string}`;
    maxFeePerGas: `0x${string}`;
    maxPriorityFeePerGas: `0x${string}`;
    paymasterAndData: `0x${string}`;
    signature: `0x${string}`;
  },
  `0x${string}`,
  `0x${string}`,
  Record<string, any>
];

type GetPaymasterStubDataResult = Record<string, `0x${string}`> // Stub paymaster values
```

###### `pm_getPaymasterStubData` Example Parameters

```json
[
  {
    "sender": "0x...",
    "nonce": "0x...",
    "initCode": "0x",
    "callData": "0x...",
    "callGasLimit": "0x...",
    "verificationGasLimit": "0x...",
    "preVerificationGas": "0x...",
    "maxFeePerGas": "0x...",
    "maxPriorityFeePerGas": "0x...",
    "paymasterAndData": "0x...",
    "signature": "0x..."
  },
  "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789",
  "0x2105",
  {
    "policyId": "962b252c-a726-4a37-8d86-333ce0a07299"
  }
]
```

###### `pm_getPaymasterStubData` Example Return Value

Paymaster services MUST detect which entrypoint version the account is using and return the correct fields.

For example, if using entrypoint v0.6:

```json
{
  "paymasterAndData": "0x..."
}
```

If using entrypoint v0.7:

```json
{
  "paymaster": "0x...",
  "paymasterData": "0x..."
}
```

#### `pm_getPaymasterData`

Returns values to be used in paymaster-related fields of a signed user operation. These are not stub values and will be used during user operation submission to a bundler. Similar to `pm_getPaymasterStubData`, accepts an unsigned user operation, entrypoint address, chain id, and a context object.

##### `pm_getPaymasterData` RPC Specification

```typescript
// [userOp, entryPoint, chainId, context]
type GetPaymasterDataParams = [
  // Below is specific to Entrypoint v0.6 but this API can be used with other entrypoint versions too
  {
    sender: `0x${string}`;
    nonce: `0x${string}`;
    initCode: `0x${string}`;
    callData: `0x${string}`;
    callGasLimit: `0x${string}`;
    verificationGasLimit: `0x${string}`;
    preVerificationGas: `0x${string}`;
    maxFeePerGas: `0x${string}`;
    maxPriorityFeePerGas: `0x${string}`;
    paymasterAndData: `0x${string}`;
    signature: `0x${string}`;
  },
  `0x${string}`,
  `0x${string}`,
  Record<string, any>
];

type GetPaymasterDataResult = Record<string, `0x${string}`> // Paymaster values
```

###### `pm_getPaymasterData` Example Parameters

```json
[
  {
    "sender": "0x...",
    "nonce": "0x...",
    "initCode": "0x",
    "callData": "0x...",
    "callGasLimit": "0x...",
    "verificationGasLimit": "0x...",
    "preVerificationGas": "0x...",
    "maxFeePerGas": "0x...",
    "maxPriorityFeePerGas": "0x...",
    "paymasterAndData": "0x...",
    "signature": "0x..."
  },
  "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789",
  "0x2105",
  {
    "policyId": "962b252c-a726-4a37-8d86-333ce0a07299"
  }
]
```

###### `pm_getPaymasterData` Example Return Value

Paymaster services MUST detect which entrypoint version the account is using and return the correct fields.

For example, if using entrypoint v0.6:

```json
{
  "paymasterAndData": "0x..."
}
```

If using entrypoint v0.7:

```json
{
  "paymaster": "0x...",
  "paymasterData": "0x..."
}
```

### `paymasterService` Capability

The `paymasterService` capability is implemented by both apps and wallets.

#### App Implementation

Apps need to give wallets a paymaster service URL they can make the above RPC calls to. They can do this using the `paymasterService` capability as part of an [EIP-5792]('./eip-5792.md') `wallet_sendCalls` call.

##### `wallet_sendCalls` Paymaster Capability Specification

```typescript
type PaymasterCapabilityParams = {
  url: string;
  context: Record<string, any>;
}
```

###### `wallet_sendCalls` Example Parameters

```json
[
  {
    "version": "1.0",
    "chainId": "0x01",
    "from": "0xd46e8dd67c5d32be8058bb8eb970870f07244567",
    "calls": [
      {
        "to": "0xd46e8dd67c5d32be8058bb8eb970870f07244567",
        "value": "0x9184e72a",
        "data": "0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675"
      },
      {
        "to": "0xd46e8dd67c5d32be8058bb8eb970870f07244567",
        "value": "0x182183",
        "data": "0xfbadbaf01"
      }
    ],
    "capabilities": {
      "paymasterService": {
        "url": "https://...",
        "context": {
          "policyId": "962b252c-a726-4a37-8d86-333ce0a07299"
        }
      }
    }
  }
]
```

The wallet will then make the above paymaster RPC calls to the URL specified in the `paymasterService` capability field.

#### Wallet Implementation

To conform to this specification, smart wallets that wish to leverage app-sponsored transactions:
1. MUST indicate to apps that they can communicate with paymaster web services via their response to an [EIP-5792]('./eip-5792.md') `wallet_getCapabilities` call.
2. SHOULD make calls to and use the values returned by the paymaster service specified in the capabilities field of an [EIP-5792]('./eip-5792.md') `wallet_sendCalls` call. An example of an exception is a wallet that allows users to select a paymaster provided by the wallet.

##### `wallet_getCapabilities` Response Specification

```typescript
type PaymasterServiceCapability = {
  supported: boolean;
}
```

###### `wallet_getCapabilities` Example Response

```json
{
  "0x2105": {
    "paymasterService": {
      "supported": true
    },
  },
  "0x14A34": {
    "paymasterService": {
      "supported": true
    }
  }
}
```

Below is a diagram illustrating the full `wallet_sendCalls` flow, including how a wallet might implement the interaction.

![flow](../assets/erc-draft_pm_capability/0.png)

## Rationale

### Gas Estimation

The current loose standard for paymaster services is to implement `pm_sponsorUserOperation`. This method returns values for paymaster-realted user operation fields and updated gas values. The problem with this method is that paymaster service providers have different ways of estimating gas, which results in different estimated gas values. Sometimes these estimates can be incorrect. As a result we believe it’s better to leave gas estimation up to the wallet, as it has more context on its onchain implementation, and then ask paymaster services to sponsor given the estimates defined by the wallet.

## Security Considerations

The URLs paymaster service providers give to app developers commonly have API keys in them. App developers might not want to pass these API keys along to wallets. To remedy this, we recommend that app developers provide a URL to their app's backend, which can then proxy calls to paymaster services. Below is a modified diagram of what this flow might look like.

![flowWithAPI](../assets/erc-draft_pm_capability/0.png)

This flow would allow developers to keep their paymaster service API keys secret. Developers might also want to do additional simulation / validation in their backends to ensure they are sponsoring a transaction they want to sponsor.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).