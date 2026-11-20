// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes} from "./ASFTypes.sol";
import {ASFErrors} from "./ASFErrors.sol";
import {IASFSpecificationRegistry} from "./interfaces/IASFSpecificationRegistry.sol";

/// @title  ASFSpecificationRegistry — reference implementation of the Safety Specification registry
/// @notice Anyone can register a specification; the registering account is its publisher. A version is
///         a content hash plus a locator; versions are immutable and numbered from 1. Deprecation is a
///         signal by the publisher and changes nothing for adopters.
contract ASFSpecificationRegistry is IASFSpecificationRegistry {
    struct Spec {
        address publisher;
        bool exists;
        uint32 latest;
        mapping(uint32 => ASFTypes.SpecificationVersion) versions;
    }

    mapping(bytes32 => Spec) private _specs;

    // ------------------------------------------------------------------------------ ERC-165

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IASFSpecificationRegistry).interfaceId;
    }

    // ------------------------------------------------------------------------------- writes

    function registerSpecification(
        bytes32 salt,
        bytes32 contentHash,
        string calldata locator,
        bytes32[] calldata requiredProfiles
    ) external returns (bytes32 specId) {
        specId = computeSpecId(msg.sender, salt);
        Spec storage s = _specs[specId];
        if (s.exists) revert ASFErrors.SpecificationExists();
        s.exists = true;
        s.publisher = msg.sender;
        emit SpecificationRegistered(specId, msg.sender, salt);
        _publish(s, specId, contentHash, locator, requiredProfiles);
    }

    function publishVersion(
        bytes32 specId,
        bytes32 contentHash,
        string calldata locator,
        bytes32[] calldata requiredProfiles
    ) external returns (uint32 version) {
        Spec storage s = _publisherOnly(specId);
        version = _publish(s, specId, contentHash, locator, requiredProfiles);
    }

    function setLocator(bytes32 specId, uint32 version, string calldata locator) external {
        Spec storage s = _publisherOnly(specId);
        if (version == 0 || version > s.latest) revert ASFErrors.UnknownVersion();
        s.versions[version].locator = locator;
        emit LocatorUpdated(specId, version, locator);
    }

    function deprecateVersion(bytes32 specId, uint32 version, bytes32 reasonRef) external {
        Spec storage s = _publisherOnly(specId);
        if (version == 0 || version > s.latest) revert ASFErrors.UnknownVersion();
        s.versions[version].deprecated = true;
        emit VersionDeprecated(specId, version, reasonRef);
    }

    function setPublisher(bytes32 specId, address newPublisher) external {
        Spec storage s = _publisherOnly(specId);
        address previous = s.publisher;
        s.publisher = newPublisher;
        emit PublisherChanged(specId, previous, newPublisher);
    }

    // -------------------------------------------------------------------------------- views

    function computeSpecId(address publisher, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), publisher, salt));
    }

    function specificationExists(bytes32 specId) external view returns (bool) {
        return _specs[specId].exists;
    }

    function publisherOf(bytes32 specId) external view returns (address) {
        if (!_specs[specId].exists) revert ASFErrors.UnknownSpecification();
        return _specs[specId].publisher;
    }

    function latestVersion(bytes32 specId) external view returns (uint32) {
        if (!_specs[specId].exists) revert ASFErrors.UnknownSpecification();
        return _specs[specId].latest;
    }

    function versionOf(bytes32 specId, uint32 version) external view returns (ASFTypes.SpecificationVersion memory) {
        Spec storage s = _specs[specId];
        if (!s.exists) revert ASFErrors.UnknownSpecification();
        if (version == 0 || version > s.latest) revert ASFErrors.UnknownVersion();
        return s.versions[version];
    }

    // ----------------------------------------------------------------------------- internal

    function _publisherOnly(bytes32 specId) private view returns (Spec storage s) {
        s = _specs[specId];
        if (!s.exists) revert ASFErrors.UnknownSpecification();
        if (s.publisher == address(0)) revert ASFErrors.SpecificationFrozen();
        if (s.publisher != msg.sender) revert ASFErrors.NotPublisher();
    }

    function _publish(
        Spec storage s,
        bytes32 specId,
        bytes32 contentHash,
        string calldata locator,
        bytes32[] calldata requiredProfiles
    ) private returns (uint32 version) {
        if (contentHash == bytes32(0)) revert ASFErrors.ZeroContentHash();
        version = ++s.latest;
        ASFTypes.SpecificationVersion storage v = s.versions[version];
        v.contentHash = contentHash;
        v.locator = locator;
        v.publishedAt = uint64(block.timestamp);
        v.requiredProfiles = requiredProfiles;
        emit SpecificationVersionPublished(specId, version, contentHash, locator, requiredProfiles);
    }
}
