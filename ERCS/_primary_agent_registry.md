---
eip: XXXX
title: Primary Agent Registry
description: A singleton registry that links each Ethereum address to a single agent identity, enabling any address to be resolved to the agent it represents.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-primary-agent-registry
status: Draft
type: Standards Track
category: ERC
created: 2026-02-11
requires: 1271
---

## Abstract

This ERC defines a singleton registry that maps each Ethereum address to exactly one agent identity (a registry address and token ID). It is deployed once per chain, providing a single authoritative source for resolving any address to the agent it represents.

## Motivation

AI agents are becoming active participants on Ethereum, executing transactions, interacting with protocols, and managing assets. Each agent operates through an Ethereum address, but an Ethereum address by itself says nothing about the agent behind it. Agent registries exist (such as [ERC-8004](./eip-8004.md)), but given an address, there is no standard way to determine which agent it represents. Wallets cannot display agent identity, protocols cannot verify counterparties, and indexers cannot map on-chain activity back to agents. Without a canonical registry, each application must build its own lookup, leading to inconsistent and unreliable resolution.

The Primary Agent Registry solves this by providing a singleton contract, deployed to every chain, where each Ethereum address can be linked to exactly one agent identity: a specific token ID in a specific agent registry. This creates a single source of truth for address-to-agent resolution. The permissioned registrar architecture supports multiple verification methods, from simple self-attestation for EOAs to cryptographic proof for smart contract wallets.

### Use Cases

- **Signed data and transactions**: When an agent signs data or submits a transaction, only the Ethereum address is visible. The registry allows anyone to resolve that address to the agent's identity.
- **Application connections**: When an agent connects to a dApp, the application can look up the agent identity from the connected address.
- **Address verification**: To prevent multiple agents from using the same Ethereum address, the agent's registered address can be reverse resolved to verify it belongs to that agent. 

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

The Primary Agent Registry is a singleton contract intended to be deployed at a deterministic address on every EVM chain. It stores a single mapping: `address → bytes`, where the bytes value packs the agent registry address and token ID. Each Ethereum address has at most one agent registration at a time.

Only addresses with the `REGISTRAR_ROLE` may write to the registry. This enables a flexible system where different registrar contracts implement different verification methods.

### Storage Encoding

Each registration is stored as a packed `bytes` value:

```
20 bytes: registry address | 1 byte: ID length | N bytes: token ID
```

- The **registry address** is stored as-is (20 bytes)
- The **ID length** (1 byte) indicates how many bytes follow for the token ID
- The **token ID** is encoded in big-endian with minimal bytes (no leading zeros). Token ID `0` has length `0` with no following bytes.

**Storage slot analysis:**

Solidity stores `bytes` values of 31 bytes or fewer inline in a single storage slot. With 20 bytes for the registry address and 1 byte for the length prefix, token IDs of up to 10 bytes (values up to 2^80 - 1) produce a total of 31 bytes, fitting in a single slot. Larger token IDs spill into additional slots but are still fully supported.

### Registry Interface

```solidity
interface IPrimaryAgentRegistry {
    event AgentRegistered(address indexed account, address indexed registry, uint256 tokenId);

    function register(address account, address registry, uint256 tokenId) external;
    function resolveAgentId(address account) external view returns (address registry, uint256 tokenId);
    function agentData(address account) external view returns (bytes memory);
    function isRegistered(address account) external view returns (bool);
}
```

#### `register(address account, address registry, uint256 tokenId)`

Registers, overwrites, or clears an account's agent identity. MUST only be callable by addresses with `REGISTRAR_ROLE`. MUST revert if `account` is the zero address. If `registry` is the zero address, the registration MUST be deleted (clearing the account's agent identity). Otherwise, the packed encoding MUST be stored as the value for the account key.

#### `resolveAgentId(address account) → (address registry, uint256 tokenId)`

Decodes and returns the agent identity for an account. If not registered, MUST return `(address(0), 0)`.

#### `agentData(address account) → bytes`

Returns the raw packed bytes for an account. Returns empty bytes if not registered.

#### `isRegistered(address account) → bool`

Returns whether the account has a registration. Implementations MUST check that the stored bytes length is greater than zero.

### Access Control

The registry MUST enforce role-based access as follows. Two roles are required; their identifiers are left to the implementation (e.g. `bytes32` constants).

- **Admin role**: The holder(s) of this role MAY grant and revoke the registrar role. There MUST be at least one address with the admin role at all times (e.g. set at deployment).
- **Registrar role**: Only addresses with this role MAY call `register`. The admin role MAY grant or revoke the registrar role.

Implementations MAY use OpenZeppelin Contracts `AccessControl` or any equivalent mechanism that provides the above semantics. The registry MUST revert if `register` is called by an address that does not have the registrar role.

### Registrar Types

Implementations SHOULD provide one or more of the following registrar contracts, each granted `REGISTRAR_ROLE`:

#### Self Registrar

Allows any `msg.sender` to register their own address. This is the simplest method suitable for EOAs.

```solidity
function register(address registry, uint256 tokenId) external;
```

The registrar calls `primaryAgentRegistry.register(msg.sender, registry, tokenId)`.

#### [ERC-1271](./eip-1271.md) Registrar

Allows smart contract wallets to register by providing a valid [ERC-1271](./eip-1271.md) signature over the registration data. To clear a registration, pass `registry = address(0)`. The registrar MUST maintain a per-account nonce to prevent signature replay attacks.

