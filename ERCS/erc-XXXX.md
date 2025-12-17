---
eip: XXXX
title: ENS Trust Registry for Agent Coordination
description: Web of trust validation using ENS names for ERC-8001 multi-party coordination
author: Kwame Bryan (@KBryan)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-ens-trust-registry-for-agent-coordination/TBD
status: Draft
type: Standards Track
category: ERC
created: 2025-12-16
requires: 137, 712, 1271, 8001
---

## Abstract

This ERC defines a **Trust Registry** that enables agents to establish and query transitive trust relationships using ENS names as identifiers. Trust is expressed at four levels (Unknown, None, Marginal, Full) and propagates through signature chains following the GNU Privacy Guard (GnuPG) web of trust model.

The registry serves as the **reputation module** anticipated by [ERC-8001](/EIPS/eip-8001), enabling coordinators to gate participation based on trust graph proximity. An agent is considered valid from a coordinator's perspective if sufficient trust paths exist between them.

This standard specifies trust attestation structures, the transitive validation algorithm, ENS integration semantics, and [ERC-8001](/EIPS/eip-8001) coordination hooks.

## Motivation

[ERC-8001](/EIPS/eip-8001) defines minimal primitives for multi-party agent coordination but explicitly defers reputation to modules:

> "Privacy, thresholds, bonding, and cross-chain are left to modules."

And in Security Considerations:

> "Equivocation: A participant can sign conflicting intents. Mitigate with module-level slashing or reputation."

This ERC provides that reputation module. Before coordinating, agents need answers to:

1. **"Should I include this agent in my coordination?"** — Participant selection
2. **"Can I trust this agent's judgment about other agents?"** — Transitive trust
3. **"How do I update trust based on coordination outcomes?"** — Trust maintenance

### Why Web of Trust?

The web of trust model, proven over 25+ years in GnuPG, solves the bootstrap problem: how do you establish trust with unknown agents without a centralised registrar?

| GnuPG Concept | This Standard |
|---------------|---------------|
| Public key | ENS name |
| Key signing | Trust attestation |
| Owner trust levels | `TrustLevel` enum |
| Key validity | Agent validity for coordination |
| Certification path | Trust chain through agents |

### Why ENS?

ENS provides a battle-tested, finalized identity layer:

- **Stable identifiers** that survive key rotation
- **Ownership semantics** via `owner()` and `isApprovedForAll()`
- **Human readable** names (`alice.agents.eth` not `0x742d...`)
- **Subdomain delegation** for protocol-issued agent identities
- **L2 support** via CCIP-Read

Using ENS avoids dependency on draft identity standards while remaining compatible with future standards through adapter patterns.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

This ERC specifies:

* Trust levels and their semantics
* ENS-indexed trust attestation structures
* [EIP-712](/EIPS/eip-712) typed data for signing attestations
* The `ITrustRegistry` interface
* Web of trust validation algorithm
* [ERC-8001](/EIPS/eip-8001) integration hooks
* Error surface and events

### Trust Levels

Implementations MUST use the canonical enum:

```solidity
enum TrustLevel {
    Unknown,   // 0: No trust relationship established
    None,      // 1: Explicitly distrusted
    Marginal,  // 2: Partial trust — multiple required for validation
    Full       // 3: Complete trust — single attestation sufficient
}
```

**Semantic definitions:**

| Level | Meaning | Validation Contribution |
|-------|---------|------------------------|
| `Unknown` | Default state; no data about agent | Cannot contribute to validation |
| `None` | Agent known to behave improperly | Explicitly excluded; voids trust paths |
| `Marginal` | Agent generally trustworthy | Contributes partial weight |
| `Full` | Agent's judgment equals own verification | Single attestation validates |

### ENS Integration

The Trust Registry uses ENS namehashes as agent identifiers.

```solidity
// ENS namehash computation (per ERC-137)
bytes32 node = keccak256(abi.encodePacked(
    keccak256(abi.encodePacked(bytes32(0), keccak256("eth"))),
    keccak256("alice")
));
// node = namehash("alice.eth")
```

