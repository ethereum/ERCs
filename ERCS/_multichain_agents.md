---
eip: XXXX
title: Multichain Agents and Agent Relationships
description: A standard for linking AI agent registrations across chains and establishing agent-to-agent relationships.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/TODO
status: Draft
type: Standards Track
category: ERC
created: 2025-10-02
requires: 7930, 8048, 8119, 8127
---

## Abstract

[ERC-8004](./eip-8004.md) is a standard for registering AI agents onchain, where there is a singleton registry, one for every chain. [ERC-8122](./eip-8122.md) is a minimal agent registry, which can be deployed for specific projects, that allows for the option of a fixed supply of agents. For multichain agents and agents that want to be registered in multiple registries, for example a fixed supply [ERC-8122](./eip-8122.md) registry and the [ERC-8004](./eip-8004.md) registry of the chain, it is possible to link them together in a secure and verifiable way. It is also possible to create a relationship between two agents by specifying an agent-to-agent relationship. In this way it's possible to create agent teams.

## Motivation

With the introduction of AI agent registries, such as [ERC-8004](./eip-8004.md), there is a need for a standardized way to create multichain and multi-registry agents, and establish relationships between agents. Agent registrations that share a single endpoint can be considered a single discoverable agent with multiple registrations. It is also necessary to have a way to specify a team of agents that all work together. [ERC-8092](./eip-8092.md) works in a similar way, for wallet addresses. This ERC takes the concepts of [ERC-8092](./eip-8092.md) and applies it to agent IDs.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Agent Registry Text Record Keys

This ERC introduces metadata records that store links to other AI agent registries where the agent is registered, and allow for a UTF-8 set of relationship bytes, which can specify the relationship between the agents, or specify a single multi-registry and/or multi-chain agent.

The record keys are:

- `linked-registry`
- `linked-registry-relationship`
- `linked-registry/N` where `N` is a base-10 integer (`1`, `2`, `3`, ...) used to represent additional entries.
- `linked-registry-relationship/N` 

These keys establish a priority order: `linked-registry` is highest priority, followed by `linked-registry/1`, then `linked-registry/2`, etc.

The key format `linked-registry/N` uses the format specified in [ERC-8119](./eip-8119.md): Parameterized Storage Keys for specifying structured keys with parameters.

### Linked Registry and Agent ID Format ([ERC-8127](./eip-8127.md) Token Identifier)

The `linked-registry` and `linked-registry/N` UTF-8 bytes record value uses the [ERC-8127](./eip-8127.md) Token Identifier format:

```
<agentId>@<registry>
```

Where:

- `<agentId>` is the numeric agent ID from the registry (decimal string)
- `<registry>` is the [ERC-7930](./eip-7930.md) interoperable address of the registry contract (hexadecimal string with `0x` prefix)

The [ERC-8127](./eip-8127.md) format also supports an optional alias prefix (`[<alias>.]<agentId>@<registry>`), but for verification purposes the alias is not required.

### Agent Relationship Data 

The `linked-registry-relationship` and `linked-registry-relationship/N` is an optional field that can be set to specify a relationship between two agent registrations. The value is UTF-8 bytes. If the value is left blank (empty), it is treated the same as `self`. For a single multichain agent, the value MUST be `self` when specified. To specify a team, it is possible to specify a parent-child relationship using `manager` and `report`. An agent that is a manager of another agent will create a link to that agent's registration (which can be the same registry), with the relationship set to `report`. Other relationship types are also possible — for example, a mutual work relationship could use a `teammate` type, where both agents link to each other with `teammate` as the relationship value.

To confirm a relationship both registrations SHOULD be linked. For example, for a `self` type relationship both agent registries should have a `linked-registry` or `linked-registry/N` record set.

Registry 1 (agent id: 27):
`linked-registry`: `12@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
`linked-registry-relationship`: `self`

Registry 2 (agent id: 12):
`linked-registry`: `27@0x00010000010114a3c7d9e2b41f0856000000000000000000000002`
`linked-registry-relationship`: `self`

For teams a relationship can be formed using the `report` and `manager` relationship keywords.

Registry 1 / Manager (agent id: 27):
`linked-registry`: `12@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
`linked-registry-relationship`: `report`

Registry 2 / Direct Report (agent id: 12):
`linked-registry`: `27@0x00010000010114a3c7d9e2b41f0856000000000000000000000002`
`linked-registry-relationship`: `manager`


### Example

The agent registry address MUST be encoded as an [ERC-7930](./eip-7930.md) interoperable address.

Example: An agent registered as ID 42 on the [ERC-8004](./eip-8004.md) registry at `0x5f8b3a2e7c1d094f600000000000000000000001` on Ethereum Mainnet (chain 1).

The `linked-registry` metadata value would be:

```
42@0x000100000101145f8b3a2e7c1d094f600000000000000000000001
```

With an optional alias, the value could be:

```
support-agent.42@0x000100000101145f8b3a2e7c1d094f600000000000000000000001
```

### Verification

To verify that two agent registrations are linked, the client MUST check that both registrations reference each other. A link is only considered valid when both sides point to each other with matching relationship types.

#### Verifying a `self` Link

1. Read the `linked-registry` (and `linked-registry/N`) metadata from agent A's registration
2. Parse the [ERC-8127](./eip-8127.md) Token Identifier to extract the agent ID and registry address of agent B
3. Verify that the `linked-registry-relationship` value is `self`
4. Read the `linked-registry` (and `linked-registry/N`) metadata from agent B's registration on the target registry and chain
5. Verify that agent B links back to agent A with a `linked-registry-relationship` value of `self`

