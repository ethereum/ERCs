// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps
///         context IDs derived from ERC-7730 binding constraints to
///         attester-attested descriptors, backed by attester-signed off-chain attestations.
interface IClearSigningRegistry {

    /// @notice A descriptor's identity, context IDs, and MirrorList pointer, submitted
    ///         together when registering a descriptor.
    struct DescriptorInfo {
        /// The ERC-8176 descriptorHash of the descriptor file.
        bytes32 descriptorHash;
        /// Context IDs this descriptor should be discoverable under.
        bytes32[] contextIds;
        /// Optional MirrorList ID the attester designates for the descriptor.
        /// References a previously published list using the 'publishMirrorLists' or an earlier registration.
        /// Set to bytes32(0) if using 'mirrorListUris' instead.
        bytes32 mirrorListId;
        /// The MirrorList being published atomically as part of the registration transaction.
        string[] mirrorListUris;
    }

    /// @notice A reference to an off-chain attestation for a descriptor.
    ///         The signed attestation blob itself is stored off-chain and retrieved via
    ///         the attestation MirrorList shared by the registration batch.
    struct OffchainAttestation {
        /// The pre-computed off-chain attestation UID. For 'ATTESTATION_FORMAT_EAS_OFFCHAIN'
        /// this is a standard EAS off-chain attestation UID; for other formats it is an
        /// attester-chosen opaque identifier.
        bytes32 uid;
        /// The expiration time from the attestation message; 0 = no expiration.
        uint64 expirationTime;
        /// A bytes32 equal to keccak256("erc7730.attestation.<format>"), namespacing the
        /// shape of the artifact retrieved via the attestation MirrorList. MUST be non-zero.
        /// Opaque to the registry, which performs no validation of the artifact against it.
        bytes32 format;
    }

    /// @notice A fully resolved active descriptor with attestation.
    struct ResolvedDescriptor {
        /// The attester.
        address attester;
        /// The context ID the descriptor was found under.
        bytes32 contextId;
        /// The descriptor hash decoded from the attestation data.
        bytes32 descriptorHash;
        /// The attestation UID.
        bytes32 attestationId;
        /// The attestation expiration time.
        uint64 expirationTime;
        /// The MirrorList URIs for retrieving the attestation blob.
        string[] attestationMirrorListUris;
        /// The attester-declared attestation format tag. Opaque to the registry;
        /// wallets select their verification procedure by this value.
        bytes32 format;
        /// The MirrorList contents.
        string[] uris;
    }

