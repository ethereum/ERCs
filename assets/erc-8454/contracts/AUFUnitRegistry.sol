// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAUFUnitRegistry} from "./interfaces/IAUFUnitRegistry.sol";
import {UnitRef, AckKind} from "./AUFTypes.sol";
import "./AUFErrors.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title AIFi Unit Registry (reference implementation)
/// @notice Reference implementation of the Unit Registry of the AIFi Unit Framework.
/// @dev Versions are immutable. Containment is acyclic by construction because a version can only
///      contain versions that already exist and never a version of its own Unit (Section 3.6).
contract AUFUnitRegistry is IAUFUnitRegistry, IERC165 {
    struct UnitData {
        address controller;
        uint32 latestVersion;
        uint64 createdAt;
    }

    struct VersionData {
        bytes32 boundaryHash;
        uint64 publishedAt;
        string descriptorURI;
        UnitRef[] contains;
    }

    uint256 private _unitCount;
    mapping(uint256 => UnitData) private _units;
    mapping(uint256 => mapping(uint32 => VersionData)) private _versions;
    // unitId => version => elementId => ackKind => account => timestamp
    mapping(uint256 => mapping(uint32 => mapping(bytes32 => mapping(uint8 => mapping(address => uint64))))) private _acks;

    // ---------------------------------------------------------------- writes

    /// @inheritdoc IAUFUnitRegistry
    function registerUnit(
        address controller,
        bytes32 boundaryHash,
        string calldata descriptorURI,
        UnitRef[] calldata contains
    ) external returns (uint256 unitId) {
        unitId = ++_unitCount;
        UnitData storage u = _units[unitId];
        u.controller = controller;
        u.createdAt = uint64(block.timestamp);
        emit UnitRegistered(unitId, controller, boundaryHash, descriptorURI);
        _publish(unitId, boundaryHash, descriptorURI, contains);
    }

    /// @inheritdoc IAUFUnitRegistry
    function publishVersion(
        uint256 unitId,
        bytes32 boundaryHash,
        string calldata descriptorURI,
        UnitRef[] calldata contains
    ) external returns (uint32 version) {
        _requireController(unitId);
        version = _publish(unitId, boundaryHash, descriptorURI, contains);
    }

    /// @inheritdoc IAUFUnitRegistry
    function setController(uint256 unitId, address newController) external {
        _requireController(unitId);
        address previous = _units[unitId].controller;
        _units[unitId].controller = newController;
        emit ControllerChanged(unitId, previous, newController);
    }

    /// @inheritdoc IAUFUnitRegistry
    function acknowledge(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind) external {
        _requireVersion(unitId, version);
        if (kind == AckKind.None) revert AUF_InvalidAckKind();
        _acks[unitId][version][elementId][uint8(kind)][msg.sender] = uint64(block.timestamp);
        emit Acknowledged(unitId, version, elementId, kind, msg.sender);
    }

    /// @inheritdoc IAUFUnitRegistry
    function withdrawAcknowledgment(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind) external {
        if (_acks[unitId][version][elementId][uint8(kind)][msg.sender] == 0) revert AUF_NoAcknowledgment();
        _acks[unitId][version][elementId][uint8(kind)][msg.sender] = 0;
        emit AcknowledgmentWithdrawn(unitId, version, elementId, kind, msg.sender);
    }

    // ---------------------------------------------------------------- views

    /// @inheritdoc IAUFUnitRegistry
    function unitCount() external view returns (uint256) {
        return _unitCount;
    }

    /// @inheritdoc IAUFUnitRegistry
    function controllerOf(uint256 unitId) external view returns (address) {
        _requireUnit(unitId);
        return _units[unitId].controller;
    }

    /// @inheritdoc IAUFUnitRegistry
    function isFrozen(uint256 unitId) external view returns (bool) {
        _requireUnit(unitId);
        return _units[unitId].controller == address(0);
    }

    /// @inheritdoc IAUFUnitRegistry
    function latestVersion(uint256 unitId) external view returns (uint32) {
        _requireUnit(unitId);
        return _units[unitId].latestVersion;
    }

    /// @inheritdoc IAUFUnitRegistry
    function versionOf(uint256 unitId, uint32 version)
        external
        view
        returns (bytes32 boundaryHash, string memory descriptorURI, uint64 publishedAt, uint256 containsCount)
    {
        _requireVersion(unitId, version);
        VersionData storage v = _versions[unitId][version];
        return (v.boundaryHash, v.descriptorURI, v.publishedAt, v.contains.length);
    }

    /// @inheritdoc IAUFUnitRegistry
    function containedAt(uint256 unitId, uint32 version, uint256 index) external view returns (UnitRef memory) {
        _requireVersion(unitId, version);
        return _versions[unitId][version].contains[index];
    }

    /// @inheritdoc IAUFUnitRegistry
    function acknowledgedAt(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind, address account)
        external
        view
        returns (uint64)
    {
        return _acks[unitId][version][elementId][uint8(kind)][account];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAUFUnitRegistry).interfaceId;
    }

    // ---------------------------------------------------------------- internals

    function _publish(uint256 unitId, bytes32 boundaryHash, string calldata descriptorURI, UnitRef[] calldata contains)
        internal
        returns (uint32 version)
    {
        if (boundaryHash == bytes32(0)) revert AUF_ZeroHash();
        UnitData storage u = _units[unitId];
        version = ++u.latestVersion;
        VersionData storage v = _versions[unitId][version];
        v.boundaryHash = boundaryHash;
        v.publishedAt = uint64(block.timestamp);
        v.descriptorURI = descriptorURI;
        for (uint256 i = 0; i < contains.length; i++) {
            UnitRef calldata r = contains[i];
            if (r.unitId == unitId) revert AUF_SelfContainment(unitId);
            _requireVersion(r.unitId, r.version);
            v.contains.push(r);
        }
        emit VersionPublished(unitId, version, boundaryHash, descriptorURI, contains.length);
    }

    function _requireUnit(uint256 unitId) internal view {
        if (unitId == 0 || unitId > _unitCount) revert AUF_UnitNotFound(unitId);
    }

    function _requireVersion(uint256 unitId, uint32 version) internal view {
        _requireUnit(unitId);
        if (version == 0 || version > _units[unitId].latestVersion) revert AUF_VersionNotFound(unitId, version);
    }

    function _requireController(uint256 unitId) internal view {
        _requireUnit(unitId);
        address controller = _units[unitId].controller;
        if (controller == address(0)) revert AUF_Frozen(unitId);
        if (msg.sender != controller) revert AUF_NotController(unitId, msg.sender);
    }
}
