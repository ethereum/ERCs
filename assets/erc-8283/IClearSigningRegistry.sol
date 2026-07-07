// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps
///         context IDs derived from ERC-7730 binding constraints to
///         attester-attested descriptors, backed by attester-signed off-chain attestations.
interface IClearSigningRegistry {

    /// @notice A MirrorList, given either by reference to an already-published list
    ///         or inline to be published atomically as part of this call. Exactly one
    ///         of 'id'/'uris' must be populated: supplying both reverts with
    ///         'RedundantMirrorListId', supplying neither with 'EmptyMirrorListRef'.
    struct MirrorListRef {
        /// References a previously published list using 'publishMirrorLists' or an
        /// earlier registration. Set to bytes32(0) if using 'uris' instead.
        bytes32 id;
        /// Published atomically as part of this call if non-empty.
        string[] uris;
    }

    /// @notice A descriptor's identity, context IDs, MirrorList pointer, and the
    ///         attestation backing it, submitted together when registering a descriptor.
    struct DescriptorInfo {
        /// The ERC-8176 descriptorHash of the descriptor file.
        bytes32 descriptorHash;
        /// The MAJOR version of the ERC-7730 descriptor schema the descriptor is authored
        /// against, per its '$schema' key. MUST be non-zero, reverting with
        /// 'ZeroSchemaMajor' otherwise. Opaque to the registry: attester-declared and
        /// never verified on-chain — wallets MUST check that the fetched descriptor's
        /// '$schema' MAJOR equals the lane it was found under.
        uint256 schemaMajor;
        /// Context IDs this descriptor should be discoverable under.
        bytes32[] contextIds;
        /// The descriptor's MirrorList — see 'MirrorListRef'.
        MirrorListRef descriptorMirrorListURIs;
        /// The pre-computed attestation identifier. For 'ATTESTATION_FORMAT_EAS_OFFCHAIN'
        /// this is a standard EAS off-chain attestation UID; for other formats it is an
        /// attester-chosen opaque identifier.
        bytes32 attestationId;
        /// A bytes32 equal to keccak256("erc7730.attestation.<format>"), namespacing the
        /// shape of the artifact retrieved via the attestation MirrorList. MUST be non-zero.
        /// Opaque to the registry, which performs no validation of the artifact against it.
        bytes32 format;
    }

    /// @notice One attestation ID being revoked, together with the context IDs to clear
    ///         immediately wherever they still point to it within the attestation's own
    ///         schema MAJOR lane (read from its stored metadata). 'contextIds' MAY be
    ///         empty — the ones covered by the replacement descriptors in the same
    ///         batch get updated automatically regardless; entries here matter for
    ///         context IDs the replacement no longer covers.
    struct RevocationEntry {
        bytes32 attestationId;
        bytes32[] contextIds;
    }

    /// @notice A fully resolved active descriptor with attestation.
    struct ResolvedDescriptor {
        /// The attester.
        address attester;
        /// The context ID the descriptor was found under.
        bytes32 contextId;
        /// The descriptor hash decoded from the attestation data.
        bytes32 descriptorHash;
        /// The schema MAJOR lane the attestation was found under (equal to the
        /// attester-declared 'DescriptorInfo.schemaMajor' of its registration).
        uint256 schemaMajor;
        /// The attestation ID.
        bytes32 attestationId;
        /// The timestamp at which the attester revoked this attestation ID, or 0 if never
        /// revoked. Non-zero when an incomplete cleanup left the context ID pointing at a
        /// revoked attestation; wallets MUST treat such an entry as revoked.
        uint64 revokedAt;
        /// The MirrorList URIs for retrieving the attestation blob.
        string[] attestationMirrorListUris;
        /// The attester-declared attestation format tag. Opaque to the registry;
        /// wallets select their verification procedure by this value.
        bytes32 format;
        /// The MirrorList contents.
        string[] descriptorMirrorListUris;
    }

    /// @notice Emitted when an attester's active attestation for a (context ID,
    ///         schema MAJOR) slot changes — once per affected slot, whether set by a
    ///         registration batch or cleared by a revocation. When a revocation clears
    ///         an active attestation, descriptorHash and attestationId are bytes32(0).
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

    /// @notice Emitted whenever a revocation timestamp is recorded for an attestation ID,
    ///         whether via 'revokeAttestation' directly or via a registration batch that
    ///         displaced it.
    /// @param attester       The attester the attestation ID is revoked under.
    /// @param attestationId  The revoked attestation ID.
    /// @param timestamp      The block timestamp at which the revocation was recorded.
    event AttestationRevoked(
        address indexed attester,
        bytes32 indexed attestationId,
        uint64          timestamp
    );

