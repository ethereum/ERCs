// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    IERC8258,
    MultiDelegatedAttestationRequest,
    MultiDelegatedRevocationRequest
} from "./IERC8258.sol";

/// @dev Minimal EAS interface required by the registry.
interface IEAS {
    struct Attestation {
        bytes32 uid;
        bytes32 schema;
        uint64  time;
        uint64  expirationTime;
        uint64  revocationTime;
        bytes32 refUID;
        address attester;
        address recipient;
        bool    revocable;
        bytes   data;
    }

    function getAttestation(bytes32 uid)
        external view returns (Attestation memory);

    function multiAttestByDelegation(
        MultiDelegatedAttestationRequest[] calldata multiDelegatedRequests
    ) external payable returns (bytes32[] memory);

    function multiRevokeByDelegation(
        MultiDelegatedRevocationRequest[] calldata multiDelegatedRequests
    ) external payable;
}

/// @title ERC8258Registry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IERC8258.
contract ERC8258Registry is IERC8258 {

    // -------------------------------------------------------------------------
    // Context type tags
    // -------------------------------------------------------------------------

    bytes32 public constant CONTEXT_TAG_CONTRACT =
        keccak256("erc7730.context.contract");

    bytes32 public constant CONTEXT_TAG_EIP712_DEP =
        keccak256("erc7730.context.eip712.deployment");

    bytes32 public constant CONTEXT_TAG_EIP712_DS =
        keccak256("erc7730.context.eip712.domainseparator");

    bytes32 public constant CONTEXT_TAG_FACTORY =
        keccak256("erc7730.context.factory");

    // -------------------------------------------------------------------------
    // Immutable configuration
    // -------------------------------------------------------------------------

    IEAS    public immutable eas;
    bytes32 public immutable easSchemaUID;

    constructor(address _eas, bytes32 _easSchemaUID) {
        eas          = IEAS(_eas);
        easSchemaUID = _easSchemaUID;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    // Active slot: one descriptor per (attester, contextId).
    mapping(address => mapping(bytes32 => bytes32)) private _descriptorId;
    mapping(address => mapping(bytes32 => bytes32)) private _attestationId;

    // URI hints, per (attester, descriptorId).
    mapping(address => mapping(bytes32 => string[])) private _attesterURIs;

    // URI write guard: set to true when an attester has attested a descriptorId.
    mapping(address => mapping(bytes32 => bool)) private _hasAttested;

    // -------------------------------------------------------------------------
    // createDescriptorAttestation
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8258
    function createDescriptorAttestation(
        bytes32[]                          calldata contextIds,
        bytes32                                     descriptorId,
        string[]                           calldata uris,
        MultiDelegatedAttestationRequest[] calldata attestations,
        MultiDelegatedRevocationRequest[]  calldata revocations
    ) external returns (bytes32 attestationId) {
        if (descriptorId == bytes32(0)) revert ZeroDescriptorId();
        if (contextIds.length == 0)    revert EmptyContextIds();
        if (attestations.length == 0 || attestations[0].data.length == 0)
            revert EmptyAttestations();

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
            eas.multiRevokeByDelegation(revocations);
        }

        // Create new attestations; capture the active UID (first in flat return).
        bytes32[] memory uids = eas.multiAttestByDelegation(attestations);
        attestationId = uids[0];

        // Mark attester as eligible to update URIs for this descriptorId.
        _hasAttested[attester][descriptorId] = true;

        // Set URI list (replaces any prior list).
        if (uris.length > 0) {
            _attesterURIs[attester][descriptorId] = uris;
            emit URIsUpdated(attester, descriptorId);
        }

        // Update active slot for each contextId.
        for (uint256 i; i < contextIds.length; ++i) {
            bytes32 cid  = contextIds[i];
            bytes32 prev = _descriptorId[attester][cid];
            _descriptorId[attester][cid]  = descriptorId;
            _attestationId[attester][cid] = attestationId;
            emit AttesterEndorsementUpdated(attester, cid, prev, descriptorId, attestationId);
        }
    }

    // -------------------------------------------------------------------------
    // URI management
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8258
    function updateURIs(bytes32 descriptorId, string[] calldata uris) external {
        if (!_hasAttested[msg.sender][descriptorId])
            revert NotActiveAttester(descriptorId, msg.sender);
        _attesterURIs[msg.sender][descriptorId] = uris;
        emit URIsUpdated(msg.sender, descriptorId);
    }

    // -------------------------------------------------------------------------
    // Storage cleanup
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8258
    function clearRevokedEndorsement(address attester, bytes32 contextId) external {
        bytes32 uid = _attestationId[attester][contextId];
        if (uid == bytes32(0)) return;

        IEAS.Attestation memory att = eas.getAttestation(uid);
        require(att.revocationTime != 0, "ERC8258: attestation not revoked on EAS");

        bytes32 prev = _descriptorId[attester][contextId];
        _descriptorId[attester][contextId]  = bytes32(0);
        _attestationId[attester][contextId] = bytes32(0);

        emit AttesterEndorsementUpdated(attester, contextId, prev, bytes32(0), bytes32(0));
    }

    // -------------------------------------------------------------------------
    // Queries
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8258
    function getDescriptors(
        address[] calldata attesters,
        bytes32            contextId
    ) external view returns (
        bytes32[] memory descriptorIds,
        bytes32[] memory attestationIds
    ) {
        uint256 n    = attesters.length;
        descriptorIds   = new bytes32[](n);
        attestationIds  = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            descriptorIds[i]  = _descriptorId[attesters[i]][contextId];
            attestationIds[i] = _attestationId[attesters[i]][contextId];
        }
    }

    /// @inheritdoc IERC8258
    function getURIs(address attester, bytes32 descriptorId)
        external view returns (string[] memory)
    {
        return _attesterURIs[attester][descriptorId];
    }

    // -------------------------------------------------------------------------
    // Context ID derivation helpers (pure)
    // -------------------------------------------------------------------------

    /// @inheritdoc IERC8258
    function computeContractContextId(uint256 chainId, address contractAddress)
        external pure returns (bytes32)
    {
        return keccak256(abi.encode(CONTEXT_TAG_CONTRACT, chainId, contractAddress));
    }

    /// @inheritdoc IERC8258
    function computeEIP712DeploymentContextId(uint256 chainId, address verifyingContract)
        external pure returns (bytes32)
    {
        return keccak256(abi.encode(CONTEXT_TAG_EIP712_DEP, chainId, verifyingContract));
    }

    /// @inheritdoc IERC8258
    function computeEIP712DomainSeparatorContextId(bytes32 domainSeparator)
        external pure returns (bytes32)
    {
        return keccak256(abi.encode(CONTEXT_TAG_EIP712_DS, domainSeparator));
    }

    /// @inheritdoc IERC8258
    function computeFactoryContextId(
        uint256 chainId,
        address factoryAddress,
        bytes32 deployEventTopic
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(CONTEXT_TAG_FACTORY, chainId, factoryAddress, deployEventTopic));
    }
}