#### Verifying a Team (tree type) Relationship

1. Read the `linked-registry` (and `linked-registry/N`) metadata from the manager agent
2. Parse the [ERC-8127](./eip-8127.md) Token Identifier to extract the agent ID and registry address of the report agent
3. Verify that the manager's `linked-registry-relationship` value is `report`
4. Read the `linked-registry` (and `linked-registry/N`) metadata from the report agent
5. Verify that the report agent links back to the manager with a `linked-registry-relationship` value of `manager`

### Example: Multichain Agent

An agent can be registered on multiple chains and linked together as a single multichain identity using the `self` relationship. Each registration uses prioritized `linked-registry` keys to reference the others.

This example uses three registries:

- **Ethereum Mainnet** (chain 1): [ERC-8004](./eip-8004.md) registry at `0x5f8b3a2e7c1d094f600000000000000000000001`

```
0x000100000101145f8b3a2e7c1d094f600000000000000000000001
```

- **Arbitrum** (chain 42161 = 0xa4b1): [ERC-8122](./eip-8122.md) registry at `0xa3c7d9e2b41f0856000000000000000000000002`

```
0x000100000202a4b114a3c7d9e2b41f0856000000000000000000000002
```

- **Optimism** (chain 10 = 0x0a): [ERC-8122](./eip-8122.md) registry at `0x7e4a1b9f3c8d2065000000000000000000000003`

```
0x00010000010a147e4a1b9f3c8d2065000000000000000000000003
```

**Agent on Ethereum Mainnet ([ERC-8004](./eip-8004.md), agent id: 42):**
- `linked-registry`: `100@0x000100000202a4b114a3c7d9e2b41f0856000000000000000000000002`
- `linked-registry-relationship`: `self`
- `linked-registry/1`: `55@0x00010000010a147e4a1b9f3c8d2065000000000000000000000003`
- `linked-registry-relationship/1`: `self`

**Agent on Arbitrum ([ERC-8122](./eip-8122.md), agent id: 100):**
- `linked-registry`: `42@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
- `linked-registry-relationship`: `self`

**Agent on Optimism ([ERC-8122](./eip-8122.md), agent id: 55):**
- `linked-registry`: `42@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
- `linked-registry-relationship`: `self`

All three registrations reference each other with `self`, confirming they represent the same agent across chains.

### Example: Agent Team

A team of agents can be established using `manager` and `report` relationships. A manager agent links to each of its direct reports, and each report links back to its manager.

Using the same registries from the multichain example above:

**Manager Agent (Ethereum Mainnet, agent id: 27):**
- `linked-registry`: `12@0x000100000202a4b114a3c7d9e2b41f0856000000000000000000000002`
- `linked-registry-relationship`: `report`
- `linked-registry/1`: `88@0x00010000010a147e4a1b9f3c8d2065000000000000000000000003`
- `linked-registry-relationship/1`: `report`

**Report Agent 1 (Arbitrum, agent id: 12):**
- `linked-registry`: `27@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
- `linked-registry-relationship`: `manager`

**Report Agent 2 (Optimism, agent id: 88):**
- `linked-registry`: `27@0x000100000101145f8b3a2e7c1d094f600000000000000000000001`
- `linked-registry-relationship`: `manager`

Clients can traverse these links to discover the full team structure.

### Registry Standards

This specification is intended to be used with registries that use numeric agent IDs, such as [ERC-8004](./eip-8004.md) and [ERC-8122](./eip-8122.md), and that support onchain metadata storage via [ERC-8048](./eip-8048.md). The metadata keys defined in this specification (`linked-registry`, `linked-registry-relationship`, and their parameterized variants) are stored using the registry's metadata interface (e.g., `setMetadata`).

## Rationale

This specification uses bidirectional metadata links between agent registrations to establish multichain identity and agent-to-agent relationships. By requiring both sides of a link to reference each other, the verification model ensures that relationships are consensual — an agent cannot unilaterally claim a relationship with another agent.

The `linked-registry` and `linked-registry/N` keys use the [ERC-8127](./eip-8127.md) Token Identifier format to encode both the agent ID and registry address (including chain via [ERC-7930](./eip-7930.md)) in a single human-readable value. This makes links self-describing and allows clients to resolve them without external documentation.

The relationship types (`self`, `manager`, `report`) are intentionally minimal. `self` enables multichain agent identity — the same agent registered on multiple chains or in multiple registries. `manager` and `report` enable simple team structures. More complex relationship types can be defined by implementers. 

The use of [ERC-8119](./eip-8119.md) parameterized keys (`linked-registry/N`) allows an agent to maintain links to multiple registrations without requiring an unbounded enumeration scheme. The priority ordering provides a deterministic resolution order for clients.

## Backwards Compatibility

This specification introduces new metadata keys for agent registries. Existing registries that support [ERC-8048](./eip-8048.md) metadata can adopt this specification without any contract changes — the new keys are simply stored as metadata values using the existing `setMetadata` interface.

## Security Considerations

### Unverified Links

Clients MUST verify both directions of a link before trusting a relationship. A single unidirectional link (e.g., agent A claims to be linked to agent B, but agent B does not link back) MUST NOT be treated as a valid relationship.

### Registry Trust

Clients SHOULD verify that the linked registry address corresponds to a known and trusted agent registry contract. Linking to an arbitrary contract could allow an attacker to spoof agent relationships.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).