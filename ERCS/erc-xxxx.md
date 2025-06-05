---
eip: xxx
title: Cross-Chain Signatures for Account Abstraction
description: Support EIP-712 signatures for cross-chain account operations using chainId 0.
author: Ernesto García (@ernestognw)
discussions-to: https://ethereum-magicians.org/t/universal-cross-chain-signatures-for-account-abstraction/24452
status: Draft
type: Standards Track
category: ERC
created: 2025-06-05
requires: 7803
---

## Abstract

This ERC extends [ERC-7803] to enable cross-chain account abstraction by reserving `chainId` 0 for universal signature validity, following the same pattern established in [EIP-7702]. It allows accounts to sign messages that authorize operations across multiple chains through a single signature, enabling cross-chain intents, multi-chain DAO voting, and unified account management.

[ERC-7803]: ./erc-7803.md
[EIP-7702]: ./eip-7702.md

## Motivation

Current account abstraction solutions require separate signatures for each blockchain network. This creates poor user experience for cross-chain operations such as:

- **Cross-chain intents**: Users wanting to trade assets across multiple chains atomically
- **Multi-chain DAO governance**: Voting on proposals that affect protocol instances across different networks
- **Unified account management**: Managing the same account deployed on multiple chains
- **Cross-chain social recovery**: Recovery processes that span multiple networks

By extending [ERC-7803]'s signing domains to support cross-chain scenarios, this ERC enables these use cases while maintaining security through explicit chain specification.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Cross-Chain Domain Semantics

When a signing domain in [ERC-7803] uses `chainId: 0`, it MUST be interpreted as "valid on any chain where the account exists" (even counterfactually).

### Cross-Chain Signature Verification

Applications verifying cross-chain signatures MUST:

1. **Recognize `chainId: 0`**: Accept signatures with `chainId: 0` domains as valid
2. **Validate account**: Confirm the signing account exists on the current chain
3. **Standard verification**: Follow normal [ERC-7803] verification for the signature
4. **Domain separator**: Use `chainId: 0` in the domain separator hash during both signature creation and verification
5. **Chain filtering**: Accept the signature as valid regardless of `block.chainid`, but protocols MUST filter out extensions that are not valid on the current chain

### Chain-Specific Operation Display

Applications implementing cross-chain signatures SHOULD validate account existence on each target chain. Wallets SHOULD display the signing domains and their associated operations in a clear, chain-specific format that helps users understand exactly what actions will be executed on each network. For example, a wallet might an scrollable list of "Ethereum: Transfer 100 USDC to 0x123...", "Polygon: Approve 50 MATIC to 0x456...", etc.

### Fallback Warning Mechanism

If a wallet cannot parse or display the chain-specific operations, it is RECOMMENDED to fallback into displaying a warning when users are about to sign a message with `chainId: 0` to prevent accidental cross-chain authorization. This warning should clearly indicate that the signature will be valid across multiple chains and may have unintended consequences if not carefully reviewed.

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

**Cross-Chain Replay**: This ERC intentionally enables replay across chains. The signing domain binds signatures to specific accounts, preventing unauthorized use by different accounts. Each application that receives the signature should filter the signing domains to only include those relevant to its chain and maintain its own non-replayability scheme.

**Account Validation**: Applications should verify the signing account exists on each chain where the signature is used. An account that exists on Ethereum but not Polygon should not have signatures accepted on Polygon. For counterfactual accounts that have not been deployed yet, applications should follow [ERC-6492](./eip-6492.md) to validate signatures.

## Reference Implementation

A collection of examples of how to use this ERC to fulfill the _Motivation_ use cases.

### Cross-Chain Intent Example

A user wants to execute a cross-chain trade: sell USDC on Ethereum, receive ETH on Arbitrum:

```javascript
{
  types: {
    EIP712Domain: [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" }
    ],
    CrossChainOrder: [
      { name: "originToken", type: "address" },
      { name: "originAmount", type: "uint256" },
      { name: "destinationChainId", type: "uint256" },
      { name: "destinationToken", type: "address" },
      { name: "minDestinationAmount", type: "uint256" },
      { name: "deadline", type: "uint256" }
    ]
  },
  primaryType: "CrossChainOrder",
  domain: {
    name: "CrossChainDEX",
    version: "1",
    chainId: 0,  // Cross-chain validity
    verifyingContract: "0xUserAccount..." // User's account
  },
  message: {
    originToken: "0xA0b86a33E6776885F5Db...", // USDC
    originAmount: "1000000000", // 1000 USDC
    destinationChainId: 42161, // Arbitrum
    destinationToken: "0x0000000000000000000000000000000000000000", // ETH
    minDestinationAmount: "500000000000000000", // 0.5 ETH
    deadline: 1704067200
  },
  signingDomains: [
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "EthereumSettler",
        chainId: 1, // Ethereum
        verifyingContract: "0xEthereumSettler..."
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "ArbitrumSettler",
        chainId: 42161, // Arbitrum
        verifyingContract: "0xArbitrumSettler..."
      }
    }
  ],
  authMethods: [
    { "id": "ERC-1271" }
  ]
}
```

This signature is valid on both Ethereum and Arbitrum. The Ethereum settler can verify it to custody the user's USDC, while the Arbitrum settler can verify it to release ETH to the user. The `chainId: 0` domain enables this cross-chain validity.

