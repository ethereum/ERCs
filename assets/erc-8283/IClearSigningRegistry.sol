// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IEAS.sol";

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum-mainnet registry that maps
///         context IDs derived from ERC-7730 binding constraints to attester-
///         endorsed descriptor hashes, with EAS-backed attestations
///         (per ERC-8176) as the sole trust mechanism.
interface IClearSigningRegistry {

    // =========================================================================
    // Types
    // =========================================================================

    /// @notice A fully resolved active endorsement, combining the registry slot,
    ///         the backing EAS attestation's lifecycle fields, and the attester's
    ///         MirrorList for the descriptor.
    struct ResolvedDescriptor {
        /// The endorsing attester.
        address attester;
        /// The context ID the slot was found under.
        bytes32 contextId;
        /// The endorsed descriptor hash.
        bytes32 descriptorHash;
        /// The backing EAS attestation UID.
        bytes32 attestationId;
        /// The EAS attestation expiration time (0 = never expires).
        uint64 expirationTime;
        /// The EAS attestation revocation time (0 = not revoked).
        uint64 revocationTime;
        /// The attester's MirrorList ID for the descriptor (bytes32(0) if none).
        bytes32 mirrorListId;
        /// The MirrorList contents (empty if none).
        string[] uris;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when an attester's active endorsement for a context ID changes.
    ///         Emitted once per contextId on each createDescriptorAttestation call.
    ///         When clearRevokedEndorsements resets the slot, newDescriptorHash and
    ///         attestationId are bytes32(0).
    /// @param attester                The attester whose endorsement changed.
    /// @param contextId               The context ID affected.
    /// @param previousDescriptorHash  The previously active descriptor hash (bytes32(0) if none).
    /// @param newDescriptorHash       The newly active descriptor hash (bytes32(0) if cleared).
    /// @param attestationId           The EAS attestation UID backing the new endorsement
    ///                                (bytes32(0) if cleared).
    event AttesterEndorsementUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32         previousDescriptorHash,
        bytes32         newDescriptorHash,
        bytes32 indexed attestationId
    );

    /// @notice Emitted the first time a MirrorList is stored on-chain.
    /// @param mirrorListId  The content hash of the published MirrorList.
    event MirrorListPublished(bytes32 indexed mirrorListId);

    /// @notice Emitted when an attester's active MirrorList for a descriptor changes.
    ///         Not emitted when the new MirrorList ID equals the currently stored one.
    /// @param attester        The attester updating the list.
    /// @param descriptorHash  The descriptor hash.
    /// @param mirrorListId    The new MirrorList ID.
    event MirrorListUpdated(
        address indexed attester,
        bytes32 indexed descriptorHash,
        bytes32 indexed mirrorListId
    );

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when attestations is empty, attestations[0].data is empty,
    ///         or attestations[0].signatures is empty.
    error EmptyAttestations();

    /// @notice Thrown when an empty URI list is passed to publishMirrorList.
    error EmptyMirrorList();

    /// @notice Thrown when an unknown or zero mirrorListId is passed.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice Thrown when attestations[0].schema does not match the registry's
    ///         configured ERC-8176 schema UID.
    error WrongEASSchema(bytes32 expected, bytes32 got);

    /// @notice Thrown when the descriptor hash encoded in attestations[0].data[0].data
    ///         does not match the descriptorHash argument.
    error EASHashMismatch(bytes32 attestedHash, bytes32 claimedHash);

    /// @notice Thrown when attestations[0].data[0].data is not exactly 32 bytes long
    ///         (ERC-8176 mandates the attested data is the 32-byte descriptorHash).
    error InvalidAttestationData();

    /// @notice Thrown when attestations[0].data[0].revocable is false. The active
    ///         attestation must be revocable so the slot can be replaced later.
    error NonRevocableAttestation();

    /// @notice Thrown when the registration is submitted by an address other than
    ///         the attester and the provided EIP-712 registration signature does
    ///         not verify against the attester.
    error InvalidRegistrationSignature();

