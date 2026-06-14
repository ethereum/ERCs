// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IEAS.sol";

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps
///         context IDs derived from ERC-7730 binding constraints to
///         attester-endorsed descriptors with EAS-backed attestations.
interface IClearSigningRegistry {

    /// @notice An descriptor input structure for registration operations.
    struct DescriptorRegistration {
        /// The ERC-8176 descriptorHash of the descriptor file.
        bytes32 descriptorHash;
        /// Context IDs this descriptor should be discoverable under.
        bytes32[] contextIds;
        /// Optional MirrorList ID this attester endorses for the descriptor.
        /// References a previously published list using the 'publishMirrorLists' or an earlier registration.
        /// Set to bytes32(0) if using 'mirrorListUris' instead.
        bytes32 mirrorListId;
        /// The MirrorList being published and endorsed atomically as part of the registration transaction.
        string[] mirrorListUris;
    }

    /// @notice A fully resolved active descriptor with attestation.
    struct ResolvedDescriptor {
        /// The endorsing attester.
        address attester;
        /// The context ID the descriptor was found under.
        bytes32 contextId;
        /// The endorsed descriptor hash decoded from the attestation data.
        bytes32 descriptorHash;
        /// The EAS attestation UID.
        bytes32 attestationId;
        /// The EAS attestation expiration time.
        uint64 expirationTime;
        /// The EAS attestation revocation time.
        uint64 revocationTime;
        /// The MirrorList contents.
        string[] uris;
    }

    /// @notice Emitted when an attester's active endorsement for a context ID changes.
    ///         Emitted once per contextId on each 'createDescriptorAttestations' call.
    ///         When 'clearRevokedEndorsements' removes a descriptor, descriptorHash and attestationId are bytes32(0).
    /// @param attester               The attester whose endorsement changed.
    /// @param contextId              The context ID affected.
    /// @param attestationId          The EAS attestation UID for this descriptor.
    /// @param previousAttestationId  The previously active attestation UID.
    /// @param descriptorHash         The newly endorsed descriptor hash.
    event AttestationUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32 indexed attestationId,
        bytes32         previousAttestationId,
        bytes32         descriptorHash
    );

    /// @notice Emitted the first time a MirrorList is stored on-chain.
    /// @param mirrorListId  The content hash of the published MirrorList.
    event MirrorListPublished(bytes32 indexed mirrorListId);

    /// @notice Emitted when an attester's active MirrorList for a descriptor changes.
    /// @param attester        The attester updating their list.
    /// @param descriptorHash  The descriptor hash.
    /// @param mirrorListId    The new MirrorList ID.
    event MirrorListUpdated(
        address indexed attester,
        bytes32 indexed descriptorHash,
        bytes32 indexed mirrorListId
    );

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

    /// @notice Create EAS attestations and register a batch of descriptors.
    ///
    ///         Each registration endorses a MirrorList, with two supported flows.
    ///         
    ///         Reference flow:
    ///         The list has been published before by any address in any prior
    ///         transaction.
    ///         
    ///         Inline flow:
    ///         The list is published as part of this call and its content hash becomes the effective 'mirrorListId'.
    ///
    ///
    /// @param registrations  The descriptors to register.
    /// @param attestations   EAS attestation batch.
    ///                       The 'attestations[0]' holds the active attestations with one data entry per registration.
    /// @param revocations    EAS delegated revocation batch for prior attestations.
    ///                       MAY be empty when no active slots are replaced.
    ///                       When the attester already has an active attestation for
    ///                       any supplied contextId, the corresponding UID MUST
    ///                       appear in this batch.
    /// @param registrationSignature  EIP-712 signature by the attester authorizing this batch when registration transaction is relayed.
    /// @return attestationIds  The EAS UIDs of the active attestations.
    function createDescriptorAttestations(
        DescriptorRegistration[]                calldata registrations,
        MultiDelegatedAttestationRequest[]      calldata attestations,
        MultiDelegatedRevocationRequest[]       calldata revocations,
        bytes                                   calldata registrationSignature
    ) external returns (bytes32[] memory attestationIds);

    /// @notice Publish a batch of MirrorLists on-chain and return their content hashes.
    /// @param uriLists       The URI lists to publish. No list may be empty.
    /// @return mirrorListIds keccak256(abi.encode(uris)) per list.
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds);

    /// @notice Clear active attestation records whose backing EAS attestation has been revoked or has expired.
    ///         Permissionless function allowing anyone to clean up stale attestations.
    ///         Invalid revocations are skipped, so a sweep cannot be blocked by a single failure.
    /// @param attesters   The attesters whose stale endorsements are cleared.
    /// @param contextIds  Per-attester lists of context IDs to clear.
    ///                    Must have the same length as attesters.
    /// @return cleared    The number of slots actually cleared.
    function clearRevokedAttestations(
        address[]   calldata attesters,
        bytes32[][] calldata contextIds
    ) external returns (uint256 cleared);

    /// @notice Resolve all active attestations filtered
    ///         by a list of attesters and a list of potential context IDs in a single call.
    ///         Returns the descriptor hash, the backing EAS attestations,
    ///         and the attester's MirrorList for the descriptor.
    ///
    /// @param attesters   Queried attester addresses.
    /// @param contextIds  Candidate context IDs to look up.
    /// @return resolved   One 'ResolvedDescriptor' entry per non-empty attestation entry.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds
    ) external view returns (ResolvedDescriptor[] memory resolved);

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