#### Controller Resolution

An address is authorized to act for an ENS name if:

```solidity
function isAuthorized(bytes32 node, address actor) internal view returns (bool) {
    address owner = ens.owner(node);
    return actor == owner || ens.isApprovedForAll(owner, actor);
}
```

Implementations MUST verify authorization before accepting trust attestations.

### EIP-712 Domain

Implementations MUST use the following [EIP-712](/EIPS/eip-712) domain:

```solidity
EIP712Domain({
    name: "ERC-XXXX-Trust",
    version: "1",
    chainId: block.chainid,
    verifyingContract: address(this)
})
```

Implementations SHOULD expose the domain via [EIP-5267](/EIPS/eip-5267).

### Primary Types

```solidity
struct TrustAttestation {
    bytes32 trustorNode;       // ENS namehash of trustor
    bytes32 trusteeNode;       // ENS namehash of trustee
    TrustLevel level;          // Trust level assigned
    bytes32 scope;             // Scope restriction; bytes32(0) = universal
    uint64 expiry;             // Unix timestamp; 0 = no expiry
    uint64 nonce;              // Per-trustor monotonic nonce
}

struct ValidationParams {
    uint8 maxPathLength;       // Maximum trust chain depth
    uint8 marginalThreshold;   // Marginal attestations required
    uint8 fullThreshold;       // Full attestations required (usually 1)
    bytes32 scope;             // Required scope; bytes32(0) = any
    bool enforceExpiry;        // Check expiry on all chain elements
}
```

#### Default Validation Parameters

When not specified, implementations SHOULD use:

```solidity
ValidationParams({
    maxPathLength: 5,
    marginalThreshold: 3,
    fullThreshold: 1,
    scope: bytes32(0),
    enforceExpiry: true
})
```

### Typed Data Hashes

```solidity
bytes32 constant TRUST_ATTESTATION_TYPEHASH = keccak256(
    "TrustAttestation(bytes32 trustorNode,bytes32 trusteeNode,uint8 level,bytes32 scope,uint64 expiry,uint64 nonce)"
);

function hashAttestation(TrustAttestation calldata att) internal pure returns (bytes32) {
    return keccak256(abi.encode(
        TRUST_ATTESTATION_TYPEHASH,
        att.trustorNode,
        att.trusteeNode,
        uint8(att.level),
        att.scope,
        att.expiry,
        att.nonce
    ));
}
```

### Interface

Implementations MUST expose the following interface:

