// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title Trust Levels for Web of Trust
/// @notice Four-level trust model based on GnuPG
enum TrustLevel {
    Unknown, // 0: No trust relationship established
    None, // 1: Explicitly distrusted
    Marginal, // 2: Partial trust — multiple required for validation
    Full // 3: Complete trust — single attestation sufficient
}

/// @title Trust Attestation
/// @notice Signed declaration of trust from one agent to another
struct TrustAttestation {
    bytes32 trustorNode; // ENS namehash of trustor
    bytes32 trusteeNode; // ENS namehash of trustee
    TrustLevel level; // Trust level assigned
    bytes32 scope; // Scope restriction; bytes32(0) = universal
    uint64 expiry; // Unix timestamp; 0 = no expiry
    uint64 nonce; // Per-trustor monotonic nonce
}

/// @title Validation Parameters
/// @notice Configuration for web of trust validation
struct ValidationParams {
    uint8 maxPathLength; // Maximum trust chain depth
    uint8 marginalThreshold; // Marginal attestations required
    uint8 fullThreshold; // Full attestations required (usually 1)
    bytes32 scope; // Required scope; bytes32(0) = any
    bool enforceExpiry; // Check expiry on all chain elements
}

/// @title ENS Trust Registry Interface
/// @notice Web of trust validation using ENS names for ERC-8001 coordination
/// @dev Implements transitive trust following GnuPG model
interface ITrustRegistry {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when trust is set or updated
    /// @param trustorNode ENS namehash of the trusting agent
    /// @param trusteeNode ENS namehash of the trusted agent
    /// @param level Trust level assigned
    /// @param scope Scope of trust (bytes32(0) = universal)
    /// @param expiry Expiration timestamp (0 = never)
    event TrustSet(
        bytes32 indexed trustorNode, bytes32 indexed trusteeNode, TrustLevel level, bytes32 indexed scope, uint64 expiry
    );

    /// @notice Emitted when trust is explicitly revoked
    /// @param trustorNode ENS namehash of the revoking agent
    /// @param trusteeNode ENS namehash of the revoked agent
    /// @param reason Human-readable reason for revocation
    event TrustRevoked(bytes32 indexed trustorNode, bytes32 indexed trusteeNode, string reason);

    /// @notice Emitted when an identity gate is configured for ERC-8001
    /// @param coordinationType The ERC-8001 coordination type
    /// @param gatekeeperNode Agent whose trust graph gates entry
    /// @param maxPathLength Maximum path length for validation
    /// @param marginalThreshold Marginal attestations required
    event IdentityGateSet(
        bytes32 indexed coordinationType, bytes32 indexed gatekeeperNode, uint8 maxPathLength, uint8 marginalThreshold
    );

    /// @notice Emitted when an identity gate is removed
    /// @param coordinationType The ERC-8001 coordination type
    event IdentityGateRemoved(bytes32 indexed coordinationType);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when attempting self-trust
    error SelfTrustProhibited();

    /// @notice Thrown when nonce is not strictly increasing
    /// @param provided The nonce provided in the attestation
    /// @param required The minimum required nonce
    error NonceTooLow(uint64 provided, uint64 required);

    /// @notice Thrown when attestation has expired
    /// @param expiry The attestation's expiry timestamp
    /// @param currentTime Current block timestamp
    error AttestationExpired(uint64 expiry, uint64 currentTime);

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when actor is not authorized for ENS node
    /// @param node The ENS namehash
    /// @param actor The unauthorized address
    error NotAuthorized(bytes32 node, address actor);

    /// @notice Thrown when ENS name does not exist
    /// @param node The ENS namehash
    error ENSNameNotFound(bytes32 node);

    /// @notice Thrown when trust relationship does not exist
    /// @param trustorNode The trustor's ENS namehash
    /// @param trusteeNode The trustee's ENS namehash
    error TrustNotFound(bytes32 trustorNode, bytes32 trusteeNode);

    /// @notice Thrown when identity gate does not exist
    /// @param coordinationType The coordination type
    error GateNotFound(bytes32 coordinationType);

    /// @notice Thrown when validation parameters are invalid
    error InvalidValidationParams();

    /// @notice Thrown when batch array lengths don't match
    error ArrayLengthMismatch();

    // ═══════════════════════════════════════════════════════════════════════════
    // TRUST MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set trust level for another agent
    /// @dev Requires EIP-712 signature from trustor's ENS controller
    /// @param attestation The trust attestation
    /// @param signature EIP-712 signature
    function setTrust(TrustAttestation calldata attestation, bytes calldata signature) external;

    /// @notice Batch set multiple trust relationships
    /// @dev More gas-efficient than multiple setTrust calls
    /// @param attestations Array of trust attestations
    /// @param signatures Corresponding EIP-712 signatures
    function setTrustBatch(TrustAttestation[] calldata attestations, bytes[] calldata signatures) external;

    /// @notice Revoke trust (sets level to None)
    /// @dev Caller must be authorized for trustor's ENS node
    /// @param trusteeNode The agent to revoke trust from
    /// @param reason Human-readable reason for revocation
    function revokeTrust(bytes32 trusteeNode, string calldata reason) external;

