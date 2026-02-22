---
eip: 8004
title: Delayed Metadata Update Extension
description: Optional extension introducing a cooldown period for agent metadata updates.
author: Enigma Team (@Cyberpaisa)
discussions-to: https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098
status: Draft
type: Standards Track
category: ERC
created: 2026-02-22
requires: 721
---

## Abstract

This proposal defines an optional extension to ERC-8004 that introduces a delayed metadata update mechanism for agent identity records. The extension prevents immediate mutation of agent metadata after verification by introducing a pending state and activation delay.

The mechanism is backward-compatible and intended to improve the reliability of verification signals and off-chain monitoring systems.

## Motivation

ERC-8004 allows agents to update metadata instantly via URI changes. While this provides flexibility, it also creates a risk where an agent can pass verification and then immediately swap its endpoint or configuration.

This creates an attack vector where verification signals remain visible while the underlying behavior changes.

Introducing a delay period allows monitoring systems, validators, and users to react before the change becomes active.

## Specification

Implementations MAY support a delayed metadata update flow.

### Storage

```solidity
struct PendingChange {
    string newURI;
    uint256 activationBlock;
    bool cancelled;
}

mapping(uint256 => PendingChange) public pendingChanges;
uint256 public uriCooldownBlocks;
```

### Events

```solidity
event PendingURIChange(
    uint256 indexed agentId,
    string oldURI,
    string newURI,
    uint256 activationBlock
);

event PendingURICancelled(uint256 indexed agentId);
event URIChangedWithoutCooldown(uint256 indexed agentId, string newURI);
```

### Functions

```solidity
function setAgentURIWithCooldown(
    uint256 tokenId,
    string calldata newURI
) external;
```

Requirements:
- MUST require token ownership
- MUST create a pending change entry
- MUST emit PendingURIChange

```solidity
function applyPendingChange(uint256 tokenId) external;
```

Requirements:
- MUST verify activation block reached
- MUST apply new URI
- MUST delete pending change entry

```solidity
function cancelPendingChange(uint256 tokenId) external;
```

Requirements:
- MUST require token ownership
- MUST mark pending change as cancelled
- MUST emit PendingURICancelled

### Immediate Update Compatibility

Implementations MAY retain the original immediate update method.

If used, they MUST emit:

```solidity
URIChangedWithoutCooldown(agentId, newURI);
```

## Backwards Compatibility

This extension is fully optional. Contracts not implementing it remain compliant with ERC-8004. Clients SHOULD monitor new events when available but MUST remain compatible with legacy behavior.

## Security Considerations

This extension mitigates post-verification mutation attacks by introducing a time window during which monitoring systems can detect suspicious changes.

It does not prevent malicious updates but ensures they cannot become active instantly.

Cooldown length remains configurable to allow different security profiles across deployments.

## Rationale

The proposal introduces minimal additional storage and events. It does not mandate a specific cooldown duration or update policy. This preserves ERC-8004’s flexibility while providing stronger guarantees for ecosystems requiring higher trust signals.

## Copyright

Copyright and related rights waived via CC0.
