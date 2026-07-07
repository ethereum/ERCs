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

    // The attestation ID currently active for the given attester, context ID and
    // schema MAJOR lane. Descriptors of different schema MAJORs occupy separate slots
    // and never displace each other. The attested descriptor hash is stored in
    // '_attestationDetails'.
    mapping(address attester => mapping(bytes32 contextId => mapping(uint256 schemaMajor => bytes32)))
        private _attestationIds;

    // Extra metadata for an attestation, stored exactly once per attestation ID.
    struct AttestationDetails {
        bytes32 descriptorHash;
        uint256 schemaMajor;             // the declared schema MAJOR lane; opaque to the registry
        bytes32 format;                  // the declared attestationFormatTag; opaque to the registry
    }
    mapping(address attester => mapping(bytes32 attestationId => AttestationDetails)) private _attestationDetails;

    // The timestamp at which 'attester' revoked 'attestationId', or 0 if never revoked.
    // Written by 'revokeAttestation' directly (msg.sender == attester), by a signed
    // 'revokeAttestations' batch, or by this registry itself when a registration batch
    // displaces an attestation on the attester's behalf — in the relayed cases only
    // after verifying that batch's own authorization chain.
    mapping(address attester => mapping(bytes32 attestationId => uint64)) private _revokedAt;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester designates for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _descriptorMirrorListIds;

    // Per-attester pointer to the MirrorList this attester designates for the given attestation ID.
    mapping(address attester => mapping(bytes32 attestationId => bytes32)) private _attestationMirrorListIds;

    // EIP-712 nonce shared by all relayed calls: registration batches, revocation
    // batches and MirrorList updates. Consumable without effect via 'invalidateNonce'.
    mapping(address attester => uint256) private _nonces;

    /// @inheritdoc IClearSigningRegistry
    function createAttestations(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations,
        MirrorListRef     calldata attestationMirrorListURIs,
        bytes             calldata signature
    ) external {
        if (descriptors.length == 0) {
            revert EmptyDescriptors();
        }

        // Resolve the attestation MirrorList exactly once for the whole batch (by
        // reference or by publishing it inline); every descriptor in this call
        // reuses the resulting pointer. Publication is content-addressed and
        // permissionless, so it may safely precede the authorization check.
        bytes32 attestationMirrorListId = attestationMirrorListURIs.resolve(_mirrorLists);

        // Authorize the batch before any attester-scoped state is touched.
        _authorizeRegistration(attester, descriptors, attestationMirrorListId, revocations, signature);

        // Revoke and clear displaced attestations (may be empty when no attestations are
        // replaced). Runs before any descriptor is processed so the displaced-attestation
        // check inside '_updateActiveAttestation' sees '_revokedAt' up to date.
        _processRevocations(attester, revocations);

        _processAllDescriptors(attester, descriptors, attestationMirrorListId);
    }

    /// @dev Consumes a nonce and verifies the attester's EIP-712 batch signature for
    ///      relayed registrations; a no-op when the attester submits the batch directly.
    function _authorizeRegistration(
        address           attester,
        DescriptorInfo[]  calldata descriptors,
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
            attester, descriptors, attestationMirrorListId, revocations, nonce, signature
        );
    }

    /// @dev Validates and processes every descriptor in a batch.
    function _processAllDescriptors(
        address                   attester,
        DescriptorInfo[] calldata descriptors,
        bytes32                   attestationMirrorListId
    ) private {
        uint256 descriptorCount = descriptors.length;
        for (uint256 descriptorIndex = 0; descriptorIndex < descriptorCount; descriptorIndex++) {
            _processDescriptor(attester, descriptors[descriptorIndex], attestationMirrorListId);
        }
    }

    /// @dev Updates the active attestation for each (contextId, schemaMajor) slot of a
    ///      descriptor. Slots of other schema MAJORs are untouched.
    function _updateActiveAttestation(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationId
    ) private {
        bytes32[] calldata contextIds  = descriptor.contextIds;
        uint256   schemaMajor          = descriptor.schemaMajor;
        for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
            bytes32 contextId             = contextIds[contextIndex];
            bytes32 previousAttestationId = _attestationIds[attester][contextId][schemaMajor];

            // A displaced active attestation must already be recorded as revoked — by this
            // batch's own 'revocations' (processed before any descriptor) or by an earlier
            // call. Checking at the moment each pointer is written also covers displacement
            // by a duplicate (contextId, schemaMajor) slot within the same batch.
            if (previousAttestationId != bytes32(0) && _revokedAt[attester][previousAttestationId] == 0) {
                revert MissingRevocation(previousAttestationId);
            }

            _attestationIds[attester][contextId][schemaMajor] = attestationId;
            emit AttestationUpdated(
                attester, contextId, attestationId, previousAttestationId, descriptor.descriptorHash, schemaMajor
            );
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds)
    {
        uint256 listCount = uriLists.length;
        mirrorListIds = new bytes32[](listCount);
        for (uint256 listIndex = 0; listIndex < listCount; listIndex++) {
            mirrorListIds[listIndex] = MirrorListRefLib.publish(uriLists[listIndex], _mirrorLists);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function revokeAttestation(bytes32 attestationId, bytes32[] calldata contextIds) external {
        _revokeAndClear(msg.sender, attestationId, contextIds);
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
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64) {
        return _revokedAt[attester][attestationId];
    }

    /// @dev Records 'attestationId' as revoked under 'attester', emitting 'AttestationRevoked'.
    ///      Revoking an already-revoked attestation ID keeps the original timestamp: the
    ///      recorded value is when the attestation *first* became revoked, and must not
    ///      move on a repeated revocation.
    function _recordRevocation(address attester, bytes32 attestationId) private {
        if (_revokedAt[attester][attestationId] != 0) {
            return;
        }
        uint64 timestamp = uint64(block.timestamp);
        _revokedAt[attester][attestationId] = timestamp;
        emit AttestationRevoked(attester, attestationId, timestamp);
    }

    /// @dev Records 'attestationId' as revoked under 'attester' and clears 'contextIds'
    ///      immediately wherever they still point to it. A context ID whose active attestation
    ///      has since moved to a different attestation ID is silently skipped. Shared by
    ///      the direct self-service path ('revokeAttestation') and the batch path
    ///      ('_processRevocations', reached from both 'createAttestations' and
    ///      'revokeAttestations').
    function _revokeAndClear(address attester, bytes32 attestationId, bytes32[] calldata contextIds) private {
        if (attestationId == bytes32(0)) {
            revert ZeroAttestationId();
        }
        _recordRevocation(attester, attestationId);

        // An attestation's schema MAJOR is intrinsic: attestation IDs are single-use and
        // their metadata is write-once, so the lane its slots live in is read from the
        // stored details rather than passed in. A never-registered ID reads lane 0, which
        // no slot can hold (registration forbids a zero schemaMajor), so its clearing
        // loop is a natural no-op while the revocation itself is still recorded.
        uint256 schemaMajor = _attestationDetails[attester][attestationId].schemaMajor;

        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
            bytes32 contextId = contextIds[contextIndex];
            if (_attestationIds[attester][contextId][schemaMajor] == attestationId) {
                _attestationIds[attester][contextId][schemaMajor] = bytes32(0);
                emit AttestationUpdated(attester, contextId, bytes32(0), attestationId, bytes32(0), schemaMajor);
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 activeAttestationCount = _countActiveAttestations(attesters, contextIds, schemaMajors);
        resolved = new ResolvedDescriptor[](activeAttestationCount);
        _collectResolvedDescriptors(attesters, contextIds, schemaMajors, allowedPrefixes, resolved);
    }

    /// @dev Counts how many (attester, contextId, schemaMajor) slots currently have an
    ///      active attestation, used to size the 'resolveDescriptors' result array.
    function _countActiveAttestations(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        uint256[] calldata schemaMajors
    ) private view returns (uint256 activeAttestationCount) {
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
                bytes32 contextId = contextIds[contextIndex];
                for (uint256 majorIndex = 0; majorIndex < schemaMajors.length; majorIndex++) {
                    if (_attestationIds[attester][contextId][schemaMajors[majorIndex]] != bytes32(0)) {
                        ++activeAttestationCount;
                    }
                }
            }
        }
    }

    /// @dev Fills 'resolved' with one entry per active (attester, contextId, schemaMajor) slot.
    function _collectResolvedDescriptors(
        address[]            calldata attesters,
        bytes32[]            calldata contextIds,
        uint256[]            calldata schemaMajors,
        string[]              calldata allowedPrefixes,
        ResolvedDescriptor[]   memory  resolved
    ) private view {
        uint256 resolvedIndex;
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex = 0; contextIndex < contextIds.length; contextIndex++) {
                bytes32 contextId = contextIds[contextIndex];
                for (uint256 majorIndex = 0; majorIndex < schemaMajors.length; majorIndex++) {
                    uint256 schemaMajor   = schemaMajors[majorIndex];
                    bytes32 attestationId = _attestationIds[attester][contextId][schemaMajor];
                    if (attestationId != bytes32(0)) {
                        resolved[resolvedIndex++] =
                            _resolveActiveAttestation(attester, contextId, schemaMajor, attestationId, allowedPrefixes);
                    }
                }
            }
        }
    }

    /// @dev Resolves one active attestation into a ResolvedDescriptor.
    function _resolveActiveAttestation(
        address            attester,
        bytes32            contextId,
        uint256            schemaMajor,
        bytes32            attestationId,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        AttestationDetails storage details = _attestationDetails[attester][attestationId];
        bytes32 descriptorMirrorListId  = _descriptorMirrorListIds[attester][details.descriptorHash];
        bytes32 attestationMirrorListId = _attestationMirrorListIds[attester][attestationId];

        return ResolvedDescriptor({
            attester:                  attester,
            contextId:                 contextId,
            descriptorHash:            details.descriptorHash,
            schemaMajor:               schemaMajor,
            attestationId:             attestationId,
            revokedAt:                 _revokedAt[attester][attestationId],
            attestationMirrorListUris: _mirrorLists[attestationMirrorListId].filter(allowedPrefixes),
            format:                    details.format,
            descriptorMirrorListUris:  _mirrorLists[descriptorMirrorListId].filter(allowedPrefixes)
        });
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
        bytes32[] calldata attestationIds,
        MirrorListRef calldata attestationMirrorListRef,
        bytes calldata signature
    ) external {
        if (attestationIds.length == 0) {
            revert EmptyKeys();
        }
        bytes32 mirrorListId = attestationMirrorListRef.resolve(_mirrorLists);
        _authorizeMirrorListUpdate(
            attester, attestationIds, mirrorListId,
            ClearSigningRegistryConstants.ATTESTATION_MIRROR_UPDATE_TYPEHASH, signature
        );

        for (uint256 i = 0; i < attestationIds.length; i++) {
            bytes32 attestationId = attestationIds[i];
            if (_attestationDetails[attester][attestationId].descriptorHash == bytes32(0)) {
                revert UnknownAttestationId(attestationId);
            }
            _setAttestationMirrorList(attester, attestationId, mirrorListId);
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

    /// @dev Points 'attester''s MirrorList for 'attestationId' at 'mirrorListId',
    ///      emitting an event only when the pointer actually changes.
    function _setAttestationMirrorList(address attester, bytes32 attestationId, bytes32 mirrorListId) private {
        if (_attestationMirrorListIds[attester][attestationId] == mirrorListId) {
            return;
        }
        _attestationMirrorListIds[attester][attestationId] = mirrorListId;
        emit AttestationMirrorListUpdated(attester, attestationId, mirrorListId);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Processes one descriptor of a registration batch: field validation,
    ///      MirrorList pointer updates, attestation metadata storage and
    ///      active-attestation updates.
    function _processDescriptor(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationMirrorListId
    ) private {
        if (descriptor.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (descriptor.attestationId == bytes32(0)) {
            revert ZeroAttestationId();
        }
        if (descriptor.format == bytes32(0)) {
            revert ZeroAttestationFormat();
        }
        if (descriptor.schemaMajor == 0) {
            revert ZeroSchemaMajor();
        }
        if (descriptor.contextIds.length == 0) {
            revert EmptyContextIds();
        }

        // Attestation IDs are single-use: an ID that was ever registered — or ever
        // revoked, even without a registration — under this attester is consumed forever.
        // This keeps the attestation metadata and the revocation timestamp write-once.
        if (_attestationDetails[attester][descriptor.attestationId].descriptorHash != bytes32(0)
            || _revokedAt[attester][descriptor.attestationId] != 0) {
            revert AttestationIdAlreadyUsed(descriptor.attestationId);
        }

        bytes32 descriptorMirrorListId = descriptor.descriptorMirrorListURIs.resolve(_mirrorLists);
        _setDescriptorMirrorList(attester, descriptor.descriptorHash, descriptorMirrorListId);

        // Store the attestation metadata exactly once per attestation ID, not per contextId.
        _attestationDetails[attester][descriptor.attestationId] = AttestationDetails({
            descriptorHash:          descriptor.descriptorHash,
            schemaMajor:             descriptor.schemaMajor,
            format:                  descriptor.format
        });
        emit AttestationRegistered(
            attester, descriptor.attestationId, descriptor.descriptorHash, descriptor.schemaMajor, descriptor.format
        );

        _setAttestationMirrorList(attester, descriptor.attestationId, attestationMirrorListId);

        _updateActiveAttestation(attester, descriptor, descriptor.attestationId);
    }

    /// @dev Verifies the attester's EIP-712 signature over a registration batch.
    ///      Binding the attestation MirrorList ID prevents a relayer from substituting
    ///      a different MirrorList; binding the revocations hash prevents a relayer from
    ///      adding or dropping revocation entries; the nonce makes the signature single-use.
    function _verifyRegistrationSignature(
        address                    attester,
        DescriptorInfo[]  calldata descriptors,
        bytes32                    attestationMirrorListId,
        RevocationEntry[] calldata revocations,
        uint256                    nonce,
        bytes             calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                ClearSigningRegistryConstants.REGISTRATION_BATCH_TYPEHASH,
                RegistrationHashLib.hashDescriptorInfos(descriptors),
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
    ///      its listed context IDs. Safe to call with an empty array when no attestations are
    ///      being displaced.
    function _processRevocations(address attester, RevocationEntry[] calldata revocations) private {
        uint256 revocationCount = revocations.length;
        for (uint256 revocationIndex = 0; revocationIndex < revocationCount; revocationIndex++) {
            RevocationEntry calldata entry = revocations[revocationIndex];
            _revokeAndClear(attester, entry.attestationId, entry.contextIds);
        }
    }

}