    /// @notice Emitted when an attester's active attestation for a context ID changes.
    ///         Emitted once per contextId on each 'createOffchainDescriptorAttestations' call.
    ///         When 'clearRevokedAttestations' removes a descriptor, descriptorHash and attestationId are bytes32(0).
    /// @param attester               The attester whose active attestation changed.
    /// @param contextId              The context ID affected.
    /// @param attestationId          The attestation UID for this descriptor.
    /// @param previousAttestationId  The previously active attestation UID.
    /// @param descriptorHash         The newly attested descriptor hash.
    event AttestationUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32 indexed attestationId,
        bytes32         previousAttestationId,
        bytes32         descriptorHash
    );

    /// @notice Emitted whenever a revocation timestamp is recorded for an attestation UID,
    ///         whether via 'revokeAttestation' directly or via a registration batch that
    ///         displaced it.
    /// @param attester   The attester the UID is revoked under.
    /// @param uid        The revoked attestation UID.
    /// @param timestamp  The block timestamp at which the revocation was recorded.
    event AttestationRevoked(
        address indexed attester,
        bytes32 indexed uid,
        uint64          timestamp
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

    /// @notice Thrown when descriptors is empty.
    error EmptyDescriptors();

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when bytes32(0) is passed where an off-chain attestation format tag is required.
    error ZeroAttestationFormat();

    /// @notice Thrown when a descriptor's contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when an empty URI list is passed to publishMirrorLists.
    error EmptyMirrorList();

    /// @notice Thrown when a descriptor references an unknown mirrorListId and
    ///         provides no inline URIs to publish it.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice Thrown when a descriptor provides inline mirrorListUris together
    ///         with a non-zero mirrorListId. The ID is derived from the URIs in
    ///         the inline flow and must not be declared redundantly.
    error RedundantMirrorListId();

    /// @notice Thrown when the registration is submitted by an address other than
    ///         the attester and the provided EIP-712 registration signature does
    ///         not verify against the attester.
    error InvalidRegistrationSignature();

    /// @notice Thrown when a descriptor replaces an active slot but the previously
    ///         active attestation UID is not included in the matching revocation set.
    error MissingRevocation(bytes32 missingUid);

    /// @notice Thrown when attesters is empty on a clearRevokedAttestations call.
    error EmptyAttesters();

    /// @notice Thrown when parallel array arguments differ in length, including when
    ///         attestations does not have one entry per descriptor.
    error ArrayLengthMismatch();

    /// @notice Register a batch of descriptors backed by off-chain attestations.
    ///
    ///         The attester produces the signed attestation artifact locally — typically
    ///         a standard EAS off-chain attestation, but any format the attester declares
    ///         via 'OffchainAttestation.format' — and stores it off-chain. The registry
    ///         records each pre-computed attestation UID together with a single attestation
    ///         MirrorList shared by the whole batch.
    ///
    ///         The registry does not validate the off-chain attestation's signature or
    ///         content, regardless of its declared format. Wallets MUST fetch the
    ///         attestation blob via the attestation MirrorList and verify it per the
    ///         procedure appropriate to its declared 'format' (UID recomputation, schema
    ///         and signature checks per ERC-8176 for 'ATTESTATION_FORMAT_EAS_OFFCHAIN').
    ///
    ///         Each descriptor references a MirrorList, with two supported flows:
    ///
    ///         Reference flow:
    ///         The list has been published before by any address in any prior transaction.
    ///
    ///         Inline flow:
    ///         The list is published as part of this call and its content hash becomes the effective 'mirrorListId'.
    ///
    /// @param attester       The attester registering the descriptors.
    /// @param descriptors    The descriptors to register.
    /// @param attestations   One off-chain attestation reference per descriptor.
    /// @param attestationMirrorListUris  Retrieval URIs for the off-chain attestation
    ///                       blobs, shared by every attestation in this batch.
    /// @param registrationSignature  EIP-712 signature by the attester authorizing this batch when the registration transaction is relayed.
    /// @param revocations    UIDs of displaced attestations this call revokes, recorded
    ///                       via 'revokeAttestation' under the attester's address. MAY
    ///                       be empty when no active slot is replaced. When a displaced
    ///                       active slot exists for any of the supplied context IDs, its
    ///                       UID MUST appear here.
    /// @return attestationIds  The off-chain attestation UIDs, one per descriptor.
    function createOffchainDescriptorAttestations(
        address               attester,
        DescriptorInfo[]      calldata descriptors,
        OffchainAttestation[] calldata attestations,
        string[]              calldata attestationMirrorListUris,
        bytes                 calldata registrationSignature,
        bytes32[]             calldata revocations
    ) external returns (bytes32[] memory attestationIds);

    /// @notice Publish a batch of MirrorLists on-chain and return their content hashes.
    /// @param uriLists       The URI lists to publish. No list may be empty.
    /// @return mirrorListIds keccak256(abi.encode(uris)) per list.
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds);

    /// @notice Records a revocation timestamp for 'uid' under the caller's address.
    ///         Permissionless self-service revocation, independent of any registration batch.
    /// @param uid  The attestation UID to revoke.
    function revokeAttestation(bytes32 uid) external;

    /// @notice The timestamp at which 'attester' revoked 'uid', via 'revokeAttestation'
    ///         or via a registration batch that displaced it — or 0 if never revoked.
    /// @param attester  The attester the UID is revoked under.
    /// @param uid       The queried attestation UID.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevocationTimestamp(address attester, bytes32 uid) external view returns (uint64 timestamp);

    /// @notice Clear active attestation records that have been revoked or have expired.
    ///         Permissionless function allowing anyone to clean up stale attestations.
    ///         Invalid revocations are skipped, so a sweep cannot be blocked by a single failure.
    /// @param attesters   The attesters whose stale attestations are cleared.
    /// @param contextIds  Per-attester lists of context IDs to clear.
    ///                    Must have the same length as attesters.
    /// @return cleared    The number of slots actually cleared.
    function clearRevokedAttestations(
        address[]   calldata attesters,
        bytes32[][] calldata contextIds
    ) external returns (uint256 cleared);

    /// @notice Resolve all active attestations filtered
    ///         by a list of attesters and a list of potential context IDs in a single call.
    ///         Returns the descriptor hash, the backing attestations,
    ///         and the attester's MirrorList for the descriptor.
    ///
    /// @param attesters   Queried attester addresses.
    /// @param contextIds  Candidate context IDs to look up.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URI lists,
    ///                    e.g. ["ipfs:", "https:"]. A URI is returned only if it starts
    ///                    with at least one of the prefixes. An empty array disables
    ///                    filtering and returns every URI. A slot is included in
    ///                    'resolved' regardless of whether any of its URIs match.
    /// @return resolved   One 'ResolvedDescriptor' entry per non-empty attestation entry.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved);

    /// @notice Return the URI list for a given MirrorList ID.
    ///         The MirrorListPublished event carries only the ID, so this getter is
    ///         the standalone way to read a published list's contents; an attester's
    ///         current MirrorList for a descriptor is part of resolveDescriptors
    ///         output and of MirrorListUpdated events.
    /// @param mirrorListId  The MirrorList content hash.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URIs;
    ///                    empty = unfiltered (see 'resolveDescriptors').
    /// @return uris  The URI list (empty if the ID is unknown).
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
        external view returns (string[] memory uris);

    /// @notice The next EIP-712 nonce for relayed 'createOffchainDescriptorAttestations'
    ///         calls by the given attester.
    /// @param attester  The queried attester address.
    /// @return nonce  The next unused registration nonce.
    function getRegistrationNonce(address attester) external view returns (uint256 nonce);

    /// @notice Update the MirrorList for existing descriptors without re-attestation.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param descriptorHashes The hashes of the descriptors to update.
    /// @param mirrorListId The new MirrorList ID.
    /// @param signature EIP-712 signature authorizing this update (ignored if msg.sender == attester).
    function updateMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        bytes32 mirrorListId,
        bytes calldata signature
    ) external;
}
