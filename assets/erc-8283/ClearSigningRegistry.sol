// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IEAS.sol";
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

    bytes32 public constant ATTESTATION_FORMAT_EAS_ONCHAIN  = keccak256("erc7730.attestation.eas.onchain");

    bytes32 public constant ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256("erc7730.attestation.eas.offchain");

    bytes32 public constant REGISTRATION_TYPEHASH = keccak256(
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
    );

    bytes32 public constant REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRegistrationBatch(DescriptorRegistration[] registrations,bytes32 attestationSignaturesHash)"
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
    );

    bytes32 public constant OFFCHAIN_ATTESTATION_TYPEHASH = keccak256(
        "OffchainAttestation(bytes32 uid,uint64 expirationTime,bytes32 format)"
    );

    bytes32 public constant OFFCHAIN_REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningOffchainRegistrationBatch(DescriptorRegistration[] registrations,OffchainAttestation[] attestations,bytes32 attestationMirrorListId,uint256 nonce)"
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
        "OffchainAttestation(bytes32 uid,uint64 expirationTime,bytes32 format)"
    );

    bytes32 public constant MIRROR_UPDATE_TYPEHASH = keccak256(
        "MirrorListUpdate(bytes32[] descriptorHashes,bytes32 mirrorListId)"
    );

    IEAS    public immutable eas;
    bytes32 public immutable easSchemaUID;

    constructor(address easAddress, bytes32 attestationSchemaUID) EIP712("ClearSigningRegistry", "1") {
        eas          = IEAS(easAddress);
        easSchemaUID = attestationSchemaUID;
    }

    // The EAS UID of the active ERC-8176 attestation for the given attester and context ID.
    // Holds either an on-chain attestation UID or a pre-computed off-chain attestation UID;
    // for on-chain UIDs the endorsed descriptor hash is stored inside the attestation's
    // 'data' field, for off-chain UIDs it is stored in '_offchainDetails'.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationUIDs;

    // Extra metadata for off-chain attestations, stored exactly once per UID.
    // Never written on the on-chain path, keeping its slot writes to the single UID.
    struct OffchainDetails {
        bytes32 descriptorHash;
        bytes32 attestationMirrorListId; // points into _mirrorLists, like a descriptor's mirrorListId
        uint64  expirationTime;
        bytes32 format;                  // the declared attestationFormatTag; opaque to the registry
    }
    mapping(address attester => mapping(bytes32 uid => OffchainDetails)) private _offchainDetails;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester endorses for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _mirrorListId;

    // EIP-712 nonce for relayed off-chain registration batches. The on-chain path
    // needs no registry nonce: EAS consumes the attester's delegated attestation nonces.
    mapping(address attester => uint256) private _registrationNonce;

    /// @inheritdoc IClearSigningRegistry
    function createDescriptorAttestations(
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedAttestationRequest[] calldata attestations,
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes                              calldata registrationSignature,
        bytes32[]                          calldata offchainRevocations
    ) external returns (bytes32[] memory attestationIds) {
        if (registrations.length == 0) {
            revert EmptyRegistrations();
        }
        if (attestations.length == 0) {
            revert EmptyAttestations();
        }

        MultiDelegatedAttestationRequest calldata activeAttestationBatch = attestations[0];
        _validateActiveAttestationBatch(activeAttestationBatch, registrations.length);

        // Every active attestation being displaced must be explicitly revoked,
        // whether the displaced slot was previously on-chain or off-chain.
        _checkRevocations(activeAttestationBatch.attester, registrations, revocations, offchainRevocations);

        // Revoke prior attestations (may be empty when no slots are replaced).
        _processRevocations(revocations, offchainRevocations);

        attestationIds = _registerOnchainBatch(registrations, attestations, registrationSignature);
    }

    /// @dev Validates that the active attestation batch uses the registry's ERC-8176
    ///      schema and carries exactly one data entry and one signature per registration.
    function _validateActiveAttestationBatch(
        MultiDelegatedAttestationRequest calldata activeAttestationBatch,
        uint256                                   registrationCount
    ) private view {
        if (activeAttestationBatch.schema != easSchemaUID) {
            revert WrongEASSchema(easSchemaUID, activeAttestationBatch.schema);
        }
        if (
            activeAttestationBatch.data.length != registrationCount ||
            activeAttestationBatch.signatures.length != registrationCount
        ) {
            revert ArrayLengthMismatch();
        }
    }

    /// @dev The registration phase of 'createDescriptorAttestations', split out
    ///      from the revocation phase to limit per-frame stack usage.
    function _registerOnchainBatch(
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedAttestationRequest[] calldata attestations,
        bytes                              calldata registrationSignature
    ) private returns (bytes32[] memory attestationIds) {
        MultiDelegatedAttestationRequest calldata activeAttestationBatch = attestations[0];
        address attester = activeAttestationBatch.attester;

        // Validate each registration against its active attestation, publish its
        // MirrorList, and collect the EIP-712 hash of each registration item.
        bytes32[] memory itemHashes =
            _processAllRegistrations(attester, registrations, activeAttestationBatch.data);

        // Validate the attester's signature over the attestation metadata for relayed registrations.
        if (msg.sender != attester) {
            _verifyRegistrationSignature(
                attester, itemHashes, activeAttestationBatch.signatures, registrationSignature
            );
        }

        // Create new attestations; the first registrations.length UIDs of the flat
        // return correspond to attestations[0].data, one per registration.
        bytes32[] memory newAttestationUids = eas.multiAttestByDelegation(attestations);

        attestationIds = _activateOnchainSlots(attester, registrations, newAttestationUids);
    }

    /// @dev Validates and processes every registration in an on-chain batch,
    ///      returning each registration's EIP-712 item hash.
    function _processAllRegistrations(
        address                            attester,
        DescriptorRegistration[]  calldata registrations,
        AttestationRequestData[]  calldata activeAttestationData
    ) private returns (bytes32[] memory itemHashes) {
        uint256 registrationCount = registrations.length;
        itemHashes = new bytes32[](registrationCount);
        for (uint256 registrationIndex; registrationIndex < registrationCount;) {
            itemHashes[registrationIndex] = _processRegistration(
                attester, registrations[registrationIndex], activeAttestationData[registrationIndex]
            );
            unchecked { ++registrationIndex; }
        }
    }

    /// @dev Records each newly created on-chain attestation UID as the active slot
    ///      for its registration's context IDs, returning the UIDs in registration order.
    function _activateOnchainSlots(
        address                           attester,
        DescriptorRegistration[] calldata registrations,
        bytes32[]                memory   newAttestationUids
    ) private returns (bytes32[] memory attestationIds) {
        uint256 registrationCount = registrations.length;
        attestationIds = new bytes32[](registrationCount);
        for (uint256 registrationIndex; registrationIndex < registrationCount;) {
            bytes32 uid = newAttestationUids[registrationIndex];
            attestationIds[registrationIndex] = uid;
            _updateSlots(attester, registrations[registrationIndex], uid);
            unchecked { ++registrationIndex; }
        }
    }

    /// @dev Updates the active slot for each contextId of a registration.
    function _updateSlots(
        address                         attester,
        DescriptorRegistration calldata registration,
        bytes32                         uid
    ) private {
        bytes32[] calldata contextIds = registration.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            bytes32 contextId   = contextIds[contextIndex];
            bytes32 previousUid = _attestationUIDs[attester][contextId];
            _attestationUIDs[attester][contextId] = uid;
            emit AttestationUpdated(
                attester, contextId, uid, previousUid, registration.descriptorHash
            );
            unchecked { ++contextIndex; }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function createOffchainDescriptorAttestations(
        address                            attester,
        DescriptorRegistration[]           calldata registrations,
        OffchainAttestation[]              calldata attestations,
        string[]                           calldata attestationMirrorListUris,
        bytes                              calldata registrationSignature,
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes32[]                          calldata offchainRevocations
    ) external returns (bytes32[] memory attestationIds) {
        if (registrations.length == 0) {
            revert EmptyRegistrations();
        }
        if (attestations.length != registrations.length) {
            revert ArrayLengthMismatch();
        }

        // Every active attestation being displaced must be explicitly revoked,
        // whether the displaced slot was previously on-chain or off-chain.
        _checkRevocations(attester, registrations, revocations, offchainRevocations);

        // Revoke displaced attestations (may be empty when no slots are replaced).
        _processRevocations(revocations, offchainRevocations);

        attestationIds = _registerOffchainBatch(
            attester, registrations, attestations, attestationMirrorListUris, registrationSignature
        );
    }

    /// @dev The registration phase of 'createOffchainDescriptorAttestations', split
    ///      out from the revocation phase to limit per-frame stack usage.
    function _registerOffchainBatch(
        address                            attester,
        DescriptorRegistration[]           calldata registrations,
        OffchainAttestation[]              calldata attestations,
        string[]                           calldata attestationMirrorListUris,
        bytes                              calldata registrationSignature
    ) private returns (bytes32[] memory attestationIds) {
        // Publish the attestation MirrorList exactly once for the whole batch;
        // every registration in this call reuses the resulting pointer.
        bytes32 attestationMirrorListId = _publishMirrorList(attestationMirrorListUris);

        (bytes32[] memory itemHashes, bytes32[] memory attestationHashes) =
            _processAllOffchainRegistrations(attester, registrations, attestations, attestationMirrorListId);

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

    /// @dev Validates and processes every registration in an off-chain batch, returning
    ///      each registration's EIP-712 item hash and its attestation's EIP-712 hash.
    function _processAllOffchainRegistrations(
        address                            attester,
        DescriptorRegistration[]  calldata registrations,
        OffchainAttestation[]     calldata attestations,
        bytes32                            attestationMirrorListId
    ) private returns (bytes32[] memory itemHashes, bytes32[] memory attestationHashes) {
        uint256 registrationCount = registrations.length;
        itemHashes        = new bytes32[](registrationCount);
        attestationHashes = new bytes32[](registrationCount);
        for (uint256 registrationIndex; registrationIndex < registrationCount;) {
            (itemHashes[registrationIndex], attestationHashes[registrationIndex]) = _processOffchainRegistration(
                attester, registrations[registrationIndex], attestations[registrationIndex], attestationMirrorListId
            );
            unchecked { ++registrationIndex; }
        }
    }

    /// @dev Collects the pre-computed off-chain attestation UID of each registration, in order.
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
    function clearRevokedEndorsements(
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
            cleared += _clearRevokedEndorsementsForAttester(attesters[attesterIndex], contextIds[attesterIndex]);
            unchecked { ++attesterIndex; }
        }
    }

    /// @dev Clears every stale context ID slot listed for one attester, returning how many were cleared.
    function _clearRevokedEndorsementsForAttester(
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

    /// @dev Checks whether the attestation backing a UID has been revoked or has
    ///      expired, reading from registry storage for off-chain attestations and
    ///      from EAS for on-chain ones.
    function _isAttestationRevokedOrExpired(address attester, bytes32 uid) private view returns (bool) {
        OffchainDetails storage details = _offchainDetails[attester][uid];
        if (details.attestationMirrorListId != bytes32(0)) {
            bool revoked = eas.getRevokeOffchain(attester, uid) != 0;
            bool expired = details.expirationTime != 0 && details.expirationTime < block.timestamp;
            return revoked || expired;
        }

        IEAS.Attestation memory attestation = eas.getAttestation(uid);
        bool revoked = attestation.revocationTime != 0;
        bool expired = attestation.expirationTime != 0 && attestation.expirationTime < block.timestamp;
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

    /// @dev Resolves one active slot into a ResolvedDescriptor, reading the
    ///      attestation metadata from registry storage for off-chain attestations
    ///      and from EAS for on-chain ones.
    function _resolveSlot(
        address            attester,
        bytes32            contextId,
        bytes32            uid,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        bytes32 descriptorHash;
        uint64  expirationTime;
        uint64  revocationTime;
        bytes32 format;
        string[] memory attestationMirrorListUris;

        OffchainDetails storage details = _offchainDetails[attester][uid];
        bool isOffchainAttestation = details.attestationMirrorListId != bytes32(0);
        if (isOffchainAttestation) {
            (descriptorHash, expirationTime, format, attestationMirrorListUris) =
                _resolveOffchainAttestation(details, allowedPrefixes);
        } else {
            (descriptorHash, expirationTime, revocationTime, format) = _resolveOnchainAttestation(uid);
            attestationMirrorListUris = new string[](0);
        }

        bytes32 mirrorListId = _mirrorListId[attester][descriptorHash];

        return ResolvedDescriptor({
            attester:                  attester,
            contextId:                 contextId,
            descriptorHash:            descriptorHash,
            attestationId:             uid,
            expirationTime:            expirationTime,
            revocationTime:            revocationTime,
            attestationMirrorListUris: attestationMirrorListUris,
            format:                    format,
            uris:                      _filterUris(_mirrorLists[mirrorListId], allowedPrefixes)
        });
    }

    /// @dev Reads an off-chain attestation's metadata from registry storage.
    ///      'revocationTime' is not returned here: it always stays 0, since off-chain
    ///      revocation requires a separate 'eas.getRevokeOffchain' call.
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

    /// @dev Reads an on-chain attestation's metadata from EAS. 'format' is reported as
    ///      the fixed 'ATTESTATION_FORMAT_EAS_ONCHAIN' constant rather than bytes32(0),
    ///      since 0 is already used elsewhere in this registry as an "unset" sentinel.
    function _resolveOnchainAttestation(bytes32 uid) private view returns (
        bytes32 descriptorHash,
        uint64  expirationTime,
        uint64  revocationTime,
        bytes32 format
    ) {
        IEAS.Attestation memory attestation = eas.getAttestation(uid);
        descriptorHash = abi.decode(attestation.data, (bytes32));
        expirationTime = attestation.expirationTime;
        revocationTime = attestation.revocationTime;
        format         = ATTESTATION_FORMAT_EAS_ONCHAIN;
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
            revert EmptyRegistrations();
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

    /// @dev Validates one registration against its active attestation data and
    ///      delegates the shared registration processing to '_processRegistrationCore'.
    /// @return The registration's EIP-712 item hash.
    function _processRegistration(
        address                          attester,
        DescriptorRegistration  calldata registration,
        AttestationRequestData  calldata attestationData
    ) private returns (bytes32) {
        // The active attestation must be revocable so the slot can be replaced later.
        if (!attestationData.revocable) {
            revert NonRevocableAttestation();
        }

        // Validate active attestation data encodes exactly the claimed descriptorHash.
        if (attestationData.data.length != 32) {
            revert InvalidAttestationData();
        }
        bytes32 attestedHash = abi.decode(attestationData.data, (bytes32));
        if (attestedHash != registration.descriptorHash) {
            revert EASHashMismatch(attestedHash, registration.descriptorHash);
        }

        return _processRegistrationCore(attester, registration);
    }

    /// @dev Validates one registration, resolves or publishes its MirrorList and
    ///      updates the attester's MirrorList pointer. Shared by the on-chain and
    ///      off-chain registration paths.
    /// @return The registration's EIP-712 item hash.
    function _processRegistrationCore(
        address                          attester,
        DescriptorRegistration  calldata registration
    ) private returns (bytes32) {
        if (registration.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (registration.contextIds.length == 0) {
            revert EmptyContextIds();
        }

        bytes32 mirrorListId = _resolveOrPublishMirrorList(registration);
        _setMirrorListPointerIfChanged(attester, registration.descriptorHash, mirrorListId);

        return keccak256(
            abi.encode(
                REGISTRATION_TYPEHASH,
                registration.descriptorHash,
                keccak256(abi.encodePacked(registration.contextIds)),
                mirrorListId
            )
        );
    }

    /// @dev Resolves a registration's MirrorList pointer: publishes the inline URIs
    ///      when supplied, or looks up a previously published list by ID otherwise.
    function _resolveOrPublishMirrorList(
        DescriptorRegistration calldata registration
    ) private returns (bytes32 mirrorListId) {
        bool isInlineFlow = registration.mirrorListUris.length > 0;
        if (isInlineFlow) {
            // inline flow - hash the supplied MirrorList to get its ID
            if (registration.mirrorListId != bytes32(0)) {
                revert RedundantMirrorListId();
            }
            return _publishMirrorList(registration.mirrorListUris);
        }

        // reference flow - the MirrorList must have been published before
        mirrorListId = registration.mirrorListId;
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

    /// @dev Processes one registration of an off-chain registration batch: shared
    ///      registration processing, off-chain metadata storage and slot updates.
    /// @return itemHash         The registration's EIP-712 item hash.
    /// @return attestationHash  The EIP-712 hash of the off-chain attestation struct.
    function _processOffchainRegistration(
        address                         attester,
        DescriptorRegistration calldata registration,
        OffchainAttestation    calldata attestation,
        bytes32                         attestationMirrorListId
    ) private returns (bytes32 itemHash, bytes32 attestationHash) {
        if (attestation.format == bytes32(0)) {
            revert ZeroAttestationFormat();
        }

        itemHash = _processRegistrationCore(attester, registration);
        attestationHash = keccak256(
            abi.encode(OFFCHAIN_ATTESTATION_TYPEHASH, attestation.uid, attestation.expirationTime, attestation.format)
        );

        // Store the off-chain metadata exactly once per UID, not per contextId.
        _offchainDetails[attester][attestation.uid] = OffchainDetails({
            descriptorHash:          registration.descriptorHash,
            attestationMirrorListId: attestationMirrorListId,
            expirationTime:          attestation.expirationTime,
            format:                  attestation.format
        });

        _updateSlots(attester, registration, attestation.uid);
    }

    /// @dev Verifies the attester's EIP-712 registration signature binding the
    ///      parameters not covered by the EAS delegated attestation signatures.
    ///      Skipped when the attester submits the transaction directly.
    ///      The signed struct includes the hash of the EAS delegated attestation signatures, which EAS accepts only once.
    function _verifyRegistrationSignature(
        address              attester,
        bytes32[]   memory   itemHashes,
        Signature[] calldata attestationSignatures,
        bytes       calldata registrationSignature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTRATION_BATCH_TYPEHASH,
                keccak256(abi.encodePacked(itemHashes)),
                keccak256(abi.encode(attestationSignatures))
            )
        );
        _verifySignature(attester, structHash, registrationSignature);
    }

    /// @dev Verifies the attester's EIP-712 signature over an off-chain registration
    ///      batch. Binding the attestation MirrorList ID and the full attestation
    ///      structs prevents a relayer from substituting a different MirrorList or
    ///      falsified expiration times; the nonce makes the signature single-use.
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

    /// @dev Flattens the UIDs of an EAS delegated revocation batch into a single array.
    function _flattenRevocationUids(
        MultiDelegatedRevocationRequest[] calldata revocations
    ) private pure returns (bytes32[] memory revokedUids) {
        uint256 totalUidCount = _countRevocationUids(revocations);
        revokedUids = new bytes32[](totalUidCount);
        _collectRevocationUids(revocations, revokedUids);
    }

    /// @dev Counts the total number of UIDs across every revocation request in the batch.
    function _countRevocationUids(
        MultiDelegatedRevocationRequest[] calldata revocations
    ) private pure returns (uint256 totalUidCount) {
        uint256 revocationBatchCount = revocations.length;
        for (uint256 revocationBatchIndex; revocationBatchIndex < revocationBatchCount;) {
            totalUidCount += revocations[revocationBatchIndex].data.length;
            unchecked { ++revocationBatchIndex; }
        }
    }

    /// @dev Copies every UID across every revocation request in the batch into 'revokedUids'.
    function _collectRevocationUids(
        MultiDelegatedRevocationRequest[] calldata revocations,
        bytes32[]                         memory   revokedUids
    ) private pure {
        uint256 revocationBatchCount = revocations.length;
        uint256 uidIndex;
        for (uint256 revocationBatchIndex; revocationBatchIndex < revocationBatchCount;) {
            AttestationRequestData[] calldata revocationBatchData = revocations[revocationBatchIndex].data;
            uint256 revocationBatchDataLength = revocationBatchData.length;
            for (uint256 entryIndex; entryIndex < revocationBatchDataLength;) {
                revokedUids[uidIndex++] = revocationBatchData[entryIndex].uid;
                unchecked { ++entryIndex; }
            }
            unchecked { ++revocationBatchIndex; }
        }
    }

    /// @dev Executes the revocation batches for displaced slots: delegated EAS
    ///      revocations for on-chain attestations, registry-recorded off-chain
    ///      revocations for off-chain ones.
    function _processRevocations(
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes32[]                          calldata offchainRevocations
    ) private {
        if (revocations.length > 0) {
            eas.multiRevokeByDelegation(revocations);
        }
        uint256 offchainRevocationCount = offchainRevocations.length;
        for (uint256 revocationIndex; revocationIndex < offchainRevocationCount;) {
            eas.revokeOffchain(offchainRevocations[revocationIndex]);
            unchecked { ++revocationIndex; }
        }
    }

    /// @dev Requires that every active attestation displaced by this batch is present
    ///      in the matching revocation batch: 'revocations' for displaced on-chain
    ///      attestations, 'offchainRevocations' for displaced off-chain ones.
    function _checkRevocations(
        address                                     attester,
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes32[]                          calldata offchainRevocations
    ) private view {
        // Build flat set of UIDs included in the on-chain revocation batch.
        bytes32[] memory revokedOnchainUids = _flattenRevocationUids(revocations);

        uint256 registrationCount = registrations.length;
        for (uint256 registrationIndex; registrationIndex < registrationCount;) {
            _checkRevocationsForRegistration(
                attester, registrations[registrationIndex], offchainRevocations, revokedOnchainUids
            );
            unchecked { ++registrationIndex; }
        }
    }

    /// @dev Checks every context ID of one registration for a displaced, unrevoked slot.
    function _checkRevocationsForRegistration(
        address                          attester,
        DescriptorRegistration  calldata registration,
        bytes32[]               calldata offchainRevocations,
        bytes32[]                memory  revokedOnchainUids
    ) private view {
        bytes32[] calldata contextIds = registration.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex; contextIndex < contextIdCount;) {
            _checkDisplacedSlotIsRevoked(attester, contextIds[contextIndex], offchainRevocations, revokedOnchainUids);
            unchecked { ++contextIndex; }
        }
    }

    /// @dev Reverts with 'MissingRevocation' if a context ID's currently active slot
    ///      is about to be displaced without appearing in the matching revocation set.
    ///      Routes the check by whether the displaced slot is on-chain or off-chain.
    function _checkDisplacedSlotIsRevoked(
        address            attester,
        bytes32            contextId,
        bytes32[] calldata offchainRevocations,
        bytes32[]  memory  revokedOnchainUids
    ) private view {
        bytes32 displacedUid = _attestationUIDs[attester][contextId];
        if (displacedUid == bytes32(0)) {
            return;
        }

        bool wasOffchain = _offchainDetails[attester][displacedUid].attestationMirrorListId != bytes32(0);
        bool isRevoked = wasOffchain
            ? _containsUid(offchainRevocations, displacedUid)
            : _containsUid(revokedOnchainUids, displacedUid);

        if (!isRevoked) {
            revert MissingRevocation(displacedUid);
        }
    }

    /// @dev Linear search for 'target' within 'uids'.
    function _containsUid(bytes32[] memory uids, bytes32 target) private pure returns (bool) {
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