```solidity
mapping(address => uint256) public nonces;

function register(address account, address registry, uint256 tokenId, bytes calldata signature) external;
```

The registrar MUST verify the signature by calling `isValidSignature(hash, signature)` on the `account` contract, where `hash` is computed as:

```solidity
keccak256(abi.encodePacked(account, registry, tokenId, block.chainid, address(this), nonces[account]))
```

The nonce MUST be incremented after each successful `register` call to prevent replay of previously-approved signatures.

#### Ownable Registrar

Allows the owner of a contract implementing `owner()` or `getOwner()` to register the contract's agent identity.

```solidity
function register(address contractAddress, address registry, uint256 tokenId) external;
```

The registrar MUST verify that `msg.sender` matches the return value of either `owner()` or `getOwner()` on the target contract.

#### Role-check Registrar

Allows the admin or authorized role holder of a contract that exposes a role check to register the contract's agent identity.

```solidity
function register(address contractAddress, address registry, uint256 tokenId) external;
```

The registrar MUST verify that `msg.sender` is authorized to act for the contract (e.g. by calling a function such as `hasRole(adminRole, msg.sender)` or `owner() == msg.sender` on the target contract, when that contract implements such an interface). The exact role or method is implementation-defined; the requirement is that only an address the target contract considers its admin or equivalent may register on its behalf.

### Verification Loop

The Primary Agent Registry provides one direction of a bidirectional identity link. To fully verify an agent's identity, consumers SHOULD complete the verification loop by checking that the agent registry confirms the same address.

Agent registries that conform to [ERC-8004](./eip-8004.md) (Trustless Agents) store an `agentWallet` for each agent token. Agent registries that conform to [ERC-8122](./eip-8122.md) (Minimal Agent Registry) store an `agent_account` metadata field. The verification loop uses these fields to create a bidirectional proof of identity:

```
┌──────────────────────────────────────────────────────────────────┐
│                      Verification Loop                           │
│                                                                  │
│   Ethereum Address                                               │
│        │                                                         │
│        │  1. resolveAgentId()                                    │
│        ▼                                                         │
│   PrimaryAgentRegistry ──→ (registry, tokenId)                   │
│                   │                                              │
│                   │  2. getAgentWallet(tokenId)                  │
│                   │     or getMetadata(tokenId, "agent_account") │
│                   ▼                                              │
│                Agent Registry ──→ wallet address                 │
│                                        │                         │
│                                        │  3. match?              │
│                                        ▼                         │
│                                 Ethereum Address                 │
│                                                                  │
│   ✓ Verified if 1. address == 3. address                         │
└──────────────────────────────────────────────────────────────────┘
```

**Forward resolution** (address → agent):

1. Call `primaryAgentRegistry.resolveAgentId(address)` to get `(registry, tokenId)`
2. Query the agent registry for the agent's linked wallet address:
   - [ERC-8004](./eip-8004.md): `getAgentWallet(tokenId)` returns the agent's wallet address
   - [ERC-8122](./eip-8122.md): `getMetadata(tokenId, "agent_account")` returns the agent's account address
3. Verify that the returned wallet/account address matches the original Ethereum address

**Reverse resolution** (agent → address):

1. Query the agent registry for the agent's wallet address (via `agentWallet` or `agent_account`)
2. Call `primaryAgentRegistry.resolveAgentId(walletAddress)` to get `(registry, tokenId)`
3. Verify that the returned `(registry, tokenId)` matches the original agent identity

A registration is considered **verified** when both directions of the loop agree: the Primary Agent Registry points to an agent token whose registry points back to the same address. Consumers SHOULD treat unverified registrations (where the loop does not complete) as unconfirmed claims.

### Singleton Deployment

The Primary Agent Registry SHOULD be deployed at a deterministic address on every EVM chain using CREATE2 or a similar mechanism. This ensures a consistent entry point for reverse resolution across all chains.

## Rationale

This design is inspired by ENS primary names, which solve the same reverse resolution problem for human-readable names: given an address, determine the single name it represents. The Primary Agent Registry applies this pattern to agent identities, mapping each address to one `(registry, tokenId)` pair. A packed `bytes` encoding keeps the common case (token IDs under 2^80) in a single storage slot. Verification logic is delegated to separate registrar contracts so that new verification methods can be added without modifying the registry.

## Backwards Compatibility

This ERC introduces a new singleton contract and does not modify existing standards. Existing Agent registry formats ERC-8004 and ERC-8122 are supported, however, any agent registry design MAY be supported that that uses a contract address and number id. 

This ERC is designed to work alongside:

- **[ERC-8004](./eip-8004.md)** (Trustless Agents): The `getAgentWallet` function provides the forward direction of the verification loop
- **[ERC-8122](./eip-8122.md)** (Minimal Agent Registry): The `agent_account` metadata field provides the forward direction of the verification loop

## Security Considerations

The security of the system depends on the correctness of registrar contracts granted `REGISTRAR_ROLE`. The Self Registrar allows any EOA to claim any `(registry, tokenId)` pair without verifying token ownership, so consumers MUST NOT trust a registration at face value and SHOULD complete the Verification Loop to confirm the agent registry points back to the same address. The [ERC-1271](./eip-1271.md) Registrar includes `block.chainid`, `address(this)`, and a per-account `nonce` in the signed hash to prevent cross-chain, cross-contract, and same-contract replay. Because the registry is a singleton, compromise of the admin role could affect all registrations on that chain, so implementations SHOULD use a multisig or governance mechanism for the admin role.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).