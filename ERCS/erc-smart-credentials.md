---
eip: TBD
title: Smart Credentials
description: A specification for blockchain-based credentials that are resolved via smart contracts with support for onchain, offchain, and zero-knowledge proofs.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-smart-credentials/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2025-12-15
requires: 3668
---

## Abstract

This ERC defines Smart Credentials, a specification for blockchain-based credentials that are resolved via smart contracts. Smart Credentials provide a uniform method for resolving credentials in the context of onchain identity profiles. Credentials are records "about" an entity controlled by a credential provider, as opposed to records "by" an entity that the entity controls directly.

Smart Credentials support fully onchain data, a mix of onchain and offchain data, or fully offchain data with onchain verification. They are designed to support Zero Knowledge Proofs (ZKPs), enabling privacy-preserving credentials where users can prove specific facts without revealing the underlying data (e.g., proving age is over 18 without revealing birthdate).

## Motivation

With the rise of AI agents, users on the internet will become increasingly indistinguishable from AI agents. We need provable onchain identities that allow real human users to prove their humanity, AI agents to prove who controls them and what they can do, and AI agents to develop reputations and trust based on their work. Blockchains are well-positioned to provide provable identity because records can be broadcast publicly with provable ownership and provenance.

### Identity and Credentials

For the purposes of this specification, "users" refers to both human users and AI agents. Unlike profile data that a user controls (e.g., name, avatar), credentials are records "about" a user controlled by third-party providers—verifiable facts that users cannot fabricate. Examples include:

- **Proof of Personhood / KYC**: Verify humanity or identity from trusted providers
- **Reputation Systems**: Ratings for AI agents based on work and reviews
- **Privacy-Preserving Proofs**: ZKPs that prove facts without revealing underlying data

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Credential Function Requirements

A Smart Credential is a smart contract that implements one or more credential functions. Each credential function MUST have the following properties:

1. **Single Function**: Each credential MUST be a single function
2. **Return Type**: The function MUST return a single `bytes` value
3. **Parameters**: The function MAY use any parameter types including addresses, structs, arrays, fixed bytes types (e.g., `bytes32`), integers, etc.
4. **Encoded Values**: Credentials MAY return ABI-encoded value types as bytes (e.g., arrays, structs, integers)

### Resolution Requirements

When resolving a Smart Credential:

1. Clients MUST enable [ERC-3668](./eip-3668.md) (CCIP-Read) for secure offchain data retrieval
2. Clients MUST support ERC-XXXX (Metadata Hooks) for hook-based credential resolution

### Credential Function Flexibility

Smart Credentials do not prescribe a specific function signature. The only requirement is that each credential function MUST return a `bytes` value. This allows Smart Credentials to leverage existing metadata standards:

- **ERC-8049**: `getContractMetadata(string key)` → `bytes` for contract-level credentials
- **ERC-8048**: `getMetadata(uint256 tokenId, string key)` → `bytes` for token-level credentials
- **Custom functions**: Any function with any parameters, as long as it returns `bytes`

This flexibility allows credential providers to design credential functions appropriate for their use case while maintaining uniform resolution through the `bytes` return type.

### Offchain Data Resolution

For credentials with offchain data:

1. The smart contract MUST implement [ERC-3668](./eip-3668.md) to redirect resolution to a gateway
2. Values returned from the gateway MUST be verified using a callback function in the smart credential contract
3. The callback function MUST validate the integrity and authenticity of the offchain data

### Integration with Identity Systems

Smart Credentials are designed to be resolved in the context of onchain profiles, such as:

- AI agent profiles in onchain agent registries such as [ERC-8004](./eip-8004.md) (Trustless Agents)
- Any identity system implementing ERC-XXXX (Metadata Hooks)

Identity systems can:
- Allow users to add credentials to their profiles
- Include credentials by default for all entities (e.g., a rating credential for all AI agents)
- Resolve credentials uniformly using the hook mechanism

## Rationale

Smart Credentials mandate only a `bytes` return type to enable uniform resolution while allowing credential providers to use any function signature, including existing standards like ERC-8048 and ERC-8049. ERC-3668 (CCIP-Read) is required to support offchain data with onchain verification, reducing costs while maintaining security. The design supports Zero Knowledge Proofs to enable privacy-preserving credentials with selective disclosure.

## Backwards Compatibility

No issues.

## Security Considerations

None.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