```solidity
interface ITrustRegistry {
    // ═══════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Emitted when trust is set or updated
    event TrustSet(
        bytes32 indexed trustorNode,
        bytes32 indexed trusteeNode,
        TrustLevel level,
        bytes32 indexed scope,
        uint64 expiry
    );

    /// @notice Emitted when trust is explicitly revoked
    event TrustRevoked(
        bytes32 indexed trustorNode,
        bytes32 indexed trusteeNode,
        string reason
    );

    /// @notice Emitted when an identity gate is configured
    event IdentityGateSet(
        bytes32 indexed coordinationType,
        bytes32 indexed gatekeeperNode,
        uint8 maxPathLength,
        uint8 marginalThreshold
    );

    // ═══════════════════════════════════════════════════════════════════
    // Trust Management
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Set trust level for another agent
    /// @param attestation The trust attestation
    /// @param signature EIP-712 signature from trustor's controller
    function setTrust(
        TrustAttestation calldata attestation,
        bytes calldata signature
    ) external;

    /// @notice Batch set multiple trust relationships
    /// @param attestations Array of trust attestations
    /// @param signatures Corresponding signatures
    function setTrustBatch(
        TrustAttestation[] calldata attestations,
        bytes[] calldata signatures
    ) external;

    /// @notice Revoke trust (sets level to None)
    /// @param trusteeNode The agent to revoke trust from
    /// @param reason Human-readable reason for revocation
    function revokeTrust(
        bytes32 trusteeNode,
        string calldata reason
    ) external;

    /// @notice Get trust record between two agents
    /// @param trustorNode The trusting agent
    /// @param trusteeNode The trusted agent
    /// @return level Current trust level
    /// @return scope Trust scope
    /// @return expiry Expiration timestamp (0 = never)
    function getTrust(
        bytes32 trustorNode,
        bytes32 trusteeNode
    ) external view returns (
        TrustLevel level,
        bytes32 scope,
        uint64 expiry
    );

    /// @notice Get current nonce for a trustor
    /// @param trustorNode The agent's ENS namehash
    /// @return Current nonce value
    function getNonce(bytes32 trustorNode) external view returns (uint64);

    /// @notice Get all agents trusted by a given agent
    /// @param trustorNode The trusting agent
    /// @param minLevel Minimum trust level to include
    /// @return trustees Array of trusted agent namehashes
    function getTrustees(
        bytes32 trustorNode,
        TrustLevel minLevel
    ) external view returns (bytes32[] memory trustees);

    /// @notice Get all agents that trust a given agent
    /// @param trusteeNode The trusted agent
    /// @param minLevel Minimum trust level to include
    /// @return trustors Array of trusting agent namehashes
    function getTrustors(
        bytes32 trusteeNode,
        TrustLevel minLevel
    ) external view returns (bytes32[] memory trustors);

    // ═══════════════════════════════════════════════════════════════════
    // Web of Trust Validation
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Validate an agent through the web of trust
    /// @param validatorNode The validating agent's perspective
    /// @param targetNode The agent to validate
    /// @param params Validation parameters
    /// @return isValid Whether the target is valid
    /// @return pathLength Shortest path found (0 = direct)
    /// @return marginalCount Marginal attestations contributing
    /// @return fullCount Full attestations contributing
    function validateAgent(
        bytes32 validatorNode,
        bytes32 targetNode,
        ValidationParams calldata params
    ) external view returns (
        bool isValid,
        uint8 pathLength,
        uint8 marginalCount,
        uint8 fullCount
    );

    /// @notice Batch validate multiple agents
    /// @param validatorNode The validating agent's perspective
    /// @param targetNodes Agents to validate
    /// @param params Validation parameters
    /// @return results Validation result for each target
    function validateAgentBatch(
        bytes32 validatorNode,
        bytes32[] calldata targetNodes,
        ValidationParams calldata params
    ) external view returns (bool[] memory results);

    /// @notice Check if a trust path exists (without full validation)
    /// @param fromNode Starting agent
    /// @param toNode Ending agent
    /// @param maxDepth Maximum path length to search
    /// @return exists Whether any path exists
    /// @return depth Length of shortest path found
    function pathExists(
        bytes32 fromNode,
        bytes32 toNode,
        uint8 maxDepth
    ) external view returns (bool exists, uint8 depth);

    // ═══════════════════════════════════════════════════════════════════
    // ERC-8001 Integration
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Set identity gate for a coordination type
    /// @param coordinationType The ERC-8001 coordination type
    /// @param gatekeeperNode Agent whose trust graph gates entry
    /// @param params Validation parameters for the gate
    function setIdentityGate(
        bytes32 coordinationType,
        bytes32 gatekeeperNode,
        ValidationParams calldata params
    ) external;

    /// @notice Remove identity gate for a coordination type
    /// @param coordinationType The ERC-8001 coordination type
    function removeIdentityGate(bytes32 coordinationType) external;

    /// @notice Get identity gate configuration
    /// @param coordinationType The ERC-8001 coordination type
    /// @return gatekeeperNode The gatekeeper agent
    /// @return params Validation parameters
    /// @return enabled Whether the gate is active
    function getIdentityGate(
        bytes32 coordinationType
    ) external view returns (
        bytes32 gatekeeperNode,
        ValidationParams memory params,
        bool enabled
    );

    /// @notice Validate participant for ERC-8001 coordination
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participantNode Agent seeking to participate
    /// @return isValid Whether participant passes the gate
    function validateParticipant(
        bytes32 coordinationType,
        bytes32 participantNode
    ) external view returns (bool isValid);

    /// @notice Batch validate participants for coordination
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participantNodes Agents seeking to participate
    /// @return results Validation result for each participant
    function validateParticipantBatch(
        bytes32 coordinationType,
        bytes32[] calldata participantNodes
    ) external view returns (bool[] memory results);
}
```

