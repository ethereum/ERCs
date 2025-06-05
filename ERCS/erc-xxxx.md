---
eip: xxx
title: Universal Cross-Chain Signatures for Account Abstraction
description: Extends ERC-7803 to support cross-chain account operations using chainId 0 for universal validity.
author: Ernesto García (@ernestognw)
discussions-to: https://ethereum-magicians.org/t/erc-xxx-cross-chain-signing-domains/
status: Draft
type: Standards Track
category: ERC
created: 2025-01-15
requires: 7803
---

## Abstract

This ERC extends [ERC-7803] to enable cross-chain account abstraction by reserving `chainId` 0 for universal signature validity. It allows accounts to sign messages that authorize operations across multiple chains through a single signature, enabling cross-chain intents, multi-chain DAO voting, and unified account management.

[ERC-7803]: ./eip-7803.md

## Motivation

Current account abstraction solutions require separate signatures for each blockchain network. This creates poor user experience for cross-chain operations such as:

- **Cross-chain intents**: Users wanting to trade assets across multiple chains atomically
- **Multi-chain DAO governance**: Voting on proposals that affect protocol instances across different networks
- **Unified account management**: Managing the same logical account deployed on multiple chains
- **Cross-chain social recovery**: Recovery processes that span multiple networks

By extending [ERC-7803]'s signing domains to support cross-chain scenarios, this ERC enables these use cases while maintaining security through explicit chain specification.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Cross-Chain Domain Semantics

When a signing domain in [ERC-7803] uses `chainId: 0`, it MUST be interpreted as "valid on any chain where the account exists" (even counterfactually).

### Domain Separator Computation

When computing domain separators for `chainId: 0` domains:

1. **During signature creation**: Use `chainId: 0` in the domain separator hash
2. **During signature verification**: Use `chainId: 0` in the domain separator hash
3. **Validity**: Accept the signature as valid regardless of `block.chainid`. Protocols MUST filter out those extensions that are not valid on the current chain.

### Simple Cross-Chain Example

A user wants to authorize the same action on multiple chains with one signature:

```javascript
// Single signature, valid on Ethereum, Polygon, and Arbitrum
{
  types: {
    EIP712Domain: [/*...*/],
    Transfer: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" }
    ]
  },
  primaryType: "Transfer",
  domain: {
    name: "MultiChainApp",
    version: "1",
    chainId: 0, // Cross-chain domain
    verifyingContract: "0xA4b..." // User's account address
  },
  message: {
    to: "0xRecipient...",
    amount: "1000000000000000000"
  },
  signingDomains: [
    {
      types: { EIP712Domain: [/*...*/] },
      domain: {
        name: "CrossChainApp",
        version: "1",
        chainId: 1, // Valid on Ethereum
        verifyingContract: "0x1234..." // App deployed on Ethereum
      }
    },
    {
      types: { EIP712Domain: [/*...*/] },
      domain: {
        name: "AMM",
        version: "1",
        chainId: 137, // Valid on Polygon
        verifyingContract: "0xabcd..." // App deployed on Polygon
      }
    },
    {
      types: { EIP712Domain: [/*...*/] },
      domain: {
        name: "ERC4626Vault",
        version: "1",
        chainId: 42161, // Valid on Arbitrum
        verifyingContract: "0x2345..." // App deployed on Arbitrum
      }
    }
  ],
  authMethods: [{"id": "ERC-1271"}]
}
```

This signature can be submitted to the same app deployed on Ethereum (chainId 1), Polygon (chainId 137), or Arbitrum (chainId 42161).

### Multi-Chain Governance Example

A DAO member votes on a proposal that affects all chain deployments:

```javascript
{
  types: {
    EIP712Domain: [/*...*/],
    Vote: [
      { name: "proposalId", type: "uint256" },
      { name: "support", type: "bool" }
    ]
  },
  primaryType: "Vote",
  domain: {
    name: "MultiChainDAO",
    version: "1",
    chainId: 0, // Cross-chain domain
    verifyingContract: "0x1234..." // User's account address
  },
  message: {
    proposalId: 42,
    support: true
  },
  signingDomains: [
    {
      types: { EIP712Domain: [/*...*/] },
      domain: {
        name: "DAOMember",
        version: "1",
        chainId: 1, // Valid on Ethereum
        verifyingContract: "0x5678..." // DAO deployed on Ethereum
      },
      {
        types: { EIP712Domain: [/*...*/] },
        domain: {
          name: "DAOMember",
          version: "1",
          chainId: 137, // Valid on Polygon
          verifyingContract: "0x5678..." // DAO deployed on Polygon
        }
      },
      {
        types: { EIP712Domain: [/*...*/] },
        domain: {
          name: "DAOMember",
          version: "1",
          chainId: 42161, // Valid on Arbitrum
          verifyingContract: "0x5678..." // DAO deployed on Arbitrum
        }
      }
    }
  ]
}
```

This vote signature is valid on Ethereum, Polygon, and Arbitrum.

### Verification Requirements

Applications verifying cross-chain signatures MUST:

1. **Recognize `chainId: 0`**: Accept signatures with `chainId: 0` domains as valid
2. **Validate account**: Confirm the signing account exists on the current chain
3. **Standard verification**: Follow normal [ERC-7803] verification for the signature

## Rationale

### Account-Centric Approach

The account-centric approach represents the most interoperable way for users to express cross-chain intents. By binding signatures to user accounts rather than specific chains, this design enables:

1. **Universal Signatures**: A single signature can be valid across multiple chains, reducing user friction and transaction overhead
2. **Wallet Compatibility**: Standard wallets can implement this pattern without breaking existing functionality
3. **Protocol Safety**: Maintains compatibility with existing protocol assumptions while enabling cross-chain operations

### `chainId: 0` Semantics

Using `chainId: 0` leverages [EIP-712]'s existing `chainId` field to indicate cross-chain validity. Zero is never used by real networks, making it a natural choice for "universal" signatures.

### Simple Extension

This ERC adds one simple rule to [ERC-7803]: treat `chainId: 0` domains as valid on any chain. No new encoding, no complex message structures, no additional verification rules beyond checking the account exists.

[EIP-712]: ./eip-712.md

## Backwards Compatibility

This ERC is fully backward compatible with [ERC-7803]. Applications that don't support `chainId: 0` will reject such signatures safely.

## Security Considerations

**Cross-Chain Replay**: This ERC intentionally enables replay across chains. The signing domain binds signatures to specific accounts, preventing unauthorized use by different accounts.

**Account Validation**: Applications MUST verify the signing account exists on each chain where the signature is used. An account that exists on Ethereum but not Polygon should not have signatures accepted on Polygon.

**User Understanding**: Wallets SHOULD clearly indicate when users create signatures valid across multiple chains.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
