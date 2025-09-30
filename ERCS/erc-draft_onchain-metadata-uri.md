---
title: Onchain Metadata URI (Optional Extension for ERC-721, ERC-6909, ERC-8004)
description: A compact, URI-based selector that lets clients fetch fully onchain agent metadata directly from the registry, without offchain JSON.
author: nxt3d (@nxt3d)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2025-09-30
---

## Abstract

This ERC defines the onchain-metadata: URI scheme for use as the return of tokenURI(uint256 tokenId) by ERC-721, ERC-6909, and ERC-8004 compliant contracts that implement the getMetadata function. The scheme provides a compact, URI-based selector that allows clients to fetch fully onchain metadata directly from the contract without requiring offchain JSON. The URI acts as a query specification that lists `keys` names to retrieve, while values are fetched onchain via the getMetadata function. This extension is particularly useful for agent registries such as ERC-8004 Identity Registries.

## Motivation

This ERC addresses the need for fully onchain metadata while maintaining compatibility with existing ERC-721, ERC-6909, and ERC-8004 standards. By keeping all metadata onchain, we ensure trust and minimalism by eliminating dependencies on offchain JSON resources. The scheme preserves compatibility by ensuring tokenURI still returns a valid RFC 3986 URI, allowing existing clients to handle the URI appropriately. Rather than embedding base64-encoded JSON or other data directly in the URI, this approach uses the URI to specify which metadata keys to retrieve from the contract. This design makes array structures and data models unambiguous and easily parsed, providing a clean separation between the URI format and the actual metadata storage.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope

This ERC is an optional extension that MAY be implemented by any ERC-721, ERC-6909, or ERC-8004 compliant contract that exposes the required metadata function. It is particularly useful for agent registries such as ERC-8004 Identity Registries.

### Required Metadata Function

Contracts implementing this ERC MUST expose the following function:

```solidity
interface IOnchainMetadata {
    /// @notice Get metadata value for a key (bytes of UTF-8 unless specified otherwise).
    function getMetadata(uint256 tokenId, bytes calldata key) external view returns (bytes memory);
}
```

- `getMetadata(tokenId, key)`: Returns the metadata value for the given token ID and key as bytes

Contracts implementing this ERC MAY also expose a `setMetadata(uint256 tokenId, bytes calldata key, bytes calldata value)` function to allow metadata updates, with write policy determined by the contract.

### URI Scheme

If implemented, tokenURI(tokenId) MAY return:

```
onchain-metadata:?keys=...
```

- `onchain-metadata` is the scheme.
- The `keys` parameter is a comma-separated list of key names to fetch via getMetadata.

**Base URI Example** (ERC-721):
```
onchain-metadata:
```

When clients encounter this base URI, they will resolve the `name`, `description`, and `image` keys from the `getMetadata` function.

**Example** (backslash-wrapped for readability):
```
onchain-metadata:?keys= \
  endpoints-0-name, \
  endpoints-0-uri, \
  endpoints-0-version
```

**ERC-8004 Example** (includes optional trust model keys):
```
onchain-metadata:?keys= \
  endpoints-0-name, \
  endpoints-0-uri, \
  endpoints-0-version, \
  supportedTrust-0-reputation, \
  supportedTrust-1-crypto-economic, \
  supportedTrust-2-tee-attestation
```

### Required Fields (implicit)

The following fields are always resolved from the contract and MUST NOT appear in the URI:

- `getMetadata(tokenId, bytes("name"))`
- `getMetadata(tokenId, bytes("description"))`
- `getMetadata(tokenId, bytes("image"))`

### Keys, Encoding, and Return Values

- Key names in `keys=` are limited to `[a-z0-9-]`; when calling the contract they are provided as `bytes(keyName)`.
- Return type: unless specified otherwise, `getMetadata(tokenId, key)` MUST return a bytes value containing a UTF-8 string.

### Arrays

Arrays are encoded using dash-separated key names with explicit numeric indexes:

- **Form**: `<arrayName>-<index>-<field>` (e.g., `endpoints-0-uri`)
- Indexes MUST start at 0, be sequential with no holes (0,1,2,…,n), and appear in ascending order in keys.

**Example keys for endpoints**:
- `endpoints-0-name, endpoints-0-uri, endpoints-0-version`
- `endpoints-1-name, endpoints-1-uri, endpoints-1-version`

### ERC-8004 Implementation

When implementing this ERC with ERC-8004 Identity Registries, the following additional specifications apply:

#### Required Fields (implicit)

The following field is always resolved from the contract and MUST NOT appear in the URI:

- `getMetadata(tokenId, bytes("type"))`

#### Endpoints Format

ERC-8004 implementations MUST support the endpoints array format when implementing endpoint metadata:

**Required format**: Arrays are encoded using dash-separated key names with explicit numeric indexes:
- `endpoints-0-name, endpoints-0-uri, endpoints-0-version`
- `endpoints-1-name, endpoints-1-uri, endpoints-1-version`

**Implementation requirement**: ERC-8004 contracts implementing endpoint metadata MUST use the dash-separated array format with dense, sequential indexes starting from 0.

#### Trust Model Keys

ERC-8004 implementations MAY support trust model keys. If implemented, they MUST follow the canonical format defined below:

**Canonical keys** (examples shown for dense array indexes):
- `supportedTrust-0-reputation`
- `supportedTrust-1-crypto-economic`
- `supportedTrust-2-tee-attestation`

**Value type**: bytes used as a boolean flag:
- `0x01` = supported
- `0x00` or absence = not supported

### Client Behavior

1. Parse the URI; read keys.
2. Resolve required fields from contract (implicit).
3. For each listed key `k` in keys, call:
   ```
   getMetadata(tokenId, bytes(k))
   ```
4. Reconstruct arrays from dash-separated names with consecutive indexes.
5. If the scheme is unrecognized, treat the returned URI as opaque (standard ERC-721 behavior).

## Rationale

This design prioritizes efficiency, clarity, and compatibility with existing standards. The following design decisions support these goals:

- Keys-only URI keeps the wire format tiny and human-readable.
- Dash notation is URL-idiomatic and easy to parse; dense indexes remove ambiguity.
- Boolean bytes for supportedTrust minimize storage while retaining canonical semantics in the key.
- Implicit required fields align with common NFT metadata expectations without repeating them in the URI.

## Backwards Compatibility

- Fully compatible with ERC-721: tokenURI returns a normal URI.
- Coexists with offchain JSON URIs; registries MAY switch per token.
- Non-supporting clients can ignore the scheme.

## Reference Implementation

The interface is defined in the Required Metadata Functions section above. Implementations should follow the standard ERC-721, ERC-6909, or ERC-8004 patterns while adding the required metadata functions.

## Security Considerations

None. This ERC is designed to keep all metadata onchain, eliminating the security risks associated with offchain JSON metadata.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