    /// @notice Emitted the first time a MirrorList is stored on-chain.
    /// @param mirrorListId  The content hash of the published MirrorList.
    event MirrorListPublished(bytes32 indexed mirrorListId);

    /// @notice Emitted when an attester invalidates their current EIP-712 nonce
    ///         via 'invalidateNonce', cancelling any outstanding signature over it.
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

    /// @notice Thrown when descriptors is empty.
    error EmptyDescriptors();

    /// @notice Thrown when an empty key array is passed to an update function.
    error EmptyKeys();

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when bytes32(0) is passed where an off-chain attestation format tag is required.
    error ZeroAttestationFormat();

    /// @notice Thrown when a descriptor declares a zero schema MAJOR version.
    error ZeroSchemaMajor();

    /// @notice Thrown when bytes32(0) is passed where an attestation ID is required.
    error ZeroAttestationId();

    /// @notice Thrown when a descriptor's contextIds is empty.
    error EmptyContextIds();

    /// @notice Thrown when 'revokeAttestations' is called with an empty 'revocations' array.
    error EmptyRevocations();

    /// @notice Thrown when a registration reuses an attestation ID that was already
    ///         registered — or already revoked — under the same attester.
    ///         Attestation IDs are single-use; see "Attestation IDs are single-use" in the ERC.
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
    ///         The attester produces the signed attestation artifact locally — typically
    ///         a standard EAS off-chain attestation, but any format the attester declares
    ///         via 'DescriptorInfo.format' — and stores it off-chain. The registry
    ///         records each pre-computed attestation ID together with a single attestation
    ///         MirrorList shared by the whole batch.
    ///
    ///         The registry does not validate the attestation's signature or
    ///         content, regardless of its declared format. Wallets MUST fetch the
    ///         attestation blob via the attestation MirrorList and verify it per the
    ///         procedure appropriate to its declared 'format' (attestation ID recomputation,
    ///         schema and signature checks per ERC-8176 for 'ATTESTATION_FORMAT_EAS_OFFCHAIN').
    ///
    ///         Both a descriptor's own MirrorList ('DescriptorInfo.descriptorMirrorListURIs')
    ///         and the batch's shared attestation MirrorList ('attestationMirrorListURIs') are
    ///         given as a 'MirrorListRef', supporting the same two flows:
    ///
    ///         Reference flow ('id' set, 'uris' empty):
    ///         The list has been published before by any address in any prior transaction.
    ///
    ///         Inline flow ('uris' non-empty, 'id' zero):
    ///         The list is published as part of this call and its content hash becomes the effective id.
    ///
    /// @param attester       The attester registering the descriptors.
    /// @param descriptors    The descriptors to register, each carrying its own attestation
    ///                       reference (`attestationId`/`format`) — a non-zero `format` is
    ///                       required, reverting with `ZeroAttestationFormat` otherwise.
    ///                       Attestation IDs are single-use: an ID ever registered or revoked
    ///                       before reverts with 'AttestationIdAlreadyUsed'. Active attestations
    ///                       are slotted per (contextId, schemaMajor): descriptors of different
    ///                       schema MAJORs never displace each other, and a (contextId,
    ///                       schemaMajor) slot may be claimed at most once per batch — a
    ///                       duplicate reverts with 'MissingRevocation'.
    /// @param revocations    Displaced attestations this call revokes and clears. MAY
    ///                       be empty when no active attestation is replaced. When a displaced
    ///                       active attestation exists for any of the supplied slots, it
    ///                       MUST already be revoked — via a 'RevocationEntry' here or via an
    ///                       earlier call.
    /// @param attestationMirrorListURIs  The MirrorList for the attestation blobs, shared by
    ///                       every descriptor's attestation in this batch. Reusing an
    ///                       already-published attestation MirrorList across calls needs
    ///                       only its 'id' — no need to resupply 'uris'.
    /// @param signature      EIP-712 signature by the attester authorizing this
    ///                       batch when the registration transaction is relayed. Covers
    ///                       'revocations' too, so a relayer cannot add or drop entries.
    function createAttestations(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata attestationMirrorListURIs,
        bytes             calldata signature
    ) external;

