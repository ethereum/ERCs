---
eip: 8156
title: Agent Onchain Metadata
description: Onchain metadata keys for ERC-8004 agent registration data
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/agent-onchain-metadata/TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-02-10
requires: 8004
---

## Abstract

This ERC defines standard onchain metadata keys for [ERC-8004](./eip-8004.md) agent registries, enabling agent registration data to be stored and read entirely onchain. When a registry contract supports this extension, clients read agent metadata directly from the blockchain instead of fetching the off-chain registration file referenced by the token URI.

## Motivation

[ERC-8004](./eip-8004.md) stores most agent registration data in an off-chain JSON file referenced by the token URI. While flexible, updating individual fields such as communication endpoints requires replacing the entire off-chain file. This involves IPFS re-pinning or server-side updates and prevents smart contracts from reading those fields directly. The current wallet/account model in [ERC-8004](./eip-8004.md) also requires a signature-based update flow, which makes it difficult to change an agent's account identifier or use alternative account schemes beyond the built-in logic.

By mapping key fields of the [ERC-8004](./eip-8004.md) registration file to a standard onchain metadata key, this extension enables:

- **Granular updates**: Change a single endpoint or agent account with a `setMetadata` call instead of replacing the entire registration file
- **Onchain composability**: Smart contracts can read agent endpoints, agent accounts, and other registration data directly
- **Availability guarantees**: Metadata stored onchain cannot become unavailable due to hosting failures
- **Decoupled account management**: The `agent_account` field allows agent accounts/wallets to be updated onchain without going through the signed registration flow, and to point to arbitrary account schemes (e.g., CAIP-10) rather than only the account model baked into [ERC-8004](./eip-8004.md)

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119.html) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174.html).

### Interface

Contracts implementing this ERC MUST implement [ERC-8004](./eip-8004.md).

Clients detect the presence of onchain metadata by reading the corresponding
`getMetadata(agentId, key)` value and treating any non-empty `bytes` value as
an override of the offchain [ERC-8004](./eip-8004.md) registration file or any
`data:` URLs it references. No additional discovery interface is required.

### Standard Metadata Keys

All metadata is stored and retrieved using [ERC-8004](./eip-8004.md)'s existing `getMetadata(uint256 agentId, string key)` and `setMetadata(uint256 agentId, string key, bytes value)` functions.

Each key below corresponds to a field in the [ERC-8004](./eip-8004.md) registration file. All values are encoded as UTF-8 string bytes.

#### Top-Level Fields

| Key | Description | Required |
|-----|-------------|----------|
| `name` | The agent's human-readable name | MUST |
| `description` | Natural language description of the agent | MUST |
| `image` | URI pointing to the agent's image | OPTIONAL |
| `agent_account` | Primary agent account or wallet address (e.g., CAIP-10). When set, this MUST override any `agentWallet` onchain value. | OPTIONAL |
| `x402_support` | Whether the agent supports X402 / ERC-8042-style cross-chain/offchain resolution (string value, e.g., `\"true\"` or `\"false\"`) | OPTIONAL |
| `active` | Whether the agent is currently active (string value, e.g., `\"true\"` or `\"false\"`) | OPTIONAL |
| `supported_trust` | Comma-separated list of supported trust models, mirroring the `"supportedTrust"` array in the ERC-8004 registration JSON | OPTIONAL |

#### Endpoint Fields

Each endpoint type from the [ERC-8004](./eip-8004.md) registration file `endpoints` array MUST be stored as a separate metadata record. The key follows the pattern `endpoint/<name>`, where `<name>` is the endpoint's `name` field in the registration file. The value is the endpoint's `endpoint` field encoded as UTF-8 bytes.

| Key | Description |
|-----|-------------|
| `endpoint/A2A` | A2A agent card endpoint URL |
| `endpoint/MCP` | MCP server endpoint URL |
| `endpoint/OASF` | OASF endpoint URI |
| `endpoint/ENS` | ENS name |
| `endpoint/DID` | Decentralized Identifier |

All endpoint keys are OPTIONAL. Additional endpoint types beyond those listed above MAY be defined using the same `endpoint/<name>` key pattern.

Endpoint versions MAY be stored using the key pattern `endpoint/<name>/version` with the version string encoded as UTF-8 bytes.

### Encoding

All metadata values MUST be encoded as UTF-8 string bytes. In Solidity, values are set and read as follows:

```solidity
// Setting a string value
registry.setMetadata(agentId, "name", bytes("myAgentName"));

// Reading a string value
string memory name = string(registry.getMetadata(agentId, "name"));

// Setting an endpoint
registry.setMetadata(agentId, "endpoint/MCP", bytes("https://mcp.agent.example/"));

// Reading an endpoint
string memory mcpEndpoint = string(registry.getMetadata(agentId, "endpoint/MCP"));
```

An empty `bytes` return value (length 0) indicates the key has not been set.

### Precedence over Offchain Metadata

When a registry implements this ERC, **onchain metadata MUST take precedence** over any conflicting values in the offchain [ERC-8004](./eip-8004.md) registration file or any `data:` URLs it references. If a given key (for example `name`, `description`, or `endpoint/MCP`) is set onchain (non-empty bytes), clients and integrators MUST use the onchain value and ignore the corresponding offchain value. If the onchain value for a key is absent (empty bytes), clients MAY fall back to the offchain registration file or associated data URL for that field.∂

