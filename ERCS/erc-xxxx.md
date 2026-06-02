---
eip: xxxx
title: On-Chain Registry for ERC-7730 Clear Signing Descriptors
description: An open on-chain protocol-agnostic registry for ERC-7730 descriptors with EAS-backed attestations
author: Alex Forshtat (@forshtat)
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standards Track
category: ERC
created: 2026-06-01
requires: 712, 7730, 8176
---

## Abstract

This ERC defines an on-chain protocol-agnostic registry that maps structured *context IDs*, derived from [ERC-7730](./eip-7730.md) `context` binding information, to ERC-7730 descriptors and their attestations.

Descriptors' URIs may reference any content-addressed scheme (`ipfs://`, `ar://`, `bzz://`, `magnet:`, etc.) and serve as a suggested retrieval mechanism for the wallet.

Attestations are backed by the Ethereum Attestation Service per [ERC-8176](./eip-8176.md).
The registry additionally provides context-aware on-chain discoverability that EAS does not offer.

## Motivation

ERC-7730 defines a JSON descriptor format that enriches smart contract calls and EIP-712 messages with human-readable display metadata. Each descriptor carries a `context` section that binds it to specific contracts or EIP-712 domains.

The maintenance and distribution of descriptors' registry is an important component of the Clear Signing protocol and must be standardized across wallets without compromising on security or decentralization.

1. **On-chain context-keyed discovery.** Wallets can trustlessly find which descriptor applies to a given contract without querying any specific off-chain repository.

2. **Unified on-chain attestation surface.** ERC-8176 defines EAS-based attestation records, but EAS contracts have no suitable attestation lookup mechanisms.

3. **Protocol-agnostic descriptor resolution.** Attesters are free to serve the descriptors via IPFS, Swarm, BitTorrent, or any other content-addressed scheme using the `URI` parameter.

4. **Unified revocation and upgrade path.** An on-chain mechanism for an attester to atomically replace their endorsement with either a newer descriptor version or a revocation message.

### Definitions

| Term                 | Definition                                                                                                            |
|----------------------|-----------------------------------------------------------------------------------------------------------------------|
| **descriptor**       | An ERC-7730 JSON file as defined in ERC-7730                                                                          |
| **descriptorId**     | `keccak256` of the canonical UTF-8 byte sequence of the descriptor file                                               |
| **contextId**        | A `bytes32` value canonically derived from an ERC-7730 `context` binding, used as the registry lookup key             |
| **contextTypeTag**   | A `bytes32` equal to `keccak256("erc7730.context.<typename>")`, namespacing a context ID derivation rule              |
| **active slot**      | The single `(descriptorId, attestationId)` pair an attester currently endorses for a given `contextId`                |
| **attester**         | An `address` whose ERC-8176 EAS attestation has been submitted to the registry                                        |
| **attestationId**    | The EAS UID of the active ERC-8176 attestation backing an attester's endorsement                                      |
| **deployEventTopic** | The factory contract's deploy event signature `topic[0]` in Ethereum logs, e.g. `keccak256("TokenDeployed(address)")` |

Descriptor IDs are computed as `keccak256` of the canonical UTF-8 byte sequence of the descriptor file.

#### Current Tag Constants

```
CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract")
CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment")
CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator")
CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory")
```

### **Context ID** Derivation

The **Context ID** keys are computed as:

```
contextId = keccak256(abi.encode(contextTypeTag, param1, param2, …))
```

The `contextTypeTag` prefix namespaces keys so that different context binding types cannot collide regardless of parameter values.

This scheme is forward-extensible: future additions of new context binding types in ERC-7730 define new tag strings and parameter lists. The registry contract requires no upgrade; wallets derive the new key type using the new rule and query the same registry.

All context IDs are computed as `keccak256(abi.encode(contextTypeTag, params...))`, where the tag and parameter list depend on the ERC-7730 context binding type. A descriptor covering *N* deployments MUST be registered under *N* context IDs — one per deployment entry.

| ERC-7730 context type            | `params` in `abi.encode`                        |
|----------------------------------|-------------------------------------------------|
| `context.contract.deployments`   | `chainId`, `contract`                           |
| `context.contract.factory`       | `chainId`, `factoryAddress`, `deployEventTopic` |
| `context.eip712.deployments`     | `chainId`, `verifyingContract`                  |
| `context.eip712.domainSeparator` | `domainSeparator`                               |

### Data Model

The registry maintains the following mappings:

```solidity
// The current descriptor hash for the specified context ID as provided by the given attester.
// Atomically replaced on each call to 'createDescriptorAttestation'.
mapping(address attester => mapping(bytes32 contextId => bytes32)) descriptorId;

// The ERC-8176 EAS UID of the active attestation for the current descriptor by the given attester.
mapping(address attester => mapping(bytes32 contextId => bytes32)) attestationId;

// The URI array for fetching the descriptor file, supplied by the given attester.
mapping(address attester => mapping(bytes32 descriptorId => string[])) attesterURIs;
```

### Interface

The full normative interface is provided in [`../assets/eip-8258/IERC8258.sol`](../assets/eip-8258/IERC8258.sol).

