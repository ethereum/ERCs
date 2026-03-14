---
eip: XXXX
title: AI Agent Authenticated Wallet
description: Policy-bound transaction execution and verifiable credential delegation for autonomous AI agents
author: Leigh Cronian (@cybercentry) <leigh.cronian@cybercentry.co.uk>
discussions-to: [https://ethereum-magicians.org/t/erc-xxxx-ai-agent-authenticated-wallet](https://ethereum-magicians.org/t/erc-xxxx-ai-agent-authenticated-wallet/27987)](https://ethereum-magicians.org/t/erc-xxxx-ai-agent-authenticated-wallet/27987)
status: Draft
type: Standards Track
category: ERC
created: 2026-03-14
requires: 155, 191, 712, 4337, 8004
---

**Context**  
This proposal aligns with the Ethereum Foundation's PhDFP-26 RFP D3 ("Agentic Economy: Verification, Delegation, and Host-Interference Mitigation", opened February 9, 2026) by providing policy-bound execution, auditable delegation, and mechanisms to mitigate host interference.

## Abstract

This ERC defines a standard interface for AI agent-authenticated wallets that execute transactions only when accompanied by a verifiable proof that ties the action to the agent's specific policy. It serves as **Layer 3 (Execute)** in a modular trust stack for autonomous agents:

- **Layer 1 (Register)**: [ERC-8004](./eip-8004.md) — on-chain identity and registration  
- **Layer 2 (Verify)**: Optional verification standards (e.g. [ERC-8126](./eip-8126.md)) — trust/risk scoring  
- **Layer 3 (Execute)**: This standard — policy-bound execution with immutable audit trail

The design enables secure credential delegation, prevents host manipulation of agent behaviour, and provides tamper-evident logging of all session activity.

## Motivation

Autonomous AI agents introduce critical security challenges when performing on-chain actions:

1. **Hosting Trust Trap** — Hosts can steal private keys if agents hold funds directly  
2. **Blind Delegation** — Credential delegation to agents lacks enforceable limits or auditable compliance  
3. **Host Manipulation** — Malicious hosts can suppress outputs, delay requests, replay probabilistic queries, or influence agent behavior through repeated sampling  
4. **Malicious Historical Activity** — Agents with prior sanctions, mixer usage, bot-like patterns, rapid forwarding, or clustering with tainted addresses pose ongoing risk  
5. **Replay & Timing Vulnerabilities** — Valid proofs from the past can be reused, or timing manipulated to the host's advantage  

This ERC provides the execution layer in a composable trust stack to mitigate these risks:

| Layer | Purpose                  | Standard                  | Core Question                          |
|-------|--------------------------|---------------------------|----------------------------------------|
| 1     | Register                 | [ERC-8004](./eip-8004.md) | "Does this agent exist on-chain?"      |
| 2     | Verify (optional)        | e.g. [ERC-8126](./eip-8126.md) | "Is this agent trustworthy and free of malicious signals?" |
| 3     | Execute                  | This ERC                  | "Is this action authorized right now?" |

Key features include:

- Cryptographically enforced policy compliance  
- Immutable, hash-chained audit trail for verifiable delegation  
- Entropy commit-reveal to counter host influence on probabilistic agents  
- Active containment mechanisms (recommended) for real-time violation response  
- Legacy credential delegation via TLSNotary attestations  

The optional verification layer allows flexibility while strongly encouraging checks (e.g. via ERC-8126 WV) against historical malicious behavior before granting control.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Required Standards

| Standard                        | Purpose in This ERC |
|---------------------------------|--------------------|
| [EIP-155](./eip-155.md)         | Replay protection via chain ID |
| [EIP-191](./eip-191.md)         | Standardized signed message format |
| [EIP-712](./eip-712.md)         | Typed structured data signing for policy-bound actions |
| [ERC-4337](./eip-4337.md)       | Account abstraction wallet foundation |
| [ERC-8004](./eip-8004.md)       | Canonical agent identity registry (Layer 1) |

### Trust Stack Integration

Implementations **SHOULD** check [ERC-8004](./eip-8004.md) registration before delegation.

Verification checks (e.g. via [ERC-8126](./eip-8126.md) risk scores) **MAY** be enforced via policy configuration but are **not required** by this standard.

### Agent Policy Structure

Policies **MUST** include:

| Field                  | Type       | Required | Description |
|------------------------|------------|----------|-------------|
| policyId               | bytes32    | Yes      | Unique ID |
| agentAddress           | address    | Yes      | Authorized agent |
| ownerAddress           | address    | Yes      | Delegator |
| allowedActions         | string[]   | Yes      | e.g. ["transfer", "swap"] |
| allowedContracts       | address[]  | No       | Whitelist |
| blockedContracts       | address[]  | No       | Blacklist |
| maxValuePerTx          | uint256    | Yes      | wei limit per tx |
| maxValuePerDay         | uint256    | No       | Daily limit |
| validAfter             | uint256    | Yes      | Start timestamp |
| validUntil             | uint256    | Yes      | Expiry timestamp |
| minVerificationScore   | uint8      | No       | Optional ERC-8126 threshold (0 = disabled) |

### EIP-712 Types

bytes32 constant AGENT_ACTION_TYPEHASH = keccak256(
    "AgentAction(address agent,string action,address target,uint256 value,bytes data,uint256 nonce,uint256 validUntil,bytes32 policyHash,bytes32 entropyCommitment)"
);

bytes32 constant DELEGATION_TYPEHASH = keccak256(
    "Delegation(address delegator,address delegatee,bytes32 policyHash,uint256 validUntil,uint256 nonce)"
);

### Core Interface

// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IAIAgentAuthenticatedWallet {
    event PolicyRegistered(bytes32 indexed policyHash, address indexed owner, address indexed agent, uint256 validUntil);
    event ActionExecuted(bytes32 indexed policyHash, address indexed agent, address target, uint256 value, bytes32 auditEntryId);
    event PolicyRevoked(bytes32 indexed policyHash, string reason);
    event AuditEntryLogged(bytes32 indexed entryId, uint256 sequence, bytes32 sessionId, string actionType);

    function registerPolicy(
        address agent,
        string[] calldata allowedActions,
        address[] calldata allowedContracts,
        address[] calldata blockedContracts,
        uint256 maxValuePerTx,
        uint256 maxValuePerDay,
        uint256 validAfter,
        uint256 validUntil,
        uint8 minVerificationScore   // 0 = no verification required
    ) external returns (bytes32 policyHash);

    function executeAction(
        bytes32 policyHash,
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        bytes32 entropyCommitment,
        bytes calldata signature
    ) external returns (bool success, bytes32 auditEntryId);

    function revokePolicy(bytes32 policyHash, string calldata reason) external;

    function getPolicy(bytes32 policyHash) external view returns (
        address agent,
        address owner,
        uint256 maxValuePerTx,
        uint256 validUntil,
        bool isActive
    );
}

