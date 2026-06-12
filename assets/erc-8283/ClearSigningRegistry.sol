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
        "ClearSigningRegistration(bytes32 descriptorHash,bytes32 contextIdsHash,bytes32 mirrorListId,bytes32 attestationSignatureHash)"
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

    // The current descriptor hash for the specified context ID as provided by the given attester.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _descriptorHash;

    // The ERC-8176 EAS UID of the active attestation for the current descriptor by the given attester.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationId;

    // Global store of MirrorLists, written once per unique URI set. Key = keccak256(abi.encode(uris)).
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer: which MirrorList does this attester use for this descriptor?
    mapping(address attester => mapping(bytes32 descriptorHash => bytes32)) private _mirrorListId;

    /// @inheritdoc IClearSigningRegistry
    function createDescriptorAttestation(
        bytes32                            descriptorHash,
        bytes32[]                          calldata contextIds,
        bytes32                            mirrorListId,
        MultiDelegatedAttestationRequest[] calldata attestations,
        MultiDelegatedRevocationRequest[]  calldata revocations,
        bytes                              calldata registrationSignature
    ) external returns (bytes32 attestationId) {
        if (descriptorHash == bytes32(0)) revert ZeroDescriptorHash();
        if (contextIds.length == 0)       revert EmptyContextIds();
        if (
            attestations.length == 0 ||
            attestations[0].data.length == 0 ||
            attestations[0].signatures.length == 0
        ) revert EmptyAttestations();
        if (_mirrorLists[mirrorListId].length == 0) revert UnknownMirrorList(mirrorListId);

        // Validate active attestation: must use ERC-8176 schema.
        if (attestations[0].schema != easSchemaUID)
            revert WrongEASSchema(easSchemaUID, attestations[0].schema);

        // The active attestation must be revocable so the slot can be replaced later.
        if (!attestations[0].data[0].revocable) revert NonRevocableAttestation();

        // Validate active attestation data encodes exactly the claimed descriptorHash.
        if (attestations[0].data[0].data.length != 32) revert InvalidAttestationData();
        bytes32 attestedHash = abi.decode(attestations[0].data[0].data, (bytes32));
        if (attestedHash != descriptorHash)
            revert EASHashMismatch(attestedHash, descriptorHash);

        address attester = attestations[0].attester;

        // Unless submitted by the attester directly, the registration parameters not
        // covered by the EAS signature (contextIds, mirrorListId) must be authorized
        // by the attester's EIP-712 registration signature.
        _verifyRegistrationSignature(
            attester,
            descriptorHash,
            contextIds,
            mirrorListId,
            attestations[0].signatures[0],
            registrationSignature
        );

        // Every active attestation being displaced must be explicitly revoked.
        _checkRevocations(attester, contextIds, revocations);

        // Revoke prior attestations (may be empty on first registration).
        if (revocations.length > 0) {
            eas.multiRevokeByDelegation(revocations);
        }

        // Create new attestations; capture the active UID (first in flat return).
        bytes32[] memory uids = eas.multiAttestByDelegation(attestations);
        attestationId = uids[0];

        // Set MirrorList pointer (replaces any prior pointer; no-op if unchanged).
        if (_mirrorListId[attester][descriptorHash] != mirrorListId) {
            _mirrorListId[attester][descriptorHash] = mirrorListId;
            emit MirrorListUpdated(attester, descriptorHash, mirrorListId);
        }

        // Update active slot for each contextId.
        for (uint256 i; i < contextIds.length; ++i) {
            bytes32 cid  = contextIds[i];
            bytes32 prev = _descriptorHash[attester][cid];
            _descriptorHash[attester][cid]  = descriptorHash;
            _attestationId[attester][cid] = attestationId;
            emit AttesterEndorsementUpdated(attester, cid, prev, descriptorHash, attestationId);
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

                bytes32 prev = _descriptorHash[attester][cid];
                _descriptorHash[attester][cid]  = bytes32(0);
                _attestationId[attester][cid] = bytes32(0);
                ++cleared;
                emit AttesterEndorsementUpdated(attester, cid, prev, bytes32(0), bytes32(0));
            }
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorList(string[] calldata uris) external returns (bytes32 mirrorListId) {
        if (uris.length == 0) revert EmptyMirrorList();
        mirrorListId = keccak256(abi.encode(uris));
        if (_mirrorLists[mirrorListId].length == 0) {
            _mirrorLists[mirrorListId] = uris;
            emit MirrorListPublished(mirrorListId);
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

                bytes32 descriptorHash = _descriptorHash[attesters[a]][contextIds[c]];
                bytes32 mirrorListId   = _mirrorListId[attesters[a]][descriptorHash];
                IEAS.Attestation memory attestation = eas.getAttestation(uid);

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
            descriptorHashes[i] = _descriptorHash[attesters[i]][contextId];
            attestationIds[i]   = _attestationId[attesters[i]][contextId];
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

    /// @dev Verifies the attester's EIP-712 registration signature binding the
    ///      parameters not covered by the EAS delegated attestation signature.
    ///      Skipped when the attester submits the transaction directly.
    ///      Replay protection: the signed struct includes the hash of the EAS
    ///      delegated attestation signature, which EAS accepts only once.
    function _verifyRegistrationSignature(
        address            attester,
        bytes32            descriptorHash,
        bytes32[] calldata contextIds,
        bytes32            mirrorListId,
        Signature calldata attestationSignature,
        bytes     calldata registrationSignature
    ) private view {
        if (msg.sender == attester) return;

        bytes32 structHash = keccak256(
            abi.encode(
                REGISTRATION_TYPEHASH,
                descriptorHash,
                keccak256(abi.encodePacked(contextIds)),
                mirrorListId,
                keccak256(abi.encode(attestationSignature))
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        if (attester.code.length > 0) {
            if (IERC1271(attester).isValidSignature(digest, registrationSignature) != ERC1271_MAGIC_VALUE)
                revert InvalidRegistrationSignature();
        } else {
            if (registrationSignature.length != 65) revert InvalidRegistrationSignature();
            bytes32 r = bytes32(registrationSignature[0:32]);
            bytes32 s = bytes32(registrationSignature[32:64]);
            uint8   v = uint8(registrationSignature[64]);
            address recovered = ecrecover(digest, v, r, s);
            if (recovered == address(0) || recovered != attester)
                revert InvalidRegistrationSignature();
        }
    }

    /// @dev Requires that every active attestation displaced by this registration
    ///      is present in the supplied revocation batch. Runs even when the batch
    ///      is empty so an existing active slot can never be silently replaced.
    function _checkRevocations(
        address                                     attester,
        bytes32[]                          calldata contextIds,
        MultiDelegatedRevocationRequest[]  calldata revocations
    ) private view {
        // Build flat set of UIDs included in the revocation batch.
        uint256 total = 0;
        for (uint256 i; i < revocations.length; ++i)
            total += revocations[i].data.length;
        bytes32[] memory revokedUids = new bytes32[](total);
        uint256 ri = 0;
        for (uint256 i; i < revocations.length; ++i)
            for (uint256 j; j < revocations[i].data.length; ++j)
                revokedUids[ri++] = revocations[i].data[j].uid;

        for (uint256 i; i < contextIds.length; ++i) {
            bytes32 oldUid = _attestationId[attester][contextIds[i]];
            if (oldUid == bytes32(0)) continue;
            bool found = false;
            for (uint256 k; k < revokedUids.length; ++k)
                if (revokedUids[k] == oldUid) { found = true; break; }
            if (!found) revert MissingRevocation(oldUid);
        }
    }
}