    /// @notice Get trust record between two agents
    /// @param trustorNode The trusting agent's ENS namehash
    /// @param trusteeNode The trusted agent's ENS namehash
    /// @return level Current trust level
    /// @return scope Trust scope
    /// @return expiry Expiration timestamp (0 = never)
    function getTrust(bytes32 trustorNode, bytes32 trusteeNode)
        external
        view
        returns (TrustLevel level, bytes32 scope, uint64 expiry);

    /// @notice Get current nonce for a trustor
    /// @param trustorNode The agent's ENS namehash
    /// @return Current nonce value
    function getNonce(bytes32 trustorNode) external view returns (uint64);

    /// @notice Get all agents trusted by a given agent
    /// @param trustorNode The trusting agent's ENS namehash
    /// @param minLevel Minimum trust level to include
    /// @return trustees Array of trusted agent namehashes
    function getTrustees(bytes32 trustorNode, TrustLevel minLevel) external view returns (bytes32[] memory trustees);

    /// @notice Get all agents that trust a given agent
    /// @param trusteeNode The trusted agent's ENS namehash
    /// @param minLevel Minimum trust level to include
    /// @return trustors Array of trusting agent namehashes
    function getTrustors(bytes32 trusteeNode, TrustLevel minLevel) external view returns (bytes32[] memory trustors);

    // ═══════════════════════════════════════════════════════════════════════════
    // WEB OF TRUST VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate an agent through the web of trust
    /// @dev Implements GnuPG-style transitive trust validation
    /// @param validatorNode The validating agent's ENS namehash
    /// @param targetNode The agent to validate
    /// @param params Validation parameters
    /// @return isValid Whether the target is valid
    /// @return pathLength Shortest path found (0 = direct trust)
    /// @return marginalCount Marginal attestations contributing
    /// @return fullCount Full attestations contributing
    function validateAgent(bytes32 validatorNode, bytes32 targetNode, ValidationParams calldata params)
        external
        view
        returns (bool isValid, uint8 pathLength, uint8 marginalCount, uint8 fullCount);

    /// @notice Batch validate multiple agents
    /// @param validatorNode The validating agent's ENS namehash
    /// @param targetNodes Array of agents to validate
    /// @param params Validation parameters
    /// @return results Validation result for each target
    function validateAgentBatch(bytes32 validatorNode, bytes32[] calldata targetNodes, ValidationParams calldata params)
        external
        view
        returns (bool[] memory results);

    /// @notice Check if a trust path exists (without full validation)
    /// @dev Lighter weight than full validation
    /// @param fromNode Starting agent's ENS namehash
    /// @param toNode Ending agent's ENS namehash
    /// @param maxDepth Maximum path length to search
    /// @return exists Whether any path exists
    /// @return depth Length of shortest path found
    function pathExists(bytes32 fromNode, bytes32 toNode, uint8 maxDepth)
        external
        view
        returns (bool exists, uint8 depth);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-8001 INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set identity gate for an ERC-8001 coordination type
    /// @dev Only callable by gatekeeper's ENS controller
    /// @param coordinationType The ERC-8001 coordination type
    /// @param gatekeeperNode Agent whose trust graph gates entry
    /// @param params Validation parameters for the gate
    function setIdentityGate(bytes32 coordinationType, bytes32 gatekeeperNode, ValidationParams calldata params)
        external;

    /// @notice Remove identity gate for a coordination type
    /// @dev Only callable by current gatekeeper's ENS controller
    /// @param coordinationType The ERC-8001 coordination type
    function removeIdentityGate(bytes32 coordinationType) external;

    /// @notice Get identity gate configuration
    /// @param coordinationType The ERC-8001 coordination type
    /// @return gatekeeperNode The gatekeeper agent's ENS namehash
    /// @return params Validation parameters
    /// @return enabled Whether the gate is active
    function getIdentityGate(bytes32 coordinationType)
        external
        view
        returns (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled);

    /// @notice Validate participant for ERC-8001 coordination
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participantNode Agent seeking to participate
    /// @return isValid Whether participant passes the gate
    function validateParticipant(bytes32 coordinationType, bytes32 participantNode) external view returns (bool isValid);

    /// @notice Batch validate participants for coordination
    /// @param coordinationType The ERC-8001 coordination type
    /// @param participantNodes Array of agents seeking to participate
    /// @return results Validation result for each participant
    function validateParticipantBatch(bytes32 coordinationType, bytes32[] calldata participantNodes)
        external
        view
        returns (bool[] memory results);

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the ENS registry address
    /// @return The ENS registry contract address
    function ens() external view returns (address);

    /// @notice Get default validation parameters
    /// @return Default ValidationParams struct
    function defaultParams() external pure returns (ValidationParams memory);

    /// @notice Compute EIP-712 digest for a trust attestation
    /// @param attestation The trust attestation
    /// @return The EIP-712 typed data hash
    function hashAttestation(TrustAttestation calldata attestation) external view returns (bytes32);
}
