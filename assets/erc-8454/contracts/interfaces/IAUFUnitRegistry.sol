// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {UnitRef, AckKind} from "../AUFTypes.sol";

/// @title AIFi Unit Registry interface (Section 4)
/// @notice Keeps Units, their versioned Unit Definitions (by boundary hash), structural containment
///         of pinned versions, definition control and typed acknowledgments.
interface IAUFUnitRegistry {
    event UnitRegistered(uint256 indexed unitId, address indexed controller, bytes32 boundaryHash, string descriptorURI);
    event VersionPublished(
        uint256 indexed unitId, uint32 indexed version, bytes32 boundaryHash, string descriptorURI, uint256 containsCount
    );
    event ControllerChanged(uint256 indexed unitId, address indexed previousController, address indexed newController);
    event Acknowledged(
        uint256 indexed unitId, uint32 indexed version, bytes32 indexed elementId, AckKind kind, address account
    );
    event AcknowledgmentWithdrawn(
        uint256 indexed unitId, uint32 indexed version, bytes32 indexed elementId, AckKind kind, address account
    );

    /// @notice Registers a Unit and publishes version 1.
    /// @param controller Definition Controller; address(0) registers a frozen Unit.
    /// @param boundaryHash Canonical hash of the Unit Definition (Section 3.2).
    /// @param descriptorURI Location of the Unit Definition.
    /// @param contains Unit versions referenced by `contains` relations of the definition.
    function registerUnit(address controller, bytes32 boundaryHash, string calldata descriptorURI, UnitRef[] calldata contains)
        external
        returns (uint256 unitId);

    /// @notice Publishes a new version. Only the Definition Controller. Reverts for frozen Units.
    function publishVersion(uint256 unitId, bytes32 boundaryHash, string calldata descriptorURI, UnitRef[] calldata contains)
        external
        returns (uint32 version);

    /// @notice Transfers or renounces definition control. address(0) freezes the Unit permanently.
    function setController(uint256 unitId, address newController) external;

    /// @notice Records an acknowledgment by msg.sender for an element of a Unit version.
    function acknowledge(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind) external;

    /// @notice Withdraws an acknowledgment previously recorded by msg.sender.
    function withdrawAcknowledgment(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind) external;

    function unitCount() external view returns (uint256);
    function controllerOf(uint256 unitId) external view returns (address);
    function isFrozen(uint256 unitId) external view returns (bool);
    function latestVersion(uint256 unitId) external view returns (uint32);
    function versionOf(uint256 unitId, uint32 version)
        external
        view
        returns (bytes32 boundaryHash, string memory descriptorURI, uint64 publishedAt, uint256 containsCount);
    function containedAt(uint256 unitId, uint32 version, uint256 index) external view returns (UnitRef memory);
    function acknowledgedAt(uint256 unitId, uint32 version, bytes32 elementId, AckKind kind, address account)
        external
        view
        returns (uint64);
}