    /// @notice Thrown when createDescriptorAttestation replaces an active slot but
    ///         the previously active attestation UID is not included in revocations.
    error MissingRevocation(bytes32 missingUid);

    /// @notice Thrown when attesters is empty on a clearRevokedEndorsements call.
    error EmptyAttesters();

    /// @notice Thrown when parallel array arguments differ in length.
    error ArrayLengthMismatch();

    // =========================================================================
    // Write functions
    // =========================================================================

    /// @notice Create EAS attestation(s) and register a descriptor under one or
    ///         more context IDs, atomically replacing any prior active slot.
    ///
    ///         The function first calls eas.multiRevokeByDelegation(revocations)
    ///         to revoke any previously active attestations being replaced, then
    ///         calls eas.multiAttestByDelegation(attestations) to create all
    ///         attestations in the same transaction.
    ///
    ///         Active-slot convention:
    ///         attestations[0] MUST use the ERC-8176 schema UID.
    ///         attestations[0].data[0].data MUST be exactly 32 bytes and ABI-decode
    ///         to bytes32 equal to descriptorHash.
    ///         attestations[0].data[0].revocable MUST be true.
    ///         The UID returned for this entry (uids[0] from the flat return of
    ///         multiAttestByDelegation) becomes the stored attestationId.
    ///         All other entries in attestations are supplementary and passed through
    ///         to EAS without registry-level validation.
    ///
    ///         The attester identity is taken from attestations[0].attester.
    ///         Any address may call this function (permissionless relay), but unless
    ///         msg.sender == attester the call MUST carry a registration signature:
    ///         an EIP-712 signature by the attester over
    ///
    ///           ClearSigningRegistration(
    ///             bytes32 descriptorHash,
    ///             bytes32 contextIdsHash,           // keccak256(abi.encodePacked(contextIds))
    ///             bytes32 mirrorListId,
    ///             bytes32 attestationSignatureHash  // keccak256(abi.encode(attestations[0].signatures[0]))
    ///           )
    ///
    ///         in the registry's own EIP-712 domain
    ///         (name "ClearSigningRegistry", version "1", chainId, verifyingContract).
    ///         Binding the registration to the single-use EAS delegated attestation
    ///         signature makes the registration signature single-use as well, with
    ///         no additional nonce state. Contract attesters are verified via
    ///         ERC-1271 isValidSignature.
    ///
    ///         For each contextId: atomically replaces any previous active slot.
    ///         One AttesterEndorsementUpdated event is emitted per contextId.
    ///
    /// @param descriptorHash  The ERC-8176 descriptorHash of the descriptor file.
    ///                        MUST NOT be bytes32(0).
    /// @param contextIds      Context IDs this descriptor should be discoverable under.
    ///                        MUST NOT be empty.
    /// @param mirrorListId    ID of a MirrorList previously published via publishMirrorList.
    ///                        MUST be a known, non-zero ID. The MirrorList may have been
    ///                        published by any address in any prior transaction.
    /// @param attestations    EAS delegated attestation batch. attestations[0] is the
    ///                        active attestation; all others are supplementary.
    ///                        MUST NOT be empty; attestations[0].data and
    ///                        attestations[0].signatures MUST NOT be empty.
    /// @param revocations     EAS delegated revocation batch for prior attestations.
    ///                        MAY be empty on first registration.
    ///                        When an attester already has an active attestation for any supplied contextId,
    ///                        the corresponding UID MUST appear in this batch.
    /// @param registrationSignature  EIP-712 signature by the attester authorizing this
    ///                        registration (see above). MAY be empty when
    ///                        msg.sender == attestations[0].attester.
    /// @return attestationId  The EAS UID of the active attestation (uids[0]).
    function createDescriptorAttestation(
        bytes32                                          descriptorHash,
        bytes32[]                               calldata contextIds,
        bytes32                                          mirrorListId,
        MultiDelegatedAttestationRequest[]      calldata attestations,
        MultiDelegatedRevocationRequest[]       calldata revocations,
        bytes                                   calldata registrationSignature
    ) external returns (bytes32 attestationId);