### Semantics

#### `setTrust`

`setTrust` MUST revert if:

* `attestation.trustorNode == attestation.trusteeNode` (self-trust prohibited)
* `attestation.nonce <= getNonce(attestation.trustorNode)`
* `attestation.expiry != 0 && attestation.expiry <= block.timestamp`
* The signature does not recover to an address authorized for `trustorNode`
* The ENS name for `trustorNode` does not exist (owner is zero address)

If valid:

* The trust record MUST be stored
* `getNonce(trustorNode)` MUST return the attestation's nonce
* `TrustSet` MUST be emitted
* If this is a new relationship (previous level was `Unknown`), the trustee MUST be added to the trustor's trustee list and vice versa

#### `revokeTrust`

`revokeTrust` MUST revert if:

* Caller is not authorized for the trustor node (derived from msg.sender's ENS ownership)
* No existing trust relationship exists

If valid:

* Trust level MUST be set to `None`
* `TrustRevoked` MUST be emitted
* The relationship MUST remain in storage (not deleted) to preserve the explicit distrust

#### `validateAgent` — Web of Trust Algorithm

The validation algorithm determines if `targetNode` is valid from `validatorNode`'s perspective.

**Validation succeeds if ANY of the following conditions are met:**

1. **Self-validation**: `validatorNode == targetNode`

2. **Direct trust**: `getTrust(validatorNode, targetNode).level >= Marginal`

3. **Full-trust delegation**: There exists an agent F where:
    * `getTrust(validatorNode, F).level == Full`
    * `getTrust(F, targetNode).level >= Marginal`
    * Path length is 1

4. **Marginal accumulation**: There exist distinct agents M₁, M₂, ..., Mₙ where:
    * `n >= params.marginalThreshold`
    * `getTrust(validatorNode, Mᵢ).level >= Marginal` for all i
    * `getTrust(Mᵢ, targetNode).level >= Marginal` for all i
    * Path length is 1

5. **Transitive validation**: There exists a path `[validatorNode → A₁ → A₂ → ... → Aₖ → targetNode]` where:
    * `k < params.maxPathLength`
    * Each edge represents trust at level `>= Marginal`
    * The terminal validation (Aₖ validates targetNode) satisfies conditions 2-4

**Scope filtering:**

If `params.scope != bytes32(0)`, only trust records where `scope == bytes32(0)` (universal) or `scope == params.scope` contribute to validation.

**Expiry enforcement:**

If `params.enforceExpiry == true`, trust records where `expiry != 0 && expiry <= block.timestamp` MUST NOT contribute to validation.

**Cycle prevention:**

The algorithm MUST NOT revisit nodes already in the current path.

#### `validateParticipant`

This function gates [ERC-8001](/EIPS/eip-8001) coordination participation.

```solidity
function validateParticipant(
    bytes32 coordinationType,
    bytes32 participantNode
) external view returns (bool isValid) {
    (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled) = 
        getIdentityGate(coordinationType);
    
    if (!enabled) return true; // No gate = open participation
    
    (isValid, , , ) = validateAgent(gatekeeperNode, participantNode, params);
}
```

### Errors

Implementations MUST revert with these errors:

```solidity
error SelfTrustProhibited();
error NonceTooLow(uint64 provided, uint64 required);
error AttestationExpired(uint64 expiry, uint64 currentTime);
error InvalidSignature();
error NotAuthorized(bytes32 node, address actor);
error ENSNameNotFound(bytes32 node);
error TrustNotFound(bytes32 trustorNode, bytes32 trusteeNode);
error GateNotFound(bytes32 coordinationType);
error InvalidValidationParams();
```

### Recommended Scopes

For interoperability, the following scope values are RECOMMENDED:

| Scope | Value | Use Case |
|-------|-------|----------|
| Universal | `bytes32(0)` | Trust applies to all contexts |
| DeFi | `keccak256("DEFI")` | DeFi coordination |
| Gaming | `keccak256("GAMING")` | Gaming/metaverse |
| MEV | `keccak256("MEV")` | MEV protection |
| Commerce | `keccak256("COMMERCE")` | Agentic commerce |
| Validation | `keccak256("VALIDATION")` | Trust for validation judgments |

### Recommended Coordination Types

For [ERC-8001](/EIPS/eip-8001) identity gates:

| Coordination Type | Value |
|-------------------|-------|
| MEV Coordination | `keccak256("MEV_COORDINATION")` |
| DeFi Yield | `keccak256("DEFI_YIELD")` |
| Gaming Match | `keccak256("GAMING_MATCH")` |
| Commerce Escrow | `keccak256("COMMERCE_ESCROW")` |

## Rationale

### Why ENS Instead of a New Identity System?

ENS is finalised (ERC-137), battle-tested, and widely adopted. Creating a new identity system would:

* Add dependency on draft standards
* Fragment the identity ecosystem
* Require new adoption efforts

ENS provides everything needed: stable identifiers, ownership semantics, and extensibility.

### Why Separate Trust from Reputation Scores?

Trust ("how much do I trust this agent's judgment?") differs from reputation ("how well did this agent perform?"). An agent can:

* Have excellent performance but poor judgment in vouching
* Have limited history but excellent judgment

Separating these concerns enables richer trust semantics.

### Why Four Trust Levels?

The four-level model (Unknown, None, Marginal, Full) is proven by GnuPG's 25+ years of use. Finer granularity adds complexity without clear benefit; coarser granularity loses important distinctions (especially Marginal vs Full).

### Why Configurable Validation Parameters?

Different contexts require different security thresholds:

| Context | Recommended Parameters |
|---------|------------------------|
| High-value DeFi | `maxPathLength: 2, marginalThreshold: 5` |
| Standard coordination | `maxPathLength: 5, marginalThreshold: 3` |
| Casual gaming | `maxPathLength: 7, marginalThreshold: 2` |

### Why On-Chain Trust Storage?

On-chain storage enables:

* Composability with other contracts
* Trustless verification
* Censorship resistance
* No reliance on off-chain infrastructure

The gas cost is acceptable given trust relationships change infrequently.

### Why Not Compute Paths On-Chain?

Full path computation is expensive. The specification allows:

* Validators to compute paths off-chain
* On-chain verification of pre-computed paths
* Hybrid approaches with cached results

Implementations MAY optimize using off-chain indexing.

## Backwards Compatibility

This ERC introduces new functionality and does not modify existing standards.

**ENS Compatibility**: Uses standard ENS interfaces (`owner`, `isApprovedForAll`). Works with any ENS deployment.

**ERC-8001 Compatibility**: Designed as a module. ERC-8001 coordinators can optionally integrate identity gates.

**Wallet Compatibility**: Uses [EIP-712](/EIPS/eip-712) signatures, compatible with all major wallets.

## Reference Implementation

### ITrustRegistry.sol

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

enum TrustLevel {
    Unknown,
    None,
    Marginal,
    Full
}

struct TrustAttestation {
    bytes32 trustorNode;
    bytes32 trusteeNode;
    TrustLevel level;
    bytes32 scope;
    uint64 expiry;
    uint64 nonce;
}

struct ValidationParams {
    uint8 maxPathLength;
    uint8 marginalThreshold;
    uint8 fullThreshold;
    bytes32 scope;
    bool enforceExpiry;
}

interface ITrustRegistry {
    event TrustSet(
        bytes32 indexed trustorNode,
        bytes32 indexed trusteeNode,
        TrustLevel level,
        bytes32 indexed scope,
        uint64 expiry
    );

    event TrustRevoked(
        bytes32 indexed trustorNode,
        bytes32 indexed trusteeNode,
        string reason
    );

    event IdentityGateSet(
        bytes32 indexed coordinationType,
        bytes32 indexed gatekeeperNode,
        uint8 maxPathLength,
        uint8 marginalThreshold
    );

    function setTrust(
        TrustAttestation calldata attestation,
        bytes calldata signature
    ) external;

    function setTrustBatch(
        TrustAttestation[] calldata attestations,
        bytes[] calldata signatures
    ) external;

    function revokeTrust(
        bytes32 trusteeNode,
        string calldata reason
    ) external;

    function getTrust(
        bytes32 trustorNode,
        bytes32 trusteeNode
    ) external view returns (TrustLevel level, bytes32 scope, uint64 expiry);

    function getNonce(bytes32 trustorNode) external view returns (uint64);

    function getTrustees(
        bytes32 trustorNode,
        TrustLevel minLevel
    ) external view returns (bytes32[] memory);

    function getTrustors(
        bytes32 trusteeNode,
        TrustLevel minLevel
    ) external view returns (bytes32[] memory);

    function validateAgent(
        bytes32 validatorNode,
        bytes32 targetNode,
        ValidationParams calldata params
    ) external view returns (
        bool isValid,
        uint8 pathLength,
        uint8 marginalCount,
        uint8 fullCount
    );

    function validateAgentBatch(
        bytes32 validatorNode,
        bytes32[] calldata targetNodes,
        ValidationParams calldata params
    ) external view returns (bool[] memory);

    function pathExists(
        bytes32 fromNode,
        bytes32 toNode,
        uint8 maxDepth
    ) external view returns (bool exists, uint8 depth);

    function setIdentityGate(
        bytes32 coordinationType,
        bytes32 gatekeeperNode,
        ValidationParams calldata params
    ) external;

    function removeIdentityGate(bytes32 coordinationType) external;

    function getIdentityGate(
        bytes32 coordinationType
    ) external view returns (
        bytes32 gatekeeperNode,
        ValidationParams memory params,
        bool enabled
    );

    function validateParticipant(
        bytes32 coordinationType,
        bytes32 participantNode
    ) external view returns (bool isValid);

    function validateParticipantBatch(
        bytes32 coordinationType,
        bytes32[] calldata participantNodes
    ) external view returns (bool[] memory);
}
```

### TrustRegistry.sol

See [`contracts/TrustRegistry.sol`](/assets/eip-XXXX/contracts/TrustRegistry.sol) for the complete implementation.

## Security Considerations

### Sybil Attacks

An attacker can create many ENS names and establish mutual trust between them.

**Mitigations:**

* Require trust paths to pass through established "anchor" agents
* Weight trust by ENS name age or registration cost
* Use short `maxPathLength` for high-value coordination
* Implement additional stake requirements at the application layer

### Trust Graph Manipulation

Attackers may attempt to position themselves in many trust paths.

**Mitigations:**

* Require multiple independent paths (not just multiple attestations from same cluster)
* Monitor trust graphs for anomalous patterns off-chain
* Cap per-agent influence in validation algorithms

### Key Compromise

If an ENS name's controller is compromised:

**Mitigations:**

* Agents SHOULD monitor for unexpected trust changes
* Implementations MAY support time-delayed trust changes
* ENS name owners can rotate controllers

### Replay Protection

[EIP-712](/EIPS/eip-712) domain binding prevents cross-contract replay. Monotonic nonces prevent replay within the same contract.

### Stale Trust

Trust relationships may become stale if agents don't update them.

**Mitigations:**

* Use `enforceExpiry: true` in validation parameters
* Implementations SHOULD emit warnings for trust > 1 year old
* Consider trust decay in off-chain reputation systems

### Privacy

Trust relationships are public. Agents concerned about privacy can:

* Use pseudonymous ENS names
* Establish trust through intermediate agents
* Use scoped trust to limit exposure

Future extensions MAY add privacy-preserving validation using zero-knowledge proofs.

### ENS Dependency

This standard depends on ENS availability. If ENS becomes unavailable:

* Existing trust relationships remain in storage
* New attestations cannot be verified
* Implementations SHOULD handle ENS failures gracefully

## Copyright

Copyright and related rights waived via [CC0](/LICENSE).
