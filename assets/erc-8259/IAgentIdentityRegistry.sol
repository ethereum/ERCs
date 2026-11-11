// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title IAgentIdentityRegistry
 * @notice Standard interface for AI agent decentralized identity and reputation management.
 */
interface IAgentIdentityRegistry {

    struct AgentIdentity {
        string did;
        bytes32 publicKey;
        uint8 verificationTier;
        uint16 reputationScore;
        uint256 registrationTime;
        uint256 lastUpdate;
        uint256 verificationExpiry;
        string metadataURI;
        bool isActive;
        uint256 totalTransactions;
        uint256 successfulTransactions;
    }

    struct VerificationTier {
        string name;
        string requirements;
        uint16 trustMultiplier;
        uint256 verificationFee;
        uint256 validityPeriod;
    }

    event AgentRegistered(
        string indexed did,
        address indexed agentAddress,
        uint8 verificationTier,
        uint16 reputationScore,
        uint256 registrationTime
    );

    event AgentUpdated(
        string indexed did,
        uint16 reputationScore,
        uint8 verificationTier,
        uint256 lastUpdate
    );

    event ReputationScoreUpdated(
        string indexed did,
        uint16 oldScore,
        uint16 newScore,
        string updateReason
    );

    event VerificationTierUpdated(
        string indexed did,
        address indexed agentAddress,
        uint8 oldTier,
        uint8 newTier,
        uint256 verificationExpiry
    );

    /**
     * @notice Registers a new AI agent identity at tier 0 (unverified).
     * @dev Newly registered agents MUST initialize at verificationTier 0. The caller MUST be authorized
     * to register the corresponding agent address.
     * @param did Decentralized identifier following did:agent:<chainId>:<address>.
     * @param publicKey Public key associated with the agent.
     * @param metadataURI Off-chain metadata URI (e.g. IPFS).
     * @return agentId Assigned unique identifier for the registered agent.
     */
    function registerAgent(
        string calldata did,
        bytes32 publicKey,
        string calldata metadataURI
    ) external payable returns (uint256 agentId);

    /**
     * @notice Updates the reputation score for an agent.
     * @dev MUST revert if called by an unauthorized address.
     * @param agentAddress Address of the agent whose score is being updated.
     * @param newScore New reputation score (0-1000).
     * @param updateReason Justification string for the score update.
     */
    function updateReputationScore(
        address agentAddress,
        uint16 newScore,
        string calldata updateReason
    ) external;

    /**
     * @notice Updates the verification tier and expiration of an agent.
     * @dev MUST revert if called by an unauthorized address.
     * @param agentAddress Address of the agent.
     * @param newTier New tier level (0-4).
     * @param validityPeriod Duration in seconds until this tier verification expires.
     */
    function updateVerificationTier(
        address agentAddress,
        uint8 newTier,
        uint256 validityPeriod
    ) external payable;

    /**
     * @notice Returns the effective verification tier of an agent, accounting for active status and expiry.
     * @dev MUST return 0 if the agent is inactive (!isActive) OR if block.timestamp > verificationExpiry.
     * @param agentAddress Address of the agent.
     * @return Effective verification tier level (0-4).
     */
    function getEffectiveTier(address agentAddress)
        external
        view
        returns (uint8);

    /**
     * @notice Returns the full identity record for a given agent address.
     * @param agentAddress Address of the agent.
     * @return AgentIdentity struct containing stored registration data.
     */
    function getAgentIdentity(address agentAddress)
        external
        view
        returns (AgentIdentity memory);

    /**
     * @notice Resolves an agent address from its DID string.
     * @param did Decentralized identifier string.
     * @return Address of the corresponding agent.
     */
    function getAgentByDID(string calldata did)
        external
        view
        returns (address);

    /**
     * @notice Queries whether an agent has active, unexpired verification.
     * @dev MUST return false if the agent is inactive (!isActive) or if getEffectiveTier <= 0.
     * @param agentAddress Address of the agent.
     * @return True if the agent is active and holds an unexpired verification tier above 0.
     */
    function isVerified(address agentAddress)
        external
        view
        returns (bool);

    /**
     * @notice Computes an effective trust score for an agent combining reputation and tier.
     * @dev MUST return 0 if the agent is inactive (!isActive).
     *      MUST use getEffectiveTier(agentAddress) — not the stored verificationTier field — for
     *      any tier-based weighting or multiplier. An expired verification MUST contribute zero
     *      tier boost to the returned score even if the stored verificationTier field is non-zero.
     * @param agentAddress Address of the agent.
     * @return Effective score between 0 and 1000 (0 for inactive agents).
     */
    function calculateTrustScore(address agentAddress)
        external
        view
        returns (uint16);
}
