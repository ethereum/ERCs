---  
title: Wallet Connection API  
description: Adds JSON-RPC method for requesting wallet connection with modular capabilities.  
author: Conner Swenberg (@ilikesymmetry).
status: Draft
type: Standards Track
category: ERC
created: 2024-12-15
requires: [ERC-1193](https://eips.ethereum.org/EIPS/eip-1193), [ERC-4361](https://eips.ethereum.org/EIPS/eip-4361), [ERC-5792](https://eips.ethereum.org/EIPS/eip-5792)  
---

## Abstract

This proposal defines a new RPC for wallet connection with an emphasis on extensibility. Builds on the notion of optional “capabilities” defined in [ERC-5792](https://eips.ethereum.org/EIPS/eip-5792#wallet_getcapabilities) to add new functionality modularly. This proposal defines one capability to reduce separate interactions for connection and authentication, but otherwise seeks to leave capability definitions open-ended.

## Motivation

As user experience expectations increase, apps demand more sophisticated options for interacting with wallets. The existing standard for wallet connection, `eth_requestAccounts`, does enable any degree of extensibility. The existing standard for wallet authentication, Sign In With Ethereum ([ERC-4361](https://eips.ethereum.org/EIPS/eip-4361)), is built on a different RPC method, `personal_sign`, which also does not enable any degree of extensibility. Together, logging in to an onchain app often requires two requests which is more complicated for both users and developers. Defining a new RPC for wallet connection creates an opportunity to immediately improve the current app experience and enable forwards compatibility for increasing sophistication.

## Specification

### `wallet_connect`

Request the user to connect a single account to allow future RPC requests.

#### RPC Specification

Accepts an array of app-supported chains (hex-encoded [EIP-155](https://eips.ethereum.org/EIPS/eip-155) chain ids) to confirm which the wallet supports. Accepts capabilities and returns results for each under the same capability name. Capability names MUST be globally unique.

Only a single `account` and `capabilityResults` are returned on connection. The account includes an `address` field and a `supportedChains` field with the same schema as a [ERC-5792 `wallet_getCapabilities`](https://eips.ethereum.org/EIPS/eip-5792#wallet_getcapabilities) result. For each chain requested by the app, wallets MUST return a mapped capabilities object if the chain is supported and SHOULD use the empty object if no capabilities exist. Wallets MUST NOT return mapped capabilities objects for chains they do not support.

```
type WalletConnectParams = [{
  version: string;
  chains: `0x${string}`[];
  capabilities?: Record<string,any>;
}]

type WalletConnectResult = {
  account: {
    address: `0x${string}`;
    supportedChains: Record<`0x${string}`,any>;
  },
  capabilityResults: Record<string,any>;
}
```

#### Example Parameters

```
[{
  "version": "1",
  "chains": ["0x1", "0x2105"],
  "capabilities": {
    "exampleCapability": {
      "foo": "bar"
    }
  }
}]
```

#### Example Result

```
{
  "account": {
    "address": "0x...",
    "supportedChains": {
      "0x1": {},
      "0x2105": {
        "atomicBatch": {
          "supported": true
        },
        "paymasterService": {
          "supported": true
        }
      }
    }
  },
  "capabilityResults": {
    "exampleCapability": {}
  }
}
```

### `signInWithEthereum` Capability

Request the user to sign an [ERC-4361](https://eips.ethereum.org/EIPS/eip-4361) Sign In WIth Ethereum message on connection.

#### Capability Specification

Same as ERC-4361 specification with minor modifications. The chain id is optional and if not provided, the wallet SHOULD use the earliest supported chain available from the requested array. The casing of multi-word fields has been adjusted to mixedCase instead of hyphen-case. Resources are an array field. The account address returned by `wallet_connect` MUST be the same address that is auto-inserted into the SIWE message.

The wallet MUST return a properly formatted ERC-4361 message that exactly matches the requested parameters and a signature over the EIP-191 hash of the message. The app SHOULD also verify that the two match for security.

```
type SignInWithEthereumCapabilityParams = {
  scheme?: string,
  domain: string,
  statement?: string
  uri: string,
  version: string,
  chainId?: string
  nonce: string,
  issuedAt: string
  expirationTime?: string,
  notBefore?: string,
  requestId?: string,
  resources?: string[]
}

type SignInWithEthereumCapabilityResult = {
  message: string,
  signature: `0x${string}`
}
```

#### Example Parameters

```
{
  "domain": "app.com",
  "uri": "https://app.com/connect",
  "version": "1",
  "chainId": "8453",
  "nonce": "12345678",
  "issuedAt": "2024-12-35T04:20:00Z",
  "expirationTime": "2024-12-35T06:09:00Z"
}
```

#### Example Result

```
{
  "message": "app.com wants you to sign in with your Ethereum account:\n0x...",
  "signature": "0x..."
}
```

## Rationale

### Chain Specificity

Account Abstraction has made chain-specific patterns common for accounts and if that initiative is to succeed, we should design for chain-specificity by default. While returning an array of supported chains would be simplest, the dictionary schema of ERC-5792’s `wallet_getCapabilities` allows for richer expression of an accounts capabilities. By returning which chains an account supports, apps are better prepared to conditionally render their experience and consider sending follow up requests like `wallet_addEthereumChain` ([ERC-3085](https://eips.ethereum.org/EIPS/eip-3085)) to fill in the gaps.

### Capability Results

Enabling capabilities to return data unlocks many use cases such as authentication, user information, and indicating existence of additional accounts. Each connection capability definition MUST include both its expected parameters and expected results. To maximize the potential and clarity of capability results, constraining the account return to a single address was chosen.

### Single Account

Most apps have been built on `eth_requestAccounts` and may find its chain-agnostic address array return the most intuitive. In practice, even if multiple accounts are returned by `eth_requestAccounts`, the supermajority of apps only engage with the first in the array anyways. This implies the most intuitive app developer experience is to operate with one account at a time, especially with the presence of capability results.

For example, a capability that requires a signature (e.g. authenticating) is not scalable for a multi-account return and would encourage antipatterns that converge back to treating the 0-th index account as the only one that matters again. Instead, we encourage apps that desire multiple unique-address accounts in connection to propose a new capability that allows for the discovery of additional accounts (not included in the scope of this ERC).

### Initial Authentication Capability

To make this proposal immediately valuable for apps, providing a means to unify connection and authentication steps was included for the most popular method: Sign In With Ethereum. This implementation is optional and others are invited to define alternative authentication capabilities.

## Backwards Compatibility

Wallets can still support existing RPCs for wallet connection and authentication. This standard builds on existing primitives for wallet-to-app communication such as ERC-5792 capabilities.

## Security Considerations

[ERC-4361’s security considerations](https://eips.ethereum.org/EIPS/eip-4361#security-considerations) are all relevant to the continued use of Sign In With Ethereum as an authentication mechanism and wallet connection generally. As more capabilities get added on top of this foundation, the risk of unpredictable coupling effects between them increases.

## Privacy Considerations

Existing considerations around the privacy considerations of revealing wallet addresses to apps are still relevant. Especially considering the probable addition of capabilities to share personal information, it is critical to consider how data is passed between wallet and app and address man-in-the-middle attacks.

## Copyright

Copyright and related rights waived via CC0.  
