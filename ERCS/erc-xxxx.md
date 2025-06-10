---
eip: XXXX
title: Storage Proof Broadcasting for Cross-Chain Messaging Gateways
description: A standard for cross-chain messaging that uses storage proofs to verify messages between blockchains.
author: Ernesto García (@ernestognw)
discussions-to: https://ethereum-magicians.org/t/storage-proof-broadcasting-for-cross-chain-messaging-gateways
status: Draft
type: Standards Track
category: ERC
created: 2025-06-06
requires: 7786
---

## Abstract

This document defines standardized broadcasting semantics and attributes for [ERC-7786] cross-chain messaging that enable trustless message verification through storage proofs. Messages are stored on source chains in predictable storage slots, then verified on destination chains using cryptographic proofs of the source chain's state. This approach provides cross-chain communication without relying on external validators or bridge operators.

## Motivation

Cross-chain messaging protocols typically rely on external validators, multisigs, or optimistic mechanisms that introduce trust assumptions and potential points of failure. Storage proofs offer an alternative approach where messages can be verified cryptographically using the consensus mechanisms of the chains themselves.

However, storage proof verification requires chain-specific routing information, proof data, and verification parameters that are not addressed by the base [ERC-7786] interface. Additionally, [ERC-7786] does not explicitly define broadcasting semantics for cross-chain messaging. Broadcasting enables messages to be sent without specifying a particular receiver, making them available for verification and execution by any contract on destination chains.

This document standardizes these requirements as [ERC-7786] attributes, enabling storage proof-based messaging within the established cross-chain messaging framework.

The key benefits of this approach include:

- **Trustless verification**: No external validators or multisigs required. Chains trust their own consensus mechanisms.
- **Universal compatibility**: Works between chains with verifiable state relationships through shared settlement infrastructure.
- **Flexible messaging patterns**: Supports both targeted and broadcast messaging through standardized semantics, enabling new classes of applications like oracles and intent settlement systems.
- **Composability**: Full integration with existing [ERC-7786] infrastructure and tooling

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Broadcasting Semantics

Gateways MUST interpret an empty string `""` in the receiver address of `sendMessage()` as broadcasting. This convention allows storage proof gateways to support both targeted messaging (to specific receivers) and broadcast messaging (to any interested party) within the same interface.

Receivers of broadcast messages SHOULD validate the source and authenticity of messages according to their own security requirements.

### Storage Proof Attributes

This specification defines the following [ERC-7786] attributes for storage proof messaging. Gateways MUST return true if `supportsAttribute` is called with the selector for supported attributes.

#### `route((address,bytes,uint256)[])`

Specifies the verification path from destination to source chain with corresponding proofs and version requirements. Each tuple contains an address that enables verification of the next chain's state, the cryptographic proof required for that verification step, and the expected version of the verification logic (0 means any version is acceptable).

When a non-zero version is specified, gateways MUST reject messages if the route address does not support the exact required version. Route addresses SHOULD implement version querying mechanisms to enable compatibility checking.

The route MUST form a valid path where each step represents a direct relationship between chains that enables state verification. Gateways MUST reject messages with invalid or incomplete proof data.

```solidity
abi.encodeWithSignature("route((address,bytes,uint256)[])", hops, proof, version);
```

#### `storageProof(bytes)`

The storage proof demonstrating that a specific message exists in the source chain's state at a finalized block.

ERC-7786 receivers MUST validate the storage proof.

```solidity
abi.encodeWithSignature("storageProof(bytes)", storageProofData);
```

#### `targetBlock(uint256)`

Specifies the block number on the source chain where the message was stored.

ERC-7786 receivers MAY validate the target block for freshness or finality requirements according to their security policies. Receivers MAY ignore this attribute if not needed for their use case.

When provided, this attribute SHOULD correspond to the block whose state is proven by the storage proof.

```solidity
abi.encodeWithSignature("targetBlock(uint256)", blockNumber);
```

### Relationship to Existing Storage Proof Protocols

This ERC provides standard attributes that enable protocols like [ERC-7888] to implement [ERC-7786] gateways without rebuilding their core verification logic. For example, an [ERC-7888] Broadcaster MAY expose an [ERC-7786] interface using these attributes while maintaining its existing storage proof architecture.

### Caching

Gateways implementing this specification MAY implement caching mechanisms to optimize repeated proof verifications.