    /// @notice Clear active slots whose backing EAS attestation has been revoked
    ///         or has expired. Permissionless: anyone may clean up stale slots,
    ///         allowing a watchdog to sweep multiple attesters in one transaction.
    ///         contextIds[i] lists the context IDs to clear for attesters[i].
    ///         A slot is cleared when it is non-empty and its backing attestation
    ///         is revoked (revocationTime != 0) or expired (expirationTime != 0
    ///         and in the past); all other slots are skipped, so a sweep cannot
    ///         be blocked by a slot changing state while the sweep is in flight.
    ///         Emits AttesterEndorsementUpdated with bytes32(0) new values per
    ///         cleared slot.
    /// @param attesters   The attesters whose stale endorsements are cleared.
    ///                    MUST NOT be empty.
    /// @param contextIds  Per-attester lists of context IDs to clear. MUST have the
    ///                    same length as attesters; no list may be empty.
    /// @return cleared    The number of slots actually cleared.
    function clearRevokedEndorsements(
        address[]   calldata attesters,
        bytes32[][] calldata contextIds
    ) external returns (uint256 cleared);

    /// @notice Publish a MirrorList on-chain and return its content hash.
    ///         Idempotent: if the list is already stored, returns its ID without
    ///         re-writing or emitting an event.
    ///         MirrorLists are shared across all attesters: publishing once makes
    ///         the list available for any subsequent createDescriptorAttestation
    ///         call, regardless of who published it.
    /// @param uris          Retrieval URIs for a descriptor. MUST NOT be empty.
    /// @return mirrorListId keccak256(abi.encode(uris))
    function publishMirrorList(string[] calldata uris) external returns (bytes32 mirrorListId);

    // =========================================================================
    // Queries
    // =========================================================================

    /// @notice Resolve all active endorsements for the given attesters across the
    ///         given context IDs in a single call. For every non-empty
    ///         (attester, contextId) slot, returns the descriptor hash, the backing
    ///         EAS attestation's expiration and revocation times (read from EAS in
    ///         the same call), and the attester's MirrorList for the descriptor.
    ///
    ///         Designed as the wallet-facing entry point: a wallet derives its
    ///         candidate context IDs locally (the contract key for a calldata
    ///         transaction; the deployment and domain-separator keys for an
    ///         EIP-712 message; factory keys for factories it knows), then
    ///         resolves slots, attestation validity, and retrieval URIs in one
    ///         eth_call. The wallet remains responsible for its trust policy and
    ///         for verifying the fetched descriptor against descriptorHash.
    /// @param attesters   Ordered attester addresses (index 0 = highest priority).
    /// @param contextIds  Candidate context IDs to look up.
    /// @return resolved   One entry per non-empty slot, ordered by attesters
    ///                    first, then contextIds.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds
    ) external view returns (ResolvedDescriptor[] memory resolved);

    /// @notice Batch-query the active descriptor and attestation for each attester
    ///         at a given context ID. Designed for wallet use: one call resolves
    ///         the full trusted-attester list.
    /// @param attesters  Ordered attester addresses (index 0 = highest priority).
    /// @param contextId  The context ID to query.
    /// @return descriptorHashes  Active descriptor hash per attester (bytes32(0) = none).
    /// @return attestationIds   Backing attestation UID per attester (bytes32(0) = none).
    function getDescriptors(
        address[] calldata attesters,
        bytes32            contextId
    ) external view returns (
        bytes32[] memory descriptorHashes,
        bytes32[] memory attestationIds
    );

    /// @notice Return the URI list for a given MirrorList ID.
    ///         The MirrorListPublished event carries only the ID, so this getter is
    ///         the standalone way to read a published list's contents; an attester's
    ///         current MirrorList for a descriptor is part of resolveDescriptors
    ///         output and of MirrorListUpdated events.
    /// @param mirrorListId  The MirrorList content hash.
    /// @return uris  The URI list (empty if the ID is unknown).
    function getMirrorListById(bytes32 mirrorListId)
        external view returns (string[] memory uris);
}
