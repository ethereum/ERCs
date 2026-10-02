---
eip: 8303
title: Contract Version
description: Interface for exposing a contract implementation version string
author: Ryan Sauge (@rya-sge)
discussions-to: https://ethereum-magicians.org/t/erc-8303-contract-version/28795
status: Draft
type: Standards Track
category: ERC
created: 2026-02-12
---

## Abstract

This ERC defines a minimal interface to expose a contract version string through a standardized `version()` view function. The design is based on the version pattern used by [ERC-3643](./eip-3643.md), while remaining token-agnostic and applicable to other smart contract domains, including DeFi applications such as lending protocols.

## Motivation

Integrators frequently need a simple, on-chain way to identify which contract implementation they interact with. A standardized version function improves:

- integration safety (feature gating by version),
- operations (faster incident triage),
- governance and migration tracking (upgrade visibility),
- ecosystem tooling interoperability.

It is also useful for end-users, developers, and security auditors to identify which version of a codebase is currently used by a deployed contract.

The same requirement appears in permissioned token systems ([ERC-3643](./eip-3643.md)) and in DeFi systems where contracts evolve over time.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Interface

```solidity
interface IERC8303 {
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
   - Returned values SHOULD follow a Semantic Versioning 2.0.0-like format: `MAJOR.MINOR.PATCH` using decimal integers (for example `1.0.0`, `3.2.1`).
   - The canonical recommended pattern is `^[0-9]+\.[0-9]+\.[0-9]+$`.
   - Implementations MAY define their own versioning policy, but SHOULD document it publicly.

3. **Deployment model compatibility**
   - This interface is compatible with immutable deployments and proxy-based upgradeable deployments.
   - In upgradeable systems, `version()` SHOULD reflect the active implementation seen by users and integrators.

### [ERC-165](./eip-165.md)

Implementations SHOULD support [ERC-165](./eip-165.md) interface discovery for this interface.

If an implementation supports [ERC-165](./eip-165.md), `supportsInterface(type(IERC8303).interfaceId)` MUST return `true`.

- The interface id for `IERC8303` is `0x54fd4d50`.

### Compatibility Note for ERC-3643 Integrations

Integrators MAY treat legacy ERC-3643 token contracts exposing a compatible `version()` function as implementing this ERC even if they do not advertise ERC-165 support.

## Rationale

- **Minimal scope**: A single function maximizes adoption and keeps gas/runtime complexity negligible.
- **ERC-3643 alignment**: Reuses a proven pattern already used in regulated token implementations.
- **Token-agnostic design**: The interface applies to token contracts and non-token contracts alike.
- **Optional ERC-165**: ERC-165 support is recommended but not required, lowering the adoption barrier for contracts that do not implement interface discovery. When ERC-165 is supported, advertising this interface is mandatory to ensure consistent detection by integrators.
- **`string` over `bytes32`**: A human-readable string is preferred to a fixed-size bytes32 for legibility in explorers and tooling, at the cost of marginally higher gas for the return value.

## Backwards Compatibility

This ERC is fully additive. Contracts already exposing `version()` are naturally compatible if they match the interface signature.

## Test Cases

The following test cases apply to any conforming implementation.

1. `version()` MUST NOT revert.
2. `version()` MUST return a non-empty string.
3. `version()` MUST return the version string declared by the implementation (e.g. `"1.0.0"`).
4. If the contract supports [ERC-165](./eip-165.md), `supportsInterface(0x54fd4d50)` MUST return `true`.
5. If the contract supports [ERC-165](./eip-165.md), `supportsInterface(0xffffffff)` MUST return `false`.

## Reference Implementation

Reference implementations are provided in the assets folder: the [interface](../assets/erc-8303/src/IERC8303.sol) and a [base implementation](../assets/erc-8303/src/ERC8303.sol), along with usage examples for [ERC-20](../assets/erc-8303/src/examples/ERC20VersionedExample.sol) and [ERC-721](../assets/erc-8303/src/examples/ERC721VersionedExample.sol) tokens. These examples are provided for educational purposes only and are not audited.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IERC8303.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract ERC8303Example is IERC8303, ERC165 {
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return interfaceId == type(IERC8303).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
```

## Security Considerations

- `version()` is metadata and must not be used as a sole authorization primitive.
- In upgradeable systems, governance controls remain the trust anchor; version reporting does not prevent malicious upgrades.
- Integrators should combine version checks with other trust signals (governance model, audits, deployment provenance).

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
