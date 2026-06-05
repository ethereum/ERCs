// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IEAS.sol";
import "./IClearSigningRegistry.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is IClearSigningRegistry {

    bytes32 public constant CONTEXT_TAG_CONTRACT  = keccak256("erc7730.context.contract");

    bytes32 public constant CONTEXT_TAG_FACTORY   = keccak256("erc7730.context.factory");

    bytes32 public constant CONTEXT_TAG_EIP712    = keccak256("erc7730.context.eip712.deployment");

    bytes32 public constant CONTEXT_TAG_EIP712_DS = keccak256("erc7730.context.eip712.domain-separator");


    IEAS    public immutable eas;
    bytes32 public immutable easSchemaUID;

    constructor(address _eas, bytes32 _easSchemaUID) {
        eas          = IEAS(_eas);
        easSchemaUID = _easSchemaUID;
    }

    // The current descriptor hash for the specified context ID as provided by the given attester.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _descriptorId;

    // The ERC-8176 EAS UID of the active attestation for the current descriptor by the given attester.
    mapping(address attester => mapping(bytes32 contextId => bytes32)) private _attestationId;

    // Global store of MirrorLists, written once per unique URI set. Key = keccak256(abi.encode(uris)).
    mapping(bytes32 mirrorListId => string[]) private _mirrorLists;

    // Per-attester pointer: which MirrorList does this attester use for this descriptor?
    mapping(address attester => mapping(bytes32 descriptorId => bytes32)) private _mirrorListId;

    /// @inheritdoc IClearSigningRegistry
    function createDescriptorAttestation(
        bytes32                            descriptorId,
        bytes32[]                          calldata contextIds,
        bytes32                            mirrorListId,
        MultiDelegatedAttestationRequest[] calldata attestations,
        MultiDelegatedRevocationRequest[]  calldata revocations
    ) external returns (bytes32 attestationId) {
        if (descriptorId == bytes32(0)) revert ZeroDescriptorId();
        if (contextIds.length == 0)    revert EmptyContextIds();
        if (attestations.length == 0 || attestations[0].data.length == 0)
            revert EmptyAttestations();
        if (_mirrorLists[mirrorListId].length == 0) revert UnknownMirrorList(mirrorListId);

        // Validate active attestation: must use ERC-8176 schema.
        if (attestations[0].schema != easSchemaUID)
            revert WrongEASSchema(easSchemaUID, attestations[0].schema);

        // Validate active attestation data encodes the claimed descriptorId.
        bytes32 attestedId = abi.decode(attestations[0].data[0].data, (bytes32));
        if (attestedId != descriptorId)
            revert EASHashMismatch(attestedId, descriptorId);

        address attester = attestations[0].attester;

        // Revoke prior attestations (may be empty on first registration).
        if (revocations.length > 0) {
            // Build flat set of UIDs included in the revocation batch.
            uint256 total = 0;
            for (uint256 i; i < revocations.length; ++i)
                total += revocations[i].data.length;
            bytes32[] memory revokedUids = new bytes32[](total);
            uint256 ri = 0;
            for (uint256 i; i < revocations.length; ++i)
                for (uint256 j; j < revocations[i].data.length; ++j)
                    revokedUids[ri++] = revocations[i].data[j].uid;

            // Every active attestation being displaced must be explicitly revoked.
            for (uint256 i; i < contextIds.length; ++i) {
                bytes32 oldUid = _attestationId[attester][contextIds[i]];
                if (oldUid == bytes32(0)) continue;
                bool found = false;
                for (uint256 k; k < revokedUids.length; ++k)
                    if (revokedUids[k] == oldUid) { found = true; break; }
                if (!found) revert MissingRevocation(oldUid);
            }

            eas.multiRevokeByDelegation(revocations);
        }

        // Create new attestations; capture the active UID (first in flat return).
        bytes32[] memory uids = eas.multiAttestByDelegation(attestations);
        attestationId = uids[0];

        // Set MirrorList pointer (replaces any prior pointer).
        _mirrorListId[attester][descriptorId] = mirrorListId;
        emit MirrorListUpdated(attester, descriptorId, mirrorListId);

        // Update active slot for each contextId.
        for (uint256 i; i < contextIds.length; ++i) {
            bytes32 cid  = contextIds[i];
            bytes32 prev = _descriptorId[attester][cid];
            _descriptorId[attester][cid]  = descriptorId;
            _attestationId[attester][cid] = attestationId;
            emit AttesterEndorsementUpdated(attester, cid, prev, descriptorId, attestationId);
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
    function getDescriptors(
        address[] calldata attesters,
        bytes32            contextId
    ) external view returns (
        bytes32[] memory descriptorIds,
        bytes32[] memory attestationIds
    ) {
        descriptorIds  = new bytes32[](attesters.length);
        attestationIds = new bytes32[](attesters.length);
        for (uint256 i = 0; i < attesters.length; i++) {
            descriptorIds[i]  = _descriptorId[attesters[i]][contextId];
            attestationIds[i] = _attestationId[attesters[i]][contextId];
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorList(address attester, bytes32 descriptorId)
        external view returns (bytes32 mirrorListId, string[] memory uris)
    {
        mirrorListId = _mirrorListId[attester][descriptorId];
        uris         = _mirrorLists[mirrorListId];
    }

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId)
        external view returns (string[] memory)
    {
        return _mirrorLists[mirrorListId];
    }
}
