---
eip: 8084
title: ZKMeta Metadata Interface
description: Define a minimal, universal interface for zero-knowledge proof metadata discoverable by Ethereum contracts and tooling.
author: cococay (@zwowo1997)
discussions-to: https://ethereum-magicians.org/t/eip-0000-standardized-zk-metadata-interface/26511
status: Draft
type: Standards Track
category: ERC
created: 2025-11-10
---

## Abstract

This standard formalizes **ERC-ZKMeta**, a minimal interface for contracts that verify or depend on zero-knowledge proofs. It defines how to expose a proof-system identifier, circuit identifier, circuit version, public-input schema (hash and URI), and verification-key URI. The goal is to enable interoperable wallet, relayer, explorer, rollup, and dApp tooling without prescribing any specific proof format.

## Motivation

Projects today use Groth16, Plonk, Halo2, zkSTARKs, zkVMs, and hybrids—each with different encodings for proofs, public inputs, verification keys, and versioning. As a result, integrators cannot reliably determine:
- how to parse a proof,
- which verification key to fetch,
- what public inputs are expected, or
- whether a circuit has changed.

**ERC-ZKMeta** standardizes metadata discovery (a “ZK ABI”) so heterogeneous systems can interoperate while leaving verification logic and proof bytes to the implementation.

## Specification

The keywords “MUST”, “MUST NOT”, “SHOULD”, and “MAY” are as in RFC 2119.

### Interface

```solidity
/// @title ERC-ZKMeta Interface
interface IZKMetadata {
    /// Emitted when any getter below would return a different value than before.
    event CircuitMetadataUpdated(bytes32 indexed circuitId, uint64 circuitVersion, bytes4 proofSystem);

    /// Content-addressed identifier of the circuit definition artifact.
    function circuitId() external view returns (bytes32);

    /// Monotonically increasing semver-style version (major.minor -> uint32.uint32 packed into uint64).
    function circuitVersion() external view returns (uint64);

    /// Hash of the canonical public-input schema document.
    function publicInputsSchemaHash() external view returns (bytes32);

    /// URI of the canonical public-input schema document.
    function publicInputsSchemaURI() external view returns (string memory);

    /// URI for verification key discovery (content-addressed or URI with trailing #hash).
    function verificationKeyURI() external view returns (string memory);

    /// Proof-system identifier (e.g., 0x0001 Groth16, 0x0002 Plonk, 0x0003 Halo2).
    function proofSystem() external view returns (bytes4);
}
```

### Proof-System Registry

| Identifier | Proof System | Notes                             |
|-----------:|--------------|-----------------------------------|
| `0x0001`   | Groth16      | BN254 (e.g., snarkjs)            |
| `0x0002`   | Plonk        | BN254 variant                     |
| `0x0003`   | Halo2        | Plonkish family                   |
| `0x0004`   | zkSTARK      | General STARK provers             |
| `0x0005`   | zkVM         | e.g., RISC-V/Jolt/RISC Zero       |

Additional identifiers MUST be proposed in the discussion thread and MUST NOT collide. Unknown identifiers SHOULD be treated as unsupported by tooling.

### Requirements

- `circuitId()` MUST be a content hash (e.g., keccak256 or multihash) of the canonical circuit artifact used to derive the verification key.
- `circuitVersion()` MUST increase upon any breaking change to constraints or public-input semantics. Projects SHOULD use the high 32 bits for major and low 32 bits for minor.
- `publicInputsSchemaHash()` MUST match the document at `publicInputsSchemaURI()`.
- `publicInputsSchemaURI()` and `verificationKeyURI()` SHOULD be content-addressed (`ipfs://`, `ar://`, `bzz://`) or HTTPS with an appended `#<hex-hash>` fragment.
- `CircuitMetadataUpdated` SHOULD be emitted in the same transaction that makes new metadata observable.

### Recommendations

1. **Content addressing**  
   Prefer IPFS/Arweave/Swarm CIDs or HTTPS with `#hash` to ensure immutability and reproducibility.

2. **Versioning discipline**  
   Treat schema or circuit constraint changes as *major*; cosmetic or doc updates as *minor*.

3. **Indexing**  
   Indexers and explorers SHOULD subscribe to `CircuitMetadataUpdated` instead of polling getters.

## Rationale

- **Hash + URI for schemas/keys** enables automatic discovery while preserving integrity.
- **Event-based updates** let tooling react to changes without polling.
- **Compact `bytes4` proof-system code** minimizes calldata while remaining extensible.
- **Proof-system neutrality** avoids locking the ecosystem to any single proving stack.

## Backwards Compatibility

Existing contracts MAY expose an adapter that implements `IZKMetadata`. Legacy systems can deploy a read-only facade or off-chain router for downstream tooling. No existing ERCs are modified.

## Reference Implementation

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IZKMetadata {
    event CircuitMetadataUpdated(bytes32 indexed circuitId, uint64 circuitVersion, bytes4 proofSystem);
    function circuitId() external view returns (bytes32);
    function circuitVersion() external view returns (uint64);
    function publicInputsSchemaHash() external view returns (bytes32);
    function publicInputsSchemaURI() external view returns (string memory);
    function verificationKeyURI() external view returns (string memory);
    function proofSystem() external view returns (bytes4);
}

contract ZKMetadataAdapter is IZKMetadata {
    bytes32 private _cid;
    uint64  private _version;
    bytes32 private _schemaHash;
    string  private _schemaURI;
    string  private _vkURI;
    bytes4  private _ps;

    constructor(
        bytes32 cid,
        uint64 version,
        bytes32 schemaHash,
        string memory schemaURI,
        string memory vkURI,
        bytes4 proofSystemId
    ) {
        _cid = cid;
        _version = version;
        _schemaHash = schemaHash;
        _schemaURI = schemaURI;
        _vkURI = vkURI;
        _ps = proofSystemId;
        emit CircuitMetadataUpdated(_cid, _version, _ps);
    }

    function circuitId() external view returns (bytes32) { return _cid; }
    function circuitVersion() external view returns (uint64) { return _version; }
    function publicInputsSchemaHash() external view returns (bytes32) { return _schemaHash; }
    function publicInputsSchemaURI() external view returns (string memory) { return _schemaURI; }
    function verificationKeyURI() external view returns (string memory) { return _vkURI; }
    function proofSystem() external view returns (bytes4) { return _ps; }

    /// Example admin update; replace with proper access control in production.
    function _adminUpdate(
        bytes32 cid,
        uint64 version,
        bytes32 schemaHash,
        string calldata schemaURI,
        string calldata vkURI,
        bytes4 proofSystemId
    ) external {
        _cid = cid;
        _version = version;
        _schemaHash = schemaHash;
        _schemaURI = schemaURI;
        _vkURI = vkURI;
        _ps = proofSystemId;
        emit CircuitMetadataUpdated(_cid, _version, _ps);
    }
}
```

## Security Considerations

- Tooling MUST verify that `publicInputsSchemaHash()` matches the fetched schema document.
- Tooling SHOULD verify that the verification key’s content hash matches `verificationKeyURI()`’s hash fragment/CID.
- Unknown `proofSystem()` identifiers SHOULD be treated as unsupported.
- Emit `CircuitMetadataUpdated` atomically with metadata changes to avoid indexer races.

## Copyright

CC0
