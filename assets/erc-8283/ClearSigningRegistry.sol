// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IClearSigningRegistry.sol";
import "./ClearSigningRegistryConstants.sol";
import "./MirrorListRefLib.sol";
import "./UriFilterLib.sol";
import "./RegistrationHashLib.sol";
import "./openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is IClearSigningRegistry, EIP712 {
    using MirrorListRefLib for MirrorListRef;
    using UriFilterLib for string[];

    constructor() EIP712("ClearSigningRegistry", "1") {}

    // The attestation set ID currently active for the given attester, context ID and
    // schema MAJOR. Records of different schema MAJORs never displace each other.
    // The attested descriptor hash is stored in '_attestationSetDetails'.
    mapping(address attester => mapping(bytes32 contextId => mapping(uint256 schemaMajor => bytes32)))
        private _activeAttestationSetIds;

    // Write-once metadata of an attestation set.
    struct AttestationSetDetails {
        bytes32 descriptorHash;
        uint256 schemaMajor;             // the declared schema MAJOR; opaque to the registry
    }
    mapping(address attester => mapping(bytes32 attestationSetId => AttestationSetDetails))
        private _attestationSetDetails;

    // The members of an attestation set, stored on-chain so 'resolveDescriptors' can
    // return and format-filter them. Written once, together with the set details.
    mapping(address attester => mapping(bytes32 attestationSetId => AttestationIdentifier[]))
        private _attestationSetContents;

    // The timestamp at which 'attester' revoked the given ID — an attestation set ID or
    // an individual attestation ID; both live in this one namespace — or 0 if never
    // revoked. Written by a 'revokeAttestations' batch (submitted directly or relayed
    // with a signature), or by this registry itself when a registration batch displaces
    // an attestation set on the attester's behalf — in the relayed cases only after
    // verifying that batch's own authorization chain.
    mapping(address attester => mapping(bytes32 attestationId => uint64)) private _revokedAt;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester designates for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _descriptorMirrorListIds;

    // Per-attester pointer to the MirrorList this attester designates for the given attestation set.
    mapping(address attester => mapping(bytes32 attestationSetId => bytes32)) private _attestationMirrorListIds;

    // EIP-712 nonce shared by all relayed calls: registration batches, revocation
    // batches, MirrorList updates and profile updates. Consumable without effect
    // via 'invalidateNonce'.
    mapping(address attester => uint256) private _nonces;

    // Self-declared profile document URI per attester ("business card").
    // Display-only metadata, never trust input; empty when unset.
    mapping(address attester => string) private _attesterProfileURIs;

    /// @inheritdoc IClearSigningRegistry
    function createAttestations(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata descriptorMirrorListURIs,
        MirrorListRef     calldata attestationMirrorListURIs,
        bytes             calldata signature
    ) external {
        if (descriptors.length == 0) {
            revert EmptyDescriptors();
        }

        // Resolve both batch-level MirrorLists exactly once (by reference or by
        // publishing them inline); every descriptor in this call reuses the resulting
        // pointers. Publication is content-addressed and permissionless, so it may
        // safely precede the authorization check.
        bytes32 descriptorMirrorListId  = descriptorMirrorListURIs.resolve(_mirrorLists);
        bytes32 attestationMirrorListId = attestationMirrorListURIs.resolve(_mirrorLists);

        // Authorize the batch before any attester-scoped state is touched.
        _authorizeRegistration(
            attester, descriptors, descriptorMirrorListId, attestationMirrorListId, revocations, signature
        );

        // Revoke and clear displaced attestation sets (may be empty when no sets are
        // replaced). Runs before any descriptor is processed so the displaced-set
        // check inside '_updateActiveAttestation' sees '_revokedAt' up to date.
        _processRevocations(attester, revocations);

        _processAllDescriptors(attester, descriptors, descriptorMirrorListId, attestationMirrorListId);
    }

    /// @dev Consumes a nonce and verifies the attester's EIP-712 batch signature for
    ///      relayed registrations; a no-op when the attester submits the batch directly.
    function _authorizeRegistration(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        bytes32           descriptorMirrorListId,
        bytes32           attestationMirrorListId,
        RevocationEntry[] calldata revocations,
        bytes             calldata signature
    ) private {
        if (msg.sender == attester) {
            return;
        }
        uint256 nonce = _nonces[attester];
        _nonces[attester] = nonce + 1;
        _verifyRegistrationSignature(
            attester, descriptors, descriptorMirrorListId, attestationMirrorListId, revocations, nonce, signature
        );
    }

    /// @dev Validates and processes every descriptor in a batch.
    function _processAllDescriptors(
        address                   attester,
        DescriptorInfo[] calldata descriptors,
        bytes32                   descriptorMirrorListId,
        bytes32                   attestationMirrorListId
    ) private {
        uint256 descriptorCount = descriptors.length;
        for (uint256 descriptorIndex = 0; descriptorIndex < descriptorCount; descriptorIndex++) {
            _processDescriptor(
                attester, descriptors[descriptorIndex], descriptorMirrorListId, attestationMirrorListId
            );
        }
    }

    /// @dev Updates the active record for each (contextId, schemaMajor) key of a
    ///      descriptor. Records of other schema MAJORs are untouched.
    function _updateActiveAttestation(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationSetId
    ) private {
        bytes32[] calldata contextIds  = descriptor.contextIds;
        uint256   schemaMajor          = descriptor.schemaMajor;
        for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
            bytes32 contextId                = contextIds[contextIndex];
            bytes32 previousAttestationSetId = _activeAttestationSetIds[attester][contextId][schemaMajor];

            // A record already pointing at this set — a re-activation batch listing existing
            // context IDs alongside new ones — is left untouched rather than displaced.
            if (previousAttestationSetId == attestationSetId) {
                continue;
            }

            // A displaced active attestation set must already be recorded as revoked — by
            // this batch's own 'revocations' (processed before any descriptor) or by an
            // earlier call. Checking at the moment each pointer is written also covers
            // displacement by a duplicate (contextId, schemaMajor) key within the same batch.
            if (previousAttestationSetId != bytes32(0) && _revokedAt[attester][previousAttestationSetId] == 0) {
                revert MissingRevocation(previousAttestationSetId);
            }

            _activeAttestationSetIds[attester][contextId][schemaMajor] = attestationSetId;
            emit AttestationUpdated(
                attester, contextId, attestationSetId, previousAttestationSetId,
                descriptor.descriptorHash, schemaMajor
            );
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists) external {
        uint256 listCount = uriLists.length;
        for (uint256 listIndex = 0; listIndex < listCount; listIndex++) {
            MirrorListRefLib.publish(uriLists[listIndex], _mirrorLists);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function revokeAttestations(
        address           attester,
        RevocationEntry[] calldata revocations,
        bytes             calldata signature
    ) external {
        if (revocations.length == 0) {
            revert EmptyRevocations();
        }
        if (msg.sender != attester) {
            uint256 nonce = _nonces[attester];
            _nonces[attester] = nonce + 1;
            _verifyRevocationSignature(attester, revocations, nonce, signature);
        }
        _processRevocations(attester, revocations);
    }

    /// @inheritdoc IClearSigningRegistry
    function invalidateNonce() external {
        uint256 newNonce = _nonces[msg.sender] + 1;
        _nonces[msg.sender] = newNonce;
        emit NonceInvalidated(msg.sender, newNonce);
    }

    /// @inheritdoc IClearSigningRegistry
    function setAttesterProfileURI(
        address         attester,
        string calldata profileURI,
        bytes  calldata signature
    ) external {
        if (msg.sender != attester) {
            uint256 nonce = _nonces[attester];
            _nonces[attester] = nonce + 1;
            _verifyProfileUpdateSignature(attester, profileURI, nonce, signature);
        }

        if (keccak256(bytes(_attesterProfileURIs[attester])) == keccak256(bytes(profileURI))) {
            return;
        }
        _attesterProfileURIs[attester] = profileURI;
        emit AttesterProfileUpdated(attester, profileURI);
    }

    /// @inheritdoc IClearSigningRegistry
    function getAttesterProfileURI(address attester) external view returns (string memory) {
        return _attesterProfileURIs[attester];
    }

    /// @inheritdoc IClearSigningRegistry
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64) {
        return _revokedAt[attester][attestationId];
    }

    /// @dev Records 'attestationId' as revoked under 'attester', emitting 'AttestationRevoked'.
    ///      Revoking an already-revoked ID keeps the original timestamp: the recorded
    ///      value is when the ID *first* became revoked, and must not move on a
    ///      repeated revocation.
    function _recordRevocation(address attester, bytes32 attestationId) private {
        if (_revokedAt[attester][attestationId] != 0) {
            return;
        }
        uint64 timestamp = uint64(block.timestamp);
        _revokedAt[attester][attestationId] = timestamp;
        emit AttestationRevoked(attester, attestationId, timestamp);
    }

    /// @dev Records 'attestationId' as revoked under 'attester' and clears 'contextIds'
    ///      immediately wherever they still point to it. A context ID whose active set
    ///      has since moved to a different attestation set ID is silently skipped. Reached
    ///      via '_processRevocations' from both 'createAttestations' and 'revokeAttestations'.
    function _revokeAndClear(address attester, bytes32 attestationId, bytes32[] calldata contextIds) private {
        if (attestationId == bytes32(0)) {
            revert ZeroAttestationId();
        }
        _recordRevocation(attester, attestationId);

        // An attestation set's schema MAJOR is intrinsic: set metadata is write-once, so
        // it is read from the stored details rather than passed in. An individual
        // attestation ID or a never-registered ID reads a schema MAJOR of 0, which no
        // active record can hold (registration forbids a zero schemaMajor), so its
        // clearing loop is a natural no-op while the revocation itself is still recorded.
        uint256 schemaMajor = _attestationSetDetails[attester][attestationId].schemaMajor;

        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
            bytes32 contextId = contextIds[contextIndex];
            if (_activeAttestationSetIds[attester][contextId][schemaMajor] == attestationId) {
                _activeAttestationSetIds[attester][contextId][schemaMajor] = bytes32(0);
                emit AttestationUpdated(attester, contextId, bytes32(0), attestationId, bytes32(0), schemaMajor);
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors,
        bytes32[] calldata formatIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 activeRecordCount = _countActiveRecords(attesters, contextIds, schemaMajors);
        resolved = new ResolvedDescriptor[](activeRecordCount);
        _collectResolvedDescriptors(attesters, contextIds, schemaMajors, formatIds, allowedPrefixes, resolved);
    }

    /// @dev Counts the active records among the queried (attester, contextId, schemaMajor)
    ///      keys, used to size the 'resolveDescriptors' result array.
    function _countActiveRecords(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors
    ) private view returns (uint256 activeRecordCount) {
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
                bytes32 contextId = contextIds[contextIndex];
                for (uint256 majorIndex = 0; majorIndex < schemaMajors.length; majorIndex++) {
                    if (_activeAttestationSetIds[attester][contextId][schemaMajors[majorIndex]] != bytes32(0)) {
                        ++activeRecordCount;
                    }
                }
            }
        }
    }

    /// @dev Fills 'resolved' with one entry per active (attester, contextId, schemaMajor) record.
    function _collectResolvedDescriptors(
        address[]            calldata attesters,
        bytes32[]            calldata contextIds,
        uint256[]            calldata schemaMajors,
        bytes32[]            calldata formatIds,
        string[]             calldata allowedPrefixes,
        ResolvedDescriptor[]   memory resolved
    ) private view {
        uint256 resolvedIndex;
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
                resolvedIndex = _resolveRecordsForContext(
                    attesters[attesterIndex], contextIds[contextIndex],
                    schemaMajors, formatIds, allowedPrefixes, resolved, resolvedIndex
                );
            }
        }
    }

    /// @dev Resolves every schema MAJOR with an active record for one (attester, contextId)
    ///      pair into 'resolved' starting at 'resolvedIndex', returning the index after the
    ///      last write.
    function _resolveRecordsForContext(
        address              attester,
        bytes32              contextId,
        uint256[]   calldata schemaMajors,
        bytes32[]   calldata formatIds,
        string[]    calldata allowedPrefixes,
        ResolvedDescriptor[] memory resolved,
        uint256              resolvedIndex
    ) private view returns (uint256) {
        for (uint256 majorIndex = 0; majorIndex < schemaMajors.length; majorIndex++) {
            uint256 schemaMajor      = schemaMajors[majorIndex];
            bytes32 attestationSetId = _activeAttestationSetIds[attester][contextId][schemaMajor];
            if (attestationSetId != bytes32(0)) {
                resolved[resolvedIndex++] = _resolveActiveRecord(
                    attester, contextId, schemaMajor, attestationSetId, formatIds, allowedPrefixes
                );
            }
        }
        return resolvedIndex;
    }

    /// @dev Resolves one active attestation set into a ResolvedDescriptor.
    function _resolveActiveRecord(
        address            attester,
        bytes32            contextId,
        uint256            schemaMajor,
        bytes32            attestationSetId,
        bytes32[] calldata formatIds,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        AttestationSetDetails storage details = _attestationSetDetails[attester][attestationSetId];
        bytes32 descriptorMirrorListId  = _descriptorMirrorListIds[attester][details.descriptorHash];
        bytes32 attestationMirrorListId = _attestationMirrorListIds[attester][attestationSetId];

        return ResolvedDescriptor({
            descriptorHash:            details.descriptorHash,
            contextId:                 contextId,
            schemaMajor:               schemaMajor,
            attestationSetId:          attestationSetId,
            descriptorMirrorListUris:  _mirrorLists[descriptorMirrorListId].filter(allowedPrefixes),
            attestationMirrorListUris: _mirrorLists[attestationMirrorListId].filter(allowedPrefixes),
            attestations:              _resolveAttestations(attester, attestationSetId, formatIds)
        });
    }

    /// @dev Builds the format-filtered ResolvedAttestation array of one attestation set.
    function _resolveAttestations(
        address            attester,
        bytes32            attestationSetId,
        bytes32[] calldata formatIds
    ) private view returns (ResolvedAttestation[] memory attestations) {
        AttestationIdentifier[] storage contents = _attestationSetContents[attester][attestationSetId];

        uint256 matchCount;
        for (uint256 entryIndex = 0; entryIndex < contents.length; entryIndex++) {
            if (_matchesFormatFilter(contents[entryIndex].formatId, formatIds)) {
                ++matchCount;
            }
        }

        attestations = new ResolvedAttestation[](matchCount);
        uint256 outIndex;
        for (uint256 entryIndex = 0; entryIndex < contents.length; entryIndex++) {
            AttestationIdentifier storage entry = contents[entryIndex];
            if (!_matchesFormatFilter(entry.formatId, formatIds)) {
                continue;
            }
            attestations[outIndex++] = ResolvedAttestation({
                attester:      attester,
                attestationId: entry.attestationId,
                formatId:      entry.formatId,
                revokedAt:     _revokedAt[attester][entry.attestationId]
            });
        }
    }

    /// @dev Whether 'formatId' passes the 'formatIds' request filter; an empty filter passes all.
    function _matchesFormatFilter(bytes32 formatId, bytes32[] calldata formatIds) private pure returns (bool) {
        if (formatIds.length == 0) {
            return true;
        }
        for (uint256 filterIndex = 0; filterIndex < formatIds.length; filterIndex++) {
            if (formatIds[filterIndex] == formatId) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
        external view returns (string[] memory)
    {
        return _mirrorLists[mirrorListId].filter(allowedPrefixes);
    }

    /// @inheritdoc IClearSigningRegistry
    function getNonce(address attester) external view returns (uint256) {
        return _nonces[attester];
    }

    /// @inheritdoc IClearSigningRegistry
    function updateDescriptorMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        MirrorListRef calldata descriptorMirrorListRef,
        bytes calldata signature
    ) external {
        if (descriptorHashes.length == 0) {
            revert EmptyKeys();
        }
        bytes32 mirrorListId = descriptorMirrorListRef.resolve(_mirrorLists);
        _authorizeMirrorListUpdate(
            attester, descriptorHashes, mirrorListId,
            ClearSigningRegistryConstants.DESCRIPTOR_MIRROR_UPDATE_TYPEHASH, signature
        );

        for (uint256 i = 0; i < descriptorHashes.length; i++) {
            bytes32 descriptorHash = descriptorHashes[i];
            // Registration always sets a non-zero descriptor MirrorList pointer, so a zero
            // pointer means the attester never registered this descriptor hash.
            if (_descriptorMirrorListIds[attester][descriptorHash] == bytes32(0)) {
                revert UnknownDescriptor(descriptorHash);
            }
            _setDescriptorMirrorList(attester, descriptorHash, mirrorListId);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function updateAttestationMirrorList(
        address attester,
        bytes32[] calldata attestationSetIds,
        MirrorListRef calldata attestationMirrorListRef,
        bytes calldata signature
    ) external {
        if (attestationSetIds.length == 0) {
            revert EmptyKeys();
        }
        bytes32 mirrorListId = attestationMirrorListRef.resolve(_mirrorLists);
        _authorizeMirrorListUpdate(
            attester, attestationSetIds, mirrorListId,
            ClearSigningRegistryConstants.ATTESTATION_MIRROR_UPDATE_TYPEHASH, signature
        );

        for (uint256 i = 0; i < attestationSetIds.length; i++) {
            bytes32 attestationSetId = attestationSetIds[i];
            if (_attestationSetDetails[attester][attestationSetId].descriptorHash == bytes32(0)) {
                revert UnknownAttestationSet(attestationSetId);
            }
            _setAttestationMirrorList(attester, attestationSetId, mirrorListId);
        }
    }

    /// @dev Consumes a nonce and verifies the attester's EIP-712 MirrorList update
    ///      signature for relayed updates; a no-op when the attester submits directly.
    function _authorizeMirrorListUpdate(
        address            attester,
        bytes32[] calldata keys,
        bytes32            mirrorListId,
        bytes32            typeHash,
        bytes     calldata signature
    ) private {
        if (msg.sender == attester) {
            return;
        }
        uint256 nonce = _nonces[attester];
        _nonces[attester] = nonce + 1;
        _verifyMirrorUpdateSignature(attester, keys, mirrorListId, nonce, typeHash, signature);
    }

    /// @dev Points 'attester''s MirrorList for 'descriptorHash' at 'mirrorListId',
    ///      emitting an event only when the pointer actually changes.
    function _setDescriptorMirrorList(address attester, bytes32 descriptorHash, bytes32 mirrorListId) private {
        if (_descriptorMirrorListIds[attester][descriptorHash] == mirrorListId) {
            return;
        }
        _descriptorMirrorListIds[attester][descriptorHash] = mirrorListId;
        emit DescriptorMirrorListUpdated(attester, descriptorHash, mirrorListId);
    }

    /// @dev Points 'attester''s MirrorList for 'attestationSetId' at 'mirrorListId',
    ///      emitting an event only when the pointer actually changes.
    function _setAttestationMirrorList(address attester, bytes32 attestationSetId, bytes32 mirrorListId) private {
        if (_attestationMirrorListIds[attester][attestationSetId] == mirrorListId) {
            return;
        }
        _attestationMirrorListIds[attester][attestationSetId] = mirrorListId;
        emit AttestationMirrorListUpdated(attester, attestationSetId, mirrorListId);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Processes one descriptor of a registration batch: field validation,
    ///      MirrorList pointer updates, attestation set storage and
    ///      active-attestation-set updates.
    function _processDescriptor(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 descriptorMirrorListId,
        bytes32                 attestationMirrorListId
    ) private {
        _validateDescriptor(attester, descriptor);

        bytes32 attestationSetId = _deriveAttestationSetId(descriptor);

        _setDescriptorMirrorList(attester, descriptor.descriptorHash, descriptorMirrorListId);
        _storeAttestationSet(attester, attestationSetId, descriptor);
        _setAttestationMirrorList(attester, attestationSetId, attestationMirrorListId);

        _updateActiveAttestation(attester, descriptor, attestationSetId);
    }

    /// @dev Validates one descriptor's fields and every entry of its attestation set.
    function _validateDescriptor(address attester, DescriptorInfo calldata descriptor) private view {
        if (descriptor.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (descriptor.schemaMajor == 0) {
            revert ZeroSchemaMajor();
        }
        if (descriptor.contextIds.length == 0) {
            revert EmptyContextIds();
        }
        AttestationIdentifier[] calldata attestationIds = descriptor.attestationIds;
        if (attestationIds.length == 0) {
            revert EmptyAttestationIds();
        }
        for (uint256 entryIndex = 0; entryIndex < attestationIds.length; entryIndex++) {
            AttestationIdentifier calldata entry = attestationIds[entryIndex];
            if (entry.attestationId == bytes32(0)) {
                revert ZeroAttestationId();
            }
            if (entry.formatId == bytes32(0)) {
                revert ZeroAttestationFormat();
            }
            // A revoked ID is consumed forever and cannot re-enter a set.
            if (_revokedAt[attester][entry.attestationId] != 0) {
                revert AttestationIdAlreadyUsed(entry.attestationId);
            }
            // One attestation per format per descriptor, so the index file's
            // format-to-attestation map stays unambiguous.
            for (uint256 earlierIndex = 0; earlierIndex < entryIndex; earlierIndex++) {
                if (attestationIds[earlierIndex].formatId == entry.formatId) {
                    revert DuplicateAttestationFormat(entry.formatId);
                }
            }
        }
    }

    /// @dev The attestation set ID of 'descriptor'. A single-attestation set uses the
    ///      sole member's own ID — in the common single-EAS case wallets address the set
    ///      directly by the ERC-8176 UID — while a larger set uses a content hash that
    ///      commits to the descriptor identity and the full member list.
    function _deriveAttestationSetId(DescriptorInfo calldata descriptor) private pure returns (bytes32) {
        AttestationIdentifier[] calldata attestationIds = descriptor.attestationIds;
        if (attestationIds.length == 1) {
            return attestationIds[0].attestationId;
        }
        return keccak256(abi.encode(descriptor.descriptorHash, descriptor.schemaMajor, attestationIds));
    }

    /// @dev Stores one attestation set's write-once metadata and contents, or verifies
    ///      them against the stored record when the set ID is already registered (a
    ///      re-activation for more context IDs). A revoked set ID is consumed forever
    ///      and can never be registered again.
    function _storeAttestationSet(
        address                 attester,
        bytes32                 attestationSetId,
        DescriptorInfo calldata descriptor
    ) private {
        if (_revokedAt[attester][attestationSetId] != 0) {
            revert AttestationIdAlreadyUsed(attestationSetId);
        }

        AttestationSetDetails storage details = _attestationSetDetails[attester][attestationSetId];
        if (details.descriptorHash != bytes32(0)) {
            // The singleton shortcut makes a set ID attester-chosen, so the ID alone does
            // not commit to what it names — the stored record must match the incoming
            // descriptor before the set may be reused. (Content-derived multi-set IDs
            // match by construction; checking uniformly costs little.)
            _requireMatchingSet(attester, attestationSetId, descriptor, details);
            return;
        }

        details.descriptorHash = descriptor.descriptorHash;
        details.schemaMajor    = descriptor.schemaMajor;

        AttestationIdentifier[] calldata attestationIds = descriptor.attestationIds;
        AttestationIdentifier[] storage  contents       = _attestationSetContents[attester][attestationSetId];
        for (uint256 entryIndex = 0; entryIndex < attestationIds.length; entryIndex++) {
            contents.push(attestationIds[entryIndex]);
        }

        emit AttestationRegistered(
            attester, attestationSetId, descriptor.descriptorHash, descriptor.schemaMajor, attestationIds
        );
    }

    /// @dev Reverts with 'AttestationIdAlreadyUsed' unless the stored record of
    ///      'attestationSetId' matches 'descriptor' exactly (details and member list,
    ///      order-sensitive like the set ID derivation).
    function _requireMatchingSet(
        address                       attester,
        bytes32                       attestationSetId,
        DescriptorInfo       calldata descriptor,
        AttestationSetDetails storage details
    ) private view {
        AttestationIdentifier[] calldata attestationIds = descriptor.attestationIds;
        AttestationIdentifier[] storage  contents       = _attestationSetContents[attester][attestationSetId];

        bool matches = details.descriptorHash == descriptor.descriptorHash
            && details.schemaMajor == descriptor.schemaMajor
            && contents.length == attestationIds.length;
        if (matches) {
            for (uint256 entryIndex = 0; entryIndex < attestationIds.length; entryIndex++) {
                if (contents[entryIndex].attestationId != attestationIds[entryIndex].attestationId
                    || contents[entryIndex].formatId != attestationIds[entryIndex].formatId) {
                    matches = false;
                    break;
                }
            }
        }
        if (!matches) {
            revert AttestationIdAlreadyUsed(attestationSetId);
        }
    }

    /// @dev Verifies the attester's EIP-712 signature over a registration batch.
    ///      Binding both MirrorList IDs prevents a relayer from substituting different
    ///      MirrorLists; binding the revocations hash prevents a relayer from adding or
    ///      dropping revocation entries; the nonce makes the signature single-use.
    function _verifyRegistrationSignature(
        address                    attester,
        DescriptorInfo[]  calldata descriptors,
        bytes32                    descriptorMirrorListId,
        bytes32                    attestationMirrorListId,
        RevocationEntry[] calldata revocations,
        uint256                    nonce,
        bytes             calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                ClearSigningRegistryConstants.REGISTRATION_BATCH_TYPEHASH,
                RegistrationHashLib.hashDescriptorInfos(descriptors),
                descriptorMirrorListId,
                attestationMirrorListId,
                RegistrationHashLib.hashRevocationEntries(revocations),
                nonce
            )
        );
        _verifySignature(attester, structHash, signature);
    }

    /// @dev Verifies the attester's EIP-712 signature over a standalone revocation batch.
    function _verifyRevocationSignature(
        address                    attester,
        RevocationEntry[] calldata revocations,
        uint256                    nonce,
        bytes             calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                ClearSigningRegistryConstants.REVOCATION_BATCH_TYPEHASH,
                RegistrationHashLib.hashRevocationEntries(revocations),
                nonce
            )
        );
        _verifySignature(attester, structHash, signature);
    }

    /// @dev Verifies the attester's EIP-712 signature over a profile URI update.
    function _verifyProfileUpdateSignature(
        address         attester,
        string calldata profileURI,
        uint256         nonce,
        bytes  calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                ClearSigningRegistryConstants.ATTESTER_PROFILE_UPDATE_TYPEHASH,
                keccak256(bytes(profileURI)),
                nonce
            )
        );
        _verifySignature(attester, structHash, signature);
    }

    /// @dev Verifies the attester's EIP-712 mirror update signature.
    function _verifyMirrorUpdateSignature(
        address              attester,
        bytes32[]   calldata keys,
        bytes32              mirrorListId,
        uint256              nonce,
        bytes32              typeHash,
        bytes       calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(keys)),
                mirrorListId,
                nonce
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

    /// @dev Records each entry in 'revocations' as revoked under 'attester' and clears
    ///      its listed context IDs. Safe to call with an empty array when no attestation
    ///      sets are being displaced.
    function _processRevocations(address attester, RevocationEntry[] calldata revocations) private {
        uint256 revocationCount = revocations.length;
        for (uint256 revocationIndex = 0; revocationIndex < revocationCount; revocationIndex++) {
            RevocationEntry calldata entry = revocations[revocationIndex];
            _revokeAndClear(attester, entry.attestationId, entry.contextIds);
        }
    }

}
