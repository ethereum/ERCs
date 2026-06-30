---
title: Alternative Gas Fees Capability
description: A capability allowing wallets to indicate that they have alternative means for paying gas fees.
author: TODO
discussions-to: <URL>
status: Draft
type: Standards
category: ERC
created: 2025-09-18
requires: EIP-5792
---

## Abstract

An [EIP-5792](https://eips.ethereum.org/EIPS/eip-5792) compliant capability that allows wallets to indicate to apps that they are able to pay for gas fees using sources other than the chain's native gas token.

A wallet's ability to pay for gas fees using alternative sources is communicated to apps as part of its response to an [EIP-5792](https://eips.ethereum.org/EIPS/eip-5792) `wallet_getCapabilities` request. The following standard does not specify the sources that can be used to pay gas fees, but some examples are:
* Funds from offchain sources that can be onramped and used just-in-time
* Wallets that manage many accounts, where assets across those accounts can be transfered to the required account before submitting a transaction requested by an app

## Motivation

Many applications check users’ balances before letting them complete some action. For example, if a user wants to swap some amount of tokens on a dex, the dex will commonly block the user from doing so if it sees that the user does not have enough native token to pay for the transaction gas fee. However, more advanced wallets have features that let users pay for gas fees from other sources. Wallets need a way to tell apps that they have access to alternative gas fee sources so that users using these more advanced wallets are not blocked by balance checks.

## Specification

One new EIP-5792 wallet capability is defined.

### Wallet Implementation

To conform to this specification, wallets that wish to indicate that they can pay for gas fees using alternative sources MUST, for each chain they can pay using alternative gas fees on, respond to `wallet_getCapabilities` calls with an `alternativeGasFees` object with a `supported` field set to true.

This specification does not put any constraints on the alternative source for gas fees.

### `wallet_getCapabilities` Response Specification
```typescript
type AlternativeGasFeesCapability = {
  supported: boolean;
};
```
#### `wallet_getCapabilities` Example Response
```json
{
  "supported": true
}
```

### `wallet_sendCalls` Usage
The `alternativeGasFees` capability DOES NOT need to be specified in the `wallet_sendCalls` request. The wallet will consider present the user with alternative gas fee sources if they are available opaquely to the app. The app simply needs to allow submission of transaction requests to the wallet even when they have determined the transacting account does not have enough gas fees to execute the transaction.

### Alternative Gas Fees and Atomic Execution
Alternative gas fees orchestration is independent of `wallet_sendCalls` execution lifecycle. The `atomicRequired` field applies only to the call bundle execution, not to the gas fee provisioning.

### Error Codes
No new error codes need to be defined. The wallet UI should continue to block the ability to accept a transaction request that it does not have enough to execute successfully. The user is forced to reject the transaction resulting in an error with code `4001` and message `User Rejected Request`.

## Rationale

We decided a simple boolean value was the best and simplest way to enable apps to determine that a transaction is still submittable despite the app knowing that the transacting account does not have enough native token to pay for the transaction gas fee. A boolean value does not leak any unnecessary information about how the gas fees might be sourced, but gives enough signal that the app can unblock their UI from allowing the user to submit a transaction request to the wallet.

In the worst case scenario, the wallet is unable find an alternative source for gas fees and the transaction approval is rejected. Apps are already written to handle this scenario.

## Backwards Compatibility

* Applications SHOULD include the `alternativeGasFees` capability with `optional: true` to provide metadata to wallets that support this optional capability while maintaining comptability with wallets that do not.


## Security Considerations

* Applications MUST NOT assume that the wallet will always be able to pay the transaction gas fee using alternative sources, and SHOULD handle failures gracefully.

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
