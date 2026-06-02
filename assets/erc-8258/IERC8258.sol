// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

// ---------------------------------------------------------------------------
// EAS types (from ethereum-attestation-service/eas-contracts)
// Defined at file scope so both IERC8258 and implementations can use them
// without the interface prefix.
// ---------------------------------------------------------------------------

struct Signature {
    uint8   v;
    bytes32 r;
    bytes32 s;
}

struct AttestationRequestData {
    address recipient;
    uint64  expirationTime;
    bool    revocable;
    bytes32 refUID;
    bytes   data;
    uint256 value;
}

struct MultiDelegatedAttestationRequest {
    bytes32                    schema;
    AttestationRequestData[]   data;
    Signature[]                signatures;
    address                    attester;
    uint64                     deadline;
}

struct RevocationRequestData {
    bytes32 uid;
    uint256 value;
}

struct MultiDelegatedRevocationRequest {
    bytes32                   schema;
    RevocationRequestData[]   data;
    Signature[]               signatures;
    address                   revoker;
    uint64                    deadline;
}

// ---------------------------------------------------------------------------

/// @title IERC8258 — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum-mainnet registry that maps
///         context IDs derived from ERC-7730 binding constraints to attester-
///         endorsed descriptor IDs, with EAS-backed attestations
///         (per ERC-8176) as the sole trust mechanism.
interface IERC8258 {

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when an attester's active endorsement for a context ID changes.
    ///         Emitted once per contextId on each createDescriptorAttestation call.
    ///         When clearRevokedEndorsement resets the slot, newDescriptorId and
    ///         attestationId are bytes32(0).
    /// @param attester           The attester whose endorsement changed.
    /// @param contextId          The context ID affected.
    /// @param previousDescriptorId  The previously active descriptor ID (bytes32(0) if none).
    /// @param newDescriptorId    The newly active descriptor ID (bytes32(0) if cleared).
    /// @param attestationId      The EAS attestation UID backing the new endorsement
    ///                           (bytes32(0) if cleared).
    event AttesterEndorsementUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32         previousDescriptorId,
        bytes32         newDescriptorId,
        bytes32 indexed attestationId
    );

    /// @notice Emitted when an attester updates their URI list for a descriptor.
    /// @param attester     The attester updating the list.
    /// @param descriptorId The descriptor ID.
    event URIsUpdated(address indexed attester, bytes32 indexed descriptorId);

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice Thrown when bytes32(0) is passed where a descriptor ID is required.
    error ZeroDescriptorId();

    /// @notice Thrown when contextIds is empty on a createDescriptorAttestation call.
    error EmptyContextIds();

    /// @notice Thrown when attestations is empty or attestations[0].data is empty.
    error EmptyAttestations();

    /// @notice Thrown when attestations[0].schema does not match the registry's
    ///         configured ERC-8176 schema UID.
    error WrongEASSchema(bytes32 expected, bytes32 got);

    /// @notice Thrown when the descriptor ID encoded in attestations[0].data[0].data
    ///         does not match the descriptorId argument.
    error EASHashMismatch(bytes32 attestedId, bytes32 claimedId);

    /// @notice Thrown when updateURIs is called by an address that has never
    ///         successfully called createDescriptorAttestation for this descriptor ID.
    error NotActiveAttester(bytes32 descriptorId, address caller);

    // =========================================================================
    // Write functions
    // =========================================================================

    /// @notice Create EAS attestation(s) and register a descriptor under one or
    ///         more context IDs, atomically replacing any prior active slot.
    ///
    ///         The function calls eas.multiAttestByDelegation(attestations) to
    ///         create all attestations in one transaction, then calls
    ///         eas.multiRevokeByDelegation(revocations) to revoke any previously
    ///         active attestations being replaced.
    ///
    ///         Active-slot convention:
    ///         attestations[0] MUST use the ERC-8176 schema UID.
    ///         attestations[0].data[0].data MUST ABI-decode to bytes32 equal to
    ///         descriptorId. The UID returned for this entry (uids[0] from the flat
    ///         return of multiAttestByDelegation) becomes the stored attestationId.
    ///         All other entries in attestations are supplementary and passed through
    ///         to EAS without registry-level validation.
    ///
    ///         The attester identity is taken from attestations[0].attester.
    ///         Any address may call this function (permissionless relay).
    ///
    ///         For each contextId: atomically replaces any previous active slot.
    ///         One AttesterEndorsementUpdated event is emitted per contextId.
    ///
    ///         The caller asserts that contextIds correctly represent the ERC-7730
    ///         context bindings in the descriptor file. The registry cannot verify
    ///         this on-chain. Wallets MUST independently validate the descriptor's
    ///         context section against the transaction (per ERC-7730 §Binding context).
    ///
    /// @param contextIds    Context IDs this descriptor should be discoverable under.
    ///                      MUST NOT be empty.
    /// @param descriptorId  keccak256 of the canonical ERC-7730 descriptor file.
    ///                      MUST NOT be bytes32(0).
    /// @param uris          Initial URI hints for retrieving the descriptor file.
    ///                      MAY be empty. Replaces any prior URI list for this
    ///                      (attester, descriptorId) pair.
    /// @param attestations  EAS delegated attestation batch. attestations[0] is the
    ///                      active attestation; all others are supplementary.
    ///                      MUST NOT be empty; attestations[0].data MUST NOT be empty.
    /// @param revocations   EAS delegated revocation batch for prior attestations.
    ///                      MAY be empty (e.g. on first registration).
    /// @return attestationId  The EAS UID of the active attestation (uids[0]).
    function createDescriptorAttestation(
        bytes32[]                               calldata contextIds,
        bytes32                                          descriptorId,
        string[]                                calldata uris,
        MultiDelegatedAttestationRequest[]      calldata attestations,
        MultiDelegatedRevocationRequest[]       calldata revocations
    ) external returns (bytes32 attestationId);

    /// @notice Update the URI list for (msg.sender, descriptorId).
    ///         Only callable after msg.sender has successfully called
    ///         createDescriptorAttestation for this descriptorId.
    ///         Replaces the entire URI list. URIs are hints only; wallets MUST
    ///         verify keccak256(retrievedBytes) == descriptorId.
    /// @param descriptorId  The descriptor ID.
    /// @param uris          New URI list. MAY be empty.
    function updateURIs(bytes32 descriptorId, string[] calldata uris) external;

    /// @notice Clear an attester's active slot for a context ID after verifying
    ///         that the backing EAS attestation has been revoked on EAS.
    ///         Permissionless: any address may call this.
    ///         No-op if there is no active slot.
    ///         Reverts if the backing EAS attestation is not currently revoked.
    ///         Emits AttesterEndorsementUpdated with newDescriptorId = bytes32(0).
    /// @param attester   The attester whose slot should be cleared.
    /// @param contextId  The context ID to clear.
    function clearRevokedEndorsement(address attester, bytes32 contextId) external;

    // =========================================================================
    // Queries
    // =========================================================================

    /// @notice Batch-query the active descriptor and attestation for each attester
    ///         at a given context ID. Designed for wallet use: one call resolves
    ///         the full trusted-attester list.
    /// @param attesters  Ordered attester addresses (index 0 = highest priority).
    /// @param contextId  The context ID to query.
    /// @return descriptorIds   Active descriptor ID per attester (bytes32(0) = none).
    /// @return attestationIds  Backing attestation UID per attester (bytes32(0) = none).
    function getDescriptors(
        address[] calldata attesters,
        bytes32            contextId
    ) external view returns (
        bytes32[] memory descriptorIds,
        bytes32[] memory attestationIds
    );

    /// @notice Return the URI list an attester has set for a descriptor.
    /// @param attester     The attester address.
    /// @param descriptorId The descriptor ID.
    /// @return uris  The URI list (may be empty).
    function getURIs(address attester, bytes32 descriptorId)
        external view returns (string[] memory uris);

    // =========================================================================
    // Context ID derivation helpers (pure)
    // =========================================================================

    /// @notice Derive the context ID for an EVM contract deployment binding.
    ///         Equivalent to:
    ///         keccak256(abi.encode(CONTEXT_TAG_CONTRACT, chainId, contractAddress))
    ///         Implements ERC-7730 §context.contract per-deployment binding.
    function computeContractContextId(uint256 chainId, address contractAddress)
        external pure returns (bytes32 contextId);

    /// @notice Derive the context ID for an EIP-712 deployment binding.
    ///         Equivalent to:
    ///         keccak256(abi.encode(CONTEXT_TAG_EIP712_DEP, chainId, verifyingContract))
    ///         Implements ERC-7730 §context.eip712.deployments per-deployment binding.
    function computeEIP712DeploymentContextId(uint256 chainId, address verifyingContract)
        external pure returns (bytes32 contextId);

    /// @notice Derive the context ID for an EIP-712 domain-separator binding.
    ///         Equivalent to:
    ///         keccak256(abi.encode(CONTEXT_TAG_EIP712_DS, domainSeparator))
    ///         Implements ERC-7730 §context.eip712.domainSeparator binding.
    function computeEIP712DomainSeparatorContextId(bytes32 domainSeparator)
        external pure returns (bytes32 contextId);

    /// @notice Derive the context ID for a factory-deployed contract binding.
    ///         Equivalent to:
    ///         keccak256(abi.encode(CONTEXT_TAG_FACTORY, chainId, factoryAddress, deployEventTopic))
    ///         Implements ERC-7730 §context.contract.factory binding.
    ///         deployEventTopic = keccak256(deployEventSignatureString) = topic[0] of the deploy event,
    ///         e.g. keccak256("TokenDeployed(address)").
    function computeFactoryContextId(
        uint256 chainId,
        address factoryAddress,
        bytes32 deployEventTopic
    ) external pure returns (bytes32 contextId);
}
