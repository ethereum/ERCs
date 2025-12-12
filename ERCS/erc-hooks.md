---
eip: TBD
title: Metadata Hooks
description: A method for redirecting metadata records to a different contract for secure resolution.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-metadata-hooks/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2025-12-12
requires: 3668
---

## Abstract

This ERC introduces Metadata Hooks, a method for redirecting metadata records to a different contract for resolution. When a metadata value contains a hook, clients "jump" to the destination contract to resolve the actual value. The destination contract MUST implement the same metadata interface as the originating contract. This enables secure resolution from known contracts, such as singleton registries with known security properties.

## Motivation

The goal of this ERC is to propose a method for securely resolving onchain metadata from known contracts. Hooks allow metadata records to be redirected to trusted resolvers by specifying a destination contract address. If the destination is a known contract, such as a credential resolver for proof of personhood (PoP) or know your customer (KYC), clients can verify the contract's security properties before resolving.

The hook both notifies resolving clients of a credential source, as well as provides the method for resolving the credential.

### Use Cases

- **Credential Resolution**: Redirect a `proof-of-person` or `kyc` record to a trusted credential registry
- **Singleton Registries**: Point to canonical registries with known security properties
- **Shared Metadata**: Multiple contracts can reference the same metadata source

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

A hook is an ABI-encoded value stored in a metadata record that redirects resolution to a different contract. When a client encounters a hook, it:

1. Parses the hook to extract the destination key and contract address
2. Verifies the destination contract is trusted (RECOMMENDED)
3. Calls the appropriate metadata function on the destination contract
4. Returns the resolved value

The destination contract MUST implement the same metadata interface as the originating contract.

### Hook Function Signatures

This ERC defines hook signatures for use with different metadata standards:

#### For ERC-8049 (Contract-Level Metadata)

```solidity
function ContractMetadataHook(
    string calldata key,
    address destination
)
```

```solidity
bytes4 constant CONTRACT_METADATA_HOOK_SELECTOR = 0xcae9bb7e;
```

When resolved, clients call `getContractMetadata(key)` on the destination contract.

#### For ERC-8048 (Token Metadata)

```solidity
function MetadataHook(
    uint256 tokenId,
    string calldata key,
    address destination
)
```

```solidity
bytes4 constant METADATA_HOOK_SELECTOR = 0x954fe887;
```

When resolved, clients call `getMetadata(tokenId, key)` on the destination contract.

### Hook Encoding

Hooks MUST be ABI-encoded and stored as the value for a metadata key:

#### ERC-8049 Hook Encoding

```solidity
bytes memory hookData = abi.encodeWithSelector(
    CONTRACT_METADATA_HOOK_SELECTOR,
    key,
    destinationContract
);

// Store the hook as the value
originatingContract.setContractMetadata("kyc", hookData);
```

#### ERC-8048 Hook Encoding

```solidity
bytes memory hookData = abi.encodeWithSelector(
    METADATA_HOOK_SELECTOR,
    tokenId,
    key,
    destinationContract
);

// Store the hook as the value
originatingContract.setMetadata(tokenId, "kyc", hookData);
```

### Detecting Hooks

Clients MUST be aware in advance which metadata keys may contain hooks. It is intentional that hook-enabled keys are known by clients beforehand, similar to how clients know to look for keys like `"image"` or `"description"`.

Specific implementations MAY:
- Require that hooks are supported for every key
- Specify a subset of keys that MUST use hooks
- Define which keys are hook-enabled on a per-contract basis

### Resolving Hooks

When a client encounters a hook:

1. **Parse the hook** to extract the `key` (and `tokenId` for ERC-8048) and `destination` address
2. **Verify the destination** (RECOMMENDED): Check that the destination contract is known and trusted
3. **Resolve from destination**: Call the appropriate metadata function on the destination contract
4. **Support ERC-3668**: Clients MUST support [ERC-3668](./eip-3668.md) offchain data retrieval when resolving from the destination contract

Clients MAY choose NOT to resolve hooks if the destination contract is not known to be secure and trustworthy. Some clients have ERC-3668 disabled by default, but clients MUST enable it before resolving the hook.

### Example: KYC Credential Resolution with ERC-8049

A contract can redirect its `"kyc"` metadata key to a trusted KYC provider contract:

**Step 1: Store the hook in the originating contract**

