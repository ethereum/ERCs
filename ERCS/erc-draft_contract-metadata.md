---
eip: TBD
title: Contract-Level Onchain Metadata
description: A standard for storing contract-level metadata onchain using ERC-7201 namespaced storage for predictable storage locations.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/add-erc-contract-level-onchain-metadata/25656
status: Draft
type: Standards Track
category: ERC
created: 2025-10-10
---

## Abstract

This ERC defines a standard for storing contract-level metadata onchain using ERC-7201 namespaced storage. It extends ERC-7572's contract-level metadata concept by providing onchain storage with predictable storage locations, enabling cross-chain compatibility and supporting upgradable contracts.

## Motivation

ERC-7572 provides a standard for contract-level metadata via contractURI(), but it primarily focuses on offchain metadata storage. This ERC extends that concept by providing onchain storage with predictable storage locations using ERC-7201 namespaced storage, enabling cross-chain compatibility and supporting upgradable contracts with consistent storage layout.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope

This ERC is an optional extension that MAY be implemented by any smart contract that wishes to store contract-level metadata onchain.

### Required Metadata Function and Event

Contracts implementing this ERC MUST implement the following interface:

```solidity
interface IERCXXXX {
    /// @notice Get contract metadata value for a key.
    function getContractMetadata(string calldata key) external view returns (bytes memory);
    
    /// @notice Emitted when contract metadata is updated.
    event ContractMetadataUpdated(string indexed indexedKey, string key, bytes value);
}
```

- `getContractMetadata(key)`: Returns the contract metadata value for the given key as bytes

Contracts implementing this ERC MAY also expose a `setContractMetadata(string calldata key, bytes calldata value)` function to allow metadata updates, with write policy determined by the contract.

Contracts implementing this ERC MUST emit the following event when metadata is set:

```solidity
event ContractMetadataUpdated(string indexed indexedKey, string key, bytes value);
```

### Storage Layout

Contracts implementing this ERC MUST use ERC-7201 namespaced storage with the namespace ID `"contract.metadata"`.

### Key/Value Pairs

This ERC specifies that the key is a string type and the value is bytes type. This provides flexibility for storing any type of data while maintaining an intuitive string-based key interface.

### Value Interpretation

If no standard is specified for a metadata value, clients MAY assume the value is a UTF-8 encoded string (bytes(string)) unless otherwise specified by the implementing contract or protocol.

### Examples

#### Example: Basic Contract Information

A contract can store basic information about itself:

- Key: `"name"` → Value: `bytes("MyToken")`
- Key: `"description"` → Value: `bytes("A decentralized exchange for trading ERC-20 tokens")`
- Key: `"collaborators"` → Value: `bytes(abi.encodePacked(address1, address2, address3))`

#### Example: ENS Name for Contract

A contract can specify its ENS name using this standard:

- Key: `"ens_name"` → Value: `bytes("mycontract.eth")`

This allows clients to discover the contract's ENS name and resolve it to get additional information about the contract.


## Rationale

This design prioritizes simplicity and flexibility by using a string-key, bytes-value store that provides an intuitive interface for any type of contract metadata. The minimal interface with a single `getContractMetadata` function provides all necessary functionality while leveraging ERC-7201 namespaced storage for predictable storage locations. The optional `setContractMetadata` function enables flexible access control for metadata updates. The required `ContractMetadataUpdated` event provides transparent audit trails with indexed key for efficient filtering. This makes the standard suitable for diverse use cases including contract identification, collaboration tracking, and custom metadata storage.

## Backwards Compatibility

- Fully compatible with existing smart contracts.
- Non-supporting clients can ignore the scheme.

## Basic Implementation

```solidity
pragma solidity ^0.8.20;

import "./IERCXXXX.sol";

contract MyContract is IERCXXXX {
    /// @custom:storage-location erc7201:contract.metadata
    struct ContractMetadataStorage {
        mapping(string key => bytes value) metadata;
    }

    // keccak256(abi.encode(uint256(keccak256("contract.metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CONTRACT_METADATA_STORAGE_LOCATION =
        0x5ef4383c549a33d0f2cb88bef8be6c7996af4b88e104ed307324efc569798d00;

    function _getContractMetadataStorage() private pure returns (ContractMetadataStorage storage $) {
        bytes32 location = CONTRACT_METADATA_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    function getContractMetadata(string calldata key) external view override returns (bytes memory) {
        ContractMetadataStorage storage $ = _getContractMetadataStorage();
        return $.metadata[key];
    }

    function setContractMetadata(string calldata key, bytes calldata value) external {
        ContractMetadataStorage storage $ = _getContractMetadataStorage();
        $.metadata[key] = value;
        emit ContractMetadataUpdated(key, key, value);
    }
}
```

## Security Considerations

This ERC uses ERC-7201 namespaced storage to prevent storage collisions and ensure predictable storage locations. Implementers should also consider the security considerations of ERC-721.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).