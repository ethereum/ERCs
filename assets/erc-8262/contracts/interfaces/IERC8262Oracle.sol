// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title IERC8262Oracle -- Standard interface for ZK compliance attestation oracle
/// @notice Records and queries compliance attestations backed by zero-knowledge proofs
interface IERC8262Oracle {
    /// @notice A compliance attestation recorded on-chain
    struct ComplianceAttestation {
        address subject; // address that proved compliance
        uint8 jurisdictionId; // jurisdiction (0=EU, 1=US, 2=UK, 3=SG)
        uint8 proofType; // which proof type generated this attestation (0x01-0x09)
        bool meetsThreshold; // whether risk score is below filing trigger
        uint256 timestamp; // block.timestamp when attestation was recorded
        uint256 expiresAt; // timestamp after which attestation is stale
        bytes32 proofHash; // keccak256(proof, proofType, chainId, oracleAddr) -- see computeProofHash
        bytes32 providerSetHash; // hash of provider IDs + weights used
        bytes32 publicInputsHash; // keccak256 of the public inputs
        address verifierUsed; // verifier contract address at submission time
    }

    /// @notice Emitted when a compliance proof is verified and attestation recorded
    event ComplianceVerified(
        address indexed subject,
        uint8 indexed jurisdictionId,
        bool meetsThreshold,
        bytes32 indexed proofHash,
        uint256 expiresAt,
        uint256 previousExpiresAt
    );

    /// @notice Emitted when provider weights are updated
    event ProviderWeightsUpdated(bytes32 indexed configHash, uint256 timestamp, string metadataURI);

    /// @notice Emitted when attestation TTL is updated
    event AttestationTTLUpdated(uint256 oldTTL, uint256 newTTL);

    /// @notice Emitted when a provider config hash is revoked
    event ConfigRevoked(bytes32 indexed configHash);

    /// @notice Emitted when a merkle root is registered for membership proofs
    event MerkleRootRegistered(bytes32 indexed merkleRoot);

    /// @notice Emitted when a merkle root is revoked
    event MerkleRootRevoked(bytes32 indexed merkleRoot);

    /// @notice Emitted when a reporting threshold is registered for PATTERN proofs
    event ReportingThresholdRegistered(bytes32 indexed threshold);

    /// @notice Emitted when a reporting threshold is revoked
    event ReportingThresholdRevoked(bytes32 indexed threshold);

    /// @notice Submit a compliance proof and record the attestation
    /// @param jurisdictionId Target jurisdiction (0=EU, 1=US, 2=UK, 3=SG)
    /// @param proofType The proof type for verifier routing (0x01-0x09)
    /// @param proof The ZK proof data
    /// @param publicInputs Public inputs matching the circuit's pub parameters
    /// @param providerSetHash Hash of provider IDs and weights used for screening
    /// @return attestation The recorded compliance attestation
    function submitCompliance(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata publicInputs,
        bytes32 providerSetHash
    ) external returns (ComplianceAttestation memory attestation);

    /// @notice Check if an address has a valid (non-expired) compliance attestation
    /// @param subject The address to check
    /// @param jurisdictionId The jurisdiction to check against
    /// @return valid Whether a valid attestation exists
    /// @return attestation The attestation if valid
    function checkCompliance(address subject, uint8 jurisdictionId)
        external
        view
        returns (bool valid, ComplianceAttestation memory attestation);

    /// @notice Check compliance filtered by proof type
    /// @param subject The address to check
    /// @param jurisdictionId The jurisdiction to check against
    /// @param proofType The required proof type (0x01-0x09)
    /// @return valid Whether a valid attestation of the specified type exists
    /// @return attestation The attestation if valid
    function checkComplianceByType(address subject, uint8 jurisdictionId, uint8 proofType)
        external
        view
        returns (bool valid, ComplianceAttestation memory attestation);

    /// @notice Retrieve a proof for retroactive verification (proof-of-innocence)
    /// @param proofHash The hash of the original compliance proof
    /// @return attestation The original attestation record
    function getHistoricalProof(bytes32 proofHash) external view returns (ComplianceAttestation memory attestation);

    /// @notice Get the proof type used to generate an attestation
    /// @param proofHash The hash of the original proof
    /// @return proofType The proof type identifier (see ProofTypes library)
    function getProofType(bytes32 proofHash) external view returns (uint8 proofType);

    /// @notice Get all attestation hashes for a subject in a jurisdiction
    /// @dev Unbounded return -- may exceed gas/RPC limits for subjects with many
    ///      attestations. Use getAttestationHistoryPaginated() for production.
    /// @param subject The address to query
    /// @param jurisdictionId The jurisdiction
    /// @return proofHashes Array of proof hashes for historical lookup
    function getAttestationHistory(address subject, uint8 jurisdictionId)
        external
        view
        returns (bytes32[] memory proofHashes);

    /// @notice Get the current provider weight configuration hash
    /// @return configHash Hash of current provider weights
    function providerConfigHash() external view returns (bytes32 configHash);

    /// @notice Submit a batch of compliance proofs atomically
    /// @param jurisdictionId Target jurisdiction for all entries (0=EU, 1=US, 2=UK, 3=SG)
    /// @param proofTypes The proof type for each entry (0x01-0x09)
    /// @param proofs The ZK proof data for each entry
    /// @param publicInputs Public inputs for each entry
    /// @param providerSetHashes Provider set hash for each entry
    /// @return attestations The recorded compliance attestations
    function submitComplianceBatch(
        uint8 jurisdictionId,
        uint8[] calldata proofTypes,
        bytes[] calldata proofs,
        bytes[] calldata publicInputs,
        bytes32[] calldata providerSetHashes
    ) external returns (ComplianceAttestation[] memory attestations);

    /// @notice Get the current attestation time-to-live
    /// @return ttl Duration in seconds that attestations remain valid
    function attestationTTL() external view returns (uint256 ttl);
}