### Multi-Chain Governance Example

A DAO member votes on a proposal affecting all chain deployments:

```javascript
{
  types: {
    EIP712Domain: [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" }
    ],
    Vote: [
      { name: "proposalId", type: "uint256" },
      { name: "support", type: "bool" }
    ]
  },
  primaryType: "Vote",
  domain: {
    name: "MultiChainDAO",
    version: "1",
    chainId: 0, // Cross-chain validity
    verifyingContract: "0xVoterAccount..." // User's account
  },
  message: {
    proposalId: 42,
    support: true
  },
  signingDomains: [
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "DAOGovernor",
        chainId: 1, // Ethereum
        verifyingContract: "0xEthereumDAO..."
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "DAOGovernor",
        chainId: 137, // Polygon
        verifyingContract: "0xPolygonDAO..."
      }
    }
  ],
  authMethods: [
    { "id": "ERC-1271" }
  ]
}
```

This vote signature can be submitted to DAO contracts on both Ethereum and Polygon, enabling coordinated multi-chain governance decisions.

### Unified Account Management Example

A user wants to add a new signer to their multisig account deployed across multiple chains using an [ERC-7579] module:

[ERC-7579]: ./erc-7579.md

```javascript
{
  types: {
    EIP712Domain: [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" }
    ],
    AddSigner: [
      { name: "newSigner", type: "bytes" },
      { name: "newThreshold", type: "uint256" },
      { name: "nonce", type: "uint256" }
    ]
  },
  primaryType: "AddSigner",
  domain: {
    name: "MultiChainMultisig",
    version: "1",
    chainId: 0, // Cross-chain validity
    verifyingContract: "0x1234567890123456789012345678901234567890" // Same account address
  },
  message: {
    newSigner: "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20", // ERC-7913 signer
    newThreshold: 3, // Update threshold from 2-of-4 to 3-of-5
    nonce: 42
  },
  signingDomains: [
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "MultiSignerERC7913",
        chainId: 1, // Ethereum
        verifyingContract: "0x1234567890123456789012345678901234567890"
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "MultiSignerERC7913",
        chainId: 137, // Polygon
        verifyingContract: "0x1234567890123456789012345678901234567890"
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "MultiSignerERC7913",
        chainId: 42161, // Arbitrum
        verifyingContract: "0x1234567890123456789012345678901234567890"
      }
    }
  ],
  authMethods: [
    { "id": "ERC-7913" }
  ]
}
```

This signature enables the multisig owners to add a new ERC-7913 signer and update the threshold across all chain deployments simultaneously. The same account address (`0x1234...`) exists on Ethereum, Polygon, and Arbitrum, and this single signature authorizes the signer addition on all three networks.

### Cross-Chain Social Recovery Example

A user has lost access to their account and guardians need to initiate recovery across multiple networks:

```javascript
{
  types: {
    EIP712Domain: [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" }
    ],
    Recover: [
      { name: "account", type: "address" },
      { name: "salt", type: "bytes32" },
      { name: "mode", type: "bytes32" },
      { name: "executionCalldata", type: "bytes" }
    ]
  },
  primaryType: "Recover",
  domain: {
    name: "CrossChainSocialRecovery",
    version: "1",
    chainId: 0, // Cross-chain validity
    verifyingContract: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdef" // Lost account address
  },
  message: {
    account: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdef", // Account being recovered
    salt: "0x1111111111111111111111111111111111111111111111111111111111111111",
    mode: "0x0100000000000000000000000000000000000000000000000000000000000000", // ERC-7579 batch execution
    executionCalldata: "0x608060405234801561001057600080fd5b50" // Encoded calls to replace signer
  },
  signingDomains: [
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "DelayedSocialRecovery",
        chainId: 1, // Ethereum
        verifyingContract: "0x1111111111111111111111111111111111111111" // DelayedSocialRecovery module
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "DelayedSocialRecovery",
        chainId: 137, // Polygon
        verifyingContract: "0x2222222222222222222222222222222222222222" // DelayedSocialRecovery module
      }
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      },
      domain: {
        name: "DelayedSocialRecovery",
        chainId: 42161, // Arbitrum
        verifyingContract: "0x3333333333333333333333333333333333333333" // DelayedSocialRecovery module
      }
    }
  ],
  authMethods: [
    { "id": "ERC-7913" }
  ]
}
```

This signature enables guardians (using a `ERC7579DelayedSocialRecovery` module combining multisig and delayed execution) to schedule a recovery operation across all chains. The module would require:

1. **Guardian Signatures**: The actual signature would contain `abi.encode(bytes[] guardians, bytes[] signatures)` where guardians are ERC-7913 formatted signers and signatures are their individual approvals
2. **Schedule Phase**: Once 3-of-5 guardians sign, the recovery is scheduled on all networks with a N-day delay
3. **Security Window**: N-day period where malicious recovery attempts can be detected and canceled
4. **Execution Phase**: After the delay, anyone can execute the recovery to replace the account's signer
5. **Cross-Chain Consistency**: The same recovery operation is scheduled simultaneously on Ethereum, Polygon, and Arbitrum

The `executionCalldata` contains batched ERC-7579 calls to remove the compromised signer and add the new recovery signer, ensuring atomic recovery across all target networks.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
