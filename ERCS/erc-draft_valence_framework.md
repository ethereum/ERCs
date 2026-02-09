---
eip: XXXX
title: Kernel-Orchestrated Modular Smart Contracts (Valence Framework)
description: A kernel-based module lifecycle and orchestration protocol for Diamond proxies, enabling self-describing, runtime-evolvable smart contract systems.
author: Zakaryae Boudi (@zakaryaeboudittv)
discussions-to: https://ethereum-magicians.org/t/eip-xxxx-kernel-orchestrated-modular-contracts
status: Draft
type: Standards Track
category: ERC
created: 2026-02-09
requires: 2535, 7201
---

## Abstract

This EIP defines an interface and lifecycle protocol for kernel-orchestrated modular smart contract systems built on [EIP-2535](./eip-2535.md) Diamond proxies. It introduces the concept of self-describing modules called **Orbitals**, each of which declares its identity, semantic version, storage schema hash, and exported function selectors as first-class on-chain metadata. A minimal, stable kernel governs module installation, upgrade, and removal through a lifecycle with explicit boot, migration, and teardown hooks. By combining [EIP-2535](./eip-2535.md) proxy routing with [EIP-7201](./eip-7201.md) namespaced storage and a manifest-driven module interface (`IValenceModule`), this proposal collapses the unit of smart contract composition into a single, self-describing auditable contract, shifting modularity from convention to protocol.

## Motivation

Existing modular smart contract architectures, including proxy-based upgradeability patterns like the Diamond proxy ([EIP-2535](./eip-2535.md)) and various multi-facet composition approaches, have successfully addressed the challenge of upgradeable on-chain systems. However, they were designed for a world where the full set of behaviors is known at deployment time and changes are infrequent, carefully planned events.

A new class of requirements is emerging as decentralized systems increasingly interact with autonomous AI agents, algorithmic governance engines, and machine-driven decision systems. These requirements expose three structural limitations of current approaches:

1. **Coordination overhead.** Conventional modular architectures decompose a module into multiple coordinated artifacts—interfaces, storage libraries, internal logic, wrappers—that must be kept in sync. As systems grow, keeping these artifacts aligned becomes the dominant source of operational risk. Version skew, silent storage drift, and brittle upgrade scripts are recurring failure modes—not edge cases.

2. **Lack of machine-legible metadata.** Current proposals do not require modules to self-describe their version, storage layout, or callable surface in a way that external agents—human or AI—can programmatically inspect and reason about. This makes automated orchestration, compatibility checking, and marketplace discovery impractical.

3. **Static composition model.** Existing frameworks treat post-deployment evolution as an exceptional operation requiring bespoke upgrade scripts. In AI-first contexts, smart contracts must support additive evolution as a native operation, where new behavior is layered alongside existing logic rather than replacing it wholesale.

This EIP addresses these limitations by defining a minimal, interoperable protocol for kernel-orchestrated modular contracts that treats runtime evolution, machine-legible module metadata, and lifecycle management as first-class primitives.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Architecture Overview

A Valence system consists of three principal components:

1. **ValenceDiamond (Proxy):** A minimal [EIP-2535](./eip-2535.md) compliant proxy contract that routes external calls to the kernel or installed modules via selector-based dispatch. The proxy MUST delegate all non-fallback logic to registered facets.

2. **ValenceKernel (Core Facet):** The system control plane responsible for module lifecycle management (install, upgrade, remove), selector routing, access control enforcement, and deployment plan execution. The kernel MUST be the sole authority for modifying the Diamond's facet registry.

3. **Orbitals (Modules):** Self-describing contracts that implement the `IValenceModule` interface. Each Orbital declares its `moduleId`, `version`, `schemaHash`, and `exportedSelectors`. Orbitals are plugged into the Diamond via the kernel's lifecycle operations.

```
                    ┌─────────────────────┐
                    │   ValenceDiamond    │
                    │   (Proxy Contract)  │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │   ValenceKernel     │
                    │   (Core Logic)      │
                    │                     │
                    │ • Module Lifecycle  │
                    │ • Diamond Cut       │
                    │ • Access Control    │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │  Module A   │     │  Module B   │     │  Module N   │
    │  (Orbital)  │     │  (Orbital)  │     │  (Orbital)  │
    └─────────────┘     └─────────────┘     └─────────────┘
```

### IValenceModule Interface

