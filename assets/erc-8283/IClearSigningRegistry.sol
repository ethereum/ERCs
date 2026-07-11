// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps ERC-7730 binding context IDs
///         to attester-attested descriptors backed by an arbitrary off-chain attestation mechanism.
interface IClearSigningRegistry {

    /// @notice A MirrorList is given either by reference to an already-published list or inline.
    ///         Inline list is a string array to be published atomically as part of the call using it.
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
        /// The attester-chosen identifier of the attestation.
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
        /// The attester-chosen identifier of the attestation.
        bytes32 attestationId;
        /// A format identifier calculated as keccak256("erc7730.attestation.<format>")
        bytes32 formatId;
        /// The timestamp at which the attester revoked this attestation ID, or 0 if never revoked.
        uint64 revokedAt;
    }

    /// @notice A fully resolved active Descriptor with Attestations.
    struct ResolvedDescriptor {
        /// The descriptor hash of this Descriptor.
        bytes32 descriptorHash;
        /// The context ID the descriptor was found under.
        bytes32 contextId;
        /// The schema MAJOR the attestation set was found under.
        uint256 schemaMajor;
        /// The attestation set ID from the active record — the key into the attestation index file.
        bytes32 attestationSetId;
        /// The full resolved array of URIs provided for this Descriptor in the MirrorList.
        string[] descriptorMirrorListUris;
        /// The MirrorList URIs of the index file for retrieving this set's attestation blobs.
        string[] attestationMirrorListUris;
        /// The full resolved array of attestation objects issued for this Descriptor matching the specified filter.
        ResolvedAttestation[] attestations;
    }

    /// @notice Emitted when an attester's active attestation set for a context ID changes.
    /// @param attester                  The attester whose active attestation set changed.
    /// @param contextId                 The context ID affected.
    /// @param attestationSetId          The newly active attestation set ID, or bytes32(0) when cleared.
    /// @param previousAttestationSetId  The previously active attestation set ID.
    /// @param descriptorHash            The newly attested descriptor hash, or bytes32(0) when cleared.
    /// @param schemaMajor               The schema MAJOR of the affected active record.
    event AttestationUpdated(
        address indexed attester,
        bytes32 indexed contextId,
        bytes32 indexed attestationSetId,
        bytes32         previousAttestationSetId,
        bytes32         descriptorHash,
        uint256         schemaMajor
    );

    /// @notice Emitted whenever a revocation timestamp is recorded for an ID —
    ///         an attestation set ID or an individual attestation ID alike.
    /// @param attester       The attester the ID is revoked under.
    /// @param attestationId  The revoked ID.
    /// @param timestamp      The block timestamp at which the revocation was recorded.
    event AttestationRevoked(
        address indexed attester,
        bytes32 indexed attestationId,
        uint64          timestamp
    );

    /// @notice Emitted exactly once per attestation set when its write-once metadata is stored during registration.
    ///
    /// @param attester          The attester the attestation set is registered under.
    /// @param attestationSetId  The registered attestation set ID.
    /// @param descriptorHash    The attested descriptor hash.
    /// @param schemaMajor       The declared schema MAJOR.
    /// @param attestationIds    The full contents of the attestation set.
    event AttestationRegistered(
        address indexed attester,
        bytes32 indexed attestationSetId,
        bytes32 indexed descriptorHash,
        uint256         schemaMajor,
        AttestationIdentifier[] attestationIds
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

    /// @notice Emitted when an attester's active MirrorList for an attestation set changes.
    /// @param attester                 The attester updating their list.
    /// @param attestationSetId         The attestation set ID.
    /// @param attestationMirrorListId  The new MirrorList ID.
    event AttestationMirrorListUpdated(
        address indexed attester,
        bytes32 indexed attestationSetId,
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

    /// @notice Thrown when bytes32(0) is passed where an attestation format ID is required.
    error ZeroAttestationFormat();

    /// @notice Thrown when two attestations of the same descriptor declare the same format ID.
    error DuplicateAttestationFormat(bytes32 formatId);

    /// @notice Thrown when a descriptor declares a zero schema MAJOR version.
    error ZeroSchemaMajor();

    /// @notice Thrown when bytes32(0) is passed where an attestation ID is required.
    error ZeroAttestationId();

    /// @notice Thrown when a descriptor's contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when a descriptor's attestationIds is empty.
    error EmptyAttestationIds();

    /// @notice Thrown when 'revokeAttestations' is called with an empty 'revocations' array.
    error EmptyRevocations();

    /// @notice Thrown when a registration includes an attestation ID that was already revoked.,
    ///         Attestation IDs are single-use and cannot be re-registered after revocation.
    error AttestationIdAlreadyUsed(bytes32 attestationId);

    /// @notice Thrown when 'updateDescriptorMirrorList' names a descriptor hash the
    ///         attester has never registered.
    error UnknownDescriptor(bytes32 descriptorHash);

    /// @notice Thrown when 'updateAttestationMirrorList' names an attestation set ID the
    ///         attester has never registered.
    error UnknownAttestationSet(bytes32 attestationSetId);

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
    ///         All attestations of a descriptor form one attestation set whose members are active together.
    ///         Every set SHOULD contain a standard ERC-8176 EAS off-chain attestation.
    ///         The registry itself is attestation-agnostic — each attestation carries a vendor format ID.
    ///
    ///         The registry does not validate any attestation's signature or content.
    ///
    ///         The registry derives an attestation set ID per descriptor.
    ///         A set with a single attestation uses that attestation's own ID directly.
    ///         A larger set uses 'keccak256(abi.encode(descriptorHash, schemaMajor, attestationIds))'.
    ///
    /// @param attester       The address of the attester registering the descriptors.
    /// @param descriptors    The descriptors to register, each carrying its attestation set.
    ///                       Active attestation sets are stored per '(contextId, schemaMajor)' keys.
    ///                       Descriptors of different schema MAJOR values never displace each other.
    ///                       Each '(contextId, schemaMajor)' active record may be written at most once per batch.
    /// @param revocations    Displaced attestation sets this call revokes and clears.
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
    /// @param uriLists  The URI lists to publish. No list may be empty.
    function publishMirrorLists(string[][] calldata uriLists) external;

    /// @notice Revokes every specified attestation ID for the specified 'attester' and clears specified context IDs.
    ///         Entries may name attestation set IDs or individual attestation IDs.
    ///
    /// @param attester     The attester whose attestations are being revoked.
    /// @param revocations  The attestation IDs to revoke, each with the context IDs to clear.
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

    /// @notice Resolve all active attestation sets for the specified query with a filter.
    ///         The request fields are:
    ///             1. The list of attesters trusted by the wallet.
    ///             2. The list of potential context IDs matching the relevant signature request.
    ///             3. The list of schema MAJOR versions supported by the wallet.
    ///             4. The list of attestation format IDs the wallet can verify.
    ///
    /// The 'attesters', 'contextIds' and 'schemaMajors' parameters are lookup keys - an empty array yields no results.
    /// An empty 'formatIds' or 'allowedPrefixes' array applies no filter for that parameter.
    ///
    /// A resolved descriptor is returned even if every one of its attestations is filtered out.
    ///
    /// @param attesters        Queried attester addresses trusted by the wallet.
    /// @param contextIds       Candidate context IDs to look up.
    /// @param schemaMajors     The schema MAJOR versions supported by the wallet.
    /// @param formatIds        Attestation format IDs to include, or empty array for all formats.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URI lists.
    ///                         e.g. ["ipfs:", "https:"].
    ///                         A URI is returned only if it starts with at least one of the prefixes.
    /// @return resolved   One 'ResolvedDescriptor' entry per active '(attester, contextId, schemaMajor)' record.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors,
        bytes32[] calldata formatIds,
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

    /// @notice Update the MirrorList for existing attestation sets without re-registration.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param attestationSetIds The IDs of the attestation sets to update. Every ID MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownAttestationSet' otherwise.
    /// @param attestationMirrorListRef The new MirrorList — see 'MirrorListRef'.
    /// @param signature EIP-712 signature authorizing this update (ignored if msg.sender == attester).
    function updateAttestationMirrorList(
        address attester,
        bytes32[] calldata attestationSetIds,
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
