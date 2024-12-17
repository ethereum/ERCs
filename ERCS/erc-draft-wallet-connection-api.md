---  
title: Wallet Connection API  
description: Adds JSON-RPC method for requesting wallet connection with modular capabilities.  
author: Conner Swenberg (@ilikesymmetry).
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-wallet-connection-api/22245
status: Draft
type: Standards Track
category: ERC
created: 2024-12-15
requires: [ERC-1193](https://eips.ethereum.org/EIPS/eip-1193), [ERC-4361](https://eips.ethereum.org/EIPS/eip-4361), [ERC-5792](https://eips.ethereum.org/EIPS/eip-5792)
---

## Abstract

This ERC introduces a new wallet connection RPC method focused on extensibility. It leverages the modular capabilities approach defined in [ERC-5792](https://eips.ethereum.org/EIPS/eip-5792#wallet_getcapabilities) to streamline connections and authentication into a single interaction. 

## Motivation

Current standards like `eth_requestAccounts` and `personal_sign` lack extensibility and require separate interactions for connection and authentication. This results in added complexity for both users and developers. A unified and extensible RPC can enhance user experience, simplify development, and prepare for increasing sophistication in wallet interactions.

## Specification

### `wallet_connect`

Request the user to connect a single account and optionally confirm chain support and add capabilities.

#### RPC Specification

For each chain requested by the app, wallets MUST return a mapped capabilities object if the chain is supported and SHOULD return an empty object if no capabilities exist. Wallets MUST NOT return mapped capabilities objects for chains they do not support. If an app does not declare chains they would like to confirm support for, the wallet can return any chains it wishes to declare support for.

```typescript
type WalletConnectParams = [{
  version: string;
  chains?: `0x${string}`[]; // optional chain IDs (EIP-155 hex)
  capabilities?: Record<string,any>; // optional connection capabilities
}]

type WalletConnectResult = {
  account: {
    address: `0x${string}`; // connected account address
    supportedChainsAndCapabilities: Record<`0x${string}`,any>; // chain-specific capabilities, mirrors ERC-5792 wallet_getCapabilities
  },
  capabilityResults: Record<string,any>; // results of this connection request's connection capabilities
}
```

#### Example Parameters

```json
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

```json
{
  "account": {
    "address": "0x...",
    "supportedChainsAndCapabilities": {
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

Adds authentication using the [ERC-4361](https://eips.ethereum.org/EIPS/eip-4361) Sign In WIth Ethereum standard.

#### Capability Specification

Same as ERC-4361 specification with minor modifications: 
* The chain id is optional and if not provided, the wallet SHOULD use the earliest supported chain available from the requested array. 
* The casing of multi-word fields has been adjusted to mixedCase instead of hyphen-case. Resources are an array field. 
* The account address returned by `wallet_connect` MUST be the same address that is auto-inserted into the SIWE message.

The wallet MUST return a properly formatted ERC-4361 message that exactly matches the requested parameters and a signature over the EIP-191 hash of the message. The app SHOULD also verify that the two match for security.

```typescript
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
  message: string, // formatted SIWE message
  signature: `0x${string}` // signed over EIP-191 hash of `message`
}
```

#### Example Parameters

```json
{
  "domain": "app.com",
  "uri": "https://app.com/connect",
  "version": "1",
  "nonce": "12345678",
  "issuedAt": "2024-12-35T04:20:00Z",
  "expirationTime": "2024-12-35T06:09:00Z"
}
```

#### Example Result

```json
{
  "message": "app.com wants you to sign in with your Ethereum account:\n0x...",
  "signature": "0x..."
}
```

## Rationale

### Chain Specificity

Account Abstraction has introduced patterns where accounts operate differently depending on the chain. Designing for chain-specificity by default ensures this proposal aligns with modern wallet and app interactions. While it might seem simpler to return an array of supported chains, adopting the dictionary schema from [ERC-5792’s `wallet_getCapabilities`](https://eips.ethereum.org/EIPS/eip-5792#wallet_getcapabilities) provides a more expressive structure. This allows wallets to communicate richer, chain-specific capabilities to apps. By returning a map of supported chains and their respective capabilities, apps can conditionally adjust user experiences and determine if follow-up requests, such as `wallet_addEthereumChain` ([ERC-3085](https://eips.ethereum.org/EIPS/eip-3085)), are necessary to fill in gaps for unsupported chains.

### Capability Results

Returning capability results alongside the connection unlocks many valuable use cases, such as authentication, user metadata sharing, or indicating additional accounts' existence. To ensure clarity and maximize potential use cases, this proposal constrains the account return to a single address while allowing modular capability results.

For example, a capability requiring a user signature (e.g., for authentication) cannot reasonably scale to multiple accounts without encouraging app behavior that defaults back to treating the first account as the primary one. Instead, this design encourages apps needing multiple accounts to define additional capabilities for account discovery, ensuring modularity and forward compatibility.

### Single Account

While `eth_requestAccounts` technically supports returning an array of addresses, in practice, most apps only interact with the first account in the array. The supermajority of existing apps assume a single connected account, so this proposal aligns with that reality for simplicity and intuitiveness.

By constraining the account return to a single address, this ERC simplifies developer experience while still supporting richer capability results. Apps that require multiple accounts for specific functionality are encouraged to propose new capabilities rather than overloading the wallet connection process.

### Initial Authentication Capability

To ensure immediate value, this proposal includes a capability that combines wallet connection with authentication using the widely adopted [Sign In With Ethereum (ERC-4361)](https://eips.ethereum.org/EIPS/eip-4361) standard. This optional capability simplifies the onboarding process for apps and users by combining two steps — connection and authentication — into a single interaction. Apps that prefer alternative authentication flows can implement their own capabilities without being constrained by this design.

By unifying connection and authentication into one step, apps can reduce friction, improve the user experience, and minimize redundant interactions.

## Backwards Compatibility

This standard builds on existing RPCs and complements ERC-5792 for future extensibility. Wallets can continue supporting legacy methods.

## Security Considerations

Applies [ERC-4361 security principles](https://eips.ethereum.org/EIPS/eip-4361#security-considerations). As more capabilities are added, care must be taken to avoid unpredictable interactions.

## Privacy Considerations

Wallet addresses and any shared capabilities must be handled securely to avoid data leaks or man-in-the-middle attacks.

## Copyright

Copyright and related rights waived via CC0.  
