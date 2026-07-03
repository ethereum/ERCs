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

    bytes32 public constant REGISTRATION_TYPEHASH = keccak256(
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
    );

    bytes32 public constant REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRegistrationBatch(DescriptorRegistration[] registrations,bytes32 attestationSignaturesHash)"
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
    );

    bytes32 public constant OFFCHAIN_ATTESTATION_TYPEHASH = keccak256(
        "OffchainAttestation(bytes32 uid,uint64 expirationTime)"
    );

    bytes32 public constant OFFCHAIN_REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningOffchainRegistrationBatch(DescriptorRegistration[] registrations,OffchainAttestation[] attestations,bytes32 attestationMirrorListId,uint256 nonce)"
        "DescriptorRegistration(bytes32 descriptorHash,bytes32[] contextIds,bytes32 mirrorListId)"
        "OffchainAttestation(bytes32 uid,uint64 expirationTime)"
    );

    bytes32 public constant MIRROR_UPDATE_TYPEHASH = keccak256(
        "MirrorListUpdate(bytes32[] descriptorHashes,bytes32 mirrorListId)"
    );

    IEAS    public immutable eas;
    bytes32 public immutable easSchemaUID;

    constructor(address _eas, bytes32 _easSchemaUID) EIP712("ClearSigningRegistry", "1") {
        eas          = IEAS(_eas);
        easSchemaUID = _easSchemaUID;
    }

    // The EAS UID of the active ERC-8176 attestation for the given attester and context ID.
    // Holds either an on-chain attestation UID or a pre-computed off-chain attestation UID;
    // for on-chain UIDs the endorsed descriptor hash is stored inside the attestation's
    // 'data' field, for off-chain UIDs it is stored in '_offchainDetails'.
    mapping(address attester => mapping(bytes32 contextId => bytes32 uid)) private _slots;

    // Extra metadata for off-chain attestations, stored exactly once per UID.
    // Never written on the on-chain path, keeping its slot writes to the single UID.
    struct OffchainDetails {
        bytes32 descriptorHash;
        bytes32 attestationMirrorListId; // points into _mirrorLists, like a descriptor's mirrorListId
        uint64  expirationTime;
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
        if (attestations.length == 0){
          revert EmptyAttestations();
        }
        // Validate active attestations: must use ERC-8176 schema, one entry per registration.
        if (attestations[0].schema != easSchemaUID)
            revert WrongEASSchema(easSchemaUID, attestations[0].schema);
        if (
            attestations[0].data.length != registrations.length ||
            attestations[0].signatures.length != registrations.length
        ) {
          revert ArrayLengthMismatch();
        }

        // Every active attestation being displaced must be explicitly revoked,
        // whether the displaced slot was previously on-chain or off-chain.
        _checkRevocations(attestations[0].attester, registrations, revocations, offchainRevocations);

        // Revoke prior attestations (may be empty when no slots are replaced).
        _processRevocations(revocations, offchainRevocations);

        attestationIds = _registerOnchainBatch(registrations, attestations, registrationSignature);
    }

    /// @dev The registration phase of 'createDescriptorAttestations', split out
    ///      from the revocation phase to limit per-frame stack usage.
    function _registerOnchainBatch(
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedAttestationRequest[] calldata attestations,
        bytes                              calldata registrationSignature
    ) private returns (bytes32[] memory attestationIds) {
        address attester = attestations[0].attester;
        uint256 regLength = registrations.length;

        // Validate each registration against its active attestation, publish its
        // MirrorList, and collect the EIP-712 hash of each registration item.
        bytes32[] memory itemHashes = new bytes32[](regLength);
        AttestationRequestData[] calldata attData = attestations[0].data;
        for (uint256 i; i < regLength;) {
            itemHashes[i] = _processRegistration(attester, registrations[i], attData[i]);
            unchecked { ++i; }
        }

        // Validate the attester's signature over the attestation metadata for relayed registrations.
        if (msg.sender != attester) {
          _verifyRegistrationSignature(attester, itemHashes, attestations[0].signatures, registrationSignature);
        }

        // Create new attestations; the first registrations.length UIDs of the flat
        // return correspond to attestations[0].data, one per registration.
        bytes32[] memory uids = eas.multiAttestByDelegation(attestations);

        attestationIds = new bytes32[](regLength);
        for (uint256 i; i < regLength;) {
            attestationIds[i] = uids[i];
            _updateSlots(attester, registrations[i], uids[i]);
            unchecked { ++i; }
        }
    }

    /// @dev Updates the active slot for each contextId of a registration.
    function _updateSlots(
        address                         attester,
        DescriptorRegistration calldata registration,
        bytes32                         uid
    ) private {
        bytes32[] calldata contextIds = registration.contextIds;
        uint256 ctxLength = contextIds.length;
        for (uint256 j; j < ctxLength;) {
            bytes32 cid  = contextIds[j];
            bytes32 prev = _slots[attester][cid];
            _slots[attester][cid] = uid;
            emit AttestationUpdated(
                attester, cid, uid, prev, registration.descriptorHash
            );
            unchecked { ++j; }
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

        uint256 regLength = registrations.length;
        bytes32[] memory itemHashes        = new bytes32[](regLength);
        bytes32[] memory attestationHashes = new bytes32[](regLength);
        attestationIds = new bytes32[](regLength);
        for (uint256 i; i < regLength;) {
            (itemHashes[i], attestationHashes[i]) = _processOffchainRegistration(
                attester, registrations[i], attestations[i], attestationMirrorListId
            );
            attestationIds[i] = attestations[i].uid;
            unchecked { ++i; }
        }

        // Validate the attester's signature over the batch for relayed registrations.
        if (msg.sender != attester) {
            uint256 nonce = _registrationNonce[attester];
            _registrationNonce[attester] = nonce + 1;
            _verifyOffchainRegistrationSignature(
                attester, itemHashes, attestationHashes, attestationMirrorListId, nonce, registrationSignature
            );
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds)
    {
        uint256 listsLength = uriLists.length;
        mirrorListIds = new bytes32[](listsLength);
        for (uint256 i; i < listsLength;) {
            mirrorListIds[i] = _publishMirrorList(uriLists[i]);
            unchecked { ++i; }
        }
    }

    /// @dev Stores a MirrorList keyed by its content hash. Idempotent: a list
    ///      with identical content is stored exactly once and emits no event on
    ///      repeated publication.
    function _publishMirrorList(string[] calldata uris) private returns (bytes32 mirrorListId) {
        if (uris.length == 0) revert EmptyMirrorList();
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
        uint256 attestersLength = attesters.length;
        if (attestersLength == 0) revert EmptyAttesters();
        if (attestersLength != contextIds.length) revert ArrayLengthMismatch();
        for (uint256 a; a < attestersLength;) {
            address attester = attesters[a];
            bytes32[] calldata ids = contextIds[a];
            uint256 idsLength = ids.length;
            if (idsLength == 0) revert EmptyContextIds();
            for (uint256 i; i < idsLength;) {
                bytes32 cid = ids[i];
                bytes32 uid = _slots[attester][cid];
                // Skip empty slots: another sweep or a re-registration won the race.
                if (uid != bytes32(0)) {
                    // Skip slots whose backing attestation is still valid.
                    bool revoked;
                    bool expired;
                    OffchainDetails storage details = _offchainDetails[attester][uid];
                    if (details.attestationMirrorListId != bytes32(0)) {
                        // off-chain attestation
                        revoked = eas.getRevokeOffchain(attester, uid) != 0;
                        expired = details.expirationTime != 0 && details.expirationTime < block.timestamp;
                    } else {
                        // on-chain attestation
                        IEAS.Attestation memory attestation = eas.getAttestation(uid);
                        revoked = attestation.revocationTime != 0;
                        expired = attestation.expirationTime != 0 && attestation.expirationTime < block.timestamp;
                    }
                    if (revoked || expired) {
                        _slots[attester][cid] = bytes32(0);
                        ++cleared;
                        emit AttestationUpdated(attester, cid, bytes32(0), uid, bytes32(0));
                    }
                }
                unchecked { ++i; }
            }
            unchecked { ++a; }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 attestersLength = attesters.length;
        uint256 contextIdsLength = contextIds.length;

        // First pass: count non-empty slots to size the result array.
        uint256 count;
        for (uint256 a; a < attestersLength;) {
            address attester = attesters[a];
            for (uint256 c; c < contextIdsLength;) {
                if (_slots[attester][contextIds[c]] != bytes32(0)) {
                    ++count;
                }
                unchecked { ++c; }
            }
            unchecked { ++a; }
        }

        resolved = new ResolvedDescriptor[](count);
        uint256 k;
        for (uint256 a; a < attestersLength;) {
            address attester = attesters[a];
            for (uint256 c; c < contextIdsLength;) {
                bytes32 cid = contextIds[c];
                bytes32 uid = _slots[attester][cid];
                if (uid != bytes32(0)) {
                    resolved[k++] = _resolveSlot(attester, cid, uid, allowedPrefixes);
                }
                unchecked { ++c; }
            }
            unchecked { ++a; }
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
        string[] memory attestationMirrorListUris;
        OffchainDetails storage details = _offchainDetails[attester][uid];
        if (details.attestationMirrorListId != bytes32(0)) {
            // off-chain attestation: read metadata from registry storage;
            // revocationTime stays 0 — it requires a separate getRevokeOffchain call.
            descriptorHash = details.descriptorHash;
            expirationTime = details.expirationTime;
            attestationMirrorListUris =
                _filterUris(_mirrorLists[details.attestationMirrorListId], allowedPrefixes);
        } else {
            // on-chain attestation: read from EAS.
            IEAS.Attestation memory attestation = eas.getAttestation(uid);
            descriptorHash = abi.decode(attestation.data, (bytes32));
            expirationTime = attestation.expirationTime;
            revocationTime = attestation.revocationTime;
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
            uris:                      _filterUris(_mirrorLists[mirrorListId], allowedPrefixes)
        });
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
        uint256 hashesLength = descriptorHashes.length;
        if (hashesLength == 0) revert EmptyRegistrations();
        if (_mirrorLists[mirrorListId].length == 0) revert UnknownMirrorList(mirrorListId);

        if (msg.sender != attester) {
            _verifyMirrorUpdateSignature(attester, descriptorHashes, mirrorListId, signature);
        }

        for (uint256 i = 0; i < hashesLength;) {
            bytes32 hash = descriptorHashes[i];
            if (_mirrorListId[attester][hash] != mirrorListId) {
                _mirrorListId[attester][hash] = mirrorListId;
                emit MirrorListUpdated(attester, hash, mirrorListId);
            }
            unchecked { ++i; }
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
        if (attestedHash != registration.descriptorHash){
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
        bytes32 mirrorListId;
        if (registration.mirrorListUris.length > 0) {
            // inline flow - hash the supplied MirrorList to get its ID
            if (registration.mirrorListId != bytes32(0)) {
              revert RedundantMirrorListId();
            }
            mirrorListId = _publishMirrorList(registration.mirrorListUris);
        } else {
            // reference flow - the MirrorList must have been published before
            mirrorListId = registration.mirrorListId;
            if (_mirrorLists[mirrorListId].length == 0) revert UnknownMirrorList(mirrorListId);
        }

        // Set the attester's active MirrorList pointer if changed.
        if (_mirrorListId[attester][registration.descriptorHash] != mirrorListId) {
            _mirrorListId[attester][registration.descriptorHash] = mirrorListId;
            emit MirrorListUpdated(attester, registration.descriptorHash, mirrorListId);
        }

        return keccak256(
            abi.encode(
                REGISTRATION_TYPEHASH,
                registration.descriptorHash,
                keccak256(abi.encodePacked(registration.contextIds)),
                mirrorListId
            )
        );
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
        itemHash = _processRegistrationCore(attester, registration);
        attestationHash = keccak256(
            abi.encode(OFFCHAIN_ATTESTATION_TYPEHASH, attestation.uid, attestation.expirationTime)
        );

        // Store the off-chain metadata exactly once per UID, not per contextId.
        _offchainDetails[attester][attestation.uid] = OffchainDetails({
            descriptorHash:          registration.descriptorHash,
            attestationMirrorListId: attestationMirrorListId,
            expirationTime:          attestation.expirationTime
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
        uint256 revsLength = revocations.length;
        uint256 total = 0;
        for (uint256 i; i < revsLength;) {
            total += revocations[i].data.length;
            unchecked { ++i; }
        }
        revokedUids = new bytes32[](total);
        uint256 ri = 0;
        for (uint256 i; i < revsLength;) {
            AttestationRequestData[] calldata revData = revocations[i].data;
            uint256 dataLength = revData.length;
            for (uint256 j; j < dataLength;) {
                revokedUids[ri++] = revData[j].uid;
                unchecked { ++j; }
            }
            unchecked { ++i; }
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
        uint256 offLength = offchainRevocations.length;
        for (uint256 i; i < offLength;) {
            eas.revokeOffchain(offchainRevocations[i]);
            unchecked { ++i; }
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
        uint256 regLength = registrations.length;
        uint256 offLength = offchainRevocations.length;
        uint256 onLength = revokedOnchainUids.length;

        for (uint256 i; i < regLength;) {
            bytes32[] calldata contextIds = registrations[i].contextIds;
            uint256 ctxLength = contextIds.length;
            for (uint256 j; j < ctxLength;) {
                bytes32 oldUid = _slots[attester][contextIds[j]];
                if (oldUid != bytes32(0)) {
                    // Route the check by what kind of slot is being displaced.
                    bool wasOffchain = _offchainDetails[attester][oldUid].attestationMirrorListId != bytes32(0);
                    bool found = false;
                    if (wasOffchain) {
                        for (uint256 k; k < offLength;) {
                            if (offchainRevocations[k] == oldUid) {
                              found = true;
                              break;
                            }
                            unchecked { ++k; }
                        }
                    } else {
                        for (uint256 k; k < onLength;) {
                            if (revokedOnchainUids[k] == oldUid) {
                              found = true;
                              break;
                            }
                            unchecked { ++k; }
                        }
                    }
                    if (!found) {
                      revert MissingRevocation(oldUid);
                    }
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Copies the URIs matching at least one of the allowed prefixes into a
    ///      memory array. An empty prefix list disables filtering. A rejected URI
    ///      is never fully loaded from storage and never reaches the return data:
    ///      the cost of discarding it is bounded by the prefix lengths, not by the
    ///      URI's own length.
    function _filterUris(string[] storage uris, string[] calldata allowedPrefixes)
        private view returns (string[] memory filtered)
    {
        uint256 allowedLength = allowedPrefixes.length;
        if (allowedLength == 0) return uris; // unfiltered: implicit storage-to-memory copy

        uint256 n = uris.length;
        uint256 count;
        for (uint256 i; i < n;) {
            if (_matchesAny(uris[i], allowedPrefixes, allowedLength)) ++count;
            unchecked { ++i; }
        }
        filtered = new string[](count);
        uint256 k;
        for (uint256 i; i < n;) {
            if (_matchesAny(uris[i], allowedPrefixes, allowedLength)) filtered[k++] = uris[i];
            unchecked { ++i; }
        }
    }

    function _matchesAny(string storage uri, string[] calldata allowedPrefixes, uint256 allowedLength) private view returns (bool) {
        for (uint256 i; i < allowedLength;) {
            if (_hasPrefix(uri, allowedPrefixes[i])) return true;
            unchecked { ++i; }
        }
        return false;
    }

    function _hasPrefix(string storage str, string calldata prefix) private view returns (bool) {
        bytes storage strBytes = bytes(str);
        bytes calldata prefixBytes = bytes(prefix);
        uint256 prefixLength = prefixBytes.length;
        if (prefixLength > strBytes.length) return false;

        // Note: In production, optimize this by reading the first 32 bytes from storage
        // in one go (handling both short and long string packing) to avoid O(N) sloads
        // for short prefixes like "ipfs:".
        for (uint256 i; i < prefixLength;) {
            if (strBytes[i] != prefixBytes[i]) return false;
            unchecked { ++i; }
        }
        return true;
    }
}
