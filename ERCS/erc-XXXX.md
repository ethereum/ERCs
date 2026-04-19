---
eip: 8234
title: Referable NFTs Authorization
description: A standalone interface that allows any ERC-5521 NFT to refer to another NFT, with optional on-chain or off-chain authorization.
author: Ruiqiang Li (@richard-620) <richard.620.research@gmail.com>, Qin Wang <qin.wang@data61.csiro.au>, Shiping Chen <shiping.chen@data61.csiro.au>, Saber Yu (@OniReimu), John Le <johnle@uow.edu.au>, Brian Yecies <byecies@uow.edu.au>
discussions-to: https://ethereum-magicians.org/t/referable-nfts-authorization/28258
status: Draft
type: Standards Track
category: ERC
created: 2026-04-16
requires: 165, 191, 712, 721, 5521
---


## Abstract

This ERC defines a standard interface for authorizing referral relationships between arbitrary [ERC-5521](./eip-5521.md) tokens. It allows the owner of a referred NFT to grant or revoke authorization for a specific referring NFT, either directly on-chain or by an off-chain signature. The ERC is intended for cross-contract referral use cases and for retrofitting referral authorization onto existing [ERC-721](./eip-721.md) collections without modifying the token contracts themselves.

## Motivation

Existing referral-capable NFT designs do not provide a general authorization layer for referral relationships across arbitrary [ERC-5521](./eip-5521.md) contracts. In particular, many existing ERC-721 collections cannot be modified to add native referral logic, and existing approaches do not standardize how the owner of a referred NFT may explicitly control which external NFTs are permitted to refer to it.

This ERC defines a minimal authorization interface for that purpose. It enables:

-   authorization between NFTs from arbitrary [ERC-5521](./eip-5521.md) contracts;
-   owner-controlled consent for referred NFTs;
-   gasless authorization through off-chain signatures;
-   deployment as a standalone registry or auxiliary module.

This ERC does not define the referral relationship itself. It defines only how authorization for such a relationship is granted, revoked, and queried.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.



### Interface

This ERC standardizes an authorization interface for referral relationships between arbitrary [ERC-5521](./eip-5521.md) tokens. It does not itself create, store, or enforce a referral relationship.

For the purposes of this ERC:

-   a **referred NFT** is the NFT being referred to;
-   a **referring NFT** is the NFT that seeks to refer to the referred NFT.

A compliant implementation MUST expose the following interface:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

/// @title Referable NFTs with Authorization
interface IAuthorizedReferral is ERC165 {
    /// @notice Emitted when a referral authorization is updated
    event ReferralAuthorizationSet(
        address indexed referredContract,
        uint256 indexed referredTokenId,
        address indexed authorizedContract,
        uint256 authorizedTokenId,
        bool authorized
    );

    /// @notice Check if a referral is authorized
    /// @param referredContract The contract address of the referred NFT
    /// @param referredTokenId The token ID of the referred NFT
    /// @param authorizedContract The contract address of the referring NFT
    /// @param authorizedTokenId The token ID of the referring NFT
    function isReferralAuthorized(
        address referredContract,
        uint256 referredTokenId,
        address authorizedContract,
        uint256 authorizedTokenId
    ) external view returns (bool);

    /// @notice Set referral authorization directly on-chain
    /// @dev Only callable by the owner of the referred NFT
    function setReferralAuthorization(
        address referredContract,
        uint256 referredTokenId,
        address authorizedContract,
        uint256 authorizedTokenId,
        bool authorized
    ) external;

    /// @notice Set referral authorization using an EIP-191 off-chain signature
    /// @dev Anyone can call this method with a valid signature from the referred NFT's owner
    function setReferralAuthorization(
        address referredContract,
        uint256 referredTokenId,
        address authorizedContract,
        uint256 authorizedTokenId,
        bytes calldata signature,
        bool authorized
    ) external;
    
