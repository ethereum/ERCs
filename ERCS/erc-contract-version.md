---
eip: XXXX
title: Contract Version Interface
description: Interface for exposing a contract implementation version string
author: Ryan Sauge (@rya-sge)
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standards Track
category: ERC
created: 2026-02-12
requires: 165
---

## Abstract

This ERC defines a minimal interface to expose a contract version string through a standardized `version()` view function. The design is based on the version pattern used by [ERC-3643](./erc-3643.md), while remaining token-agnostic and applicable to other smart contract domains, including DeFi applications such as lending protocols.

## Motivation

Integrators frequently need a simple, on-chain way to identify which contract implementation they interact with. A standardized version function improves:

- integration safety (feature gating by version),
- operations (faster incident triage),
- governance and migration tracking (upgrade visibility),
- ecosystem tooling interoperability.

It is also useful for end-users, developers, and security auditors to identify which version of a codebase is currently used by a deployed contract.

The same requirement appears in permissioned token systems ([ERC-3643](./erc-3643.md)) and in DeFi systems where contracts evolve over time.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Interface

```solidity
interface IERCVersion {
    /// @notice Returns the implementation version string.
    /// @return The version value (for example "1.0.0").
    function version() external view returns (string memory);
}
```

### Required Behavior

1. **Version read**
   - `version()` MUST be a view function.
   - `version()` MUST NOT revert under normal operation.
   - `version()` MUST return a non-empty string.

2. **Version meaning**
   - Returned values SHOULD be stable and machine-comparable by off-chain tooling.
   - Returned values SHOULD follow a SemVer-like format: `MAJOR.MINOR.PATCH` using decimal integers (for example `1.0.0`, `3.2.1`).
   - The canonical recommended pattern is `^[0-9]+\.[0-9]+\.[0-9]+$`.
   - Implementations MAY define their own versioning policy, but SHOULD document it publicly.

3. **Deployment model compatibility**
   - This interface is compatible with immutable deployments and proxy-based upgradeable deployments.
   - In upgradeable systems, `version()` SHOULD reflect the active implementation seen by users and integrators.

### [ERC-165](./erc-165.md)

Implementations MUST support [ERC-165](./erc-165.md) interface discovery for this interface.

- `supportsInterface(type(IERCVersion).interfaceId)` MUST return `true`.
- The interface id for `IERCVersion` is `0x54fd4d50`.

### Compatibility Note for ERC-3643 Integrations

Integrators MAY treat legacy ERC-3643 token contracts exposing a compatible `version()` function as implementing this ERC even if they do not advertise ERC-165 support.

## Rationale

- **Minimal scope**: A single function maximizes adoption and keeps gas/runtime complexity negligible.
- **ERC-3643 alignment**: Reuses a proven pattern already used in regulated token implementations.
- **Token-agnostic design**: The interface applies to token contracts and non-token contracts alike.
- **Required ERC-165**: Standardized interface discovery ensures integrators can detect support consistently and reduce integration ambiguity.
- **`string` over `bytes32`**: A human-readable string is preferred to a fixed-size bytes32 for legibility in explorers and tooling, at the cost of marginally higher gas for the return value.

## Backwards Compatibility

This ERC is fully additive. Contracts already exposing `version()` are naturally compatible if they match the interface signature.

## Security Considerations

- `version()` is metadata and must not be used as a sole authorization primitive.
- In upgradeable systems, governance controls remain the trust anchor; version reporting does not prevent malicious upgrades.
- Integrators should combine version checks with other trust signals (governance model, audits, deployment provenance).

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
