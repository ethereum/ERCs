// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps ERC-7730 binding context IDs
///         to attester-attested descriptors backed by an arbitrary off-chain attestation mechanism.
interface IClearSigningRegistry {

    /// @notice A MirrorList is given either by reference to an already-published list or inline.
    ///         Inline list is a string array be published atomically as part of the call using it.
    ///         Only one of 'id' or 'uris' must be populated while attempts to supply both will revert.
    struct MirrorListRef {
        /// References a previously published list.
        bytes32 id;
        /// Publishes atomically as part of this call.
        string[] uris;
    }

    /// @notice An identifier of the Attestation used to discover the full attestation data in the off-chain index.
    ///         Additionally serves as a key to the on-chain attestation revocations mapping.
    struct AttestationIdentifier {
        /// The attester-chosen identifier of the additional attestation.
        bytes32 attestationId;
        /// A format identifier calculated as keccak256("erc7730.attestation.<format>")
        bytes32 formatId;
    }

    /// @notice Descriptor data provided to the 'createAttestations' function for new descriptor registration.
    struct DescriptorInfo {
        /// The ERC-8176 "descriptor hash" identifier of this Descriptor.
        bytes32 descriptorHash;
        /// The MAJOR version of the ERC-7730 descriptor schema per its '$schema' key.
        uint256 schemaMajor;
        /// Context IDs this descriptor will be discoverable for.
        bytes32[] contextIds;
        /// Identifiers and formats of all attestations relating to this Descriptor.
        AttestationIdentifier[] attestationIds;
    }

    /// @notice One attestation ID being revoked, together with the context IDs to clear immediately.
    struct RevocationEntry {
        bytes32 attestationId;
        bytes32[] contextIds;
    }

    /// @notice A fully resolved active Attestation structure for ResolvedDescriptor.
    struct ResolvedAttestation {
        /// The attester that issued this particular attestation.
        address attester;
        /// The attester-chosen identifier of the additional attestation.
        bytes32 attestationId;
        /// A format identifier calculated as keccak256("erc7730.attestation.<format>")
        bytes32 formatId;
        /// The timestamp at which the attester revoked this attestation ID, or 0 if never revoked.
        uint64 revokedAt;
        /// The MirrorList URIs for retrieving the attestation blob.
        string[] attestationMirrorListUris;
    }

    /// @notice A fully resolved active Descriptor with Attestations.
    struct ResolvedDescriptor {
        /// The descriptor hash of this Descriptor.
        bytes32 descriptorHash;
        /// The context ID the descriptor was found under.
        bytes32 contextId;
        /// The schema MAJOR lane the attestation was found under.
        uint256 schemaMajor;
        /// The full resolved array of URIs provided for this Descriptor in the MirrorList.
        string[] descriptorMirrorListUris;
        /// The full resolved array of attestation objects issued for this Descriptor matching the specified filter.
        ResolvedAttestation[] attestations;
    }

