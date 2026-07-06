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
    // this registry itself when a registration batch displaces an attestation on the
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

        // Revoke and clear displaced attestations (may be empty when no attestations are replaced).
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
        bytes32 attestationMirrorListId = attestationURIs.resolve(_mirrorLists);

        _processAllDescriptors(attester, descriptors, attestationMirrorListId);

        // Validate the attester's signature over the batch for relayed registrations. The
        // per-descriptor EIP-712 hashes are only ever needed on this path, so they're
        // recomputed here from calldata rather than carried out of the processing loop above.
        if (msg.sender != attester) {
            uint256 nonce = _registrationNonce[attester];
            _registrationNonce[attester] = nonce + 1;
            _verifyRegistrationSignature(
                attester, descriptors, attestationMirrorListId, revocations, nonce, signature
            );
        }
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

    /// @dev Updates the active attestation for each contextId of a descriptor.
    function _updateActiveAttestation(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationId
    ) private {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
            bytes32 contextId             = contextIds[contextIndex];
            bytes32 previousAttestationId = _attestationIds[attester][contextId];
            _attestationIds[attester][contextId] = attestationId;
            emit AttestationUpdated(
                attester, contextId, attestationId, previousAttestationId, descriptor.descriptorHash
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
    ///      immediately wherever they still point to it. A context ID whose active attestation
    ///      has since moved to a different attestation ID is silently skipped. Shared by
    ///      the direct self-service path ('revokeAttestation') and the registration-batch
    ///      displacement path ('_processRevocations').
    function _revokeAndClear(address attester, bytes32 attestationId, bytes32[] calldata contextIds) private {
        _recordRevocation(attester, attestationId);
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
            bytes32 contextId = contextIds[contextIndex];
            if (_attestationIds[attester][contextId] == attestationId) {
                _attestationIds[attester][contextId] = bytes32(0);
                emit AttestationUpdated(attester, contextId, bytes32(0), attestationId, bytes32(0));
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 activeAttestationCount = _countActiveAttestations(attesters, contextIds);
        resolved = new ResolvedDescriptor[](activeAttestationCount);
        _collectResolvedDescriptors(attesters, contextIds, allowedPrefixes, resolved);
    }

    /// @dev Counts how many (attester, contextId) pairs currently have an active attestation,
    ///      used to size the 'resolveDescriptors' result array.
    function _countActiveAttestations(
        address[] calldata attesters,
        bytes32[] calldata contextIds
    ) private view returns (uint256 activeAttestationCount) {
        uint256 attesterCount = attesters.length;
        uint256 contextIdCount = contextIds.length;
        for (uint256 attesterIndex = 0; attesterIndex < attesterCount; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
                if (_attestationIds[attester][contextIds[contextIndex]] != bytes32(0)) {
                    ++activeAttestationCount;
                }
            }
        }
    }

    /// @dev Fills 'resolved' with one entry per active (attester, contextId) attestation.
    function _collectResolvedDescriptors(
        address[]            calldata attesters,
        bytes32[]            calldata contextIds,
        string[]              calldata allowedPrefixes,
        ResolvedDescriptor[]   memory  resolved
    ) private view {
        uint256 attesterCount = attesters.length;
        uint256 contextIdCount = contextIds.length;
        uint256 resolvedIndex;
        for (uint256 attesterIndex = 0; attesterIndex < attesterCount; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
                bytes32 contextId = contextIds[contextIndex];
                bytes32 attestationId = _attestationIds[attester][contextId];
                if (attestationId != bytes32(0)) {
                    resolved[resolvedIndex++] = _resolveActiveAttestation(attester, contextId, attestationId, allowedPrefixes);
                }
            }
        }
    }

    /// @dev Resolves one active attestation into a ResolvedDescriptor.
    function _resolveActiveAttestation(
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
            uris:                      _mirrorLists[mirrorListId].filter(allowedPrefixes)
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
        attestationMirrorListUris = _mirrorLists[details.attestationMirrorListId].filter(allowedPrefixes);
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
        external view returns (string[] memory)
    {
        return _mirrorLists[mirrorListId].filter(allowedPrefixes);
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

        for (uint256 descriptorHashIndex = 0; descriptorHashIndex < descriptorHashCount; descriptorHashIndex++) {
            _updateMirrorListInternal(attester, descriptorHashes[descriptorHashIndex], mirrorListId);
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Validates one descriptor, resolves or publishes its MirrorList, and updates
    ///      the attester's MirrorList pointer for it.
    function _processDescriptorCore(
        address                          attester,
        DescriptorInfo          calldata descriptor
    ) private {
        if (descriptor.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (descriptor.contextIds.length == 0) {
            revert EmptyContextIds();
        }

        bytes32 mirrorListId = descriptor.descriptorURIs.resolve(_mirrorLists);
        _updateMirrorListInternal(attester, descriptor.descriptorHash, mirrorListId);
    }

    /// @dev Points an attester's active MirrorList for a descriptor at 'mirrorListId',
    ///      emitting 'MirrorListUpdated' only when the pointer actually changes.
    function _updateMirrorListInternal(
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
    ///      processing, attestation metadata storage and active-attestation updates.
    function _processDescriptor(
        address                 attester,
        DescriptorInfo calldata descriptor,
        bytes32                 attestationMirrorListId
    ) private {
        if (descriptor.format == bytes32(0)) {
            revert ZeroAttestationFormat();
        }

        _processDescriptorCore(attester, descriptor);

        // Store the attestation metadata exactly once per attestation ID, not per contextId.
        _attestationDetails[attester][descriptor.attestationId] = AttestationDetails({
            descriptorHash:          descriptor.descriptorHash,
            attestationMirrorListId: attestationMirrorListId,
            format:                  descriptor.format
        });

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

    /// @dev Verifies the attester's EIP-712 mirror update signature.
    function _verifyMirrorUpdateSignature(
        address              attester,
        bytes32[]   calldata descriptorHashes,
        bytes32              mirrorListId,
        bytes       calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                ClearSigningRegistryConstants.MIRROR_UPDATE_TYPEHASH,
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

    /// @dev Requires that every active attestation displaced by this batch is
    ///      present in 'revocations'.
    function _checkRevocations(
        address                    attester,
        DescriptorInfo[]  calldata descriptors,
        RevocationEntry[] calldata revocations
    ) private view {
        uint256 descriptorCount = descriptors.length;
        for (uint256 descriptorIndex = 0; descriptorIndex < descriptorCount; descriptorIndex++) {
            _checkRevocationsForDescriptor(attester, descriptors[descriptorIndex], revocations);
        }
    }

    /// @dev Checks every context ID of one descriptor for a displaced, unrevoked attestation.
    function _checkRevocationsForDescriptor(
        address                   attester,
        DescriptorInfo   calldata descriptor,
        RevocationEntry[] calldata revocations
    ) private view {
        bytes32[] calldata contextIds = descriptor.contextIds;
        uint256 contextIdCount = contextIds.length;
        for (uint256 contextIndex = 0; contextIndex < contextIdCount; contextIndex++) {
            _checkDisplacedAttestationIsRevoked(attester, contextIds[contextIndex], revocations);
        }
    }

    /// @dev Reverts with 'MissingRevocation' if a context ID's currently active attestation
    ///      is about to be displaced without its attestation ID appearing in 'revocations'.
    function _checkDisplacedAttestationIsRevoked(
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
        for (uint256 i = 0; i < count; i++) {
            if (revocations[i].attestationId == target) {
                return true;
            }
        }
        return false;
    }
}
