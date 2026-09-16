// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Trust Level
/// @notice Canonical trust levels, following the GnuPG web of trust model
/// @dev Ordering is significant: `verifyPath` compares levels with `<`
enum TrustLevel {
    Unknown, // 0: No trust relationship established
    None, // 1: Explicitly distrusted
    Marginal, // 2: Partial trust - multiple required for validation
    Full // 3: Complete trust - single attestation sufficient

}

/// @title Trust Attestation
/// @notice A signed statement that `trustorNode` trusts `trusteeNode` in `scope`
struct TrustAttestation {
    bytes32 trustorNode; // ENS namehash of trustor
    bytes32 trusteeNode; // ENS namehash of trustee
    TrustLevel level; // Trust level assigned
    bytes32 scope; // Scope restriction; bytes32(0) = universal
    uint64 expiry; // Unix timestamp; 0 = no expiry
    uint64 nonce; // Per-trustor monotonic nonce
}

/// @title Validation Parameters
/// @notice Configuration for web of trust path validation
struct ValidationParams {
    uint8 maxPathLength; // Maximum trust chain depth (1-10)
    TrustLevel minEdgeTrust; // Minimum trust level required on each edge
    bytes32 scope; // Scope to verify against; bytes32(0) = universal
    bool enforceExpiry; // Check expiry on all chain elements
    bytes32[] requiredAnchors; // Path MUST traverse at least one anchor; empty = no requirement
}

/// @title Trust Path
/// @notice A pre-computed chain of ENS nodes: [validator, ...intermediaries..., target]
/// @dev Path length is measured in edges: `nodes.length - 1`
struct TrustPath {
    bytes32[] nodes;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

error SelfTrustProhibited();
error InvalidAttestationLevel(TrustLevel level);
error NonceTooLow(uint64 provided, uint64 required);
error AttestationExpired(uint64 expiry, uint64 currentTime);
error InvalidSignature();
error NotAuthorized(bytes32 node, address actor);
error ENSNameNotFound(bytes32 node);
error GateNotFound(bytes32 coordinationType);
error InvalidMaxPathLength(uint8 provided);
error InvalidMinEdgeTrust(TrustLevel provided);
error TooManyRequiredAnchors(uint256 provided);
error BatchTrustorMismatch();
error BatchNonceNotIncreasing();
error EmptyScopeList();

/// @title ENS Trust Registry Interface
/// @notice Web of trust validation using ENS names for ERC-8001 coordination
/// @dev Reference interface for ERC-8107
interface ITrustRegistry is IERC165 {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when trust is set or updated
    event TrustSet(
        bytes32 indexed trustorNode, bytes32 indexed trusteeNode, TrustLevel level, bytes32 indexed scope, uint64 expiry
    );

    /// @notice Emitted when trust is explicitly revoked
    event TrustRevoked(
        bytes32 indexed trustorNode, bytes32 indexed trusteeNode, bytes32 indexed scope, bytes32 reasonCode
    );

    /// @notice Emitted when a trustor invalidates outstanding attestations
    event NoncesInvalidated(bytes32 indexed trustorNode, uint64 newNonce);

    /// @notice Emitted when an identity gate is configured
    /// @dev Carries the complete ValidationParams so indexers can reconstruct gate
    ///      configuration from logs alone
    event IdentityGateSet(
        address indexed coordinator,
        bytes32 indexed coordinationType,
        bytes32 indexed gatekeeperNode,
        uint8 maxPathLength,
        TrustLevel minEdgeTrust,
        bytes32 scope,
        bool enforceExpiry,
        bytes32[] requiredAnchors
    );

    /// @notice Emitted when an identity gate is removed
    event IdentityGateRemoved(address indexed coordinator, bytes32 indexed coordinationType);

    // ═══════════════════════════════════════════════════════════════════════════
    // TRUST MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set trust level for another agent in a specific scope
    /// @dev Signature MUST be from ENS owner (EOA) or validate via EIP-1271 (contract).
    ///      `level` MUST be Marginal or Full; distrust goes through revokeTrust.
    /// @param attestation The trust attestation
    /// @param signature EIP-712 signature from trustor's ENS owner
    function setTrust(TrustAttestation calldata attestation, bytes calldata signature) external;

    /// @notice Batch set multiple trust relationships
    /// @dev All attestations MUST share the same trustorNode
    /// @param attestations Array of trust attestations
    /// @param signatures Corresponding signatures
    function setTrustBatch(TrustAttestation[] calldata attestations, bytes[] calldata signatures) external;

    /// @notice Set explicit distrust (level None) for one scope
    /// @dev Caller MUST be ENS owner or approved operator. Prior trust is NOT required:
    ///      a trustor may preemptively distrust an agent it never trusted.
    /// @param trustorNode The trustor's ENS namehash
    /// @param trusteeNode The agent to revoke trust from
    /// @param scope The scope to revoke trust in
    /// @param reasonCode Reason code for revocation
    function revokeTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode) external;

    /// @notice Revoke trust across several scopes in one transaction
    /// @dev Caller MUST be name controller or approved operator. Scopes are supplied by
    ///      the caller; this standard does not enumerate them on-chain.
    /// @param trustorNode The trustor's ENS namehash
    /// @param trusteeNode The agent to revoke trust from
    /// @param scopes The scopes to revoke trust in
    /// @param reasonCode Reason code for revocation
    function revokeTrustBatch(
        bytes32 trustorNode,
        bytes32 trusteeNode,
        bytes32[] calldata scopes,
        bytes32 reasonCode
    ) external;

