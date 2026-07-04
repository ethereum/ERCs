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
        "DescriptorInfo(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
    );

    bytes32 public constant OFFCHAIN_ATTESTATION_TYPEHASH = keccak256(
        "OffchainAttestation(bytes32 uid,uint64 expirationTime,bytes32 format)"
    );

    bytes32 public constant OFFCHAIN_REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningOffchainRegistrationBatch(DescriptorInfo[] descriptors,OffchainAttestation[] attestations,bytes32 attestationMirrorListId,uint256 nonce)"
        "DescriptorInfo(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
        "OffchainAttestation(bytes32 uid,uint64 expirationTime,bytes32 format)"
    );

    bytes32 public constant MIRROR_UPDATE_TYPEHASH = keccak256(
        "MirrorListUpdate(bytes32[] descriptorHashes,bytes32 mirrorListId)"
    );

    constructor() EIP712("ClearSigningRegistry", "1") {}

    // The UID of the active attestation for the given attester and context ID.
    // The attested descriptor hash is stored in '_offchainDetails'.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationUIDs;

    // Extra metadata for an attestation, stored exactly once per UID.
    struct OffchainDetails {
        bytes32 descriptorHash;
        bytes32 attestationMirrorListId; // points into _mirrorLists, like a descriptor's mirrorListId
        uint64  expirationTime;
        bytes32 format;                  // the declared attestationFormatTag; opaque to the registry
    }
    mapping(address attester => mapping(bytes32 uid => OffchainDetails)) private _offchainDetails;

    // The timestamp at which 'attester' revoked 'uid', or 0 if never revoked. Written
    // either by 'revokeAttestation' directly (msg.sender == attester) or by this
    // registry itself when a registration batch displaces a slot on the attester's
    // behalf, after verifying that batch's own authorization chain.
    mapping(address attester => mapping(bytes32 uid => uint64)) private _revokedAt;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester designates for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _mirrorListId;

    // EIP-712 nonce for relayed registration batches.
    mapping(address attester => uint256) private _registrationNonce;

    /// @inheritdoc IClearSigningRegistry
    function createOffchainDescriptorAttestations(
        address                attester,
        DescriptorInfo[]       calldata descriptors,
        OffchainAttestation[]  calldata attestations,
        string[]               calldata attestationMirrorListUris,
        bytes                  calldata registrationSignature,
        bytes32[]              calldata revocations
    ) external returns (bytes32[] memory attestationIds) {
        if (descriptors.length == 0) {
            revert EmptyDescriptors();
        }
        if (attestations.length != descriptors.length) {
            revert ArrayLengthMismatch();
        }

        // Every active attestation being displaced must be explicitly revoked.
        _checkRevocations(attester, descriptors, revocations);

        // Revoke displaced attestations (may be empty when no slots are replaced).
        _processRevocations(attester, revocations);

        attestationIds = _registerOffchainBatch(
            attester, descriptors, attestations, attestationMirrorListUris, registrationSignature
        );
    }

    /// @dev The registration phase of 'createOffchainDescriptorAttestations', split
    ///      out from the revocation phase to limit per-frame stack usage.
    function _registerOffchainBatch(
        address                            attester,
        DescriptorInfo[]                   calldata descriptors,
        OffchainAttestation[]              calldata attestations,
        string[]                           calldata attestationMirrorListUris,
        bytes                              calldata registrationSignature
    ) private returns (bytes32[] memory attestationIds) {
        // Publish the attestation MirrorList exactly once for the whole batch;
        // every descriptor in this call reuses the resulting pointer.
        bytes32 attestationMirrorListId = _publishMirrorList(attestationMirrorListUris);

        (bytes32[] memory itemHashes, bytes32[] memory attestationHashes) =
            _processAllOffchainDescriptors(attester, descriptors, attestations, attestationMirrorListId);

        attestationIds = _collectOffchainAttestationIds(attestations);

        // Validate the attester's signature over the batch for relayed registrations.
        if (msg.sender != attester) {
            uint256 nonce = _registrationNonce[attester];
            _registrationNonce[attester] = nonce + 1;
            _verifyOffchainRegistrationSignature(
                attester, itemHashes, attestationHashes, attestationMirrorListId, nonce, registrationSignature
            );
        }
    }

    /// @dev Validates and processes every descriptor in an off-chain batch, returning
    ///      each descriptor's EIP-712 item hash and its attestation's EIP-712 hash.
    function _processAllOffchainDescriptors(
        address                            attester,
        DescriptorInfo[]          calldata descriptors,
        OffchainAttestation[]     calldata attestations,
        bytes32                            attestationMirrorListId
    ) private returns (bytes32[] memory itemHashes, bytes32[] memory attestationHashes) {
        uint256 descriptorCount = descriptors.length;
        itemHashes        = new bytes32[](descriptorCount);
        attestationHashes = new bytes32[](descriptorCount);
        for (uint256 descriptorIndex; descriptorIndex < descriptorCount;) {
            (itemHashes[descriptorIndex], attestationHashes[descriptorIndex]) = _processOffchainDescriptor(
                attester, descriptors[descriptorIndex], attestations[descriptorIndex], attestationMirrorListId
            );
            unchecked { ++descriptorIndex; }
        }
    }

    /// @dev Collects the pre-computed off-chain attestation UID of each descriptor, in order.
    function _collectOffchainAttestationIds(
        OffchainAttestation[] calldata attestations
    ) private pure returns (bytes32[] memory attestationIds) {
        uint256 attestationCount = attestations.length;
        attestationIds = new bytes32[](attestationCount);
        for (uint256 attestationIndex; attestationIndex < attestationCount;) {
            attestationIds[attestationIndex] = attestations[attestationIndex].uid;
            unchecked { ++attestationIndex; }
        }
    }

    /// @dev Updates the active slot for each contextId of a descriptor.
    function _updateSlots(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 uid
    ) private {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            bytes32 contextId   = contextIds[contextIndex];
            bytes32 previousUid = _attestationUIDs[attester][contextId];
            _attestationUIDs[attester][contextId] = uid;
            emit AttestationUpdated(
                attester, contextId, uid, previousUid, descriptor.descriptorHash
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
    function revokeAttestation(bytes32 uid) external {
        _recordRevocation(msg.sender, uid);
    }

    /// @inheritdoc IClearSigningRegistry
    function getRevocationTimestamp(address attester, bytes32 uid) external view returns (uint64) {
        return _revokedAt[attester][uid];
    }

    /// @dev Records 'uid' as revoked under 'attester', emitting 'AttestationRevoked'.
    ///      Shared by the direct self-service path ('revokeAttestation') and the
    ///      batch-displacement path ('_processRevocations').
    function _recordRevocation(address attester, bytes32 uid) private {
        uint64 timestamp = uint64(block.timestamp);
        _revokedAt[attester][uid] = timestamp;
        emit AttestationRevoked(attester, uid, timestamp);
    }

    /// @inheritdoc IClearSigningRegistry
    function clearRevokedAttestations(
        address[]   calldata attesters,
        bytes32[][] calldata contextIds
    ) external returns (uint256 cleared) {
        uint256 attesterCount = attesters.length;
        if (attesterCount == 0) {
            revert EmptyAttesters();
        }
        if (attesterCount != contextIds.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 attesterIndex; attesterIndex < attesterCount;) {
            cleared += _clearRevokedAttestationsForAttester(attesters[attesterIndex], contextIds[attesterIndex]);
            unchecked { ++attesterIndex; }
        }
    }

    /// @dev Clears every stale context ID slot listed for one attester, returning how many were cleared.
    function _clearRevokedAttestationsForAttester(
        address            attester,
        bytes32[] calldata contextIdsForAttester
    ) private returns (uint256 cleared) {
        uint256 contextIdCount = contextIdsForAttester.length;
        if (contextIdCount == 0) {
            revert EmptyContextIds();
        }

        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            if (_clearSlotIfRevokedOrExpired(attester, contextIdsForAttester[contextIndex])) {
                ++cleared;
            }
            unchecked { ++contextIndex; }
        }
    }

    /// @dev Clears one context ID's active slot if its backing attestation is
    ///      revoked or expired. Returns whether the slot was cleared.
    function _clearSlotIfRevokedOrExpired(address attester, bytes32 contextId) private returns (bool) {
        bytes32 uid = _attestationUIDs[attester][contextId];
        // Skip empty slots: another sweep or a re-registration won the race.
        if (uid == bytes32(0)) {
            return false;
        }
        if (!_isAttestationRevokedOrExpired(attester, uid)) {
            return false;
        }

        _attestationUIDs[attester][contextId] = bytes32(0);
        emit AttestationUpdated(attester, contextId, bytes32(0), uid, bytes32(0));
        return true;
    }

    /// @dev Checks whether the attestation backing a UID has been revoked or has expired.
    function _isAttestationRevokedOrExpired(address attester, bytes32 uid) private view returns (bool) {
        OffchainDetails storage details = _offchainDetails[attester][uid];
        bool revoked = _revokedAt[attester][uid] != 0;
        bool expired = details.expirationTime != 0 && details.expirationTime < block.timestamp;
        return revoked || expired;
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
                if (_attestationUIDs[attester][contextIds[contextIndex]] != bytes32(0)) {
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
                bytes32 uid = _attestationUIDs[attester][contextId];
                if (uid != bytes32(0)) {
                    resolved[resolvedIndex++] = _resolveSlot(attester, contextId, uid, allowedPrefixes);
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
        bytes32            uid,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        OffchainDetails storage details = _offchainDetails[attester][uid];
        (bytes32 descriptorHash, uint64 expirationTime, bytes32 format, string[] memory attestationMirrorListUris) =
            _resolveOffchainAttestation(details, allowedPrefixes);

        bytes32 mirrorListId = _mirrorListId[attester][descriptorHash];

        return ResolvedDescriptor({
            attester:                  attester,
            contextId:                 contextId,
            descriptorHash:            descriptorHash,
            attestationId:             uid,
            expirationTime:            expirationTime,
            attestationMirrorListUris: attestationMirrorListUris,
            format:                    format,
            uris:                      _filterUris(_mirrorLists[mirrorListId], allowedPrefixes)
        });
    }

    /// @dev Reads an attestation's metadata from registry storage.
    function _resolveOffchainAttestation(
        OffchainDetails storage details,
        string[]       calldata allowedPrefixes
    ) private view returns (
        bytes32  descriptorHash,
        uint64   expirationTime,
        bytes32  format,
        string[] memory attestationMirrorListUris
    ) {
        descriptorHash = details.descriptorHash;
        expirationTime = details.expirationTime;
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

    /// @dev Validates one descriptor, resolves or publishes its MirrorList and
    ///      updates the attester's MirrorList pointer.
    /// @return The descriptor's EIP-712 item hash.
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

        bytes32 mirrorListId = _resolveOrPublishMirrorList(descriptor);
        _setMirrorListPointerIfChanged(attester, descriptor.descriptorHash, mirrorListId);

        return keccak256(
            abi.encode(
                DESCRIPTOR_TYPEHASH,
                descriptor.descriptorHash,
                keccak256(abi.encodePacked(descriptor.contextIds)),
                mirrorListId
            )
        );
    }

    /// @dev Resolves a descriptor's MirrorList pointer: publishes the inline URIs
    ///      when supplied, or looks up a previously published list by ID otherwise.
    function _resolveOrPublishMirrorList(
        DescriptorInfo calldata descriptor
    ) private returns (bytes32 mirrorListId) {
        bool isInlineFlow = descriptor.mirrorListUris.length > 0;
        if (isInlineFlow) {
            // inline flow - hash the supplied MirrorList to get its ID
            if (descriptor.mirrorListId != bytes32(0)) {
                revert RedundantMirrorListId();
            }
            return _publishMirrorList(descriptor.mirrorListUris);
        }

        // reference flow - the MirrorList must have been published before
        mirrorListId = descriptor.mirrorListId;
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

    /// @dev Processes one descriptor of an off-chain registration batch: shared
    ///      descriptor processing, off-chain metadata storage and slot updates.
    /// @return itemHash         The descriptor's EIP-712 item hash.
    /// @return attestationHash  The EIP-712 hash of the off-chain attestation struct.
    function _processOffchainDescriptor(
        address                         attester,
        DescriptorInfo         calldata descriptor,
        OffchainAttestation    calldata attestation,
        bytes32                         attestationMirrorListId
    ) private returns (bytes32 itemHash, bytes32 attestationHash) {
        if (attestation.format == bytes32(0)) {
            revert ZeroAttestationFormat();
        }

        itemHash = _processDescriptorCore(attester, descriptor);
        attestationHash = keccak256(
            abi.encode(OFFCHAIN_ATTESTATION_TYPEHASH, attestation.uid, attestation.expirationTime, attestation.format)
        );

        // Store the off-chain metadata exactly once per UID, not per contextId.
        _offchainDetails[attester][attestation.uid] = OffchainDetails({
            descriptorHash:          descriptor.descriptorHash,
            attestationMirrorListId: attestationMirrorListId,
            expirationTime:          attestation.expirationTime,
            format:                  attestation.format
        });

        _updateSlots(attester, descriptor, attestation.uid);
    }

    /// @dev Verifies the attester's EIP-712 signature over a registration batch.
    ///      Binding the attestation MirrorList ID and the full attestation structs
    ///      prevents a relayer from substituting a different MirrorList or falsified
    ///      expiration times; the nonce makes the signature single-use.
    function _verifyOffchainRegistrationSignature(
        address            attester,
        bytes32[] memory   itemHashes,
        bytes32[] memory   attestationHashes,
        bytes32            attestationMirrorListId,
        uint256            nonce,
        bytes     calldata registrationSignature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                OFFCHAIN_REGISTRATION_BATCH_TYPEHASH,
                keccak256(abi.encodePacked(itemHashes)),
                keccak256(abi.encodePacked(attestationHashes)),
                attestationMirrorListId,
                nonce
            )
        );
        _verifySignature(attester, structHash, registrationSignature);
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

    /// @dev Records each UID in 'revocations' as revoked under 'attester'. Safe to
    ///      call with an empty array when no slots are being displaced.
    function _processRevocations(address attester, bytes32[] calldata revocations) private {
        uint256 revocationCount = revocations.length;
        for (uint256 revocationIndex; revocationIndex < revocationCount;) {
            _recordRevocation(attester, revocations[revocationIndex]);
            unchecked { ++revocationIndex; }
        }
    }

    /// @dev Requires that every active attestation displaced by this batch is
    ///      present in 'revocations'.
    function _checkRevocations(
        address                   attester,
        DescriptorInfo[] calldata descriptors,
        bytes32[]        calldata revocations
    ) private view {
        uint256 descriptorCount = descriptors.length;
        for (uint256 descriptorIndex; descriptorIndex < descriptorCount;) {
            _checkRevocationsForDescriptor(attester, descriptors[descriptorIndex], revocations);
            unchecked { ++descriptorIndex; }
        }
    }

    /// @dev Checks every context ID of one descriptor for a displaced, unrevoked slot.
    function _checkRevocationsForDescriptor(
        address                  attester,
        DescriptorInfo  calldata descriptor,
        bytes32[]       calldata revocations
    ) private view {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            _checkDisplacedSlotIsRevoked(attester, contextIds[contextIndex], revocations);
            unchecked { ++contextIndex; }
        }
    }

    /// @dev Reverts with 'MissingRevocation' if a context ID's currently active slot
    ///      is about to be displaced without appearing in 'revocations'.
    function _checkDisplacedSlotIsRevoked(
        address            attester,
        bytes32            contextId,
        bytes32[] calldata revocations
    ) private view {
        bytes32 displacedUid = _attestationUIDs[attester][contextId];
        if (displacedUid == bytes32(0)) {
            return;
        }

        if (!_containsUid(revocations, displacedUid)) {
            revert MissingRevocation(displacedUid);
        }
    }

    /// @dev Linear search for 'target' within 'uids'.
    function _containsUid(bytes32[] calldata uids, bytes32 target) private pure returns (bool) {
        uint256 uidCount = uids.length;
        for (uint256 uidIndex; uidIndex < uidCount;) {
            if (uids[uidIndex] == target) {
                return true;
            }
            unchecked { ++uidIndex; }
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