    function supportsReferenceRoyalties() external view returns (bool);
}
```

### Authorization Semantics

If `isReferralAuthorized(referredContract, referredTokenId, referringContract, referringTokenId)` returns `true`, the current authorization state indicates that the referred NFT permits the specified referring NFT to establish or claim a referral relationship, subject to the logic of the consuming application or protocol.

This ERC does not mandate how a referral relationship is materialized, displayed, interpreted, or enforced. Applications that integrate this ERC MUST define how authorization state is consumed.

### Direct Authorization

For direct authorization, the caller of `setReferralAuthorization(...)` MUST be either:

-   the current owner of the referred NFT; or
-   an address approved to manage that token under ERC-5521.

A successful call to `setReferralAuthorization(...)` MUST update the current authorization state for the specified `(referred NFT, referring NFT)` pair and MUST emit `ReferralAuthorizationUpdated`.

### Signature-Based Authorization

A successful call to `setReferralAuthorizationBySig(...)` MUST satisfy all of the following conditions:

-   the recovered signer is the current owner of the referred NFT at execution time;
-   `nonce` matches the current nonce of the referred NFT;
-   the current block timestamp is less than or equal to `deadline`;
-   the signature is valid for the supplied authorization parameters.

A compliant implementation MUST consume or increment the nonce associated with the referred NFT whenever a signature-based authorization is successfully processed.

A successful call to `setReferralAuthorizationBySig(...)` MUST update the current authorization state for the specified `(referred NFT, referring NFT)` pair and MUST emit `ReferralAuthorizationUpdated`.

### Signature Message

Off-chain authorization signatures MUST be produced by the current owner of `referredContract:referredTokenId` over the following fields:

-   `referredContract`
-   `referredTokenId`
-   `referringContract`
-   `referringTokenId`
-   `authorized`
-   `nonce`
-   `deadline`
-   `chainId`
-   `verifyingContract`

One [EIP-191](./eip-191.md)-compatible message construction is:

```
keccak256(  
    abi.encodePacked(  
        "\x19Ethereum Signed Message:\n32",  
        keccak256(  
            abi.encode(  
                referredContract,  
                referredTokenId,  
                referringContract,  
                referringTokenId,  
                authorized,  
                nonce,  
                deadline,  
                chainId,  
                verifyingContract  
            )  
        )  
    )  
);
```

-   `nonce` prevents replay and MUST be unique per referred NFT;
-   `deadline` limits the validity period of the signature;
-   `chainId` prevents cross-chain replay;
-   `verifyingContract` binds the signature to a specific implementing contract.

### Ownership Change Semantics

Authorization under this ERC represents consent from the current owner of the referred NFT.

If ownership of the referred NFT changes before a signature-based authorization is submitted, the signature MUST be treated as invalid.

Implementations MUST define whether previously stored on-chain authorizations persist across transfer. For interoperability, this ERC RECOMMENDS that a transfer of the referred NFT invalidate prior authorizations associated with that token, unless the new owner explicitly re-authorizes them.

## Rationale

This ERC is intentionally limited to authorization. It does not define a canonical data model for referral relationships. This keeps the interface small and allows the ERC to be used across arbitrary ERC-5521 contracts, including existing collections that were not designed with referral functionality in mind.

A separate authorization interface is useful because it:

-   allows owner-side consent for referred NFTs;
-   supports cross-contract referral use cases;
-   can be deployed as a standalone registry or auxiliary module.

Separate entry points are defined for direct authorization and signature-based authorization. This makes the interface easier to implement, audit, and integrate than an overloaded method design.

Both `referredContract` and `referringContract` are explicit parameters so that authorization can be expressed across arbitrary ERC-5521 contracts.

This ERC specifies an EIP-191-compatible signature format for simplicity and broad compatibility. Implementations MAY additionally support [EIP-712](./eip-712.md)-compatible signing, but they MUST clearly document the canonical digest used for interoperability.

## Backward Compatibility

This ERC does not require any modification to existing ERC-721 token contracts. It may be implemented as a standalone registry, middleware contract, or auxiliary module.

This ERC does not replace ERC-5521. Instead, it standardizes an external authorization layer that may be used by systems implementing referral-capable NFTs, including legacy ERC-721 collections that cannot be modified. Such systems MAY consult this ERC before accepting or materializing a referral claim.

## Reference Implementation

A reference implementation may maintain authorization state as a mapping keyed by:

-   referred contract address;
-   referred token ID;
-   referring contract address;
-   referring token ID.

A reference implementation may maintain one nonce per referred NFT for signature-based authorization.

## Security Considerations

-   Signature replay protection MUST be enforced through a nonce scoped to each referred NFT.
-   Signature-based authorization MUST verify that the recovered signer is the current owner of the referred NFT at execution time.
-   Expired signatures MUST be rejected.
-   If ownership of the referred NFT changes before a signed authorization is submitted, the signature MUST be treated as invalid.
-   Because any address may relay a valid signature, applications MUST assume that signature submission may be front-run.
-   Authorization updates and revocations may race in the mempool. Applications that depend on authorization state SHOULD rely on final on-chain state rather than off-chain intent alone.
-   If multiple registries implementing this ERC exist, applications MUST define which registry they trust, because authorization state may differ across registries.
-   Implementations SHOULD consider storage-growth risks arising from unbounded authorization records.
-   Implementations SHOULD use safe signature recovery procedures and reject malformed or ambiguous signatures.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).