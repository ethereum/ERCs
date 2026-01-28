---
eip: 8139
title: Authorization Objects (AO)
description: A portable, revocable EIP-712 authorization primitive that exists independently of execution.
author: Mats Heming Julner (@recurmj)
discussions-to: https://ethereum-magicians.org/t/erc-8139-authorization-objects/27608
status: Draft
type: Standards Track
category: ERC
created: 2026-01-27
requires: 712
---

## Abstract

This EIP defines an **Authorization Object (AO)**: an [EIP-712](./eip-712.md) typed struct describing a *time-bounded, revocable permission* granted by a **grantor** to a **grantee**, within an application-defined **scope**.

An AO is:

- signed off-chain by the **grantor**,
- specifies the **grantee**, **scope**, **validity window**, and **nonce**,
- portable across chains and consumers that adopt the same type,
- revocable by invalidating the authorization prior to (or independent of) any execution.

This EIP defines **no execution semantics**. It does not specify when, how, or whether any action occurs.

## Motivation

Most systems implicitly conflate **authorization** with **execution**.

Permission is often represented indirectly (approvals, implicit allowances, session keys, credentials) and becomes difficult to inspect, revoke, audit, or compose across systems. In practice this leads to:

- one-shot permissions that cannot be inspected or revoked,
- continuous allowances that are too broad or too long-lived,
- execution systems inferring intent indirectly,
- time acting as a de facto authority via scheduling and automation coupling.

What is missing is a **general, chain-agnostic authorization primitive** that:

- encodes explicit consent in a single signed payload,
- is inspectable and independently verifiable as a persistent object,
- can be revoked without implying execution,
- allows application-specific interpretation via a scoped field.

This EIP specifies such a primitive and its hashing rules, so that:

- registries and observers can index authorizations consistently,
- wallets can display and reason about permission state,
- downstream standards can define *profiles* that interpret `scope` without redefining the primitive.

## Specification

### 1. EIP-712 Type Definition

The canonical type for an Authorization Object is:

~~~text
Authorization(
  address grantor,
  address grantee,
  bytes32 scope,
  uint256 validAfter,
  uint256 validBefore,
  bytes32 nonce
)
~~~

Where:

- `grantor`: address providing consent.
- `grantee`: address permitted within the stated scope.
- `scope`: application-defined scope identifier. This EIP treats `scope` as opaque.  
  Profiles MAY define semantics for `scope`.
- `validAfter`: unix timestamp (seconds) from which this authorization becomes valid (inclusive).
- `validBefore`: unix timestamp (seconds) after which this authorization is no longer valid (exclusive).
- `nonce`: unique value chosen by the grantor for replay protection and revocation identity.

#### TYPEHASH (normative)

The canonical `AO_TYPEHASH` MUST be:

~~~solidity
bytes32 constant AO_TYPEHASH = keccak256(
  "Authorization(address grantor,address grantee,bytes32 scope,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
);
~~~

#### Struct Hash (normative)

Given:

~~~solidity
struct Authorization {
    address grantor;
    address grantee;
    bytes32 scope;
    uint256 validAfter;
    uint256 validBefore;
    bytes32 nonce;
}
~~~

The struct hash MUST be computed as:

~~~solidity
function _aoStructHash(Authorization memory a) internal pure returns (bytes32) {
    return keccak256(
        abi.encode(
            AO_TYPEHASH,
            a.grantor,
            a.grantee,
            a.scope,
            a.validAfter,
            a.validBefore,
            a.nonce
        )
    );
}
~~~

The EIP-712 digest is then:

~~~solidity
bytes32 digest = keccak256(
    abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        _aoStructHash(auth)
    )
);
~~~

where `domainSeparator` is as defined in EIP-712 by the verifying contract (typically an AO registry or consumer contract).

### 2. Identity and Nonce Semantics

This EIP defines requirements on identity and replay behavior, but does not prescribe storage layout.

Normative requirements:

1. `nonce` MUST be treated as **single-use** in the context of a given `(grantor, domainSeparator)`.

2. Implementations SHOULD treat `(grantor, nonce)` as a unique pair for purposes of:
   - “used” tracking (if applicable), and/or
   - revocation tracking (MUST be supported, see below).

