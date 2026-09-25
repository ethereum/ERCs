// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC8262Oracle} from "./interfaces/IERC8262Oracle.sol";
import {IERC8262Verifier} from "./interfaces/IERC8262Verifier.sol";
import {IUltraVerifier} from "./interfaces/IUltraVerifier.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {ProofTypes} from "./libraries/ProofTypes.sol";
import {JurisdictionConfig} from "./libraries/JurisdictionConfig.sol";
import {AccessControl} from "./libraries/AccessControl.sol";
import {Pausable} from "./libraries/Pausable.sol";
import {EIP712Attestation} from "./libraries/EIP712Attestation.sol";
import {EIP712CredentialRoot} from "./libraries/EIP712CredentialRoot.sol";

/// @title ERC8262Oracle -- Reference implementation of the ERC-8262 compliance oracle
/// @notice Records compliance attestations backed by verified ZK proofs and supports
///         retroactive proof-of-innocence lookups
/// @dev Privileged actions are split across roles (see AccessControl):
///      - GUARDIAN: pause/unpause (global + per-proof-type), revokeConfig, denyProvider
///      - REGISTRAR: register/revoke merkle roots and reporting thresholds, set provider publishers
///      - CONFIG: updateProviderConfig (atomic with provider expansion),
///        updateAttestationTTL, compactConfigHistory
///      - owner: grant/revoke roles, transfer ownership
contract ERC8262Oracle is IERC8262Oracle, IERC165, AccessControl, Pausable {
    /// @notice The verifier contract used to validate proofs
    IERC8262Verifier public immutable verifier;

    /// @notice Hash of the current provider weight configuration
    bytes32 internal _providerConfigHash;

    /// @notice Duration in seconds that attestations remain valid (default: 24 hours)
    uint256 internal _attestationTTL;

    /// @notice Latest attestation per subject per jurisdiction
    /// @dev subject => jurisdictionId => attestation
    mapping(address subject => mapping(uint8 jurisdictionId => ComplianceAttestation attestation)) internal
        _attestations;

    /// @notice Attestation lookup by proof hash (for retroactive verification)
    mapping(bytes32 proofHash => ComplianceAttestation attestation) internal _proofIndex;

    /// @notice History of proof hashes per subject per jurisdiction
    /// @dev subject => jurisdictionId => proofHash[]
    mapping(address subject => mapping(uint8 jurisdictionId => bytes32[] proofHashes)) internal _attestationHistory;

    /// @notice Historical provider config hashes (versioned)
    bytes32[] internal _configHistory;

    /// @notice Track used proof hashes to prevent replay
    mapping(bytes32 proofHash => bool used) internal _usedProofs;

    /// @notice Proof type per proof hash (for downstream proof-type verification)
    mapping(bytes32 proofHash => uint8 proofType) internal _proofTypes;

    /// @notice Set of all valid (current + historical) provider config hashes
    mapping(bytes32 configHash => bool valid) internal _validConfigs;

    /// @notice Permanently-revoked provider config hashes; cannot be re-registered
    mapping(bytes32 configHash => bool revoked) internal _revokedConfigs;

    /// @notice Set of valid merkle roots for MEMBERSHIP/NON_MEMBERSHIP/ATTESTATION proofs
    mapping(bytes32 merkleRoot => bool valid) internal _validMerkleRoots;

    /// @notice Registered reporting thresholds for PATTERN proofs (anti-structuring)
    /// @dev Maps threshold value (as bytes32) to validity. Prevents jurisdiction spoofing
    ///      by ensuring the reporting_threshold in a PATTERN proof matches a registered value.
    mapping(bytes32 threshold => bool valid) internal _validReportingThresholds;

    /// @notice Per-proof-type pause state for surgical incident response
    mapping(uint8 proofType => bool isPaused) internal _proofTypePaused;

    /// @notice Per-provider authorized publisher EOA for ATTESTATION credential roots
    mapping(uint256 providerId => address publisher) internal _providerPublisher;

    /// @notice Per-provider credential-root signing key (audit C-1 closure).
    /// @dev Distinct from the publisher EOA. The publisher submits the publish tx;
    ///      the signing key (held in HSM/KMS) authorizes the *content* of the tree
    ///      via an EIP-712 signature over `CredentialRootPublication`. Compromise
    ///      of the publisher alone cannot forge credentials -- the publish tx
    ///      reverts unless the signature verifies against `_credentialSigner[providerId]`.
    mapping(uint256 providerId => address signer) internal _credentialSigner;

    /// @notice Per-config provider expansion: which provider IDs are members of a config hash.
    /// @dev Written atomically alongside the config registration (constructor +
    ///      `updateProviderConfig`). Used by `denyProvider` to invalidate every
    ///      config containing a compromised provider without rotating the
    ///      underlying hash. The expansion is trust-on-publish: the Oracle cannot
    ///      recompute the Pedersen-based providerSetHash on-chain, so CONFIG is
    ///      responsible for ensuring the expansion matches the off-chain config.
    ///      Mismatches do not affect proof acceptance unless `denyProvider` is
    ///      invoked -- which only the GUARDIAN can do.
    mapping(bytes32 configHash => uint256[] providerIds) internal _configProviders;

    /// @notice Provider IDs marked as compromised. Configs that include any denied provider
    ///         are rejected at compliance proof submission time.
    mapping(uint256 providerId => bool denied) internal _deniedProviders;

    /// @notice Highest proof-internal timestamp recorded per (subject, jurisdiction).
    /// @dev Per-subject ratchet that prevents an old proof from overwriting a newer attestation.
    ///      The stored value is the proof's `timestamp` public input (or `block.timestamp` for
    ///      proof types without an internal timestamp -- RISK_SCORE and PATTERN). New proofs
    ///      must be non-decreasing (>= last); equal timestamps are allowed so legitimate
    ///      same-block submissions of different proof types can coexist for the same pair.
    mapping(address subject => mapping(uint8 jurisdictionId => uint256 lastProofTimestamp)) internal
        _lastProofTimestamp;

    /// @notice Metadata for a published credential tree root
    struct CredentialRootInfo {
        uint256 providerId;
        uint64 registeredAt;
        bool revoked;
    }

    /// @notice Published credential roots with provenance + TTL window
    mapping(bytes32 root => CredentialRootInfo info) internal _credentialRoots;

    /// @notice Authorized signer pubkey hashes for COMPLIANCE_SIGNED / RISK_SCORE_SIGNED proofs.
    /// @dev Pedersen commitment to a secp256k1 (x, y) pubkey, layout per
    ///      `erc8262_shared::sig::compute_signer_pubkey_hash` in the circuits crate.
    ///      The signed-variant circuits expose `signer_pubkey_hash` as a public input;
    ///      the Oracle validates it against this registry. Rotating a compromised key
    ///      is `revokeSignerPubkeyHash` followed by `registerSignerPubkeyHash` for the
    ///      replacement -- the registry intentionally has no reuse-after-revoke
    ///      protection because secp256k1 keys are externally generated and a re-issued
    ///      key is a fresh hash.
    mapping(bytes32 signerPubkeyHash => bool valid) internal _validSignerPubkeyHashes;

    error ProofVerificationFailed();
    error ProofAlreadyUsed(bytes32 proofHash);
    error InvalidTTL();
    error AttestationNotFound(bytes32 proofHash);
    error PublicInputMismatch();
    error InvalidConfigHash(bytes32 configHash);
    error InvalidMerkleRoot(bytes32 merkleRoot);
    error InvalidReportingThreshold(bytes32 threshold);
    error CannotRevokeCurrentConfig();
    error ProofResultNegative();
    error SubmitterMismatch();
    error ConfigHistoryFull();
    error ConfigAlreadyCurrent();
    error AlreadyRegistered();
    error NotRegistered();
    error BatchLengthMismatch();
    error EmptyBatch();
    error BatchTooLarge();
    error TimeWindowTooSmall(uint256 timeWindow, uint256 minimum);
    error ProofTimestampStale(uint256 proofTimestamp, uint256 blockTimestamp);
    error ProofTimestampInFuture(uint256 proofTimestamp, uint256 blockTimestamp);
    error ProofTypePaused(uint8 proofType);
    error ProofTypeNotPaused(uint8 proofType);
    error InvalidRiskProofType(uint256 proofType);
    error InvalidRiskDirection(uint256 direction);
    error TrivialRiskBound(uint256 boundLower, uint256 boundUpper);
    error InvalidRiskBound(uint256 boundLower, uint256 boundUpper);
    error InvalidAnalysisType(uint256 analysisType);
    error ConfigPermanentlyRevoked(bytes32 configHash);
    error NotProviderPublisher(uint256 providerId, address caller);
    error CredentialRootAlreadyPublished(bytes32 root);
    error CredentialRootNotFound(bytes32 root);
    error InvalidProviderId();
    error CredentialRootExpired(bytes32 root, uint256 registeredAt);
    error CredentialRootProviderMismatch(uint256 expected, uint256 actual);
    error ConfigExpansionNotRegistered(bytes32 configHash);
    error ProviderDenied(uint256 providerId);
    error EmptyProviderExpansion();
    error ProofTimestampNotMonotonic(uint256 proofTimestamp, uint256 lastTimestamp);
    error SignedSignalsRequired(uint8 jurisdictionId, uint8 proofType);
    error InvalidSignerPubkeyHash(bytes32 signerPubkeyHash);
    error InsufficientSigners(uint8 active, uint8 required);
    error BelowJurisdictionMinProviders(uint8 jurisdictionId, uint8 m, uint8 floor);
    error DuplicateSigner(bytes32 signerPubkeyHash);
    error InvalidThresholdM(uint8 thresholdM);
    error CredentialSignerNotSet(uint256 providerId);
    error InvalidCredentialSignature();
    error CredentialSignatureOutOfWindow(uint64 notBefore, uint64 notAfter);
    error InvalidSignatureLength(uint256 length);
    /// @notice Raised when revoking a credential root that has already been revoked.
    ///         Distinct from `AlreadyRegistered` so consumers can distinguish
    ///         "double-revoke" from "duplicate registration".
    error CredentialRootAlreadyRevoked(bytes32 root);

    event ConfigHistoryCompacted(uint256 entriesRemoved, uint256 newLength);
    event ProviderPublisherSet(uint256 indexed providerId, address indexed previous, address indexed publisher);
    event CredentialSignerSet(uint256 indexed providerId, address indexed previous, address indexed signer);
    event CredentialRootPublished(uint256 indexed providerId, bytes32 indexed root, string cid, uint256 registeredAt);
    event CredentialRootRevoked(bytes32 indexed root);
    event ProviderConfigExpansionRegistered(bytes32 indexed configHash, uint256[] providerIds);
    event ProviderDeniedEvent(uint256 indexed providerId);
    event ProviderUndeniedEvent(uint256 indexed providerId);
    event SignerPubkeyHashRegistered(bytes32 indexed signerPubkeyHash);
    event SignerPubkeyHashRevoked(bytes32 indexed signerPubkeyHash);

    /// @notice Maximum number of entries in the config history array
    uint256 public constant MAX_CONFIG_HISTORY = 256;

    /// @notice Maximum number of proofs in a single batch submission.
    /// @dev Calibrated against the per-proof gas baseline in `.gas-snapshot`
    ///      (~2.83M for submitCompliance). 10 × 2.83M ≈ 28.3M, just under the
    ///      30M mainnet block gas target. Audit F-3.
    uint256 public constant MAX_BATCH_SIZE = 10;

    /// @notice Minimum time window for PATTERN (anti-structuring) proofs in seconds
    uint256 public constant MIN_TIME_WINDOW = 3600;

    /// @notice Maximum age of a proof timestamp relative to block.timestamp
    uint256 public constant MAX_PROOF_AGE = 1 hours;

    /// @notice Maximum risk score in basis points (matches risk_score circuit semantics)
    uint256 public constant MAX_RISK_SCORE_BPS = 10000;

    /// @notice Risk score proof_type identifiers (must match circuits/risk_score)
    uint8 internal constant RISK_PROOF_THRESHOLD = 0x01;
    uint8 internal constant RISK_PROOF_RANGE = 0x02;

    /// @notice Risk score direction identifiers (must match circuits/risk_score)
    uint8 internal constant RISK_DIRECTION_GT = 1;
    uint8 internal constant RISK_DIRECTION_LT = 2;

    /// @notice Pattern analysis identifiers (must match circuits/pattern)
    uint8 public constant PATTERN_STRUCTURING = 1;
    uint8 public constant PATTERN_VELOCITY = 2;
    uint8 public constant PATTERN_ROUND_AMOUNT = 3;

    /// @notice Lifetime of a published credential root before it auto-expires
    /// @dev Providers are expected to publish new roots more frequently than this; the
    ///      window allows a grace period during which old paths against an outgoing root
    ///      remain provable. After expiry, users must obtain paths against a current root.
    uint256 public constant CREDENTIAL_ROOT_TTL = 48 hours;

    /// @param _verifier The ERC8262Verifier contract address
    /// @param initialOwner The initial owner address
    /// @param initialConfigHash The initial provider weight configuration hash
    /// @param initialProviderIds Provider IDs whose weights are committed-to by
    ///        `initialConfigHash`. The expansion is written atomically with the
    ///        config so `denyProvider` enforcement is in effect from block one.
    ///        Must be non-empty; zero IDs are rejected (audit F-2).
    constructor(
        address _verifier,
        address initialOwner,
        bytes32 initialConfigHash,
        uint256[] memory initialProviderIds
    ) {
        if (_verifier == address(0) || initialOwner == address(0)) {
            revert ZeroAddress();
        }
        if (initialConfigHash == bytes32(0)) revert InvalidConfigHash(bytes32(0));

        verifier = IERC8262Verifier(_verifier);
        owner = initialOwner;
        _providerConfigHash = initialConfigHash;
        _attestationTTL = 24 hours;

        _configHistory.push(initialConfigHash);
        _validConfigs[initialConfigHash] = true;
        _writeConfigExpansion(initialConfigHash, initialProviderIds);

        emit OwnershipTransferred(address(0), initialOwner);
        emit ProviderWeightsUpdated(initialConfigHash, block.timestamp, "");
        emit ProviderConfigExpansionRegistered(initialConfigHash, initialProviderIds);
    }

    // -------------------------------------------------------------------------
    // IERC8262Oracle -- Core
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8262Oracle
    function submitCompliance(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata publicInputs,
        bytes32 providerSetHash
    ) external whenNotPaused returns (ComplianceAttestation memory attestation) {
        if (_proofTypePaused[proofType]) revert ProofTypePaused(proofType);
        JurisdictionConfig.validateJurisdiction(jurisdictionId);

        // Validate that caller-supplied parameters match what's in the proof's public inputs.
        // This prevents submitting a proof generated for one context in a different context.
        // Each validator returns the timestamp to ratchet on -- proof-internal for types that
        // expose one, block.timestamp otherwise.
        uint256 proofTimestamp = _validateAndExtractTimestamp(jurisdictionId, proofType, providerSetHash, publicInputs);
        _ratchet(jurisdictionId, proofTimestamp);

        // Verify proof and check replay (extracted to reduce stack depth)
        (address verifierUsed, bytes32 proofHash) = _verifyAndRecordProof(proofType, proof, publicInputs);

        // Build and store attestation (providerSetHash only meaningful for COMPLIANCE proofs)
        bytes32 effectiveProviderSetHash = (proofType == ProofTypes.COMPLIANCE
                || proofType == ProofTypes.COMPLIANCE_SIGNED || proofType == ProofTypes.COMPLIANCE_MULTI_SIGNED)
            ? providerSetHash
            : bytes32(0);
        attestation = _buildAttestation(
            jurisdictionId, proofType, proofHash, effectiveProviderSetHash, keccak256(publicInputs), verifierUsed
        );

        uint256 previousExpiresAt = _attestations[msg.sender][jurisdictionId].expiresAt;
        _attestations[msg.sender][jurisdictionId] = attestation;
        _proofIndex[proofHash] = attestation;
        _proofTypes[proofHash] = proofType;
        _attestationHistory[msg.sender][jurisdictionId].push(proofHash);

        emit ComplianceVerified(msg.sender, jurisdictionId, true, proofHash, attestation.expiresAt, previousExpiresAt);
    }

    /// @inheritdoc IERC8262Oracle
    function submitComplianceBatch(
        uint8 jurisdictionId,
        uint8[] calldata proofTypes,
        bytes[] calldata proofs,
        bytes[] calldata publicInputs,
        bytes32[] calldata providerSetHashes
    ) external whenNotPaused returns (ComplianceAttestation[] memory attestations) {
        uint256 length = proofTypes.length;
        if (length == 0) revert EmptyBatch();
        if (length > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (length != proofs.length || length != publicInputs.length || length != providerSetHashes.length) {
            revert BatchLengthMismatch();
        }

        JurisdictionConfig.validateJurisdiction(jurisdictionId);

        attestations = new ComplianceAttestation[](length);

        for (uint256 i; i < length;) {
            attestations[i] =
                _submitSingle(jurisdictionId, proofTypes[i], proofs[i], publicInputs[i], providerSetHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IERC8262Oracle
    function checkCompliance(address subject, uint8 jurisdictionId)
        external
        view
        returns (bool valid, ComplianceAttestation memory attestation)
    {
        attestation = _attestations[subject][jurisdictionId];

        // Valid if attestation exists, threshold was met, and not expired
        valid = attestation.timestamp > 0 && attestation.meetsThreshold && block.timestamp <= attestation.expiresAt;
    }

    /// @inheritdoc IERC8262Oracle
    function checkComplianceByType(address subject, uint8 jurisdictionId, uint8 proofType)
        external
        view
        returns (bool valid, ComplianceAttestation memory attestation)
    {
        attestation = _attestations[subject][jurisdictionId];
        valid = attestation.timestamp > 0 && attestation.meetsThreshold && block.timestamp <= attestation.expiresAt
            && attestation.proofType == proofType;
    }

    /// @inheritdoc IERC8262Oracle
    function getHistoricalProof(bytes32 proofHash) external view returns (ComplianceAttestation memory attestation) {
        attestation = _proofIndex[proofHash];
        if (attestation.timestamp == 0) revert AttestationNotFound(proofHash);
    }

    /// @inheritdoc IERC8262Oracle
    function getProofType(bytes32 proofHash) external view returns (uint8) {
        if (_proofIndex[proofHash].timestamp == 0) revert AttestationNotFound(proofHash);
        return _proofTypes[proofHash];
    }

    /// @inheritdoc IERC8262Oracle
    /// @dev WARNING: Returns an unbounded array. Gas cost scales linearly with the
    ///      number of attestations for the given (subject, jurisdictionId) pair.
    ///      A subject could self-attest many times (each with a unique proof), growing
    ///      the array until this view exceeds block gas limits or RPC response size.
    ///      This does NOT affect other users (submitter pays their own gas), but can
    ///      make this view unusable for the affected subject.
    ///      For production integrations, use getAttestationHistoryPaginated() which
    ///      supports offset/limit pagination and is safe regardless of history size.
    function getAttestationHistory(address subject, uint8 jurisdictionId)
        external
        view
        returns (bytes32[] memory proofHashes)
    {
        return _attestationHistory[subject][jurisdictionId];
    }

    /// @notice Get a paginated slice of attestation history
    /// @param subject The address to query
    /// @param jurisdictionId The jurisdiction
    /// @param offset Starting index
    /// @param limit Maximum number of entries to return
    /// @return proofHashes The proof hashes in the requested range
    /// @return total Total number of attestations for pagination
    function getAttestationHistoryPaginated(address subject, uint8 jurisdictionId, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory proofHashes, uint256 total)
    {
        bytes32[] storage history = _attestationHistory[subject][jurisdictionId];
        total = history.length;

        if (offset >= total) {
            return (new bytes32[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;

        proofHashes = new bytes32[](count);
        for (uint256 i; i < count;) {
            proofHashes[i] = history[offset + i];
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IERC8262Oracle
    function providerConfigHash() external view returns (bytes32 configHash) {
        return _providerConfigHash;
    }

    /// @inheritdoc IERC8262Oracle
    function attestationTTL() external view returns (uint256 ttl) {
        return _attestationTTL;
    }

    /// @notice EIP-712 domain separator for this oracle instance
    /// @dev Computed at call time using block.chainid (fork-safe, not cached)
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return EIP712Attestation.buildDomainSeparator(address(this));
    }

    /// @notice Compute the proofHash that this Oracle will derive for a given (proof, proofType).
    /// @dev Pure helper exposing the hashing scheme: keccak256(proof, proofType, chainId, oracle).
    ///      Off-chain integrators and tests should use this to derive expected proofHash values
    ///      rather than recomputing the encoding manually -- this function is the source of truth.
    function computeProofHash(bytes calldata proof, uint8 proofType) external view returns (bytes32) {
        return keccak256(abi.encodePacked(proof, proofType, block.chainid, address(this)));
    }

    /// @notice EIP-712 struct hash of a ComplianceAttestation
    /// @param att The attestation to hash
    /// @return structHash The EIP-712 struct hash
    function hashAttestation(ComplianceAttestation memory att) external pure returns (bytes32) {
        return EIP712Attestation.hashAttestation(att);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the provider weight configuration AND atomically register
    ///         its provider expansion (audit F-2 closure).
    /// @dev A previously-revoked config hash cannot be re-registered. Mistaken
    ///      revocations require deploying a fresh hash (hash of new metadata),
    ///      not reusing the old one. The expansion is written in the same call
    ///      so `denyProvider` enforcement is never silently disabled by a
    ///      partially-applied rotation.
    /// @param newConfigHash The new configuration hash
    /// @param metadataURI URI pointing to the full config (IPFS, Arweave, etc.)
    /// @param providerIds Provider IDs whose weights are committed-to by
    ///        `newConfigHash`. Must be non-empty; zero IDs are rejected.
    function updateProviderConfig(bytes32 newConfigHash, string calldata metadataURI, uint256[] calldata providerIds)
        external
        onlyRole(CONFIG_ROLE)
    {
        if (newConfigHash == _providerConfigHash) revert ConfigAlreadyCurrent();
        if (_revokedConfigs[newConfigHash]) revert ConfigPermanentlyRevoked(newConfigHash);
        if (_configHistory.length >= MAX_CONFIG_HISTORY) revert ConfigHistoryFull();
        _providerConfigHash = newConfigHash;
        _configHistory.push(newConfigHash);
        _validConfigs[newConfigHash] = true;
        _writeConfigExpansion(newConfigHash, providerIds);
        emit ProviderWeightsUpdated(newConfigHash, block.timestamp, metadataURI);
        emit ProviderConfigExpansionRegistered(newConfigHash, providerIds);
    }

    /// @notice Update the attestation TTL
    /// @param newTTL The new TTL in seconds (minimum 1 hour, maximum 30 days)
    function updateAttestationTTL(uint256 newTTL) external onlyRole(CONFIG_ROLE) {
        if (newTTL < 1 hours || newTTL > 30 days) revert InvalidTTL();
        uint256 oldTTL = _attestationTTL;
        _attestationTTL = newTTL;
        emit AttestationTTLUpdated(oldTTL, newTTL);
    }

    /// @notice Get the number of historical provider config versions
    /// @return count Number of config versions
    function configHistoryLength() external view returns (uint256 count) {
        return _configHistory.length;
    }

    /// @notice Get a historical provider config hash by index
    /// @param index The version index (0 = initial)
    /// @return configHash The config hash at that version
    function configHistoryAt(uint256 index) external view returns (bytes32 configHash) {
        return _configHistory[index];
    }

    /// @notice Revoke a provider config hash so proofs using it are no longer accepted
    /// @dev Revocation is permanent. Once revoked, the same hash cannot be re-registered
    ///      via `updateProviderConfig`; this prevents silently un-revoking by reuse.
    /// @param configHash The config hash to revoke (cannot be the current active config)
    function revokeConfig(bytes32 configHash) external onlyRole(GUARDIAN_ROLE) {
        if (configHash == _providerConfigHash) revert CannotRevokeCurrentConfig();
        _validConfigs[configHash] = false;
        _revokedConfigs[configHash] = true;
        emit ConfigRevoked(configHash);
    }

    /// @notice Check if a config hash has been permanently revoked
    /// @param configHash The config hash to check
    /// @return revoked Whether the config hash is in the revoked set
    function isRevokedConfig(bytes32 configHash) external view returns (bool revoked) {
        return _revokedConfigs[configHash];
    }

    /// @notice Remove revoked entries from config history to free slots
    /// @dev Preserves ordering of remaining entries. Current config (last entry) is
    ///      never revoked (CannotRevokeCurrentConfig guard), so it always survives.
    ///      Gas cost scales with history length (up to ~2.5M at 256 entries).
    /// @return removed Number of entries removed
    function compactConfigHistory() external onlyRole(CONFIG_ROLE) returns (uint256 removed) {
        uint256 len = _configHistory.length;
        uint256 writeIdx;

        for (uint256 readIdx; readIdx < len;) {
            bytes32 cfg = _configHistory[readIdx];
            if (_validConfigs[cfg]) {
                if (writeIdx != readIdx) {
                    _configHistory[writeIdx] = cfg;
                }
                unchecked {
                    ++writeIdx;
                }
            }
            unchecked {
                ++readIdx;
            }
        }

        removed = len - writeIdx;

        for (uint256 i; i < removed;) {
            _configHistory.pop();
            unchecked {
                ++i;
            }
        }

        if (removed > 0) {
            emit ConfigHistoryCompacted(removed, writeIdx);
        }
    }

    /// @notice Check if a config hash is valid (current or historical, not revoked)
    /// @param configHash The config hash to check
    /// @return valid Whether the config hash has been registered and not revoked
    function isValidConfig(bytes32 configHash) external view returns (bool valid) {
        return _validConfigs[configHash];
    }

    // -------------------------------------------------------------------------
    // Per-provider denylist (compliance proofs)
    // -------------------------------------------------------------------------

    /// @dev Atomically write a provider expansion for `configHash`. Used by the
    ///      constructor and `updateProviderConfig`. Validates non-empty + no zero
    ///      IDs. The expansion is written via memory copy because the constructor
    ///      receives a memory array; calldata copies are implicitly converted.
    function _writeConfigExpansion(bytes32 configHash, uint256[] memory providerIds) internal {
        uint256 length = providerIds.length;
        if (length == 0) revert EmptyProviderExpansion();
        for (uint256 i; i < length;) {
            if (providerIds[i] == 0) revert InvalidProviderId();
            _configProviders[configHash].push(providerIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Mark a provider as denied. Compliance proofs whose config expansion includes
    ///         this provider are rejected at submission time.
    /// @dev Reversible via `undenyProvider`. Pair with `pauseProofType(COMPLIANCE)` for an
    ///      immediate freeze while owners coordinate the new config rotation.
    /// @param providerId The provider identifier (must be non-zero)
    function denyProvider(uint256 providerId) external onlyRole(GUARDIAN_ROLE) {
        if (providerId == 0) revert InvalidProviderId();
        if (_deniedProviders[providerId]) revert AlreadyRegistered();
        _deniedProviders[providerId] = true;
        emit ProviderDeniedEvent(providerId);
    }

    /// @notice Lift a previous denial. Mistaken denials should generally roll forward via a
    ///         config rotation rather than reuse, but this path exists for false-positive recovery.
    /// @param providerId The provider identifier
    function undenyProvider(uint256 providerId) external onlyRole(GUARDIAN_ROLE) {
        if (!_deniedProviders[providerId]) revert NotRegistered();
        _deniedProviders[providerId] = false;
        emit ProviderUndeniedEvent(providerId);
    }

    /// @notice Check whether a provider is currently denied.
    function isProviderDenied(uint256 providerId) external view returns (bool denied) {
        return _deniedProviders[providerId];
    }

    /// @notice Get the registered provider expansion for a config hash.
    /// @return providerIds The provider IDs registered for this config (empty array if unset)
    function getProviderConfigExpansion(bytes32 configHash) external view returns (uint256[] memory providerIds) {
        return _configProviders[configHash];
    }

    /// @dev True if the registered expansion for `configHash` contains any denied provider.
    ///      Every valid config has a non-empty expansion (audit F-2): the constructor
    ///      and `updateProviderConfig` both write atomically, so the `length == 0` branch
    ///      can only fire for configs that were never registered, which the caller has
    ///      already excluded via `_validConfigs`.
    function _configContainsDeniedProvider(bytes32 configHash) internal view returns (bool) {
        uint256[] storage providers = _configProviders[configHash];
        uint256 length = providers.length;
        for (uint256 i; i < length;) {
            if (_deniedProviders[providers[i]]) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @dev Toggle a `bytes32 => bool` registry entry on. Reverts if already set --
    ///      every register* admin call funnels through here so the duplicate state +
    ///      revert pattern lives in one place.
    function _addBoolEntry(mapping(bytes32 => bool) storage set, bytes32 key) internal {
        if (set[key]) revert AlreadyRegistered();
        set[key] = true;
    }

    /// @dev Toggle a `bytes32 => bool` registry entry off. Reverts if not currently set.
    function _removeBoolEntry(mapping(bytes32 => bool) storage set, bytes32 key) internal {
        if (!set[key]) revert NotRegistered();
        set[key] = false;
    }

    /// @notice Register a merkle root as valid for MEMBERSHIP/NON_MEMBERSHIP/ATTESTATION proofs
    /// @param merkleRoot The merkle root to register
    function registerMerkleRoot(bytes32 merkleRoot) external onlyRole(REGISTRAR_ROLE) {
        _addBoolEntry(_validMerkleRoots, merkleRoot);
        emit MerkleRootRegistered(merkleRoot);
    }

    /// @notice Revoke a merkle root so proofs using it are no longer accepted
    /// @param merkleRoot The merkle root to revoke
    function revokeMerkleRoot(bytes32 merkleRoot) external onlyRole(REGISTRAR_ROLE) {
        _removeBoolEntry(_validMerkleRoots, merkleRoot);
        emit MerkleRootRevoked(merkleRoot);
    }

    /// @notice Check if a merkle root is valid
    /// @param merkleRoot The merkle root to check
    /// @return valid Whether the merkle root has been registered and not revoked
    function isValidMerkleRoot(bytes32 merkleRoot) external view returns (bool valid) {
        return _validMerkleRoots[merkleRoot];
    }

    // -------------------------------------------------------------------------
    // Per-provider credential roots (ATTESTATION proofs)
    // -------------------------------------------------------------------------

    /// @notice Authorize an EOA to publish credential roots for a provider.
    /// @dev Initial set or rotation. Set publisher = address(0) to disable a provider.
    /// @param providerId Provider identifier (must be non-zero)
    /// @param publisher Address authorized to call publishCredentialRoot for this providerId
    function setProviderPublisher(uint256 providerId, address publisher) external onlyRole(REGISTRAR_ROLE) {
        if (providerId == 0) revert InvalidProviderId();
        address previous = _providerPublisher[providerId];
        _providerPublisher[providerId] = publisher;
        emit ProviderPublisherSet(providerId, previous, publisher);
    }

    /// @notice Authorize a credential-root signing key for a provider (audit C-1).
    /// @dev The signing key (held in HSM/KMS, distinct from the publisher EOA) signs
    ///      `CredentialRootPublication` structs that the publisher EOA forwards via
    ///      `publishCredentialRoot`. Compromise of the publisher alone can no longer
    ///      mint credential roots; the publish tx reverts unless the EIP-712
    ///      signature verifies against this address. Set signer = address(0) to
    ///      disable credential-root publishing for the provider entirely (existing
    ///      roots remain provable until TTL or explicit revocation).
    /// @param providerId Provider identifier (must be non-zero)
    /// @param signer Address whose private key signs `CredentialRootPublication`
    function setCredentialSigner(uint256 providerId, address signer) external onlyRole(REGISTRAR_ROLE) {
        if (providerId == 0) revert InvalidProviderId();
        address previous = _credentialSigner[providerId];
        _credentialSigner[providerId] = signer;
        emit CredentialSignerSet(providerId, previous, signer);
    }

    /// @notice Get the credential-root signing key for a provider.
    function getCredentialSigner(uint256 providerId) external view returns (address) {
        return _credentialSigner[providerId];
    }

    /// @notice Publish a new credential tree root for a provider.
    /// @dev Called by the provider's authorized publisher EOA. The publisher must
    ///      additionally present an EIP-712 signature over a `CredentialRootPublication`
    ///      struct, signed by the address registered via `setCredentialSigner`. The
    ///      signature is verified on-chain via `ecrecover` (audit C-1 closure).
    ///
    ///      `notBefore` / `notAfter` bound replay of the signature itself; they are
    ///      independent of the on-chain `CREDENTIAL_ROOT_TTL` that bounds an
    ///      already-published root's lifetime for ATTESTATION proof acceptance.
    ///
    ///      `cidHash = keccak256(bytes(cid))` is committed in the signed struct so
    ///      a malicious publisher cannot bait-and-switch tree contents under a
    ///      signed root.
    /// @param providerId Provider identifier
    /// @param root New credential merkle root
    /// @param cid IPFS / Arweave CID for the full tree contents
    /// @param notBefore Unix timestamp; signature is invalid before this
    /// @param notAfter Unix timestamp; signature is invalid after this
    /// @param signature 65-byte ECDSA signature (r || s || v) over the EIP-712 digest
    function publishCredentialRoot(
        uint256 providerId,
        bytes32 root,
        string calldata cid,
        uint64 notBefore,
        uint64 notAfter,
        bytes calldata signature
    ) external {
        address publisher = _providerPublisher[providerId];
        if (publisher == address(0) || msg.sender != publisher) {
            revert NotProviderPublisher(providerId, msg.sender);
        }
        address signer = _credentialSigner[providerId];
        if (signer == address(0)) revert CredentialSignerNotSet(providerId);
        if (block.timestamp < notBefore || block.timestamp > notAfter) {
            revert CredentialSignatureOutOfWindow(notBefore, notAfter);
        }

        bytes32 digest = EIP712CredentialRoot.toTypedDataHash(
            EIP712CredentialRoot.buildDomainSeparator(address(this)),
            providerId,
            root,
            keccak256(bytes(cid)),
            notBefore,
            notAfter
        );
        address recovered = _recoverSigner(digest, signature);
        if (recovered != signer) revert InvalidCredentialSignature();

        if (_credentialRoots[root].registeredAt != 0) revert CredentialRootAlreadyPublished(root);

        _credentialRoots[root] =
            CredentialRootInfo({providerId: providerId, registeredAt: uint64(block.timestamp), revoked: false});
        emit CredentialRootPublished(providerId, root, cid, block.timestamp);
    }

    /// @dev Recover the signer of an EIP-712 digest from a 65-byte ECDSA signature
    ///      (`r || s || v`). Reverts on bad length. We accept both v=27/28 and the
    ///      legacy v=0/1 (some signers emit the latter); reject otherwise. Audit F-4:
    ///      enforce low-s to block signature malleability -- secp256k1 group order
    ///      n means (r, s) and (r, n-s) both recover to the same signer; rejecting
    ///      s > n/2 leaves exactly one canonical encoding per signer.
    /// @dev `secp256k1n / 2` (EIP-2 canonical low-s bound).
    bytes32 internal constant SECP256K1N_HALF = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignatureLength(signature.length);
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        if (uint256(s) > uint256(SECP256K1N_HALF)) revert InvalidCredentialSignature();
        uint8 v = uint8(signature[64]);
        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidCredentialSignature();
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0)) revert InvalidCredentialSignature();
        return recovered;
    }

    /// @notice Revoke a credential root before its TTL elapses.
    /// @dev Either the contract owner or the provider's publisher may revoke.
    /// @param root The credential root to revoke
    function revokeCredentialRoot(bytes32 root) external {
        CredentialRootInfo storage info = _credentialRoots[root];
        if (info.registeredAt == 0) revert CredentialRootNotFound(root);
        if (msg.sender != owner && msg.sender != _providerPublisher[info.providerId]) {
            revert NotProviderPublisher(info.providerId, msg.sender);
        }
        if (info.revoked) revert CredentialRootAlreadyRevoked(root);
        info.revoked = true;
        emit CredentialRootRevoked(root);
    }

    /// @notice Check whether a credential root is currently provable.
    /// @dev Valid iff registered, not revoked, and within the TTL window.
    function isValidCredentialRoot(bytes32 root) public view returns (bool) {
        return _isValidCredentialRoot(root);
    }

    /// @notice Get full metadata for a published credential root.
    function getCredentialRoot(bytes32 root) external view returns (CredentialRootInfo memory) {
        CredentialRootInfo memory info = _credentialRoots[root];
        if (info.registeredAt == 0) revert CredentialRootNotFound(root);
        return info;
    }

    /// @notice Get the publisher EOA authorized to publish for a provider.
    function getProviderPublisher(uint256 providerId) external view returns (address) {
        return _providerPublisher[providerId];
    }

    function _isValidCredentialRoot(bytes32 root) internal view returns (bool) {
        CredentialRootInfo memory info = _credentialRoots[root];
        if (info.registeredAt == 0) return false;
        if (info.revoked) return false;
        if (block.timestamp > uint256(info.registeredAt) + CREDENTIAL_ROOT_TTL) return false;
        return true;
    }

    // -------------------------------------------------------------------------
    // Signer pubkey hashes (COMPLIANCE_SIGNED / RISK_SCORE_SIGNED proofs)
    // -------------------------------------------------------------------------

    /// @notice Authorize a secp256k1 signer pubkey hash for signed-signals proofs.
    /// @dev `signerPubkeyHash` is the Pedersen commitment computed by
    ///      `erc8262_shared::sig::compute_signer_pubkey_hash` (circuits/shared/src/sig.nr).
    ///      Off-chain computation MUST use the same domain tag and field-splitting layout
    ///      to produce a registry-matching hash. Rotating a key: revoke the outgoing hash,
    ///      register the new one; in-flight proofs from the outgoing key are rejected the
    ///      moment its hash is revoked.
    function registerSignerPubkeyHash(bytes32 signerPubkeyHash) external onlyRole(REGISTRAR_ROLE) {
        if (signerPubkeyHash == bytes32(0)) revert InvalidSignerPubkeyHash(signerPubkeyHash);
        _addBoolEntry(_validSignerPubkeyHashes, signerPubkeyHash);
        emit SignerPubkeyHashRegistered(signerPubkeyHash);
    }

    /// @notice Revoke a previously-authorized signer pubkey hash.
    function revokeSignerPubkeyHash(bytes32 signerPubkeyHash) external onlyRole(REGISTRAR_ROLE) {
        _removeBoolEntry(_validSignerPubkeyHashes, signerPubkeyHash);
        emit SignerPubkeyHashRevoked(signerPubkeyHash);
    }

    /// @notice Whether a signer pubkey hash is currently authorized.
    function isValidSignerPubkeyHash(bytes32 signerPubkeyHash) external view returns (bool valid) {
        return _validSignerPubkeyHashes[signerPubkeyHash];
    }

    /// @notice Register a reporting threshold for PATTERN (anti-structuring) proofs
    /// @param threshold The threshold value (as bytes32-encoded u64)
    function registerReportingThreshold(bytes32 threshold) external onlyRole(REGISTRAR_ROLE) {
        _addBoolEntry(_validReportingThresholds, threshold);
        emit ReportingThresholdRegistered(threshold);
    }

    /// @notice Revoke a reporting threshold
    /// @param threshold The threshold to revoke
    function revokeReportingThreshold(bytes32 threshold) external onlyRole(REGISTRAR_ROLE) {
        _removeBoolEntry(_validReportingThresholds, threshold);
        emit ReportingThresholdRevoked(threshold);
    }

    /// @notice Check if a reporting threshold is valid
    /// @param threshold The threshold to check
    /// @return valid Whether the threshold has been registered and not revoked
    function isValidReportingThreshold(bytes32 threshold) external view returns (bool valid) {
        return _validReportingThresholds[threshold];
    }

    /// @notice Pause the contract, blocking all new submissions
    function pause() external override onlyRole(GUARDIAN_ROLE) {
        if (paused) revert ContractPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract, resuming all submissions
    function unpause() external override onlyRole(GUARDIAN_ROLE) {
        if (!paused) revert ContractNotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Pause submissions for a single proof type (surgical response)
    /// @param proofType The proof type to pause (0x01-0x08)
    function pauseProofType(uint8 proofType) external onlyRole(GUARDIAN_ROLE) {
        if (!ProofTypes.isValidProofType(proofType)) revert ProofTypes.InvalidProofType(proofType);
        if (_proofTypePaused[proofType]) revert ProofTypePaused(proofType);
        _proofTypePaused[proofType] = true;
        emit ProofTypePausedEvent(proofType, msg.sender);
    }

    /// @notice Unpause submissions for a single proof type
    /// @param proofType The proof type to unpause (0x01-0x08)
    function unpauseProofType(uint8 proofType) external onlyRole(GUARDIAN_ROLE) {
        if (!ProofTypes.isValidProofType(proofType)) revert ProofTypes.InvalidProofType(proofType);
        if (!_proofTypePaused[proofType]) revert ProofTypeNotPaused(proofType);
        _proofTypePaused[proofType] = false;
        emit ProofTypeUnpausedEvent(proofType, msg.sender);
    }

    /// @notice Check if a specific proof type is paused
    /// @param proofType The proof type to check
    /// @return Whether the proof type is paused
    function isProofTypePaused(uint8 proofType) external view returns (bool) {
        return _proofTypePaused[proofType];
    }

    event ProofTypePausedEvent(uint8 indexed proofType, address indexed account);
    event ProofTypeUnpausedEvent(uint8 indexed proofType, address indexed account);

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /// @dev Process a single entry in a batch (or standalone) submission.
    ///      Extracted to avoid stack-too-deep in the batch loop.
    function _submitSingle(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata inputs,
        bytes32 providerSetHash
    ) internal returns (ComplianceAttestation memory attestation) {
        if (_proofTypePaused[proofType]) revert ProofTypePaused(proofType);
        uint256 proofTimestamp = _validateAndExtractTimestamp(jurisdictionId, proofType, providerSetHash, inputs);
        _ratchet(jurisdictionId, proofTimestamp);

        (address verifierUsed, bytes32 proofHash) = _verifyAndRecordProof(proofType, proof, inputs);

        bytes32 effectiveProviderSetHash = (proofType == ProofTypes.COMPLIANCE
                || proofType == ProofTypes.COMPLIANCE_SIGNED || proofType == ProofTypes.COMPLIANCE_MULTI_SIGNED)
            ? providerSetHash
            : bytes32(0);
        attestation = _buildAttestation(
            jurisdictionId, proofType, proofHash, effectiveProviderSetHash, keccak256(inputs), verifierUsed
        );

        uint256 previousExpiresAt = _attestations[msg.sender][jurisdictionId].expiresAt;
        _attestations[msg.sender][jurisdictionId] = attestation;
        _proofIndex[proofHash] = attestation;
        _proofTypes[proofHash] = proofType;
        _attestationHistory[msg.sender][jurisdictionId].push(proofHash);

        emit ComplianceVerified(msg.sender, jurisdictionId, true, proofHash, attestation.expiresAt, previousExpiresAt);
    }

    /// @dev Verify the ZK proof and record replay protection.
    ///      Resolves verifier address once to eliminate TOCTOU.
    function _verifyAndRecordProof(uint8 proofType, bytes calldata proof, bytes calldata publicInputs)
        internal
        returns (address verifierUsed, bytes32 proofHash)
    {
        verifierUsed = verifier.getVerifier(proofType);
        if (verifierUsed == address(0)) revert ProofVerificationFailed();
        ProofTypes.validatePublicInputs(proofType, publicInputs);
        bytes32[] memory inputs = ProofTypes.decodePublicInputs(publicInputs);
        bool valid = IUltraVerifier(verifierUsed).verify(proof, inputs);
        if (!valid) revert ProofVerificationFailed();

        // Key on (proof, proofType, chainId, oracleAddress) so identical proof bytes for
        // different types, chains, or oracle deployments don't collide. The chainid +
        // address(this) binding prevents cross-chain replay (same proof bytes submitted on
        // Optimism, Base, Arbitrum, etc.) and cross-deployment replay (same proof submitted
        // to a forked or alternate Oracle on the same chain).
        proofHash = keccak256(abi.encodePacked(proof, proofType, block.chainid, address(this)));
        if (_usedProofs[proofHash]) revert ProofAlreadyUsed(proofHash);
        _usedProofs[proofHash] = true;
    }

    /// @dev Build a ComplianceAttestation struct (extracted to reduce stack depth)
    function _buildAttestation(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes32 proofHash,
        bytes32 providerSetHash,
        bytes32 publicInputsHash,
        address verifierUsed
    ) internal view returns (ComplianceAttestation memory attestation) {
        attestation = ComplianceAttestation({
            subject: msg.sender,
            jurisdictionId: jurisdictionId,
            proofType: proofType,
            meetsThreshold: true,
            timestamp: block.timestamp,
            expiresAt: block.timestamp + _attestationTTL,
            proofHash: proofHash,
            providerSetHash: providerSetHash,
            publicInputsHash: publicInputsHash,
            verifierUsed: verifierUsed
        });
    }

    /// @dev Dispatch validation by proofType and return the timestamp to ratchet on.
    ///      Also enforces per-jurisdiction signed-signals policy: when the jurisdiction
    ///      requires signed signals (`requireSignedSignals == true`), the unsigned
    ///      COMPLIANCE / RISK_SCORE variants are rejected before any cryptographic work.
    function _validateAndExtractTimestamp(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes32 providerSetHash,
        bytes calldata publicInputs
    ) internal view returns (uint256 proofTimestamp) {
        if (JurisdictionConfig.requireSignedSignals(jurisdictionId) && ProofTypes.isUnsignedScreeningVariant(proofType))
        {
            revert SignedSignalsRequired(jurisdictionId, proofType);
        }

        if (proofType == ProofTypes.COMPLIANCE) {
            return _validateComplianceInputs(jurisdictionId, providerSetHash, publicInputs);
        } else if (proofType == ProofTypes.RISK_SCORE) {
            return _validateRiskScoreInputs(publicInputs);
        } else if (proofType == ProofTypes.PATTERN) {
            return _validatePatternInputs(publicInputs);
        } else if (proofType == ProofTypes.ATTESTATION) {
            return _validateAttestationInputs(publicInputs);
        } else if (proofType == ProofTypes.MEMBERSHIP) {
            return _validateMembershipInputs(publicInputs);
        } else if (proofType == ProofTypes.NON_MEMBERSHIP) {
            return _validateNonMembershipInputs(publicInputs);
        } else if (proofType == ProofTypes.COMPLIANCE_SIGNED) {
            return _validateComplianceSignedInputs(jurisdictionId, providerSetHash, publicInputs);
        } else if (proofType == ProofTypes.RISK_SCORE_SIGNED) {
            return _validateRiskScoreSignedInputs(publicInputs);
        } else if (proofType == ProofTypes.COMPLIANCE_MULTI_SIGNED) {
            return _validateComplianceMultiSignedInputs(jurisdictionId, providerSetHash, publicInputs);
        } else {
            revert ProofTypes.InvalidProofType(proofType);
        }
    }

    /// @dev Per-(subject, jurisdiction) non-decreasing ratchet on the proof timestamp.
    ///      Blocks an older proof from overwriting a newer attestation -- the canonical
    ///      replay-extension attack where an attacker holds a "passed" proof and re-submits
    ///      it after state has degraded. The ratchet's effective value is the proof's
    ///      internal timestamp for types that expose one (COMPLIANCE/ATTESTATION/MEMBERSHIP/
    ///      NON_MEMBERSHIP), or `block.timestamp` for types that don't (RISK_SCORE/PATTERN).
    ///      Equal timestamps are allowed: legitimate same-block submissions of different
    ///      proof types for the same (subject, jurisdiction) must remain possible.
    function _ratchet(uint8 jurisdictionId, uint256 proofTimestamp) internal {
        uint256 last = _lastProofTimestamp[msg.sender][jurisdictionId];
        if (proofTimestamp < last) revert ProofTimestampNotMonotonic(proofTimestamp, last);
        if (proofTimestamp != last) {
            _lastProofTimestamp[msg.sender][jurisdictionId] = proofTimestamp;
        }
    }

    /// @notice Last ratcheted proof timestamp for a (subject, jurisdiction) pair.
    /// @dev Returns 0 when no proof has been recorded yet for the pair.
    function lastProofTimestamp(address subject, uint8 jurisdictionId) external view returns (uint256) {
        return _lastProofTimestamp[subject][jurisdictionId];
    }

    /// @dev Check that a proof timestamp is within MAX_PROOF_AGE in the past and
    ///      never in the future. Future-dated proofs serve no honest use case --
    ///      accepting them lets a submitter ratchet `_lastProofTimestamp` ahead of
    ///      wall-clock and block their own subsequent older-timestamp submissions
    ///      until the chain catches up (audit M-1).
    function _validateProofTimestamp(uint256 proofTimestamp) internal view {
        if (proofTimestamp > block.timestamp) {
            revert ProofTimestampInFuture(proofTimestamp, block.timestamp);
        }
        unchecked {
            if (block.timestamp - proofTimestamp > MAX_PROOF_AGE) {
                revert ProofTimestampStale(proofTimestamp, block.timestamp);
            }
        }
    }

    /// @dev Assert that the encoded submitter equals msg.sender.
    function _assertSubmitter(bytes32 raw) internal view {
        if (address(uint160(uint256(raw))) != msg.sender) revert SubmitterMismatch();
    }

    /// @dev Assert that the encoded boolean result is canonical true.
    function _assertResultPositive(bytes32 raw) internal pure {
        if (raw != bytes32(uint256(1))) revert ProofResultNegative();
    }

    /// @dev Assert that `configHash` is a registered (non-revoked) provider configuration.
    function _assertValidConfig(bytes32 configHash) internal view {
        if (!_validConfigs[configHash]) revert InvalidConfigHash(configHash);
    }

    /// @dev Assert that none of the providers expanded from `configHash` have been denied.
    ///      Centralizes the `_configContainsDeniedProvider` -> `_firstDeniedProviderInConfig`
    ///      revert pattern shared by every compliance validator.
    function _assertConfigNotDenied(bytes32 configHash) internal view {
        if (_configContainsDeniedProvider(configHash)) {
            revert ProviderDenied(_firstDeniedProviderInConfig(configHash));
        }
    }

    /// @dev Assert that the two 32-byte words at `publicInputs[offset:offset+64]` are
    ///      (chain_id, oracle_address) matching this deployment. Used by every signed
    ///      validator to enforce audit F-6 cross-chain / cross-Oracle replay protection.
    function _assertChainAndOracleBinding(bytes calldata publicInputs, uint256 offset) internal view {
        if (bytes32(publicInputs[offset:offset + 32]) != bytes32(block.chainid)) revert PublicInputMismatch();
        if (bytes32(publicInputs[offset + 32:offset + 64]) != bytes32(uint256(uint160(address(this))))) {
            revert PublicInputMismatch();
        }
    }

    /// @dev Validate RISK_SCORE / RISK_SCORE_SIGNED bound semantics. Rejects trivially-true
    ///      claims (`score > 0`, full-domain ranges, etc.) and ill-formed proof_type / direction.
    function _validateRiskBounds(uint256 proofType, uint256 direction, uint256 boundLower, uint256 boundUpper)
        internal
        pure
    {
        if (proofType == RISK_PROOF_THRESHOLD) {
            if (direction == RISK_DIRECTION_GT) {
                // "score > 0" is trivially true for any nonzero score; "score > 10000+" is impossible
                if (boundLower == 0 || boundLower >= MAX_RISK_SCORE_BPS) {
                    revert TrivialRiskBound(boundLower, boundUpper);
                }
            } else if (direction == RISK_DIRECTION_LT) {
                // "score < 0" impossible; "score < 10001+" trivially true
                if (boundLower == 0 || boundLower > MAX_RISK_SCORE_BPS) {
                    revert TrivialRiskBound(boundLower, boundUpper);
                }
            } else {
                revert InvalidRiskDirection(direction);
            }
        } else if (proofType == RISK_PROOF_RANGE) {
            if (boundLower >= boundUpper || boundUpper > MAX_RISK_SCORE_BPS) {
                revert InvalidRiskBound(boundLower, boundUpper);
            }
            // Reject the full-domain range [0, 10000] which any score satisfies
            if (boundLower == 0 && boundUpper == MAX_RISK_SCORE_BPS) {
                revert TrivialRiskBound(boundLower, boundUpper);
            }
        } else {
            revert InvalidRiskProofType(proofType);
        }
    }

    /// @dev Validate that caller-supplied jurisdiction and providerSetHash match
    ///      the corresponding fields in the COMPLIANCE proof's public inputs,
    ///      and that the config_hash is a known (current or historical) config.
    function _validateComplianceInputs(uint8 jurisdictionId, bytes32 providerSetHash, bytes calldata publicInputs)
        internal
        view
        returns (uint256 proofTimestamp)
    {
        // COMPLIANCE public inputs layout (each 32 bytes):
        //   [0]: jurisdiction_id
        //   [1]: provider_set_hash
        //   [2]: config_hash
        //   [3]: timestamp
        //   [4]: meets_threshold
        //   [5]: submitter
        bytes32 proofJurisdiction = bytes32(publicInputs[0:32]);
        bytes32 proofProviderSet = bytes32(publicInputs[32:64]);
        bytes32 proofConfigHash = bytes32(publicInputs[64:96]);

        if (proofJurisdiction != bytes32(uint256(jurisdictionId))) revert PublicInputMismatch();
        if (proofProviderSet != providerSetHash) revert PublicInputMismatch();
        _assertValidConfig(proofConfigHash);
        _assertResultPositive(bytes32(publicInputs[128:160]));
        _assertSubmitter(bytes32(publicInputs[160:192]));
        _assertConfigNotDenied(proofConfigHash);
        proofTimestamp = uint256(bytes32(publicInputs[96:128]));
        _validateProofTimestamp(proofTimestamp);
    }

    /// @dev Return the first denied provider ID found in `configHash`'s expansion.
    ///      Caller must have already verified at least one denied provider exists.
    function _firstDeniedProviderInConfig(bytes32 configHash) internal view returns (uint256) {
        uint256[] storage providers = _configProviders[configHash];
        uint256 length = providers.length;
        for (uint256 i; i < length;) {
            if (_deniedProviders[providers[i]]) return providers[i];
            unchecked {
                ++i;
            }
        }
        return 0; // unreachable when caller has confirmed via _configContainsDeniedProvider
    }

    /// @dev Validate that the config_hash in RISK_SCORE public inputs is a known config,
    ///      that semantic public inputs (proof_type, direction, bounds) are well-formed
    ///      and non-trivial, and that the result field indicates a positive outcome.
    ///      NOTE: RISK_SCORE has no timestamp in public inputs; staleness not enforced.
    function _validateRiskScoreInputs(bytes calldata publicInputs) internal view returns (uint256 proofTimestamp) {
        // RISK_SCORE has no proof-internal timestamp; ratchet uses block.timestamp instead
        proofTimestamp = block.timestamp;
        // RISK_SCORE public inputs layout (each 32 bytes):
        //   [0]: proof_type
        //   [1]: direction
        //   [2]: bound_lower
        //   [3]: bound_upper
        //   [4]: result
        //   [5]: config_hash
        //   [6]: provider_set_hash
        //   [7]: submitter
        _assertResultPositive(bytes32(publicInputs[128:160]));
        _assertValidConfig(bytes32(publicInputs[160:192]));
        _assertSubmitter(bytes32(publicInputs[224:256]));
        _validateRiskBounds(
            uint256(bytes32(publicInputs[0:32])),
            uint256(bytes32(publicInputs[32:64])),
            uint256(bytes32(publicInputs[64:96])),
            uint256(bytes32(publicInputs[96:128]))
        );
    }

    /// @dev Validate PATTERN public inputs.
    ///      Ensures analysis_type is in the supported set, result is positive,
    ///      reporting_threshold is registered, tx_set_hash is non-zero,
    ///      time_window meets minimum, and submitter matches msg.sender.
    ///      NOTE: PATTERN uses time_window (not a timestamp); staleness not enforced.
    ///      NOTE: callers that require a specific analysis (e.g. anti-structuring) MUST
    ///      verify the analysis_type field themselves; this validator only enforces
    ///      that it is well-formed.
    ///      NOTE (audit H-1): `settlement_root` is treated as opaque here. Downstream
    ///      consumers (e.g. SettlementRegistry) recompute it from their own state and
    ///      assert equality; the Oracle has no opinion on its value.
    function _validatePatternInputs(bytes calldata publicInputs) internal view returns (uint256 proofTimestamp) {
        // PATTERN has no proof-internal timestamp (uses time_window); ratchet uses block.timestamp
        proofTimestamp = block.timestamp;
        // PATTERN public inputs layout (each 32 bytes):
        //   [0]: analysis_type
        //   [1]: result
        //   [2]: reporting_threshold
        //   [3]: time_window
        //   [4]: tx_set_hash
        //   [5]: submitter
        //   [6]: settlement_root        (audit H-1 -- opaque to Oracle)
        uint256 analysisType = uint256(bytes32(publicInputs[0:32]));
        if (
            analysisType != PATTERN_STRUCTURING && analysisType != PATTERN_VELOCITY
                && analysisType != PATTERN_ROUND_AMOUNT
        ) {
            revert InvalidAnalysisType(analysisType);
        }
        _assertResultPositive(bytes32(publicInputs[32:64]));
        bytes32 reportingThreshold = bytes32(publicInputs[64:96]);
        if (!_validReportingThresholds[reportingThreshold]) {
            revert InvalidReportingThreshold(reportingThreshold);
        }
        uint256 timeWindow = uint256(bytes32(publicInputs[96:128]));
        if (timeWindow < MIN_TIME_WINDOW) revert TimeWindowTooSmall(timeWindow, MIN_TIME_WINDOW);
        if (bytes32(publicInputs[128:160]) == bytes32(0)) revert PublicInputMismatch();
        _assertSubmitter(bytes32(publicInputs[160:192]));
        // publicInputs[192:224] = settlement_root -- intentionally not validated here.
    }

    /// @dev Validate ATTESTATION public inputs (post C-1 redesign).
    ///      Ensures provider_id is non-zero, is_valid is true, the proof's
    ///      credential_root is currently registered for that provider (not expired,
    ///      not revoked), the proof timestamp is fresh, and submitter == msg.sender.
    function _validateAttestationInputs(bytes calldata publicInputs) internal view returns (uint256 proofTimestamp) {
        // ATTESTATION public inputs layout (each 32 bytes):
        //   [0]: provider_id
        //   [1]: credential_type
        //   [2]: is_valid
        //   [3]: credential_root
        //   [4]: current_timestamp
        //   [5]: submitter
        uint256 providerId = uint256(bytes32(publicInputs[0:32]));
        if (providerId == 0) revert InvalidProviderId();

        _assertResultPositive(bytes32(publicInputs[64:96]));

        bytes32 credentialRoot = bytes32(publicInputs[96:128]);
        CredentialRootInfo memory rootInfo = _credentialRoots[credentialRoot];
        if (rootInfo.registeredAt == 0) revert CredentialRootNotFound(credentialRoot);
        if (rootInfo.revoked) revert CredentialRootExpired(credentialRoot, rootInfo.registeredAt);
        if (block.timestamp > uint256(rootInfo.registeredAt) + CREDENTIAL_ROOT_TTL) {
            revert CredentialRootExpired(credentialRoot, rootInfo.registeredAt);
        }
        if (rootInfo.providerId != providerId) {
            revert CredentialRootProviderMismatch(rootInfo.providerId, providerId);
        }

        proofTimestamp = uint256(bytes32(publicInputs[128:160]));
        _validateProofTimestamp(proofTimestamp);
        _assertSubmitter(bytes32(publicInputs[160:192]));
    }

    /// @dev Validate MEMBERSHIP public inputs.
    ///      Ensures is_member is true, merkle_root is registered, and submitter matches msg.sender.
    function _validateMembershipInputs(bytes calldata publicInputs) internal view returns (uint256 proofTimestamp) {
        // MEMBERSHIP public inputs layout (each 32 bytes):
        //   [0]: merkle_root
        //   [1]: set_id
        //   [2]: timestamp
        //   [3]: is_member
        //   [4]: submitter
        bytes32 merkleRoot = bytes32(publicInputs[0:32]);
        if (!_validMerkleRoots[merkleRoot]) revert InvalidMerkleRoot(merkleRoot);
        proofTimestamp = uint256(bytes32(publicInputs[64:96]));
        _validateProofTimestamp(proofTimestamp);
        _assertResultPositive(bytes32(publicInputs[96:128]));
        _assertSubmitter(bytes32(publicInputs[128:160]));
    }

    /// @dev Validate NON_MEMBERSHIP public inputs.
    ///      Ensures is_non_member is true, merkle_root is registered, and submitter matches msg.sender.
    function _validateNonMembershipInputs(bytes calldata publicInputs) internal view returns (uint256 proofTimestamp) {
        // NON_MEMBERSHIP public inputs layout (each 32 bytes):
        //   [0]: merkle_root
        //   [1]: set_id
        //   [2]: timestamp
        //   [3]: is_non_member
        //   [4]: submitter
        bytes32 merkleRoot = bytes32(publicInputs[0:32]);
        if (!_validMerkleRoots[merkleRoot]) revert InvalidMerkleRoot(merkleRoot);
        proofTimestamp = uint256(bytes32(publicInputs[64:96]));
        _validateProofTimestamp(proofTimestamp);
        _assertResultPositive(bytes32(publicInputs[96:128]));
        _assertSubmitter(bytes32(publicInputs[128:160]));
    }

    /// @dev Validate COMPLIANCE_SIGNED public inputs (audit I-1 + F-6).
    ///      Identical to _validateComplianceInputs plus `signer_pubkey_hash`,
    ///      `chain_id`, and `oracle_address` -- the latter two bind the signed
    ///      digest to a specific deployment so a provider signature cannot be
    ///      replayed cross-chain or against an alternate Oracle.
    function _validateComplianceSignedInputs(uint8 jurisdictionId, bytes32 providerSetHash, bytes calldata publicInputs)
        internal
        view
        returns (uint256 proofTimestamp)
    {
        // COMPLIANCE_SIGNED public inputs layout (each 32 bytes):
        //   [0]: jurisdiction_id
        //   [1]: provider_set_hash
        //   [2]: config_hash
        //   [3]: timestamp
        //   [4]: meets_threshold
        //   [5]: signer_pubkey_hash
        //   [6]: chain_id            (audit F-6)
        //   [7]: oracle_address      (audit F-6)
        //   [8]: submitter
        bytes32 proofJurisdiction = bytes32(publicInputs[0:32]);
        bytes32 proofProviderSet = bytes32(publicInputs[32:64]);
        bytes32 proofConfigHash = bytes32(publicInputs[64:96]);
        bytes32 proofSignerPubkeyHash = bytes32(publicInputs[160:192]);

        if (proofJurisdiction != bytes32(uint256(jurisdictionId))) revert PublicInputMismatch();
        if (proofProviderSet != providerSetHash) revert PublicInputMismatch();
        _assertValidConfig(proofConfigHash);
        _assertResultPositive(bytes32(publicInputs[128:160]));
        if (!_validSignerPubkeyHashes[proofSignerPubkeyHash]) {
            revert InvalidSignerPubkeyHash(proofSignerPubkeyHash);
        }
        _assertChainAndOracleBinding(publicInputs, 192);
        _assertSubmitter(bytes32(publicInputs[256:288]));
        _assertConfigNotDenied(proofConfigHash);
        proofTimestamp = uint256(bytes32(publicInputs[96:128]));
        _validateProofTimestamp(proofTimestamp);
    }

    /// @dev Validate COMPLIANCE_MULTI_SIGNED public inputs.
    ///      Verifies that at least `threshold_m` of the (up to 5) provided
    ///      `signer_pubkey_hash` slots are registered and distinct, and that
    ///      `threshold_m` meets the jurisdiction-specific multi-provider floor.
    ///      The Noir circuit has already verified that each active slot's
    ///      signature is valid and that each active slot's score is below the
    ///      jurisdiction high-risk threshold; the on-chain validator handles
    ///      registry authorization, jurisdiction policy, and deployment binding.
    function _validateComplianceMultiSignedInputs(
        uint8 jurisdictionId,
        bytes32 providerSetHash,
        bytes calldata publicInputs
    ) internal view returns (uint256 proofTimestamp) {
        // COMPLIANCE_MULTI_SIGNED public inputs layout (each 32 bytes):
        //   [0]:  jurisdiction_id
        //   [1]:  provider_set_hash
        //   [2]:  config_hash
        //   [3]:  timestamp
        //   [4]:  meets_threshold
        //   [5]:  threshold_m
        //   [6..11): signer_pubkey_hash_0..4
        //   [11]: chain_id            (audit F-6)
        //   [12]: oracle_address      (audit F-6)
        //   [13]: submitter
        bytes32 proofJurisdiction = bytes32(publicInputs[0:32]);
        bytes32 proofProviderSet = bytes32(publicInputs[32:64]);
        bytes32 proofConfigHash = bytes32(publicInputs[64:96]);

        if (proofJurisdiction != bytes32(uint256(jurisdictionId))) revert PublicInputMismatch();
        if (proofProviderSet != providerSetHash) revert PublicInputMismatch();
        _assertValidConfig(proofConfigHash);
        _assertResultPositive(bytes32(publicInputs[128:160]));

        uint256 thresholdMRaw = uint256(bytes32(publicInputs[160:192]));
        if (thresholdMRaw == 0 || thresholdMRaw > 5) revert InvalidThresholdM(uint8(thresholdMRaw));
        uint8 thresholdM = uint8(thresholdMRaw);

        // Authorize each non-zero signer slot and assert distinctness.
        bytes32[5] memory signerHashes = [
            bytes32(publicInputs[192:224]),
            bytes32(publicInputs[224:256]),
            bytes32(publicInputs[256:288]),
            bytes32(publicInputs[288:320]),
            bytes32(publicInputs[320:352])
        ];
        uint8 activeCount;
        for (uint256 i; i < 5; ++i) {
            bytes32 h = signerHashes[i];
            if (h == bytes32(0)) continue;
            if (!_validSignerPubkeyHashes[h]) revert InvalidSignerPubkeyHash(h);
            for (uint256 j; j < i; ++j) {
                if (signerHashes[j] == h) revert DuplicateSigner(h);
            }
            unchecked {
                ++activeCount;
            }
        }
        if (activeCount < thresholdM) revert InsufficientSigners(activeCount, thresholdM);
        uint8 floor = JurisdictionConfig.minMultiProviderThreshold(jurisdictionId);
        if (thresholdM < floor) revert BelowJurisdictionMinProviders(jurisdictionId, thresholdM, floor);

        _assertChainAndOracleBinding(publicInputs, 352);
        _assertSubmitter(bytes32(publicInputs[416:448]));
        _assertConfigNotDenied(proofConfigHash);
        proofTimestamp = uint256(bytes32(publicInputs[96:128]));
        _validateProofTimestamp(proofTimestamp);
    }

    /// @dev Validate RISK_SCORE_SIGNED public inputs (audit I-1).
    ///      Identical semantic checks to _validateRiskScoreInputs but with an additional
    ///      `signer_pubkey_hash` slot validated against the on-chain registry.
    function _validateRiskScoreSignedInputs(bytes calldata publicInputs)
        internal
        view
        returns (uint256 proofTimestamp)
    {
        // RISK_SCORE_SIGNED has no proof-internal timestamp; ratchet uses block.timestamp.
        proofTimestamp = block.timestamp;
        // RISK_SCORE_SIGNED public inputs layout (each 32 bytes):
        //   [0]:  proof_type
        //   [1]:  direction
        //   [2]:  bound_lower
        //   [3]:  bound_upper
        //   [4]:  result
        //   [5]:  config_hash
        //   [6]:  provider_set_hash
        //   [7]:  signer_pubkey_hash
        //   [8]:  chain_id            (audit F-6)
        //   [9]:  oracle_address      (audit F-6)
        //   [10]: submitter
        bytes32 proofSignerPubkeyHash = bytes32(publicInputs[224:256]);

        _assertResultPositive(bytes32(publicInputs[128:160]));
        _assertValidConfig(bytes32(publicInputs[160:192]));
        if (!_validSignerPubkeyHashes[proofSignerPubkeyHash]) {
            revert InvalidSignerPubkeyHash(proofSignerPubkeyHash);
        }
        _assertChainAndOracleBinding(publicInputs, 256);
        _assertSubmitter(bytes32(publicInputs[320:352]));
        _validateRiskBounds(
            uint256(bytes32(publicInputs[0:32])),
            uint256(bytes32(publicInputs[32:64])),
            uint256(bytes32(publicInputs[64:96])),
            uint256(bytes32(publicInputs[96:128]))
        );
    }

    // -------------------------------------------------------------------------
    // IERC165
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC8262Oracle).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