    /// @notice Publish a batch of MirrorLists on-chain and return their content hashes.
    /// @param uriLists       The URI lists to publish. No list may be empty.
    /// @return mirrorListIds keccak256(abi.encode(uris)) per list.
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds);

    /// @notice Revokes 'attestationId' under the caller's address, and clears 'contextIds'
    ///         immediately wherever they still point to it within the attestation's own
    ///         schema MAJOR lane — combining revocation and cleanup into a single
    ///         transaction. A context ID whose active attestation has since moved to a
    ///         different attestation ID is silently skipped rather than reverting the
    ///         whole call. Self-service and independent of any registration batch; see
    ///         'revokeAttestations' for the batch and relayed form.
    /// @param attestationId  The attestation ID to revoke.
    /// @param contextIds     The context IDs to clear if they still point to 'attestationId'.
    ///                       MAY be empty for a revoke-only call that skips clearing.
    function revokeAttestation(bytes32 attestationId, bytes32[] calldata contextIds) external;

    /// @notice The batch and relayed counterpart of 'revokeAttestation': revokes every
    ///         entry's attestation ID under 'attester' and clears its listed context IDs.
    ///         Unless 'msg.sender == attester', 'signature' MUST be a valid EIP-712
    ///         signature by the attester over the batch and the attester's current nonce.
    ///         Emergency revocation therefore never requires the attester to hold ETH or
    ///         to attach a descriptor registration.
    /// @param attester     The attester whose attestations are being revoked.
    /// @param revocations  The attestations to revoke, each with the context IDs to clear.
    ///                     MUST be non-empty. An entry's 'contextIds' MAY be empty.
    /// @param signature    EIP-712 signature by the attester authorizing this batch
    ///                     (ignored when 'msg.sender == attester').
    function revokeAttestations(
        address           attester,
        RevocationEntry[] calldata revocations,
        bytes             calldata signature
    ) external;

    /// @notice The timestamp at which 'attester' revoked 'attestationId', via
    ///         'revokeAttestation', a 'revokeAttestations' batch, or a registration
    ///         batch that displaced it — or 0 if never revoked.
    /// @param attester       The attester the attestation ID is revoked under.
    /// @param attestationId  The queried attestation ID.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64 timestamp);

    /// @notice Resolve all active attestations filtered by a list of attesters, a list
    ///         of potential context IDs and a list of schema MAJOR lanes in a single call.
    ///         Returns the descriptor hash, the backing attestation with its revocation
    ///         timestamp ('revokedAt', 0 if never revoked), and the attester's MirrorLists
    ///         for the descriptor and the attestation blob.
    ///
    /// @param attesters   Queried attester addresses.
    /// @param contextIds  Candidate context IDs to look up.
    /// @param schemaMajors  The schema MAJOR lanes to look up — a wallet passes exactly
    ///                    the MAJOR versions it implements. Results are ordered by
    ///                    'attesters' first, then 'contextIds', then 'schemaMajors'; an
    ///                    empty array yields no results.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URI lists,
    ///                    e.g. ["ipfs:", "https:"]. A URI is returned only if it starts
    ///                    with at least one of the prefixes. An empty array disables
    ///                    filtering and returns every URI. An active attestation is included in
    ///                    'resolved' regardless of whether any of its URIs match.
    /// @return resolved   One 'ResolvedDescriptor' entry per non-empty attestation entry.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors,
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

    /// @notice The next EIP-712 nonce for relayed calls by the given attester — shared by
    ///         'createAttestations', 'revokeAttestations' and both MirrorList update functions.
    /// @param attester  The queried attester address.
    /// @return nonce  The next unused nonce.
    function getNonce(address attester) external view returns (uint256 nonce);

    /// @notice Invalidates the caller's current EIP-712 nonce by consuming it,
    ///         cancelling any outstanding signature over that nonce.
    ///         Emits 'NonceInvalidated' with the next valid nonce.
    function invalidateNonce() external;

    /// @notice Update the MirrorList for existing descriptors without re-attestation.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param descriptorHashes The hashes of the descriptors to update. Every hash MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownDescriptor' otherwise.
    /// @param descriptorMirrorListRef The new MirrorList — see 'MirrorListRef'. Supports both
    ///                      the reference flow (rotate to an already-published list) and the
    ///                      inline flow (publish a brand-new list and rotate to it
    ///                      atomically in the same call).
    /// @param signature EIP-712 signature authorizing this update (ignored if msg.sender == attester).
    ///                  Covers the resolved MirrorList id, regardless of which flow produced it.
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
}