### Mutability of Storage Locations

Gateways MAY choose to write messages to storage locations that cannot be deleted or accessed after being set, providing immutability guarantees. While not required by this standard, implementers can use [ERC-7201] to calculate namespaces for these not-mutable storage locations.

### Verification Process

Message verification follows these steps:

1. Parse the `route` and `storageProof` attributes from the message, and optionally `targetBlock` if provided
2. Validate all required attributes are present and well-formed
3. For each route step, verify block hash transition using the paired proof and validate version requirements if specified (non-zero)
4. Use the `storageProof` to verify that message data exists in the source chain's state at the target block obtained from the route verification. The source chain SHOULD correspond to the final validated step in the route verification process
5. Optionally validate the `targetBlock` for freshness or finality requirements if the attribute is provided and the receiver chooses to validate it
6. Execute the message if all verifications pass

## Rationale

This standard extends [ERC-7786]'s attribute system to add storage proof capabilities without creating new interfaces. This approach maintains compatibility with existing infrastructure while enabling trustless cross-chain verification, allowing implementations to focus on storage proof logic rather than rebuilding messaging infrastructure.

### Broadcasting and Storage Proofs

The empty string `""` is used for broadcast addressing because it cannot collide with any valid destination address. Storage proofs provide trustless verification relying only on chain consensus mechanisms. This approach offers universal accessibility, cryptographic guarantees, cost efficiency (gas only on source/destination chains), and enables implicit batching through shared storage roots.

### Attribute Design

The two required attributes provide the essential functionality for storage proof verification, while the optional `targetBlock` attribute enables additional freshness and finality validation when needed. Combining route information into a single tuple maintains type safety while separating storage verification from chain state transitions allows independent optimization. The optional nature of `targetBlock` provides implementation flexibility without adding unnecessary complexity to basic use cases.

### Caching

Caching can improve performance by storing verification results for reuse. Since proofs are deterministic, they can be safely cached. This is especially useful for broadcast messages that need multiple verifications. Implementations should cache both block hash transitions and storage proof results, while invalidating the cache when proof infrastructure changes.

### Mutability of Storage Locations

Proving a storage location that could've been deleted may introduce additional security risks. For example, if a message is stored in a storage location that is deleted after the message is sent, the proof will still be valid. This is why the specification does not require immutability, but allows gateways to choose to write messages to not-mutable storage locations if they so desire.

## Backwards Compatibility

This ERC extends [ERC-7786] through its attribute system and introduces no breaking changes to existing implementations. Gateways that do not support storage proof attributes will simply reject messages containing them, which is the expected behavior for unsupported features.

Existing [ERC-7786] tooling and infrastructure can immediately leverage storage proof messaging without modification, as the base interface remains unchanged.

## Security Considerations

### Validation Requirements

Gateways must rigorously validate all proof data to prevent message forgery, including proof format, completeness, and cryptographic validity. Route addresses must correspond to legitimate proof infrastructure forming a valid, connected path between chains. Only finalized blocks should be used for proof generation to prevent reorganization attacks.

Consumers of storage proof messages should implement appropriate freshness checks, as storage proofs can verify messages at any historical block, potentially including very old messages. This is not required for gateways offering not-mutable storage locations.

### Broadcast Message Security

Since broadcast messages can be executed by any party, receivers should implement robust validation of message sources and contents. This includes verifying the sender's authority and the message's semantic validity.

## Reference Implementation

### Basic Gateway Usage

```solidity
struct Hop {
    address gateway;
    bytes proof;
    uint256 version; // 0 = any version
}

// Prepare route with proofs and version requirements
Hop[] memory hops = new Hop[](2);
hops[0] = Hop(gateway1, proof1, 1); // Require version 1
hops[1] = Hop(gateway2, proof2, 0); // Any version acceptable

// Sending a broadcast message with optional targetBlock
bytes[] memory attributes = new bytes[](3);
attributes[0] = abi.encodeWithSignature("route((address,bytes,uint256)[])", hops);
attributes[1] = abi.encodeWithSignature("storageProof(bytes)", storageProofData);
attributes[2] = abi.encodeWithSignature("targetBlock(uint256)", blockNumber); // Optional

gateway.sendMessage(
    "eip155:42161",
    "", // broadcast
    abi.encode("priceUpdate", asset, price),
    attributes
);
```

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