    /// @notice Emitted when an attester's active attestation for a context ID changes.
    /// @param attester               The attester whose active attestation changed.
    /// @param contextId              The context ID affected.
    /// @param attestationId          The attestation ID for this descriptor.
    /// @param previousAttestationId  The previously active attestation ID.
    /// @param descriptorHash         The newly attested descriptor hash.
    /// @param schemaMajor            The schema MAJOR lane of the affected slot.
    event AttestationUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32 indexed attestationId,
        bytes32         previousAttestationId,
        bytes32         descriptorHash,
        uint256         schemaMajor
    );

    /// @notice Emitted whenever a revocation timestamp is recorded for an attestation ID.
    /// @param attester       The attester the attestation ID is revoked under.
    /// @param attestationId  The revoked attestation ID.
    /// @param timestamp      The block timestamp at which the revocation was recorded.
    event AttestationRevoked(
        address indexed attester,
        bytes32 indexed attestationId,
        uint64          timestamp
    );

    /// @notice Emitted exactly once per attestation ID when its write-once metadata is stored during registration.
    /// @param attester        The attester the attestation is registered under.
    /// @param attestationId   The registered attestation ID.
    /// @param descriptorHash  The attested descriptor hash.
    /// @param schemaMajor     The declared schema MAJOR lane.
    /// @param format          The attestation format tag: 'ATTESTATION_FORMAT_EAS_OFFCHAIN'
    ///                        for a primary attestation, the declared vendor tag otherwise.
    event AttestationRegistered(
        address indexed attester,
        bytes32 indexed attestationId,
        bytes32 indexed descriptorHash,
        uint256         schemaMajor,
        bytes32         format
    );

    /// @notice Emitted the first time a MirrorList is stored on-chain, carrying its full URI contents.
    /// @param mirrorListId  The content hash of the published MirrorList.
    /// @param uris          The published URI list.
    event MirrorListPublished(bytes32 indexed mirrorListId, string[] uris);

    /// @notice Emitted when an attester invalidates their current EIP-712 nonce via 'invalidateNonce'.
    ///         Indicates cancelling any outstanding signature using the old nonce value.
    /// @param attester  The attester whose nonce was invalidated.
    /// @param newNonce  The next valid nonce after the invalidation.
    event NonceInvalidated(address indexed attester, uint256 newNonce);

    /// @notice Emitted when an attester's active MirrorList for a descriptor changes.
    /// @param attester                The attester updating their list.
    /// @param descriptorHash          The descriptor hash.
    /// @param descriptorMirrorListId  The new MirrorList ID.
    event DescriptorMirrorListUpdated(
        address indexed attester,
        bytes32 indexed descriptorHash,
        bytes32 indexed descriptorMirrorListId
    );

    /// @notice Emitted when an attester's active MirrorList for an attestation changes.
    /// @param attester                 The attester updating their list.
    /// @param attestationId            The attestation ID.
    /// @param attestationMirrorListId  The new MirrorList ID.
    event AttestationMirrorListUpdated(
        address indexed attester,
        bytes32 indexed attestationId,
        bytes32 indexed attestationMirrorListId
    );

    /// @notice Emitted when an attester's profile document URI changes.
    /// @param attester    The attester whose profile changed.
    /// @param profileURI  The new profile document URI.
    event AttesterProfileUpdated(address indexed attester, string profileURI);

    /// @notice Thrown when descriptors is empty.
    error EmptyDescriptors();

    /// @notice Thrown when an empty key array is passed to an update function.
    error EmptyKeys();

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when bytes32(0) is passed where an off-chain attestation format tag is required.
    error ZeroAttestationFormat();

    /// @notice Thrown when an additional attestation declares 'ATTESTATION_FORMAT_EAS_OFFCHAIN'
    ///         (reserved for the primary attestation), or a format tag already registered
    ///         for the same primary attestation.
    error DuplicateAttestationFormat(bytes32 format);

    /// @notice Thrown when a descriptor declares a zero schema MAJOR version.
    error ZeroSchemaMajor();

    /// @notice Thrown when bytes32(0) is passed where an attestation ID is required.
    error ZeroAttestationId();

    /// @notice Thrown when a descriptor's contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when 'revokeAttestations' is called with an empty 'revocations' array.
    error EmptyRevocations();

    /// @notice Thrown when a registration reuses an attestation ID that was already registered.
    ///         Attestation IDs are single-use and cannot be re-registered after revocation.
    error AttestationIdAlreadyUsed(bytes32 attestationId);

    /// @notice Thrown when 'updateDescriptorMirrorList' names a descriptor hash the
    ///         attester has never registered.
    error UnknownDescriptor(bytes32 descriptorHash);

    /// @notice Thrown when 'updateAttestationMirrorList' names an attestation ID the
    ///         attester has never registered.
    error UnknownAttestationId(bytes32 attestationId);

    /// @notice Thrown when an empty URI list is passed to publishMirrorLists.
    error EmptyMirrorList();

    /// @notice Thrown when a 'MirrorListRef' references an unknown 'id' and
    ///         provides no inline 'uris' to publish it.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice Thrown when a 'MirrorListRef' carries neither an 'id' nor inline 'uris'.
    error EmptyMirrorListRef();

    /// @notice Thrown when a 'MirrorListRef' provides inline 'uris' together
    ///         with a non-zero 'id'. The id is derived from the uris in
    ///         the inline flow and must not be declared redundantly.
    error RedundantMirrorListId();

    /// @notice Thrown when the registration is submitted by an address other than
    ///         the attester and the provided EIP-712 registration signature does
    ///         not verify against the attester.
    error InvalidRegistrationSignature();

    /// @notice Thrown when a descriptor replaces an active attestation but the previously
    ///         active attestation ID is not included in the matching revocation set.
    error MissingRevocation(bytes32 missingAttestationId);

    /// @notice Register a batch of descriptors backed by attestations.
    ///
    ///         The attester produces the signed attestation artifacts locally and stores them off-chain.
    ///         A standard ERC-8176 EAS off-chain attestation per descriptor is a required primary attestation.
    ///         It serves as the compatibility baseline every wallet should be able to verify.

    ///         The registry itself is attestation-agnostic and attestations are accompanied by vendor-format id.
    ///         The registry records each attestation ID with an attestation "mirror list" shared by the whole batch.
    ///
    ///         The registry does not validate any attestation's signature or content.
    ///
    /// @param attester       The address of the attester registering the descriptors.
    /// @param descriptors    The descriptors to register, each carrying its vendor-format attestations.
    ///                       Active attestations are stored per '(contextId, schemaMajor)' keys.
    ///                       Descriptors of different schema MAJOR values never displace each other.
    ///                       Each '(contextId, schemaMajor)' slot may be written at most once per batch.
    /// @param revocations    Displaced attestations this call revokes and clears.
    ///
    /// @param descriptorMirrorListURIs  The MirrorList link to the index file containing all specified descriptors.
    ///
    /// @param attestationMirrorListURIs The MirrorList link to the index file containing all specified attestations.
    ///
    /// @param signature      EIP-712 signature by the attester authorizing this batch.
    ///                       Required when the registration transaction is relayed.
    ///
    function createAttestations(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata descriptorMirrorListURIs,
        MirrorListRef     calldata attestationMirrorListURIs,
        bytes             calldata signature
    ) external;

    /// @notice Publish a batch of MirrorLists on-chain.
    /// @param uriLists       The URI lists to publish. No list may be empty.
    /// @return mirrorListIds keccak256(abi.encode(uris)) per list.
    function publishMirrorLists(string[][] calldata uriLists) external;

    /// @notice Revokes every specified attestation ID for the specified 'attester' and clears specified context IDs.
    ///
    /// @param attester     The attester whose attestations are being revoked.
    /// @param revocations  The attestations to revoke, each with the context IDs to clear.
    /// @param signature    EIP-712 signature by the attester authorizing this batch.
    ///                     Required when the revocation transaction is relayed.
    function revokeAttestations(
        address           attester,
        RevocationEntry[] calldata revocations,
        bytes             calldata signature
    ) external;

    /// @notice The timestamp at which 'attester' revoked 'attestationId' or 0 if never revoked.
    ///
    /// @param attester       The attester whose revocation is being checked for the specified attestation ID.
    /// @param attestationId  The queried attestation ID.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64 timestamp);

    /// @notice Resolve all active attestations for the specified query with a filter.
    ///         The request fields are:
    ///             1. The list of attesters trusted by the wallet
    ///             2. The list of potential context IDs matching the relevant signature request
    ///             3. The list of schema MAJOR versions supported by the wallet.
    ///
    /// An empty array specified in the request filter indicates no filter applied for the given parameter.
    ///
    /// @param attesters        Queried attester addresses trusted by the wallet.
    /// @param contextIds       Candidate context IDs to look up.
    /// @param schemaMajors     The schema MAJOR versions supported by the wallet.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URI lists.
    ///                         e.g. ["ipfs:", "https:"].
    ///                         A URI is returned only if it starts with at least one of the prefixes.
    ///                         An active attestation is returned regardless of whether any of its URIs are filtered.
    /// @return resolved   One 'ResolvedDescriptor' entry per non-empty attestation entry.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved);

    /// @notice Return the URI list for a given MirrorList ID.
    ///
    /// @param mirrorListId     The MirrorList content hash.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URIs, or empty array for no filters.
    ///
    /// @return uris  The fully resolved URI list.
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
        external view returns (string[] memory uris);

    /// @notice The next EIP-712 nonce for all relayed calls by the given attester.
    /// @param attester  The queried attester address.
    /// @return nonce  The next unused nonce.
    function getNonce(address attester) external view returns (uint256 nonce);

    /// @notice Invalidates the caller's current EIP-712 nonce and cancel any outstanding signature using that nonce.
    function invalidateNonce() external;

    /// @notice Update the MirrorList for existing descriptors without re-issuing attestations.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param descriptorHashes The hashes of the descriptors to update. Every hash MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownDescriptor' otherwise.
    /// @param descriptorMirrorListRef The new MirrorList — see 'MirrorListRef'. Supports both
    ///                      the reference flow (rotate to an already-published list) and the
    ///                      inline flow (publish a brand-new list and rotate to it
    ///                      atomically in the same call).
    /// @param signature EIP-712 signature authorizing this update.
    function updateDescriptorMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        MirrorListRef calldata descriptorMirrorListRef,
        bytes calldata signature
    ) external;

    /// @notice Update the MirrorList for existing attestations without re-registration.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param attestationIds The IDs of the attestations to update. Every ID MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownAttestationId' otherwise.
    /// @param attestationMirrorListRef The new MirrorList — see 'MirrorListRef'.
    /// @param signature EIP-712 signature authorizing this update (ignored if msg.sender == attester).
    function updateAttestationMirrorList(
        address attester,
        bytes32[] calldata attestationIds,
        MirrorListRef calldata attestationMirrorListRef,
        bytes calldata signature
    ) external;

    /// @notice Set the attester's profile document URI — a self-declared "business card" pointing at its JSON profile.
    ///
    ///         The profile is display-only metadata and MUST NOT be used as trust input.
    ///         Wallets select and trust attesters by address ONLY.
    ///         Consumers SHOULD render profile data only for attesters they already trust.
    ///
    /// @param attester    The attester whose profile is being set.
    /// @param profileURI  The new profile document URI.
    /// @param signature   EIP-712 signature by the attester authorizing this update.
    function setAttesterProfileURI(
        address         attester,
        string calldata profileURI,
        bytes  calldata signature
    ) external;

    /// @notice The attester's current profile document URI, or an empty string if unset.
    /// @param attester  The queried attester address.
    /// @return profileURI  The profile document URI.
    function getAttesterProfileURI(address attester) external view returns (string memory profileURI);
}
