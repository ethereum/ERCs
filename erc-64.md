---
eip: xx
title: Decentralized Identity Verification (DID) Standard
description: A standard for decentralized identity verification on the Ethereum blockchain.
author: Anushka Yadav <64anushka@gmail.com>
discussions-to: https://ethereum-magicians.org/t/discussion-on-decentralized-identity-verification-did-standard/20392
status: Draft
type: Standards Track
category: ERC
created: 2024-07-02
---

## Abstract

This proposal introduces a standard for decentralized identity verification (DID) on the Ethereum blockchain. The standard aims to provide a secure, privacy-preserving method for identity verification that can be used by decentralized applications (dApps).

## Motivation

Centralized identity verification methods are often cumbersome, prone to data breaches, and do not give users control over their identity data. A decentralized identity verification standard will allow users to maintain control over their identity information while ensuring security and privacy.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
pragma solidity ^0.8.0;

interface IDecentralizedIdentity {
    // Struct to represent an identity
    struct Identity {
        address userAddress; // Ethereum address of the user
        bytes32 identityHash; // Hash of the identity data
        bytes32[2] verificationHashes; // Hashes used for verifying identity
        bool isVerified; // Indicates if the identity is verified
        uint256 timestamp; // Timestamp of identity creation
    }

    // Event emitted when a new identity is created
    event IdentityCreated(address indexed userAddress, bytes32 identityHash, uint256 timestamp);

    // Event emitted when an identity is verified
    event IdentityVerified(address indexed userAddress, bytes32[2] verificationHashes, uint256 timestamp);

    // Event emitted when an identity is revoked
    event IdentityRevoked(address indexed userAddress, uint256 timestamp);

    // Function to create a new decentralized identity for the caller.
    // Parameters:
    // - identityHash: Hash of the identity data.
    function createIdentity(bytes32 identityHash) external;

    // Function to verify the decentralized identity for the caller.
    // Parameters:
    // - verificationHashes: Hashes used for verifying the identity.
    function verifyIdentity(bytes32[2] calldata verificationHashes) external;

    // Function to revoke the decentralized identity for the caller.
    function revokeIdentity() external;
    
    // Function to retrieve the decentralized identity for a given user address
    // Parameters:
    // - userAddress Ethereum address of the user.
    // Returns:
    // identity The decentralized identity struct.
    function getIdentity(address userAddress) external view returns (Identity memory);
}

```

## Rationale

The design leverages cryptographic hashes to represent identity information, ensuring that sensitive data is not stored directly on the blockchain. The use of verification hashes allows for flexible identity verification mechanisms, and the inclusion of events ensures transparency and traceability.

## Reference Implementation

```solidity
pragma solidity ^0.8.0;

import "./IDecentralizedIdentity.sol";

contract DecentralizedIdentity is IDecentralizedIdentity {
    // Mapping to store identities by user address
    mapping(address => Identity) private identities;

    // Function to create a new decentralized identity for the caller.
    // Parameters:
    // - identityHash Hash of the identity data.
    function createIdentity(bytes32 identityHash) external override {
        // Ensure identity does not already exist
        require(identities[msg.sender].userAddress == address(0), "Identity already exists");

        // Create the identity for the caller
        identities[msg.sender] = Identity({
            userAddress: msg.sender,
            identityHash: identityHash,
            verificationHashes: [bytes32(0), bytes32(0)], // Initialize with empty hashes
            isVerified: false,
            timestamp: block.timestamp
        });

        // Emit event for the creation of a new identity
        emit IdentityCreated(msg.sender, identityHash, block.timestamp);
    }

    // Function to verify the decentralized identity for the caller.
    // Parameters:
    // - verificationHashes: Hashes used for verifying the identity.
    function verifyIdentity(bytes32[2] calldata verificationHashes) external override {
        // Ensure identity exists
        require(identities[msg.sender].userAddress != address(0), "Identity does not exist");

        // Update verification hashes and mark identity as verified
        identities[msg.sender].verificationHashes = verificationHashes;
        identities[msg.sender].isVerified = true;

        // Emit event for the verification of identity
        emit IdentityVerified(msg.sender, verificationHashes, block.timestamp);
    }

    // Function to revoke the decentralized identity for the caller.
    function revokeIdentity() external override {
        // Ensure identity exists
        require(identities[msg.sender].userAddress != address(0), "Identity does not exist");

        // Mark identity as not verified
        identities[msg.sender].isVerified = false;

        // Emit event for the revocation of identity
        emit IdentityRevoked(msg.sender, block.timestamp);
    }

    // Function to retrieve the decentralized identity for a given user address
    // Parameters:
    // - userAddress Ethereum address of the user.
    // Returns:
    // identity The decentralized identity struct.
    function getIdentity(address userAddress) external view override returns (Identity memory) {
        return identities[userAddress];
    }
}
```

## Security Considerations

**Secure Hashing**: Ensure that identity and verification hashes are generated using a secure hashing algorithm to prevent collisions and ensure the integrity of the identity data.

**User Control**: Users have control over their identity data, which reduces the risk of unauthorized access and ensures privacy.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).