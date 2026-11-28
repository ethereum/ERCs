// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "./interfaces/ACCFTypes.sol";
import {IACCFProfiles} from "./interfaces/IACCFProfiles.sol";
import {ACCFBaseline} from "./ACCFBaseline.sol";
import {ACCFErrors} from "./ACCFErrors.sol";

/// @title ACCFProfileRegistry
/// @notice Reference registry of Completeness Profiles. A profile that claims the Baseline Requirements is
///         accepted only when it covers every Baseline class without weakening it.
contract ACCFProfileRegistry is IACCFProfiles, ACCFErrors {
    uint256 private constant MAX_REQUIREMENTS = 256;

    mapping(bytes32 => T.Profile) private _profiles;
    mapping(bytes32 => T.Requirement[]) private _requirements;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACCFProfiles).interfaceId || interfaceId == 0x01ffc9a7; // ERC-165
    }

    function publish(
        bytes32 contentHash,
        string calldata uri,
        bool baseline,
        bytes32 supersedes,
        T.Requirement[] calldata requirements
    ) external returns (bytes32 profileId) {
        uint256 count = requirements.length;
        if (count == 0 || count > MAX_REQUIREMENTS) revert TooManyRequirements();
        if (contentHash == bytes32(0)) revert InvalidRequirement(0);
        profileId = computeProfileId(msg.sender, contentHash);
        T.Profile storage p = _profiles[profileId];
        if (p.publishedAt != 0) revert ProfileExists(profileId);
        if (supersedes != bytes32(0) && _profiles[supersedes].publisher != msg.sender) {
            revert NotPublisher(supersedes, msg.sender);
        }

        uint256 covered; // bit c set: Baseline class c is implemented
        uint256[3] memory axisMasks;
        uint256 conditionalMask;
        T.Requirement[] storage stored = _requirements[profileId];
        for (uint256 i = 0; i < count; ++i) {
            T.Requirement calldata r = requirements[i];
            if (r.axis > T.AXIS_ECONOMIC || r.dependencies == 0 || r.dependencies & ~T.DEPENDENCY_MASK != 0) {
                revert InvalidRequirement(i);
            }
            if (r.baselineClass != 0) {
                if (r.baselineClass > ACCFBaseline.CLASS_COUNT) revert InvalidRequirement(i);
                (uint8 axis, uint256 minimum) = ACCFBaseline.classOf(r.baselineClass);
                if (r.axis != axis) revert InvalidRequirement(i);
                // a requirement cannot stand for a class and ask for less than the class does
                if (r.conditional) revert BaselineConditional(i, r.baselineClass);
                if (r.dependencies & minimum != minimum) revert BaselineDependencyOmitted(i, r.baselineClass);
                covered |= uint256(1) << r.baselineClass;
            }
            axisMasks[r.axis] |= uint256(1) << i;
            if (r.conditional) conditionalMask |= uint256(1) << i;
            stored.push(r);
        }
        if (baseline) {
            for (uint8 c = 1; c <= ACCFBaseline.CLASS_COUNT; ++c) {
                if (covered & (uint256(1) << c) == 0) revert BaselineClassMissing(c);
            }
        }

        p.publisher = msg.sender;
        p.contentHash = contentHash;
        p.supersedes = supersedes;
        p.baseline = baseline;
        p.count = uint16(count);
        p.publishedAt = uint48(block.timestamp);
        p.axisMasks = axisMasks;
        p.conditionalMask = conditionalMask;
        emit ProfilePublished(profileId, msg.sender, contentHash, baseline, supersedes, uint16(count), uri);
    }

    function deprecate(bytes32 profileId, bytes32 reasonHash) external {
        T.Profile storage p = _profiles[profileId];
        if (p.publishedAt == 0) revert UnknownProfile(profileId);
        if (p.publisher != msg.sender) revert NotPublisher(profileId, msg.sender);
        p.deprecated = true;
        emit ProfileDeprecated(profileId, reasonHash);
    }

    function profileExists(bytes32 profileId) external view returns (bool) {
        return _profiles[profileId].publishedAt != 0;
    }

    function profileOf(bytes32 profileId) external view returns (T.Profile memory) {
        if (_profiles[profileId].publishedAt == 0) revert UnknownProfile(profileId);
        return _profiles[profileId];
    }

    function requirementOf(bytes32 profileId, uint256 index) external view returns (T.Requirement memory) {
        return _requirements[profileId][index];
    }

    function requirementsOf(bytes32 profileId) external view returns (T.Requirement[] memory) {
        return _requirements[profileId];
    }

    function resolveCoverage(bytes32 profileId, uint8 axis, uint256 coverage)
        external
        view
        returns (uint256 dependencies, bool allConditional)
    {
        T.Profile storage p = _profiles[profileId];
        if (p.publishedAt == 0) revert UnknownProfile(profileId);
        if (axis > T.AXIS_ECONOMIC || coverage == 0 || coverage & ~p.axisMasks[axis] != 0) revert CoverageOffAxis(coverage);
        allConditional = coverage & ~p.conditionalMask == 0;
        T.Requirement[] storage stored = _requirements[profileId];
        for (uint256 i = 0; coverage >> i != 0; ++i) {
            if ((coverage >> i) & 1 == 1) dependencies |= stored[i].dependencies;
        }
    }

    function computeProfileId(address publisher, bytes32 contentHash) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), publisher, contentHash));
    }

    function baselineVersion() external pure returns (uint32) {
        return ACCFBaseline.VERSION;
    }

    function baselineClassCount() external pure returns (uint8) {
        return ACCFBaseline.CLASS_COUNT;
    }

    function baselineClass(uint8 classId) external pure returns (uint8 axis, uint256 dependencies) {
        if (classId == 0 || classId > ACCFBaseline.CLASS_COUNT) revert InvalidRequirement(classId);
        return ACCFBaseline.classOf(classId);
    }
}