```solidity
// KYCProvider is a trusted singleton registry at a known address
address kycProvider = 0x1234567890AbcdEF1234567890aBcdef12345678;

// Create hook that redirects "kyc" to the KYC provider
bytes memory hookData = abi.encodeWithSelector(
    CONTRACT_METADATA_HOOK_SELECTOR,
    "kyc:0x76F1Ff0186DDb9461890bdb3094AF74A5F24a162",
    kycProvider
);

// Store the hook
originatingContract.setContractMetadata("kyc", hookData);
```

**Step 2: Client resolves the hook**

```javascript
// Client reads metadata from originating contract
const value = await originatingContract.getContractMetadata("kyc");

// Client detects this is a hook (starts with CONTRACT_METADATA_HOOK_SELECTOR)
if (value.startsWith("0xcae9bb7e")) {
    // Parse the hook (ABI decode after 4-byte selector)
    const { key, destination } = decodeHook(value);
    
    // Verify destination is trusted (implementation-specific)
    if (!isTrustedResolver(destination)) {
        throw new Error("Untrusted resolver");
    }
    
    // Enable ERC-3668 (CCIP-Read) support for this resolution
    const destinationContract = new ethers.Contract(
        destination,
        ["function getContractMetadata(string) view returns (bytes)"],
        provider.ccipReadEnabled(true)  // Enable CCIP-Read
    );
    
    // Resolve from destination contract
    const credential = await destinationContract.getContractMetadata(key);
    
    // credential contains: "Maria Garcia /0x76F1Ff0186DDb9461890bdb3094AF74A5F24a162/ ID: 146-DJH-6346-25294"
}
```

## Rationale

Hooks introduce redirection for resolving metadata records, which allows for resolving records from "known" contracts. Known contracts may have security properties which are verifiable, for example a singleton registry which resolves Proof-of-Personhood IDs or Know-your-Customer credentials.

### Why Mandate ERC-3668?

ERC-3668 (CCIP-Read) is a powerful technology that enables both cross-chain and verified offchain resolution of metadata. However, because some clients disable ERC-3668 by default due to security considerations, hooks explicitly mandate ERC-3668 support. This gives clients the opportunity to enable ERC-3668 specifically for hook resolution without needing to have it enabled globally. By tying ERC-3668 to hooks, clients can make a deliberate choice to enable it when resolving from known, trusted contracts, while keeping it disabled for general use.

## Backwards Compatibility

Hooks are backwards compatible; clients that are not aware of hooks will simply return the hook encoding as the raw value.

## Reference Implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library MetadataHooks {
    bytes4 constant CONTRACT_METADATA_HOOK_SELECTOR = 0xcae9bb7e;
    bytes4 constant METADATA_HOOK_SELECTOR = 0x954fe887;
    
    function isContractMetadataHook(bytes memory value) internal pure returns (bool) {
        if (value.length < 4) return false;
        bytes4 selector;
        assembly {
            selector := mload(add(value, 32))
        }
        return selector == CONTRACT_METADATA_HOOK_SELECTOR;
    }
    
    function isMetadataHook(bytes memory value) internal pure returns (bool) {
        if (value.length < 4) return false;
        bytes4 selector;
        assembly {
            selector := mload(add(value, 32))
        }
        return selector == METADATA_HOOK_SELECTOR;
    }
    
    function parseContractMetadataHook(bytes memory value) 
        internal 
        pure 
        returns (string memory key, address destination) 
    {
        require(isContractMetadataHook(value), "Not a contract metadata hook");
        
        bytes memory encoded = new bytes(value.length - 4);
        for (uint i = 4; i < value.length; i++) {
            encoded[i - 4] = value[i];
        }
        
        (key, destination) = abi.decode(encoded, (string, address));
    }
    
    function parseMetadataHook(bytes memory value) 
        internal 
        pure 
        returns (uint256 tokenId, string memory key, address destination) 
    {
        require(isMetadataHook(value), "Not a metadata hook");
        
        bytes memory encoded = new bytes(value.length - 4);
        for (uint i = 4; i < value.length; i++) {
            encoded[i - 4] = value[i];
        }
        
        (tokenId, key, destination) = abi.decode(encoded, (uint256, string, address));
    }
}
```

## Security Considerations

### Destination Trust

The primary use of hooks is to resolve data from known contracts with verifiable security properties. Clients SHOULD:

- Maintain a list of trusted destination contract addresses or use a third-party registry
- Fail when resolving from untrusted destinations

### Recursive Hooks

Implementations SHOULD limit the depth of hook resolution to prevent infinite loops where a hook resolves to another hook. A reasonable limit is 3-5 levels of indirection.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