3. Consumers that use AO signatures for authorization MUST ensure replay safety by checking that the authorization has not been revoked for the relevant `(grantor, nonce)` and domain.

### 3. Revocation Model

This EIP defines **requirements on revocation semantics**, but does not prescribe storage layout. Implementations MAY use:

- a shared registry contract (recommended),
- local per-consumer storage, and/or
- wallet-maintained revocation maps.

Normative requirements:

1. Grantors MUST be able to revoke any authorization (identified by `nonce`) prior to (or independent of) any execution.

2. Consumers MUST check revocation status at the time they evaluate an AO, via one or more of:
   - a shared registry e.g., `isRevoked(grantor, nonce)`, and/or
   - a local cancel mapping keyed by `(grantor, nonce)`.

3. Consumers MUST treat revoked authorizations as invalid.

### 4. Optional Registry Interface (Recommended)

This EIP RECOMMENDS a minimal registry/observer interface to standardize on-chain publication and revocation of AO state.

Compliant registry contracts SHOULD implement the following Solidity interface (or an ABI-compatible equivalent):

~~~solidity
pragma solidity ^0.8.20;

interface IAuthorizationObjectRegistry {
    struct Authorization {
        address grantor;
        address grantee;
        bytes32 scope;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    // Views

    /// @notice EIP-712 domain separator used for Authorization digests.
    function domainSeparator() external view returns (bytes32);

    /// @notice Returns true if the authorization nonce has been revoked by the grantor.
    function isRevoked(address grantor, bytes32 nonce) external view returns (bool);

    // Mutations

    /// @notice Records observation/registration of an Authorization Object.
    ///         This function MUST NOT imply execution.
    /// @dev Registry MAY validate signature and emit an event.
    function observe(
        Authorization calldata auth,
        bytes calldata signature
    ) external;

    /// @notice Revokes an authorization nonce for msg.sender.
    function revoke(bytes32 nonce) external;

    // Events

    event AuthorizationObserved(
        address indexed grantor,
        address indexed grantee,
        bytes32 indexed scope,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes32 structHash
    );

    event AuthorizationRevoked(
        address indexed grantor,
        bytes32 indexed nonce
    );

    // Errors

    error BadSignature();
    error ZeroAddress();
    error NotYetValid();
    error Expired();
    error Revoked();
}
~~~

#### Registry Behavior (Normative)

A registry implementation of `observe` MUST:

1. Compute `structHash` using `_aoStructHash` as specified above.
2. Compute `digest = keccak256("\x19\x01" || domainSeparator() || structHash)`.
3. Recover signer from `digest` and `signature`.
4. Signer MUST equal `auth.grantor`, otherwise revert `BadSignature()`.

Registries MAY enforce additional checks (e.g., time window sanity, nonzero addresses), but MUST NOT introduce execution semantics.

A registry implementation of `revoke` MUST:

- mark `(msg.sender, nonce)` as revoked, and
- emit `AuthorizationRevoked(msg.sender, nonce)`.

### 5. Profiles

Authorization Objects are intentionally generic.

Domain-specific standards MAY define **profiles** that interpret `scope` according to application-specific rules (e.g., token pulls, agent delegation, API access), without modifying the AO primitive or its hashing rules.

## Rationale

- **Primitive-first**: Defines authorization as a portable object independent of execution.
- **EIP-712 typed structure**: Enables wallet UX, human review, and signature portability.
- **Opaque `scope`**: Allows domain specialization via profiles without fragmenting the primitive.
- **Revocation as first-class**: Ensures authorization can be invalidated without implying action.

## Backwards Compatibility

This EIP is additive. It does not modify existing token standards or account models.

Downstream standards MAY map existing permission mechanisms into AO-compatible representations.

## Security Considerations

- Consumers MUST implement replay safety and revocation checks appropriate to their domain.
- Implementations SHOULD enforce EIP-2 signature rules (low-s) and validate `v` values to reduce malleability risk.
- Validity windows reduce exposure of leaked signatures, but key security remains critical.
- `scope` is opaque at the primitive layer; profiles MUST specify clear semantics to avoid ambiguity.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