### Audit Trail (Hash-Chained)

Each audit entry MUST include `previousHash` for integrity. Implementations MAY store entries off-chain (e.g. IPFS) with periodic on-chain Merkle roots posted to [ERC-8004](./eip-8004.md)'s Validation Registry.

### Recommended Extensions

- **Active Containment** — real-time monitoring, policy validation, kill switch (**SHOULD**)  
- **Host Interference Detection** — timing, output suppression, repeated query analysis (**MAY**)  
- **Entropy Commit-Reveal** — prevents host manipulation of probabilistic agents (**SHOULD**)  
- **TLSNotary Attestations** — legacy credential delegation without site changes (**MAY**)

### Error Codes

error PolicyExpired(bytes32 policyHash, uint256 validUntil);
error ValueExceedsLimit(uint256 value, uint256 maxValue);
error InvalidSignature(address recovered, address expected);
error EntropyVerificationFailed(bytes32 commitment, bytes32 revealed);
error AgentNotRegistered(address agent);

## Rationale

- Separation of concerns: identity ([ERC-8004](./eip-8004.md)) and optional verification decoupled from execution  
- `policyHash` in EIP-712 signatures binds actions immutably  
- Hash-chain audit provides tamper detection without full on-chain cost  
- Optional verification gating allows flexibility while encouraging trust standards like [ERC-8126](./eip-8126.md)

This specification explores novel combinations of policy-bound signing, hash-chained auditing, and entropy commitments to enable verifiable agent autonomy under potentially hostile hosts, with open questions around gas-efficient audit roots and threshold-based containment mechanisms.

## Security Considerations

- MUST verify [ERC-8004](./eip-8004.md) registration  
- SHOULD enforce expiration and nonce uniqueness  
- Audit tampering is detectable via chain breaks  
- Host manipulation probabilistic; combine with multiple hosts for high-value use  
- SHOULD require a recent [ERC-8126](./eip-8126.md) verification with low risk score before delegation — particularly clean Wallet Verification (WV) results from ERC-8126 indicating no sanctions, mixers, bot-like patterns, rapid forwarding, or threat intelligence hits  
- Wallets SHOULD reject or revoke delegations if WV flags malicious activity (e.g. sanctioned funding, clustering with bad actors, or automation indicators), even if the overall ERC-8126 score appears acceptable

## Backwards Compatibility

Compatible with [ERC-4337](./eip-4337.md) wallets and existing standards. No breaking changes.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
