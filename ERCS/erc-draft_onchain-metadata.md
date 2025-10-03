---
title: Onchain Metadata for Multicoin and NFT Registries
description: A key-value store interface that allows registries to store and retrieve arbitrary bytes as metadata directly onchain.
author: Prem Makeig (@nxt3d)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2025-10-2
requires: 165
---

## Abstract

This ERC defines an onchain metadata standard for multicoin and NFT registries including ERC-721, ERC-1155, ERC-6909, and ERC-8004. The standard provides a key-value store allowing for arbitrary bytes to be stored onchain.

## Motivation

This ERC addresses the need for fully onchain metadata while maintaining compatibility with existing ERC-721, ERC-1155, ERC-6909, and ERC-8004 standards. It has been a long-felt need for developers to store metadata onchain for NFTs and other multitoken contracts; however, there has been no uniform standard way to do this. Some projects have used the tokenURI field to store metadata onchain using Data URLs, which introduces gas inefficiencies and has other downstream effects (for example making storage proofs more complex). This standard provides a uniform way to store metadata onchain, and is backwards compatible with existing ERC-721, ERC-1155, ERC-6909, and ERC-8004 standards.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope

This ERC is an optional extension that MAY be implemented by any ERC-721, ERC-1155, ERC-6909, or ERC-8004 compliant registries.

### Required Metadata Function and Event

Contracts implementing this ERC MUST implement the following interface:

```solidity
interface IOnchainMetadata {
    /// @notice Get metadata value for a key (bytes of UTF-8 unless specified otherwise).
    function getMetadata(uint256 tokenId, bytes calldata key) external view returns (bytes memory);
    
    /// @notice Emitted when metadata is set for a token.
    event OnchainMetadataSet(uint256 indexed tokenId, bytes key, bytes32 value);
}
```

- `getMetadata(tokenId, key)`: Returns the metadata value for the given token ID and key as bytes

Contracts implementing this ERC MAY also expose a `setMetadata(uint256 tokenId, bytes calldata key, bytes calldata value)` function to allow metadata updates, with write policy determined by the contract.

### ERC-165 Interface Detection

Contracts implementing this ERC MUST implement ERC-165 and return `true` when `supportsInterface(0x8476e84b)` is called.

The interface ID for `IOnchainMetadata` is `0x8476e84b`.

### Event

Contracts implementing this ERC MUST emit the following event when metadata is set:

```solidity
event OnchainMetadataSet(uint256 indexed tokenId, bytes key, bytes indexed value);
```

### Key/Value Pairs

This ERC specifies that the key and value are both bytes type values. This has been done to allow for the widest range of possible values and to allow developers to use the most appropriate encodings for their use cases. 

If not otherwise specified, the key and value should be a bytes encoding of a UTF-8 string, such as `bytes("name")` for the key and `bytes("Vitalik")` for the value.

### Examples

The inspiration for this standard was trustless AI agents. An example of how this could be used is with a key for onchain context data, designed to be consumed by AI agents.

#### Example: Context for LLM-Facing Agent Metadata

A typical usage for LLM-facing agents is to provide context that contains machine-readable descriptions of the agent's identity, purpose, and capabilities. For example, using a key like `bytes("root-context")` to store agent information. This context can be used by LLMs or other AI systems as a first point of connection to bootstrap interactions with the agent.

**Example:**

- Key: `bytes("root-context")`
- Value: `bytes("This ERC-8004 AI agent is specialized in DeFi analysis and trading recommendations.")`

#### Example: Biometric Identity for Proof of Personhood

A biometric identity system using open source hardware to create universal proof of personhood tokens.

- Key: `bytes("biometric_hash")` → Value: `bytes32(bytes(identity_commitment))`
- Key: `bytes("verification_time")` → Value: `uint256(bytes(timestamp))`
- Key: `bytes("device_proof")` → Value: `bytes32(bytes(device_attestation))`


## Rationale

This design prioritizes simplicity and flexibility by using a bytes-based key-value store that allows any data type to be stored without encoding restrictions. The minimal interface with a single `getMetadata` function provides all necessary functionality while remaining backwards compatible with existing ERC-721, ERC-1155, ERC-6909, and ERC-8004 standards. The optional `setMetadata` function enables flexible access control for metadata updates. The required `OnchainMetadataSet` event provides transparent audit trails and efficient offchain indexing. This makes the standard suitable for diverse use cases including AI agents, proof of personhood systems, and custom metadata storage.

## Backwards Compatibility

- Fully compatible with ERC-721, ERC-1155, ERC-6909, and ERC-8004.
- Non-supporting clients can ignore the scheme.

## Reference Implementation

The interface is defined in the Required Metadata Function and Event section above. Here is a reference implementation:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IOnchainMetadata.sol";

contract OnchainMetadataExample is IOnchainMetadata {
    // Mapping from tokenId => key => value
    mapping(uint256 => mapping(bytes => bytes)) private _metadata;
    
    /// @notice Get metadata value for a key
    function getMetadata(uint256 tokenId, bytes calldata key) 
        external view override returns (bytes memory) {
        return _metadata[tokenId][key];
    }
    
    /// @notice Set metadata for a token (optional implementation)
    function setMetadata(uint256 tokenId, bytes calldata key, bytes calldata value) 
        external {
        _metadata[tokenId][key] = value;
        emit OnchainMetadataSet(tokenId, key, value);
    }
    
    /// @notice ERC-165 interface detection
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IOnchainMetadata).interfaceId || 
               super.supportsInterface(interfaceId);
    }
}
```

Implementations should follow the standard ERC-721, ERC-1155, ERC-6909, or ERC-8004 patterns while adding the required metadata function and event.

## Security Considerations

This ERC is designed to put metadata onchain, providing security benefits through onchain storage.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).