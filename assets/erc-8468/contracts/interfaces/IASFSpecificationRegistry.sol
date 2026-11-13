// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes} from "../ASFTypes.sol";

/// @title  IASFSpecificationRegistry — registry of versioned, content-addressed Safety Specifications
/// @notice A Safety Specification is a reusable arrangement of safety requirements and of the means by
///         which they are enforced and evidenced. Versions are immutable once published; publishing a
///         new version never changes any adoption of an earlier one.
interface IASFSpecificationRegistry /* is IERC165 */ {
    event SpecificationRegistered(bytes32 indexed specId, address indexed publisher, bytes32 salt);
    event SpecificationVersionPublished(
        bytes32 indexed specId, uint32 indexed version, bytes32 contentHash, string locator, bytes32[] requiredProfiles
    );
    event LocatorUpdated(bytes32 indexed specId, uint32 indexed version, string locator);
    event VersionDeprecated(bytes32 indexed specId, uint32 indexed version, bytes32 reasonRef);
    event PublisherChanged(bytes32 indexed specId, address indexed previousPublisher, address indexed newPublisher);

    /// @notice Registers a specification under `msg.sender` and publishes its version 1.
    /// @dev specId = keccak256(abi.encode(block.chainid, address(this), msg.sender, salt)).
    function registerSpecification(
        bytes32 salt,
        bytes32 contentHash,
        string calldata locator,
        bytes32[] calldata requiredProfiles
    ) external returns (bytes32 specId);

    /// @notice Publishes the next version. Only the publisher. Reverts for frozen specifications.
    function publishVersion(
        bytes32 specId,
        bytes32 contentHash,
        string calldata locator,
        bytes32[] calldata requiredProfiles
    ) external returns (uint32 version);

    /// @notice Replaces the locator of a version; the content hash is untouched. Only the publisher.
    function setLocator(bytes32 specId, uint32 version, string calldata locator) external;

    /// @notice Marks a version as deprecated by its publisher. Informative: bindings are unaffected.
    function deprecateVersion(bytes32 specId, uint32 version, bytes32 reasonRef) external;

    /// @notice Transfers or renounces publishing control. address(0) freezes the specification.
    function setPublisher(bytes32 specId, address newPublisher) external;

    function computeSpecId(address publisher, bytes32 salt) external view returns (bytes32);
    function specificationExists(bytes32 specId) external view returns (bool);
    function publisherOf(bytes32 specId) external view returns (address);
    function latestVersion(bytes32 specId) external view returns (uint32);
    function versionOf(bytes32 specId, uint32 version) external view returns (ASFTypes.SpecificationVersion memory);
}
