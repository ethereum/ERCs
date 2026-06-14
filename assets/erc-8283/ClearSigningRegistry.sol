// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IEAS.sol";
import "./IClearSigningRegistry.sol";

/// @dev Minimal ERC-1271 interface for contract-account attesters.
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is IClearSigningRegistry {

    bytes32 public constant CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract");

    bytes32 public constant CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory");

    bytes32 public constant CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment");

    bytes32 public constant CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator");

    bytes32 public constant REGISTRATION_TYPEHASH = keccak256(
        "DescriptorRegistration(bytes32 descriptorHash,bytes32 contextIdsHash,bytes32 mirrorListId)"
    );

    bytes32 public constant REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRegistrationBatch(DescriptorRegistration[] registrations,bytes32 attestationSignaturesHash)"
        "DescriptorRegistration(bytes32 descriptorHash,bytes32 contextIdsHash,bytes32 mirrorListId)"
    );

    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable DOMAIN_SEPARATOR;

    IEAS    public immutable eas;
    bytes32 public immutable easSchemaUID;

    constructor(address _eas, bytes32 _easSchemaUID) {
        eas          = IEAS(_eas);
        easSchemaUID = _easSchemaUID;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ClearSigningRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // The EAS UID of the active ERC-8176 attestation for the given attester and context ID.
    // The endorsed descriptor hash is stored inside the attestation's 'data' field.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationId;

    // Global store of MirrorLists, written once per unique URI set.
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer to the MirrorList this attester endorses for the given descriptor hash.
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _mirrorListId;

    /// @inheritdoc IClearSigningRegistry
    function createDescriptorAttestations(
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedAttestationRequest[] calldata attestations,
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes                              calldata registrationSignature
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

        address attester = attestations[0].attester;

        // Validate each registration against its active attestation, publish its
        // MirrorList, and collect the EIP-712 hash of each registration item.
        bytes32[] memory itemHashes = new bytes32[](registrations.length);
        for (uint256 i; i < registrations.length; ++i) {
            itemHashes[i] = _processRegistration(attester, registrations[i], attestations[0].data[i]);
        }

        // Validate the attester's signature over the attestation metadata for relayed registrations.
        if (msg.sender != attester) {
          _verifyRegistrationSignature(attester, itemHashes, attestations[0].signatures, registrationSignature);
        }

        // Every active attestation being displaced must be explicitly revoked.
        _checkRevocations(attester, registrations, revocations);

        // Revoke prior attestations (may be empty when no slots are replaced).
        if (revocations.length > 0) {
            eas.multiRevokeByDelegation(revocations);
        }

        // Create new attestations; the first registrations.length UIDs of the flat
        // return correspond to attestations[0].data, one per registration.
        bytes32[] memory uids = eas.multiAttestByDelegation(attestations);

        attestationIds = new bytes32[](registrations.length);
        for (uint256 i; i < registrations.length; ++i) {
            attestationIds[i] = uids[i];

            // Update active slot for each contextId of this registration.
            bytes32[] calldata contextIds = registrations[i].contextIds;
            for (uint256 j; j < contextIds.length; ++j) {
                bytes32 cid  = contextIds[j];
                bytes32 prev = _attestationId[attester][cid];
                _attestationId[attester][cid] = uids[i];
                emit AttestationUpdated(
                    attester, cid, prev, registrations[i].descriptorHash, uids[i]
                );
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists)
        external returns (bytes32[] memory mirrorListIds)
    {
        mirrorListIds = new bytes32[](uriLists.length);
        for (uint256 i; i < uriLists.length; ++i) {
            mirrorListIds[i] = _publishMirrorList(uriLists[i]);
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
        if (attesters.length == 0) revert EmptyAttesters();
        if (attesters.length != contextIds.length) revert ArrayLengthMismatch();
        for (uint256 a; a < attesters.length; ++a) {
            address attester = attesters[a];
            bytes32[] calldata ids = contextIds[a];
            if (ids.length == 0) revert EmptyContextIds();
            for (uint256 i; i < ids.length; ++i) {
                bytes32 cid = ids[i];
                bytes32 uid = _attestationId[attester][cid];
                // Skip empty slots: another sweep or a re-registration won the race.
                if (uid == bytes32(0)) continue;

                // Skip slots whose backing attestation is still valid.
                IEAS.Attestation memory attestation = eas.getAttestation(uid);
                bool revoked = attestation.revocationTime != 0;
                bool expired = attestation.expirationTime != 0 && attestation.expirationTime < block.timestamp;
                if (!revoked && !expired) continue;

                _attestationId[attester][cid] = bytes32(0);
                ++cleared;
                emit AttesterEndorsementUpdated(attester, cid, uid, bytes32(0), bytes32(0));
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextIds
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        // First pass: count non-empty slots to size the result array.
        uint256 count;
        for (uint256 a; a < attesters.length; ++a)
            for (uint256 c; c < contextIds.length; ++c)
                if (_attestationId[attesters[a]][contextIds[c]] != bytes32(0))
                    ++count;

        resolved = new ResolvedDescriptor[](count);
        uint256 k;
        for (uint256 a; a < attesters.length; ++a) {
            for (uint256 c; c < contextIds.length; ++c) {
                bytes32 uid = _attestationId[attesters[a]][contextIds[c]];
                if (uid == bytes32(0)) continue;

                IEAS.Attestation memory attestation = eas.getAttestation(uid);
                bytes32 descriptorHash = abi.decode(attestation.data, (bytes32));
                bytes32 mirrorListId   = _mirrorListId[attesters[a]][descriptorHash];

                resolved[k++] = ResolvedDescriptor({
                    attester:       attesters[a],
                    contextId:      contextIds[c],
                    descriptorHash: descriptorHash,
                    attestationId:  uid,
                    expirationTime: attestation.expirationTime,
                    revocationTime: attestation.revocationTime,
                    mirrorListId:   mirrorListId,
                    uris:           _mirrorLists[mirrorListId]
                });
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function getDescriptors(
        address[] calldata attesters,
        bytes32            contextId
    ) external view returns (
        bytes32[] memory descriptorHashes,
        bytes32[] memory attestationIds
    ) {
        descriptorHashes = new bytes32[](attesters.length);
        attestationIds   = new bytes32[](attesters.length);
        for (uint256 i = 0; i < attesters.length; i++) {
            bytes32 uid = _attestationId[attesters[i]][contextId];
            if (uid == bytes32(0)) continue;
            attestationIds[i]   = uid;
            descriptorHashes[i] = abi.decode(eas.getAttestation(uid).data, (bytes32));
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId)
        external view returns (string[] memory)
    {
        return _mirrorLists[mirrorListId];
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Validates one registration against its active attestation data,
    ///      updates the attester's MirrorList pointer
    /// @returns the registration's EIP-712 item hash.
    function _processRegistration(
        address                          attester,
        DescriptorRegistration  calldata registration,
        AttestationRequestData  calldata attestationData
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        if (attester.code.length > 0) {
            if (IERC1271(attester).isValidSignature(digest, registrationSignature) != ERC1271_MAGIC_VALUE)
                revert InvalidRegistrationSignature();
        } else {
            if (registrationSignature.length != 65) {
              revert InvalidRegistrationSignature();
            }
            bytes32 r = bytes32(registrationSignature[0:32]);
            bytes32 s = bytes32(registrationSignature[32:64]);
            uint8   v = uint8(registrationSignature[64]);
            address recovered = ecrecover(digest, v, r, s);
            if (recovered == address(0) || recovered != attester) {
                revert InvalidRegistrationSignature();
            }
        }
    }

    /// @dev Requires that every active attestation displaced by this batch is present in the supplied revocation batch.
    function _checkRevocations(
        address                                     attester,
        DescriptorRegistration[]           calldata registrations,
        MultiDelegatedRevocationRequest[]  calldata revocations
    ) private view {
        // Build flat set of UIDs included in the revocation batch.
        uint256 total = 0;
        for (uint256 i; i < revocations.length; ++i) {
            total += revocations[i].data.length;
        }
        bytes32[] memory revokedUids = new bytes32[](total);
        uint256 ri = 0;
        for (uint256 i; i < revocations.length; ++i) {
            for (uint256 j; j < revocations[i].data.length; ++j) {
                revokedUids[ri++] = revocations[i].data[j].uid;
            }
        }

        for (uint256 i; i < registrations.length; ++i) {
            bytes32[] calldata contextIds = registrations[i].contextIds;
            for (uint256 j; j < contextIds.length; ++j) {
                bytes32 oldUid = _attestationId[attester][contextIds[j]];
                if (oldUid == bytes32(0)) {
                  continue;
                }
                bool found = false;
                for (uint256 k; k < revokedUids.length; ++k) {
                    if (revokedUids[k] == oldUid) {
                      found = true;
                      break;
                    }
                }
                if (!found) {
                  revert MissingRevocation(oldUid);
                }
            }
        }
    }
}
