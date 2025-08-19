---
title: Gas Limit Override Capability
description: A way for apps to communicate call gas limits to wallets
author: Adam Hodges (@ajhodges)
discussions-to: 
status: Draft
type: Standards Track
category: ERC
created: 2025-08-19
requires: 5792
---

## Abstract

With the introduction of ERC-5792, apps can now request calls to be batched by a Wallet, but there is no way for an app to set a gas limit for those calls. Gas estimation for 5792 batches is currently fully delegated to the wallet. This proposal introduces a capability that restores the ability for apps to specify a gas limit for calls in a 5792 batch, analogous to the `gas` parameter of an `eth_sendTransaction` request.

## Motivation

Some calls can have nondeterministic behavior that make it difficult for a wallet to accurately estimate gas limits for them. Apps have the most context around the calls they are making and can provide reasonable gas limits for them.

## Specification

One new [EIP-5792](./eip-5792.md) wallet capability is defined.

### `gasLimitOverride` Capability

The `gasLimitOverride` capability is implemented by both apps and wallets.

### Wallet Implementation

To conform to this specification, wallets that implement the `gasLimitOverride` capability:

1. MUST indicate support for the `gasLimitOverride` capability for _all_ chains (`0x0`) in their [EIP-5792](./eip-5792.md) `wallet_getCapabilities` response.
2. SHOULD return an error (`-32602`) if the `gasLimitOverride` is partially specified in a batch (i.e., if some calls have the capability but others do not).
3. SHOULD factor in the app-provided gas limits when processing the batch of calls.
4. SHOULD factor in any additional gas required for the batch processing itself, such as gas for the batch transaction overhead.

##### `wallet_getCapabilities` Response Specification

```typescript
type GasLimitOverrideCapability = {
  supported: boolean;
}
```

###### `wallet_getCapabilities` Example Response

```json
{
  "0x0": {
    "gasLimitOverride": {
      "supported": true
    }
  }
}
```

#### App Implementation

When an app wants to override the gas limits used for calls in a batch, they SHOULD do this using the `gasLimitOverride` capability as part of an [EIP-5792](./eip-5792.md) `wallet_sendCalls` call.

This is a call-level capability; if the app specifies this capability for one call, it MUST be specified for all calls in the batch.

##### `wallet_sendCalls` Gas Limit Override Capability Specification

```typescript
type GasLimitOverrideParams = {
  value: `0x${string}`; // hex-encoded uint256
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
        "data": "0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
        "capabilities": {
          "gasLimitOverride": {
            "value": "0x1234"
          }
        }
      },
      {
        "to": "0xd46e8dd67c5d32be8058bb8eb970870f07244567",
        "value": "0x182183",
        "data": "0xfbadbaf01",
        "capabilities": {
          "gasLimitOverride": {
            "value": "0x765"
          }
        }
      }
    ]
  }
]
```

The wallet will then account for these provided gas limits when processing the batch of calls.

## Rationale

The complexities with applying app-supplied gas limits are discussed briefly in the [Rationale section of EIP-5792](https://eips.ethereum.org/EIPS/eip-5792#rationale).

To restate the issue, apps have no context around how calls may or may not be batched by wallets that implement EIP-5792, so they cannot account for any batching overhead. Wallets have low context around the nature of app-provided calls, so they cannot always provide an accurate gas limit.

This proposal allows apps to specify call-level gas limits, and delegates the responsibility of estimating batching overhead (via static analysis or tracing) to the wallet.

### Alternative Approaches

#### Top-level Gas Limit Override Capability

This simplifies the interface somewhat by allowing the app to pass a single gas limit value, but there are a few issues with this approach

1. The app isn’t aware of what batching overhead the wallet might have.
2. Apps would need to sum the call gas limits on their end, which puts more responsibility on the app and more room for error (apps would need to understand that they need to sum gas limits for ALL calls)
3. This wouldn’t be compatible with `atomic: false`/EOA mode for wallet_sendCalls, where a wallet might be making multiple transactions.


## Backwards Compatibility

* Applications SHOULD only include the `gasLimitOverride` capability in their `wallet_sendCalls` requests if they are aware that the wallet supports it (e.g., by checking the `wallet_getCapabilities` response).
* Applications SHOULD include the `gasLimitOverride` capability with `optional: true` in their `wallet_sendCalls` requests to ensure compatibility with wallets that do not support this capability.

## Security Considerations

* Wallets MUST validate the provided gas limits to ensure they are within reasonable bounds and do not exceed the maximum allowed gas limit for the chain.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
