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

    /// @notice A single descriptor registration within a batch.
    struct DescriptorRegistration {
        /// The ERC-8176 descriptorHash of the descriptor file. MUST NOT be bytes32(0).
        bytes32 descriptorHash;
        /// Context IDs this descriptor should be discoverable under. MUST NOT be empty.
        bytes32[] contextIds;
        /// Reference flow: the MirrorList this attester endorses for the
        /// descriptor. MUST reference a list previously published (by any
        /// address) via publishMirrorLists or an earlier registration.
        /// MUST be bytes32(0) when mirrorListUris is provided instead.
        bytes32 mirrorListId;
        /// Inline flow: when non-empty, the list is published idempotently as
        /// part of the registration and its content hash becomes the effective
        /// mirrorListId.
        string[] mirrorListUris;
    }

    /// @notice A fully resolved active endorsement, combining the registry slot,
    ///         the backing EAS attestation's lifecycle fields, and the attester's
    ///         MirrorList for the descriptor.
    struct ResolvedDescriptor {
        /// The endorsing attester.
        address attester;
        /// The context ID the slot was found under.
        bytes32 contextId;
        /// The endorsed descriptor hash (decoded from the attestation data).
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
    ///         Emitted once per contextId on each createDescriptorAttestations call.
    ///         When clearRevokedEndorsements resets the slot, descriptorHash and
    ///         attestationId are bytes32(0).
    /// @param attester               The attester whose endorsement changed.
    /// @param contextId              The context ID affected.
    /// @param previousAttestationId  The previously active attestation UID (bytes32(0) if none).
    /// @param descriptorHash         The newly endorsed descriptor hash (bytes32(0) if cleared).
    /// @param attestationId          The EAS attestation UID backing the new endorsement
    ///                               (bytes32(0) if cleared).
    event AttesterEndorsementUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32         previousAttestationId,
        bytes32         descriptorHash,
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

    /// @notice Thrown when registrations is empty.
    error EmptyRegistrations();

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when a registration's contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when attestations is empty.
    error EmptyAttestations();

    /// @notice Thrown when an empty URI list is passed to publishMirrorLists.
    error EmptyMirrorList();

    /// @notice Thrown when a registration references an unknown mirrorListId and
    ///         provides no inline URIs to publish it.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice Thrown when a registration provides inline mirrorListUris together
    ///         with a non-zero mirrorListId. The ID is derived from the URIs in
    ///         the inline flow and must not be declared redundantly.
    error RedundantMirrorListId();

    /// @notice Thrown when attestations[0].schema does not match the registry's
    ///         configured ERC-8176 schema UID.
    error WrongEASSchema(bytes32 expected, bytes32 got);

    /// @notice Thrown when the descriptor hash encoded in an active attestation's
    ///         data does not match the corresponding registration's descriptorHash.
    error EASHashMismatch(bytes32 attestedHash, bytes32 claimedHash);

    /// @notice Thrown when an active attestation's data is not exactly 32 bytes long
    ///         (ERC-8176 mandates the attested data is the 32-byte descriptorHash).
    error InvalidAttestationData();

    /// @notice Thrown when an active attestation is not revocable. The active
    ///         attestation must be revocable so the slot can be replaced later.
    error NonRevocableAttestation();

    /// @notice Thrown when the registration is submitted by an address other than
    ///         the attester and the provided EIP-712 registration signature does
    ///         not verify against the attester.
    error InvalidRegistrationSignature();

    /// @notice Thrown when createDescriptorAttestations replaces an active slot but
    ///         the previously active attestation UID is not included in revocations.
    error MissingRevocation(bytes32 missingUid);

    /// @notice Thrown when attesters is empty on a clearRevokedEndorsements call.
    error EmptyAttesters();

    /// @notice Thrown when parallel array arguments differ in length, including when
    ///         attestations[0].data does not have one entry per registration.
    error ArrayLengthMismatch();

    // =========================================================================
    // Write functions
    // =========================================================================

    /// @notice Create EAS attestations and register a batch of descriptors, each
    ///         under one or more context IDs, atomically replacing any prior
    ///         active slots.
    ///
    ///         The function first calls eas.multiRevokeByDelegation(revocations)
    ///         to revoke any previously active attestations being replaced, then
    ///         calls eas.multiAttestByDelegation(attestations) to create all
    ///         attestations in the same transaction.
    ///
    ///         Active-attestation convention:
    ///         attestations[0] MUST use the ERC-8176 schema UID and MUST contain
    ///         exactly one data entry per registration: attestations[0].data[i] is
    ///         the active attestation for registrations[i]. Each entry's data MUST
    ///         be exactly 32 bytes and ABI-decode to registrations[i].descriptorHash,
    ///         and MUST be revocable. The UIDs returned by EAS for these entries
    ///         (uids[0..registrations.length) of the flat return) become the stored
    ///         attestation IDs. Entries in attestations[1..] are supplementary and
    ///         passed through to EAS without registry-level validation.
    ///
    ///         Each registration endorses a MirrorList, with two supported flows.
    ///         Reference flow (mirrorListId set, mirrorListUris empty): the list
    ///         MUST have been published before — by any address, in any prior
    ///         transaction — allowing mirror operation to be a separate role from
    ///         attestation. Inline flow (mirrorListUris non-empty, mirrorListId
    ///         zero): the list is published idempotently as part of this call and
    ///         its content hash becomes the effective mirrorListId, so a first
    ///         registration needs no separate publication transaction.
    ///         The registration signature always covers the effective mirrorListId.
    ///
    ///         The registry stores only the attestation UID per (attester,
    ///         contextId) slot. The endorsed descriptor hash is carried in the
    ///         attestation's data and read from EAS when queried.
    ///
    ///         The attester identity is taken from attestations[0].attester.
    ///         Any address may call this function (permissionless relay), but unless
    ///         msg.sender == attester the call MUST carry a registration signature:
    ///         an EIP-712 signature by the attester over
    ///
    ///           ClearSigningRegistrationBatch(
    ///             DescriptorRegistration[] registrations,
    ///             bytes32 attestationSignaturesHash
    ///           )
    ///           DescriptorRegistration(
    ///             bytes32 descriptorHash,
    ///             bytes32 contextIdsHash,           // keccak256(abi.encodePacked(contextIds))
    ///             bytes32 mirrorListId
    ///           )
    ///
    ///         where attestationSignaturesHash = keccak256(abi.encode(attestations[0].signatures)),
    ///         in the registry's own EIP-712 domain
    ///         (name "ClearSigningRegistry", version "1", chainId, verifyingContract).
    ///         Binding the batch to the single-use EAS delegated attestation
    ///         signatures makes the registration signature single-use as well, with
    ///         no additional nonce state. Contract attesters are verified via
    ///         ERC-1271 isValidSignature.
    ///
    ///         For each contextId of each registration: atomically replaces any
    ///         previous active slot. One AttesterEndorsementUpdated event is
    ///         emitted per contextId.
    ///
    /// @param registrations  The descriptors to register. MUST NOT be empty.
    /// @param attestations   EAS delegated attestation batch. attestations[0] holds
    ///                       the active attestations (one data entry per
    ///                       registration); all others are supplementary.
    /// @param revocations    EAS delegated revocation batch for prior attestations.
    ///                       MAY be empty when no active slots are replaced.
    ///                       When the attester already has an active attestation for
    ///                       any supplied contextId, the corresponding UID MUST
    ///                       appear in this batch.
    /// @param registrationSignature  EIP-712 signature by the attester authorizing
    ///                       this batch (see above). MAY be empty when
    ///                       msg.sender == attestations[0].attester.
    /// @return attestationIds  The EAS UIDs of the active attestations, one per
    ///                       registration.
    function createDescriptorAttestations(
        DescriptorRegistration[]                calldata registrations,
        MultiDelegatedAttestationRequest[]      calldata attestations,
        MultiDelegatedRevocationRequest[]       calldata revocations,
        bytes                                   calldata registrationSignature
    ) external returns (bytes32[] memory attestationIds);

    /// @notice Publish a batch of MirrorLists on-chain and return their content
    ///         hashes. Idempotent per list: a list whose content is already stored
    ///         is not re-written and emits no event.
    ///         Permissionless: mirror operation may be a separate role — a pinning
    ///         service, mirror operator, or any other party can publish lists that
    ///         attesters then reference by ID in createDescriptorAttestations,
    ///         without the attesters ever handling URI payloads.
    /// @param uriLists       The URI lists to publish. No list may be empty.
    /// @return mirrorListIds keccak256(abi.encode(uris)) per list.
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds);

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

    // =========================================================================
    // Queries
    // =========================================================================

    /// @notice Resolve all active endorsements for the given attesters across the
    ///         given context IDs in a single call. For every non-empty
    ///         (attester, contextId) slot, returns the descriptor hash (decoded
    ///         from the attestation data), the backing EAS attestation's
    ///         expiration and revocation times, and the attester's MirrorList for
    ///         the descriptor.
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
    ///         at a given context ID. The registry stores only attestation UIDs;
    ///         descriptor hashes are decoded from the corresponding EAS
    ///         attestations' data.
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