#### `createDescriptorAttestation(bytes32 descriptorId, bytes32[] contextIds, string[] uris, MultiDelegatedAttestationRequest[] attestations, MultiDelegatedRevocationRequest[] revocations) returns (bytes32 attestationId)`

The primary write function that calls `eas.multiAttestByDelegation(attestations)` to create all attestations on-chain, then calls `eas.multiRevokeByDelegation(revocations)` to revoke any previously active attestations that are being replaced.

Any address may permissionlessly call this function, and the attester identity is taken from `attestations[0].attester`.

The `attestations` parameter supports multiple EAS attestation requests in a single transaction, however `attestations[0]` MUST use the ERC-8176 schema UID, and `attestations[0].data[0].data` MUST ABI-decode to `bytes32` equal to `descriptorId`.
All other entries in the batch are supplementary and are passed through to EAS without registry-level validation.

The `uris` parameter MUST NOT be empty.

The `revocations` parameter MAY be empty on first registration. When an attester already has an active attestation for any of the supplied `contextIds`, the corresponding attestation UID MUST appear in the `revocations` batch; otherwise the call reverts with `MissingRevocation`.

The returned `attestationId` is `uids[0]` — the first element of the flat `bytes32[]` returned by `eas.multiAttestByDelegation`. Because `multiAttestByDelegation` returns UIDs in insertion order (one per `data[]` entry, across all requests), `uids[0]` always corresponds to `attestations[0].data[0]`, making the convention unambiguous.

Wallets MUST independently validate the descriptor's `context` section against the actual transaction before applying any formatting, per ERC-7730 Binding context format rules.

#### `updateURIs(bytes32 descriptorId, string[] uris)`

Replaces the URI list for `(msg.sender, descriptorId)`. Only callable after `msg.sender` has successfully called `createDescriptorAttestation` for this `descriptorId`. Allows attesters to update retrieval endpoints without creating a new EAS attestation. The `uris` parameter MUST NOT be empty.

#### `getDescriptors(address[] attesters, bytes32 contextId)`

Returns parallel arrays `(descriptorIds[], attestationIds[])` — the active slot values for each attester in `attesters` for the given `contextId`.

This function is the primary wallet-facing query entry point that resolves the full trusted-attester list.

### Descriptor files URIs

URI lists are stored per `(attester, descriptorId)`, and only attesters that have previously called `createDescriptorAttestation` for a given `descriptorId` may write URIs for that ID.

This ensures the retrieved URIs list size is bounded by the number of trusted attesters, which should be a small, accountable set, preventing DoS attacks.

Retrieving the descriptors from the published URIs is never the source of trust, and wallets MUST verify attestations' cryptographic signatures before using any descriptor. 

## Rationale

### EAS as the sole attestation authority

Having two parallel attestation mechanisms, native and EAS, would mean the same information is stored in two places.

EAS provides on-chain `attest()` and `revoke()` with full lifecycle guarantees.

The registry adds the context-keyed discovery surface that EAS itself does not provide.

### Mainnet-only deployment

The registry is deployed on Ethereum mainnet only.

Context IDs encode `chainId`, so a single registry can serve wallets operating on any EVM chain.

The ERC-7730 descriptors format is designed to cover all deployments on all EVM-compatible chains.

## Security Considerations

### Malicious registration

Any address can call `createDescriptorAttestation` with their own EAS attestation.

Wallets only query active slots for their configured `trustedAttesters`.

An unknown attacker's address will never appear in a trusted list, so their slot is invisible to wallets.

Registration is permissionless precisely because it is harmless without trusted attester endorsement.

### Attester key compromise

If a trusted attester's key is compromised, an attacker can create a malicious EAS attestation and call `createDescriptorAttestation`.

Attesters SHOULD use secure setup multisig accounts or governance contracts rather than EOAs.

Wallet vendors SHOULD publish their trusted attester addresses and key rotation procedures.

### EAS attestation revoked after slot update (staleness)

An attester may revoke their EAS attestation directly after calling `createDescriptorAttestation`. The registry's active slot continues to point to the revoked attestation until cleared by the caller.

### Atomicity of slot replacement and revocation

When `createDescriptorAttestation` replaces an existing active slot, the registry requires that every displaced attestation UID is present in the supplied `revocations` batch. This prevents a permissionless relay from silently updating a slot while leaving a stale active attestation on EAS.

### Caller asserts incorrect context IDs

The caller provides `contextIds` that the registry cannot verify against the off-chain JSON descriptor.

A malicious or mistaken caller could associate a descriptor for contract A under the context ID for contract B.

## Backwards Compatibility

This ERC introduces a new contract interface and makes no modifications to ERC-7730 or ERC-8176.

ERC-7730 descriptor files require no changes. The context section fields used for context ID derivation are already present in all compliant descriptors.

## Reference Implementation

The reference implementation is provided in two files:

- [`../assets/eip-8258/IERC8258.sol`](../assets/eip-8258/IERC8258.sol) — the normative interface
- [`../assets/eip-8258/ERC8258Registry.sol`](../assets/eip-8258/ERC8258Registry.sol) — the reference implementation

Both files are provided under CC0. The reference implementation is not audited and is intended for specification clarity only; production deployments SHOULD undergo independent security review.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