### Resolution Strategy

Clients SHOULD use the following strategy to read agent metadata:

1. For each standard key defined above (e.g., `name`, `description`, `agent_account`, `x402_support`, `active`, `supported_trust`, `endpoint/ENS`, `endpoint/MCP`), call `getMetadata(agentId, key)`
2. If `getMetadata` returns a non-empty `bytes` value for that key, treat it as the **authoritative onchain value** and ignore the corresponding field in the off-chain registration file (or any `data:` URL)
3. If `getMetadata` returns an empty `bytes` value for that key, fall back to the off-chain [ERC-8004](./eip-8004.md) registration file (or associated `data:` URL) for that field

The mapping between onchain keys and off-chain [ERC-8004](./eip-8004.md) fields is:

| Onchain key        | ERC-8004 JSON field it overrides                                                                      |
|--------------------|------------------------------------------------------------------------------------------------------|
| `name`             | Top-level `"name"` field                                                                             |
| `description`      | Top-level `"description"` field                                                                      |
| `image`            | Top-level `"image"` field                                                                            |
| `x402_support`     | Top-level `"x402Support"` field                                                                      |
| `active`           | Top-level `"active"` field                                                                           |
| `supported_trust`  | Top-level `"supportedTrust"` array, encoded as a comma-separated string (e.g., `\"reputation,crypto-economic,tee-attestation\"`) |
| `agent_account`    | Effective agent account / wallet identifier (logically overriding the `agentWallet` reserved field and any wallet/account value implied by ERC-8004 logic) |
| `endpoint/A2A`     | The `"endpoint"` value of the object in the `\"services\"` array with `\"name\": \"A2A\"`           |
| `endpoint/MCP`     | The `"endpoint"` value of the object in the `\"services\"` array with `\"name\": \"MCP\"`           |
| `endpoint/OASF`    | The `"endpoint"` value of the object in the `\"services\"` array with `\"name\": \"OASF\"`          |
| `endpoint/ENS`     | The `"endpoint"` value of the object in the `\"services\"` array with `\"name\": \"ENS\"`           |
| `endpoint/DID`     | The `"endpoint"` value of the object in the `\"services\"` array with `\"name\": \"DID\"`           |
| `endpoint/<name>`  | In general, the `"endpoint"` value of the entry in the `\"services\"` array whose `\"name\"` = `<name>` |

When both onchain metadata and an off-chain registration file exist for the same agent, the onchain values MUST take precedence for any key that has been set (non-empty `bytes`).

## Rationale

- **Reuse of [ERC-8004](./eip-8004.md) primitives**: This extension builds on the existing `getMetadata`/`setMetadata` functions rather than introducing new storage mechanisms, keeping the interface minimal.
- **Per-endpoint keys**: Storing each endpoint type as a separate metadata record (`endpoint/A2A`, `endpoint/MCP`, etc.) enables granular updates. An agent can update its MCP endpoint without affecting its A2A endpoint or wallet address.
- **UTF-8 encoding**: Raw UTF-8 bytes are the simplest and most gas-efficient encoding for string values. In Solidity, `bytes(str)` and `string(bts)` handle conversion directly without ABI encoding overhead.
- **Precedence rule**: Onchain metadata takes precedence over off-chain data so that the most authoritative source (blockchain-verified) is used when available. This also allows agents to gradually migrate individual fields onchain while keeping the rest off-chain.

## Backwards Compatibility

This ERC is fully backwards compatible with [ERC-8004](./eip-8004.md). Existing agents that do not use onchain metadata continue to function through the off-chain registration file.

## Security Considerations

- **Onchain vs. off-chain URLs**: Onchain metadata is generally more secure and predictable than traditional HTTP(S) URLs, which can be changed or repointed at any time without onchain visibility. By preferring onchain values when present, clients reduce their reliance on mutable off-chain infrastructure.
- **Access control**: The same access control rules that apply to [ERC-8004](./eip-8004.md)'s `setMetadata` apply to the keys defined in this ERC. Only the agent owner or approved operator SHOULD be able to set metadata.
- **Agent account semantics**: The `agent_account` field is intentionally more flexible than the reserved `agentWallet` in [ERC-8004](./eip-8004.md). It MAY be set to any account identifier chosen by the owner, including counterfactual addresses. The fact that the registry owner (or approved operator) has explicitly set `agent_account` is considered sufficient validation for its use within this standard and is not, by itself, treated as a security issue.
- **Sync with `agentURI`**: For registries that mirror the full ERC-8004 registration JSON onchain, it is RECOMMENDED to keep onchain metadata values in sync with the `agentURI` (which may itself be a base64 `data:` URI) for maximum compatibility. In practice, this means updating individual onchain metadata keys first, then updating `agentURI` last, so that the `agentURI` update timestamp is always >= the timestamps of the onchain updates. This update order is only a simple guideline and does not guarantee perfect synchronization, and any client following this ERC MUST still treat the onchain per-key values as authoritative over the `agentURI` payload whenever both are present.
- **Data validation**: Clients MUST NOT assume onchain metadata values are valid URIs, addresses, or identifiers without performing their own validation. Malformed values should be handled gracefully.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
