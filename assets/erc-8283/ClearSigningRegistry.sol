// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IClearSigningRegistry.sol";
import "./openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is IClearSigningRegistry, EIP712 {

    bytes32 public constant CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract");

    bytes32 public constant CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory");

    bytes32 public constant CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment");

    bytes32 public constant CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator");

    bytes32 public constant ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256("erc7730.attestation.eas.offchain");

    bytes32 public constant DESCRIPTOR_TYPEHASH = keccak256(
        "DescriptorInfo(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId,bytes32 attestationId,bytes32 format)"
    );

    bytes32 public constant REVOCATION_ENTRY_TYPEHASH = keccak256(
        "RevocationEntry(bytes32 attestationId,bytes32[] contextIds)"
    );

    bytes32 public constant REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRegistrationBatch(DescriptorInfo[] descriptors,bytes32 attestationMirrorListId,RevocationEntry[] revocations,uint256 nonce)"
        "DescriptorInfo(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId,bytes32 attestationId,bytes32 format)"
        "RevocationEntry(bytes32 attestationId,bytes32[] contextIds)"
    );

    bytes32 public constant MIRROR_UPDATE_TYPEHASH = keccak256(
        "MirrorListUpdate(bytes32[] descriptorHashes,bytes32 mirrorListId)"
    );

    constructor() EIP712("ClearSigningRegistry", "1") {}

    // The attestation ID currently active for the given attester and context ID.
    // The attested descriptor hash is stored in '_attestationDetails'.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationIds;

    // Extra metadata for an attestation, stored exactly once per attestation ID.
    struct AttestationDetails {
        bytes32 descriptorHash;
        bytes32 attestationMirrorListId; // points into _mirrorLists, like a descriptor's mirrorListId
        bytes32 format;                  // the declared attestationFormatTag; opaque to the registry
    }
    mapping(address attester => mapping(bytes32 attestationId => AttestationDetails)) private _attestationDetails;

    // The timestamp at which 'attester' revoked 'attestationId', or 0 if never revoked.
    // Written either by 'revokeAttestation' directly (msg.sender == attester) or by
    // this registry itself when a registration batch displaces a slot on the
    // attester's behalf, after verifying that batch's own authorization chain.
    mapping(address attester => mapping(bytes32 attestationId => uint64)) private _revokedAt;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester designates for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _mirrorListId;

    // EIP-712 nonce for relayed registration batches.
    mapping(address attester => uint256) private _registrationNonce;

    /// @inheritdoc IClearSigningRegistry
    function createAttestations(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata attestationURIs,
        bytes             calldata signature
    ) external {
        if (descriptors.length == 0) {
            revert EmptyDescriptors();
        }

        // Every active attestation being displaced must be explicitly revoked.
        _checkRevocations(attester, descriptors, revocations);

        // Revoke and clear displaced attestations (may be empty when no slots are replaced).
        _processRevocations(attester, revocations);

        _registerBatch(attester, descriptors, revocations, attestationURIs, signature);
    }

    /// @dev The registration phase of 'createAttestations', split out from the
    ///      revocation phase to limit per-frame stack usage.
    function _registerBatch(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata attestationURIs,
        bytes             calldata signature
    ) private {
        // Resolve the attestation MirrorList exactly once for the whole batch (by
        // reference or by publishing it inline); every descriptor in this call
        // reuses the resulting pointer.
        bytes32 attestationMirrorListId = _resolveOrPublishMirrorList(attestationURIs);

        bytes32[] memory itemHashes = _processAllDescriptors(attester, descriptors, attestationMirrorListId);

        // Validate the attester's signature over the batch for relayed registrations.
        if (msg.sender != attester) {
            uint256 nonce = _registrationNonce[attester];
            _registrationNonce[attester] = nonce + 1;
            _verifyRegistrationSignature(
                attester, itemHashes, attestationMirrorListId,
                _hashRevocationEntries(revocations), nonce, signature
            );
        }
    }

    /// @dev Validates and processes every descriptor in a batch, returning each
    ///      descriptor's EIP-712 item hash.
    function _processAllDescriptors(
        address                   attester,
        DescriptorInfo[] calldata descriptors,
        bytes32                   attestationMirrorListId
    ) private returns (bytes32[] memory itemHashes) {
        uint256 descriptorCount = descriptors.length;
        itemHashes = new bytes32[](descriptorCount);
        for (uint256 descriptorIndex; descriptorIndex < descriptorCount;) {
            itemHashes[descriptorIndex] = _processDescriptor(
                attester, descriptors[descriptorIndex], attestationMirrorListId
            );
            unchecked { ++descriptorIndex; }
        }
    }

    /// @dev Updates the active slot for each contextId of a descriptor.
    function _updateSlots(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationId
    ) private {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            bytes32 contextId             = contextIds[contextIndex];
            bytes32 previousAttestationId = _attestationIds[attester][contextId];
            _attestationIds[attester][contextId] = attestationId;
            emit AttestationUpdated(
                attester, contextId, attestationId, previousAttestationId, descriptor.descriptorHash
            );
            unchecked { ++contextIndex; }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds)
    {
        uint256 listCount = uriLists.length;
        mirrorListIds = new bytes32[](listCount);
        for (uint256 listIndex; listIndex < listCount;) {
            mirrorListIds[listIndex] = _publishMirrorList(uriLists[listIndex]);
            unchecked { ++listIndex; }
        }
    }

    /// @dev Stores a MirrorList keyed by its content hash. Idempotent: a list
    ///      with identical content is stored exactly once and emits no event on
    ///      repeated publication.
    function _publishMirrorList(string[] calldata uris) private returns (bytes32 mirrorListId) {
        if (uris.length == 0) {
            revert EmptyMirrorList();
        }
        mirrorListId = keccak256(abi.encode(uris));
        if (_mirrorLists[mirrorListId].length == 0) {
            _mirrorLists[mirrorListId] = uris;
            emit MirrorListPublished(mirrorListId);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function revokeAttestation(bytes32 attestationId, bytes32[] calldata contextIds) external {
        if (contextIds.length == 0) {
            revert EmptyContextIds();
        }
        _revokeAndClear(msg.sender, attestationId, contextIds);
    }

    /// @inheritdoc IClearSigningRegistry
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64) {
        return _revokedAt[attester][attestationId];
    }

    /// @dev Records 'attestationId' as revoked under 'attester', emitting 'AttestationRevoked'.
    function _recordRevocation(address attester, bytes32 attestationId) private {
        uint64 timestamp = uint64(block.timestamp);
        _revokedAt[attester][attestationId] = timestamp;
        emit AttestationRevoked(attester, attestationId, timestamp);
    }

    /// @dev Records 'attestationId' as revoked under 'attester' and clears 'contextIds'
    ///      immediately wherever they still point to it. A context ID whose active slot
    ///      has since moved to a different attestation ID is silently skipped. Shared by
    ///      the direct self-service path ('revokeAttestation') and the registration-batch
    ///      displacement path ('_processRevocations').
    function _revokeAndClear(address attester, bytes32 attestationId, bytes32[] calldata contextIds) private {
        _recordRevocation(attester, attestationId);
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            bytes32 contextId = contextIds[contextIndex];
            if (_attestationIds[attester][contextId] == attestationId) {
                _attestationIds[attester][contextId] = bytes32(0);
                emit AttestationUpdated(attester, contextId, bytes32(0), attestationId, bytes32(0));
            }
            unchecked { ++contextIndex; }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 activeSlotCount = _countActiveSlots(attesters, contextIds);
        resolved = new ResolvedDescriptor[](activeSlotCount);
        _collectResolvedDescriptors(attesters, contextIds, allowedPrefixes, resolved);
    }

    /// @dev Counts how many (attester, contextId) pairs currently have an active slot,
    ///      used to size the 'resolveDescriptors' result array.
    function _countActiveSlots(
        address[] calldata attesters,
        bytes32[] calldata contextIds
    ) private view returns (uint256 activeSlotCount) {
        uint256 attesterCount = attesters.length;
        uint256 contextIdCount = contextIds.length;
        for (uint256 attesterIndex; attesterIndex < attesterCount;) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex; contextIndex < contextIdCount;) {
                if (_attestationIds[attester][contextIds[contextIndex]] != bytes32(0)) {
                    ++activeSlotCount;
                }
                unchecked { ++contextIndex; }
            }
            unchecked { ++attesterIndex; }
        }
    }

    /// @dev Fills 'resolved' with one entry per active (attester, contextId) slot.
    function _collectResolvedDescriptors(
        address[]            calldata attesters,
        bytes32[]            calldata contextIds,
        string[]              calldata allowedPrefixes,
        ResolvedDescriptor[]   memory  resolved
    ) private view {
        uint256 attesterCount = attesters.length;
        uint256 contextIdCount = contextIds.length;
        uint256 resolvedIndex;
        for (uint256 attesterIndex; attesterIndex < attesterCount;) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex; contextIndex < contextIdCount;) {
                bytes32 contextId = contextIds[contextIndex];
                bytes32 attestationId = _attestationIds[attester][contextId];
                if (attestationId != bytes32(0)) {
                    resolved[resolvedIndex++] = _resolveSlot(attester, contextId, attestationId, allowedPrefixes);
                }
                unchecked { ++contextIndex; }
            }
            unchecked { ++attesterIndex; }
        }
    }

    /// @dev Resolves one active slot into a ResolvedDescriptor.
    function _resolveSlot(
        address            attester,
        bytes32            contextId,
        bytes32            attestationId,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        AttestationDetails storage details = _attestationDetails[attester][attestationId];
        (bytes32 descriptorHash, bytes32 format, string[] memory attestationMirrorListUris) =
            _resolveAttestation(details, allowedPrefixes);

        bytes32 mirrorListId = _mirrorListId[attester][descriptorHash];

        return ResolvedDescriptor({
            attester:                  attester,
            contextId:                 contextId,
            descriptorHash:            descriptorHash,
            attestationId:             attestationId,
            attestationMirrorListUris: attestationMirrorListUris,
            format:                    format,
            uris:                      _filterUris(_mirrorLists[mirrorListId], allowedPrefixes)
        });
    }

    /// @dev Reads an attestation's metadata from registry storage.
    function _resolveAttestation(
        AttestationDetails storage details,
        string[]           calldata allowedPrefixes
    ) private view returns (
        bytes32  descriptorHash,
        bytes32  format,
        string[] memory attestationMirrorListUris
    ) {
        descriptorHash = details.descriptorHash;
        format         = details.format;
        attestationMirrorListUris = _filterUris(_mirrorLists[details.attestationMirrorListId], allowedPrefixes);
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
        external view returns (string[] memory)
    {
        return _filterUris(_mirrorLists[mirrorListId], allowedPrefixes);
    }

    /// @inheritdoc IClearSigningRegistry
    function getRegistrationNonce(address attester) external view returns (uint256) {
        return _registrationNonce[attester];
    }

    /// @inheritdoc IClearSigningRegistry
    function updateMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        bytes32 mirrorListId,
        bytes calldata signature
    ) external {
        uint256 descriptorHashCount = descriptorHashes.length;
        if (descriptorHashCount == 0) {
            revert EmptyDescriptors();
        }
        if (_mirrorLists[mirrorListId].length == 0) {
            revert UnknownMirrorList(mirrorListId);
        }

        if (msg.sender != attester) {
            _verifyMirrorUpdateSignature(attester, descriptorHashes, mirrorListId, signature);
        }

        for (uint256 descriptorHashIndex; descriptorHashIndex < descriptorHashCount;) {
            _setMirrorListPointerIfChanged(attester, descriptorHashes[descriptorHashIndex], mirrorListId);
            unchecked { ++descriptorHashIndex; }
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Validates one descriptor, resolves or publishes its MirrorList, updates
    ///      the attester's MirrorList pointer, and returns its EIP-712 item hash
    ///      (covering the descriptor identity and the attestation reference together).
    function _processDescriptorCore(
        address                          attester,
        DescriptorInfo          calldata descriptor
    ) private returns (bytes32) {
        if (descriptor.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (descriptor.contextIds.length == 0) {
            revert EmptyContextIds();
        }

        bytes32 mirrorListId = _resolveOrPublishMirrorList(descriptor.descriptorURIs);
        _setMirrorListPointerIfChanged(attester, descriptor.descriptorHash, mirrorListId);

        return keccak256(
            abi.encode(
                DESCRIPTOR_TYPEHASH,
                descriptor.descriptorHash,
                keccak256(abi.encodePacked(descriptor.contextIds)),
                mirrorListId,
                descriptor.attestationId,
                descriptor.format
            )
        );
    }

    /// @dev Resolves a MirrorListRef: publishes the inline URIs when supplied, or
    ///      looks up a previously published list by ID otherwise. Shared by a
    ///      descriptor's own MirrorList and the batch's attestation MirrorList.
    function _resolveOrPublishMirrorList(
        MirrorListRef calldata ref
    ) private returns (bytes32 mirrorListId) {
        bool isInlineFlow = ref.uris.length > 0;
        if (isInlineFlow) {
            // inline flow - hash the supplied MirrorList to get its ID
            if (ref.id != bytes32(0)) {
                revert RedundantMirrorListId();
            }
            return _publishMirrorList(ref.uris);
        }

        // reference flow - the MirrorList must have been published before
        mirrorListId = ref.id;
        if (_mirrorLists[mirrorListId].length == 0) {
            revert UnknownMirrorList(mirrorListId);
        }
    }

    /// @dev Points an attester's active MirrorList for a descriptor at 'mirrorListId',
    ///      emitting 'MirrorListUpdated' only when the pointer actually changes.
    function _setMirrorListPointerIfChanged(
        address attester,
        bytes32 descriptorHash,
        bytes32 mirrorListId
    ) private {
        if (_mirrorListId[attester][descriptorHash] == mirrorListId) {
            return;
        }
        _mirrorListId[attester][descriptorHash] = mirrorListId;
        emit MirrorListUpdated(attester, descriptorHash, mirrorListId);
    }

    /// @dev Processes one descriptor of a registration batch: shared descriptor
    ///      processing, attestation metadata storage and slot updates.
    /// @return itemHash  The descriptor's EIP-712 item hash.
    function _processDescriptor(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationMirrorListId
    ) private returns (bytes32 itemHash) {
        if (descriptor.format == bytes32(0)) {
            revert ZeroAttestationFormat();
        }

        itemHash = _processDescriptorCore(attester, descriptor);

        // Store the attestation metadata exactly once per attestation ID, not per contextId.
        _attestationDetails[attester][descriptor.attestationId] = AttestationDetails({
            descriptorHash:          descriptor.descriptorHash,
            attestationMirrorListId: attestationMirrorListId,
            format:                  descriptor.format
        });

        _updateSlots(attester, descriptor, descriptor.attestationId);
    }

    /// @dev Verifies the attester's EIP-712 signature over a registration batch.
    ///      Binding the attestation MirrorList ID prevents a relayer from substituting
    ///      a different MirrorList; binding 'revocationsHash' prevents a relayer from
    ///      adding or dropping revocation entries; the nonce makes the signature single-use.
    function _verifyRegistrationSignature(
        address            attester,
        bytes32[] memory   itemHashes,
        bytes32            attestationMirrorListId,
        bytes32            revocationsHash,
        uint256            nonce,
        bytes     calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTRATION_BATCH_TYPEHASH,
                keccak256(abi.encodePacked(itemHashes)),
                attestationMirrorListId,
                revocationsHash,
                nonce
            )
        );
        _verifySignature(attester, structHash, signature);
    }

    /// @dev Verifies the attester's EIP-712 mirror update signature.
    function _verifyMirrorUpdateSignature(
        address              attester,
        bytes32[]   calldata descriptorHashes,
        bytes32              mirrorListId,
        bytes       calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                MIRROR_UPDATE_TYPEHASH,
                keccak256(abi.encodePacked(descriptorHashes)),
                mirrorListId
            )
        );
        _verifySignature(attester, structHash, signature);
    }

    /// @dev Verifies an EIP-712 signature over the given struct hash via ECDSA
    ///      recovery for EOA attesters and ERC-1271 for contract attesters.
    function _verifySignature(
        address        attester,
        bytes32        structHash,
        bytes calldata signature
    ) private view {
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(attester, digest, signature)) {
            revert InvalidRegistrationSignature();
        }
    }

    /// @dev EIP-712 array-hash of 'revocations', following the same pattern as
    ///      'itemHashes': one 'REVOCATION_ENTRY_TYPEHASH' hash per entry, aggregated
    ///      via 'keccak256(abi.encodePacked(...))'.
    function _hashRevocationEntries(RevocationEntry[] calldata revocations) private pure returns (bytes32) {
        uint256 count = revocations.length;
        bytes32[] memory entryHashes = new bytes32[](count);
        for (uint256 i; i < count;) {
            RevocationEntry calldata entry = revocations[i];
            entryHashes[i] = keccak256(
                abi.encode(REVOCATION_ENTRY_TYPEHASH, entry.attestationId, keccak256(abi.encodePacked(entry.contextIds)))
            );
            unchecked { ++i; }
        }
        return keccak256(abi.encodePacked(entryHashes));
    }

    /// @dev Records each entry in 'revocations' as revoked under 'attester' and clears
    ///      its listed context IDs. Safe to call with an empty array when no slots are
    ///      being displaced.
    function _processRevocations(address attester, RevocationEntry[] calldata revocations) private {
        uint256 revocationCount = revocations.length;
        for (uint256 revocationIndex; revocationIndex < revocationCount;) {
            RevocationEntry calldata entry = revocations[revocationIndex];
            _revokeAndClear(attester, entry.attestationId, entry.contextIds);
            unchecked { ++revocationIndex; }
        }
    }

    /// @dev Requires that every active attestation displaced by this batch is
    ///      present in 'revocations'.
    function _checkRevocations(
        address                    attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations
    ) private view {
        uint256 descriptorCount = descriptors.length;
        for (uint256 descriptorIndex; descriptorIndex < descriptorCount;) {
            _checkRevocationsForDescriptor(attester, descriptors[descriptorIndex], revocations);
            unchecked { ++descriptorIndex; }
        }
    }

    /// @dev Checks every context ID of one descriptor for a displaced, unrevoked slot.
    function _checkRevocationsForDescriptor(
        address                   attester,
        DescriptorInfo   calldata descriptor,
        RevocationEntry[] calldata revocations
    ) private view {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            _checkDisplacedSlotIsRevoked(attester, contextIds[contextIndex], revocations);
            unchecked { ++contextIndex; }
        }
    }

    /// @dev Reverts with 'MissingRevocation' if a context ID's currently active slot
    ///      is about to be displaced without its attestation ID appearing in 'revocations'.
    function _checkDisplacedSlotIsRevoked(
        address                    attester,
        bytes32                    contextId,
        RevocationEntry[] calldata revocations
    ) private view {
        bytes32 displacedAttestationId = _attestationIds[attester][contextId];
        if (displacedAttestationId == bytes32(0)) {
            return;
        }

        if (!_containsAttestationId(revocations, displacedAttestationId)) {
            revert MissingRevocation(displacedAttestationId);
        }
    }

    /// @dev Linear search for a 'RevocationEntry' whose 'attestationId' equals 'target'.
    function _containsAttestationId(RevocationEntry[] calldata revocations, bytes32 target) private pure returns (bool) {
        uint256 count = revocations.length;
        for (uint256 i; i < count;) {
            if (revocations[i].attestationId == target) {
                return true;
            }
            unchecked { ++i; }
        }
        return false;
    }

    /// @dev Copies the URIs matching at least one of the allowed prefixes into a
    ///      memory array. An empty prefix list disables filtering. A rejected URI
    ///      is never fully loaded from storage and never reaches the return data:
    ///      the cost of discarding it is bounded by the prefix lengths, not by the
    ///      URI's own length.
    function _filterUris(string[] storage uris, string[] calldata allowedPrefixes)
        private view returns (string[] memory filtered)
    {
        if (allowedPrefixes.length == 0) {
            return uris; // unfiltered: implicit storage-to-memory copy
        }

        uint256 matchingUriCount = _countMatchingUris(uris, allowedPrefixes);
        filtered = new string[](matchingUriCount);
        _collectMatchingUris(uris, allowedPrefixes, filtered);
    }

    /// @dev Counts how many URIs in storage match at least one allowed prefix.
    function _countMatchingUris(
        string[] storage  uris,
        string[] calldata allowedPrefixes
    ) private view returns (uint256 matchingUriCount) {
        uint256 uriCount = uris.length;
        for (uint256 uriIndex; uriIndex < uriCount;) {
            if (_matchesAnyPrefix(uris[uriIndex], allowedPrefixes)) {
                ++matchingUriCount;
            }
            unchecked { ++uriIndex; }
        }
    }

    /// @dev Copies every URI in storage that matches at least one allowed prefix into 'filtered'.
    function _collectMatchingUris(
        string[] storage  uris,
        string[] calldata allowedPrefixes,
        string[]  memory  filtered
    ) private view {
        uint256 uriCount = uris.length;
        uint256 filteredIndex;
        for (uint256 uriIndex; uriIndex < uriCount;) {
            if (_matchesAnyPrefix(uris[uriIndex], allowedPrefixes)) {
                filtered[filteredIndex++] = uris[uriIndex];
            }
            unchecked { ++uriIndex; }
        }
    }

    /// @dev Whether 'uri' starts with at least one of 'allowedPrefixes'.
    function _matchesAnyPrefix(string storage uri, string[] calldata allowedPrefixes) private view returns (bool) {
        uint256 prefixCount = allowedPrefixes.length;
        for (uint256 prefixIndex; prefixIndex < prefixCount;) {
            if (_hasPrefix(uri, allowedPrefixes[prefixIndex])) {
                return true;
            }
            unchecked { ++prefixIndex; }
        }
        return false;
    }

    /// @dev Whether 'uri' starts with 'prefix', comparing byte by byte.
    function _hasPrefix(string storage uri, string calldata prefix) private view returns (bool) {
        bytes storage uriBytes = bytes(uri);
        bytes calldata prefixBytes = bytes(prefix);
        uint256 prefixLength = prefixBytes.length;
        if (prefixLength > uriBytes.length) {
            return false;
        }

        // Note: In production, optimize this by reading the first 32 bytes from storage
        // in one go (handling both short and long string packing) to avoid O(N) sloads
        // for short prefixes like "ipfs:".
        for (uint256 byteIndex; byteIndex < prefixLength;) {
            if (uriBytes[byteIndex] != prefixBytes[byteIndex]) {
                return false;
            }
            unchecked { ++byteIndex; }
        }
        return true;
    }
}