    /// @notice Invalidate every outstanding attestation below a nonce
    /// @dev Caller MUST be the name controller. Approved operators are NOT sufficient:
    ///      this voids every outstanding attestation across all trustees and scopes.
    ///      Revocation alone does NOT invalidate attestations the trustor already signed
    ///      but has not yet submitted; this does.
    /// @param trustorNode The trustor's ENS namehash
    /// @param newNonce The new nonce floor; MUST exceed the current nonce
    function invalidateNonces(bytes32 trustorNode, uint64 newNonce) external;

    /// @notice Get trust record between two agents in a specific scope
    /// @param trustorNode The trusting agent
    /// @param trusteeNode The trusted agent
    /// @param scope The trust scope (bytes32(0) for universal)
    /// @return level Current trust level
    /// @return expiry Expiration timestamp (0 = never)
    function getTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope)
        external
        view
        returns (TrustLevel level, uint64 expiry);

    /// @notice Get current nonce for a trustor
    /// @param trustorNode The agent's ENS namehash
    /// @return Current nonce value
    function getNonce(bytes32 trustorNode) external view returns (uint64);

    // ═══════════════════════════════════════════════════════════════════════════
    // PATH VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify a pre-computed trust path
    /// @dev Returns true only if every edge check AND the requiredAnchors constraint
    ///      are satisfied. There is no partial success.
    /// @param path The trust path to verify
    /// @param params Validation parameters
    /// @return valid Whether the path satisfies all validation requirements
    function verifyPath(TrustPath calldata path, ValidationParams calldata params)
        external
        view
        returns (bool valid);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-8001 INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set the identity gate for one of the caller's coordination types
    /// @dev Stored under `(msg.sender, coordinationType)`. Callers own their own
    ///      namespace, so no cross-caller authorisation is needed and well-known
    ///      coordination type constants cannot be squatted.
    /// @param coordinationType The ERC-8001 coordination type
    /// @param gatekeeperNode Agent whose trust graph gates entry
    /// @param params Validation parameters for the gate
    function setIdentityGate(bytes32 coordinationType, bytes32 gatekeeperNode, ValidationParams calldata params)
        external;

    /// @notice Remove the caller's identity gate for a coordination type
    /// @param coordinationType The ERC-8001 coordination type
    function removeIdentityGate(bytes32 coordinationType) external;

    /// @notice Get identity gate configuration
    /// @param coordinator The address that registered the gate
    /// @param coordinationType The ERC-8001 coordination type
    /// @return gatekeeperNode The gatekeeper agent
    /// @return params Validation parameters
    /// @return enabled Whether the gate is active
    function getIdentityGate(address coordinator, bytes32 coordinationType)
        external
        view
        returns (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled);

    /// @notice Resolve the agent address bound to an ENS node
    /// @param node The agent's ENS namehash
    /// @return agent The node's forward address record, or address(0) if unset
    function resolveAgent(bytes32 node) external view returns (address agent);

    /// @notice Validate a participant identified by ENS node
    /// @param coordinator The address that registered the gate
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participantNode The agent being gated
    /// @param path Pre-computed trust path from gatekeeper to participantNode
    /// @return isValid Whether participant passes the gate
    function validateParticipantWithPath(
        address coordinator,
        bytes32 coordinationType,
        bytes32 participantNode,
        TrustPath calldata path
    ) external view returns (bool isValid);

    /// @notice Validate an ERC-8001 participant identified by address
    /// @dev The terminal node of `path` MUST resolve to `participant`. This is the hook
    ///      an ERC-8001 coordinator calls for each entry in `participants`.
    /// @param coordinator The address that registered the gate
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participant The participant address taken from the ERC-8001 intent
    /// @param path Pre-computed trust path from gatekeeper to the participant's node
    /// @return isValid Whether participant passes the gate
    function validateParticipantAddress(
        address coordinator,
        bytes32 coordinationType,
        address participant,
        TrustPath calldata path
    ) external view returns (bool isValid);
}

/// @title ENS Trust Registry - OPTIONAL Extensions
/// @notice Convenience and on-chain-search functions. NOT required for ERC-8107 compliance.
/// @dev On-chain graph traversal is expensive and DoS-prone; prefer off-chain path
///      computation with `verifyPath`. Provided for completeness only.
interface ITrustRegistryExtended is ITrustRegistry {
    /// @notice Get agents trusted by a given agent (paginated)
    function getTrustees(bytes32 trustorNode, TrustLevel minLevel, bytes32 scope, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory trustees, uint256 total);

    /// @notice Get agents that trust a given agent (paginated)
    function getTrustors(bytes32 trusteeNode, TrustLevel minLevel, bytes32 scope, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory trustors, uint256 total);

    /// @notice Validate an agent through on-chain graph traversal
    function validateAgent(
        bytes32 validatorNode,
        bytes32 targetNode,
        ValidationParams calldata params,
        uint8 marginalThreshold,
        uint8 fullThreshold
    ) external view returns (bool isValid, uint8 pathLength, uint8 marginalCount, uint8 fullCount);

    /// @notice Check if any trust path exists
    function pathExists(bytes32 fromNode, bytes32 toNode, uint8 maxDepth)
        external
        view
        returns (bool exists, uint8 depth);

    /// @notice Validate participant without pre-computed path
    function validateParticipant(
        address coordinator,
        bytes32 coordinationType,
        bytes32 participantNode,
        uint8 marginalThreshold,
        uint8 fullThreshold
    ) external view returns (bool isValid);
}