Every module (Orbital) MUST implement the following interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IValenceModule {
    /// @notice Unique identifier for this module type
    /// @return A bytes32 identifier (e.g., keccak256 of a human-readable name)
    function moduleId() external pure returns (bytes32);

    /// @notice Semantic version encoded as uint64
    /// @dev Format: MAJOR * 1_000_000 + MINOR * 1_000 + PATCH
    /// @return Version number (e.g., 1_000_001 for v1.0.1)
    function moduleVersion() external pure returns (uint64);

    /// @notice Hash of the module's storage layout schema
    /// @return keccak256 hash of the storage struct definition
    function schemaHash() external pure returns (bytes32);

    /// @notice List of function selectors this module exports
    /// @return Array of bytes4 selectors to be registered in the Diamond
    function exportedSelectors() external pure returns (bytes4[] memory);

    /// @notice Called by the kernel when the module is first installed
    /// @param config ABI-encoded initialization parameters
    function boot(bytes calldata config) external;

    /// @notice Called by the kernel when upgrading from a previous version
    /// @param config ABI-encoded migration parameters
    function onUpgrade(bytes calldata config) external;

    /// @notice Called by the kernel before the module is removed
    /// @param config ABI-encoded teardown parameters
    function onRemove(bytes calldata config) external;
}
```

### Module Metadata Requirements

- **`moduleId()`:** MUST return a unique `bytes32` identifier. It is RECOMMENDED to derive this as `keccak256` of a reverse-DNS style name (e.g., `keccak256("fevertokens.module.bond")`).

- **`moduleVersion()`:** MUST return a `uint64` encoding semantic versioning as `MAJOR * 1_000_000 + MINOR * 1_000 + PATCH`. The kernel MUST reject upgrades where the new version is not strictly greater than the installed version.

- **`schemaHash()`:** MUST return `keccak256` of the canonical string representation of the module's storage struct. This enables the kernel and external tooling to detect storage layout changes across versions.

- **`exportedSelectors()`:** MUST return the complete list of function selectors the module exposes for external calls. The kernel registers these selectors in the Diamond's facet mapping during installation.

### Storage Model

Modules MUST use [EIP-7201](./eip-7201.md) namespaced storage to prevent slot collisions. Each module MUST compute its storage slot as:

```solidity
bytes32 constant STORAGE_SLOT = keccak256(
    abi.encode(
        uint256(keccak256("namespace.storage.ModuleName")) - 1
    )
) & ~bytes32(uint256(0xff));
```

This ensures deterministic, collision-free storage allocation across independently developed modules. Modules MUST NOT write to storage slots outside their declared namespace.

### Kernel Lifecycle Operations

The kernel MUST support the following lifecycle operations:

#### `install(address module, bytes calldata config)`

1. MUST verify the module implements `IValenceModule`.
2. MUST verify no selector collision exists with already-installed modules.
3. MUST register the module's exported selectors in the Diamond's facet mapping.
4. MUST call `boot(config)` via `delegatecall` to initialize module state.
5. MUST record the module's `moduleId`, `version`, and `schemaHash` in the kernel registry.
6. MUST emit a `ModuleInstalled(bytes32 moduleId, address implementation, uint64 version)` event.

#### `upgrade(address newModule, bytes calldata config)`

1. MUST verify the new module has the same `moduleId` as the existing installation.
2. MUST verify the new module's version is strictly greater than the installed version.
3. MUST replace the old module's selectors with the new module's selectors in the facet mapping.
4. MUST call `onUpgrade(config)` via `delegatecall` for state migration.
5. MUST emit a `ModuleUpgraded(bytes32 moduleId, address newImpl, uint64 oldVersion, uint64 newVersion)` event.

#### `remove(bytes32 moduleId, bytes calldata config)`

1. MUST call `onRemove(config)` via `delegatecall` for cleanup.
2. MUST remove all of the module's selectors from the Diamond's facet mapping.
3. MUST delete the module's entry from the kernel registry.
4. MUST emit a `ModuleRemoved(bytes32 moduleId, address implementation)` event.

### Access Control

The kernel MUST enforce access control on all lifecycle operations (install, upgrade, remove). This EIP defines an `IAuthority` interface that the kernel delegates authorization checks to:

```solidity
interface IAuthority {
    function canCall(
        address caller,
        address target,
        bytes4 selector
    ) external view returns (bool);
}
```

The reference implementation provides an `OwnableAuthority` that restricts lifecycle operations to the contract owner. Implementers MAY substitute more sophisticated authority contracts (multi-sig, DAO governance, role-based) provided they conform to the `IAuthority` interface.

### Events

Compliant implementations MUST emit the following events:

```solidity
event ModuleInstalled(bytes32 indexed moduleId, address implementation, uint64 version);
event ModuleUpgraded(bytes32 indexed moduleId, address newImplementation, uint64 oldVersion, uint64 newVersion);
event ModuleRemoved(bytes32 indexed moduleId, address implementation);
event AuthorityUpdated(address indexed oldAuthority, address indexed newAuthority);
```

## Rationale

### Contract-as-Manifest over Multi-Artifact Modules

Traditional modular smart contract designs decompose a module into several coordinated files: interface definitions, internal logic, storage libraries, wrappers, and external facades. While this enforces separation of concerns, it creates a coordination cost that scales non-linearly with system size. Valence collapses the unit of composition into a single contract that self-describes its metadata through an interface. This is not a reduction in rigor but a relocation of it: the invariants that were previously maintained by developer convention (naming, file structure, import discipline) are now enforced by the kernel at the protocol level.

### Semantic Versioning On-Chain

Encoding semantic versions as `uint64` (`MAJOR * 1_000_000 + MINOR * 1_000 + PATCH`) enables the kernel to enforce monotonic version progression using simple integer comparison. This eliminates an entire class of upgrade errors where stale or incompatible module versions are accidentally installed. The `schemaHash` further allows tooling to detect storage layout changes that could cause data corruption.

### Lifecycle Hooks over Bespoke Scripts

The `boot`/`onUpgrade`/`onRemove` lifecycle hooks define the three critical moments in a module's existence: initialization, migration, and teardown. By making these hooks part of the module interface rather than external scripts, the lifecycle becomes auditable, testable, and predictable—for both human operators and automated agents.

### AI-First Architectural Alignment

The deeper motivation behind this proposal is alignment with AI-first development patterns. In systems where autonomous agents manage treasuries, execute governance, or adapt risk parameters, the control surface must be explicit, enumerable, and machine-legible. Valence modules advertise exactly the metadata that agents need to inspect, reason about, and act upon a system: what functions are available, what version is running, and what the storage layout looks like. The additive evolution model—layering new modules alongside existing ones—aligns with how AI systems evolve by adding new policies or strategies rather than mutating existing ones.

### Module Marketplace Suitability

The self-describing nature of Orbitals makes them naturally suited to module marketplaces and registries. Stable identifiers, semantic versions, schema hashes, and explicit callable surfaces provide exactly the metadata that marketplace tooling requires for discovery, compatibility checking, and safe integration. The kernel acts as a universal integration point, eliminating the need for idiosyncratic assembly logic or bespoke adapters.

## Backwards Compatibility

This EIP is fully backwards compatible with [EIP-2535](./eip-2535.md). A Valence system is a valid Diamond: the proxy routes calls via selector-based dispatch, and the kernel performs DiamondCut operations internally. Existing Diamond tooling (loupes, explorers) can inspect Valence systems without modification.

This EIP extends [EIP-2535](./eip-2535.md) by adding a mandatory module metadata interface (`IValenceModule`) and formalizing the lifecycle through the kernel. Existing Diamond facets that do not implement `IValenceModule` cannot be installed through the kernel's lifecycle operations but remain compatible with direct DiamondCut operations for migration purposes.

This EIP builds on [EIP-7201](./eip-7201.md) for storage namespacing. Modules MUST use [EIP-7201](./eip-7201.md) slot derivation to ensure collision-free storage.

## Reference Implementation

A complete reference implementation is available at: [https://github.com/FeverTokens-Labs/Valence](https://github.com/FeverTokens-Labs/Valence)

The reference implementation includes:

- **ValenceDiamond.sol** — Minimal [EIP-2535](./eip-2535.md) proxy with kernel-first routing
- **ValenceKernel.sol** — Core facet implementing install/upgrade/remove lifecycle with access control and reentrancy protection
- **IValenceModule.sol** — The module interface as specified in this EIP
- **OwnableAuthority.sol** — Reference access control implementation
- **BondOrbital example** — Complete bond issuance system demonstrating the module pattern in a real-world financial use case

## Security Considerations

### Kernel as Trust Boundary

The kernel becomes the critical trust boundary in a Valence system. All module lifecycle operations pass through the kernel, making it the single point that must be secured. Implementers MUST ensure the kernel's access control is correctly configured before any modules are installed. A compromised authority contract would allow arbitrary module installation, potentially replacing critical system logic.

### Delegatecall Risks

Module functions execute via `delegatecall` in the Diamond proxy's storage context. Malicious or buggy modules could corrupt storage belonging to other modules if they write outside their [EIP-7201](./eip-7201.md) namespace. The `schemaHash` mechanism provides a detection layer but does not enforce isolation at the EVM level. Implementers SHOULD perform thorough audits of all modules before installation and SHOULD consider formal verification for critical modules.

### Reentrancy

The reference implementation includes reentrancy guards on state-modifying kernel operations. Implementers MUST protect lifecycle operations (install, upgrade, remove) against reentrancy attacks, as a reentering call during module installation could leave the system in an inconsistent state.

### Selector Collision

The kernel MUST check for selector collisions during installation and upgrade operations. Two modules exporting the same selector MUST NOT be simultaneously installed. Implementers SHOULD use the `exportedSelectors()` function to pre-validate compatibility before on-chain transactions.

### Upgrade Safety

The kernel enforces monotonic version progression to prevent downgrade attacks. However, the `onUpgrade` hook executes arbitrary migration logic. Implementers MUST audit migration code with the same rigor as the module logic itself, as a faulty migration could corrupt state irrecoverably.

### Storage Layout Evolution

When a module's storage schema changes between versions (indicated by a different `schemaHash`), the `onUpgrade` hook is responsible for migrating state. Implementers MUST ensure that storage additions are append-only (new fields added at the end of the struct) or that explicit migration logic handles reordering. The [EIP-7201](./eip-7201.md) slot derivation ensures that different modules cannot accidentally overwrite each other's storage, but it does not protect against intra-module layout changes.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
