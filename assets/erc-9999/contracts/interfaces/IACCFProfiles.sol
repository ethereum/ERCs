// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes} from "./ACCFTypes.sol";

/// @title IACCFProfiles
/// @notice Completeness Profiles and the Baseline class table they are checked against.
interface IACCFProfiles {
    event ProfilePublished(
        bytes32 indexed profileId,
        address indexed publisher,
        bytes32 contentHash,
        bool baseline,
        bytes32 supersedes,
        uint16 count,
        string uri
    );
    event ProfileDeprecated(bytes32 indexed profileId, bytes32 reasonHash);

    /// @notice Publishes an immutable profile. With `baseline` set, the call reverts unless every Baseline
    ///         class is implemented by an unconditional requirement on the class's axis whose dependency mask
    ///         includes the class's minimum.
    function publish(
        bytes32 contentHash,
        string calldata uri,
        bool baseline,
        bytes32 supersedes,
        ACCFTypes.Requirement[] calldata requirements
    ) external returns (bytes32 profileId);

    /// @notice Marks a profile as deprecated. Publisher only. Nothing recorded under the profile changes.
    function deprecate(bytes32 profileId, bytes32 reasonHash) external;

    function profileExists(bytes32 profileId) external view returns (bool);
    function profileOf(bytes32 profileId) external view returns (ACCFTypes.Profile memory);
    function requirementOf(bytes32 profileId, uint256 index) external view returns (ACCFTypes.Requirement memory);
    function requirementsOf(bytes32 profileId) external view returns (ACCFTypes.Requirement[] memory);

    /// @notice Checks that every requirement in `coverage` is on `axis` and returns the union of their
    ///         minimum dependency masks and whether all of them are conditional.
    function resolveCoverage(bytes32 profileId, uint8 axis, uint256 coverage)
        external
        view
        returns (uint256 dependencies, bool allConditional);

    function computeProfileId(address publisher, bytes32 contentHash) external view returns (bytes32);

    /// @notice Version of the Baseline class table this registry checks profiles against.
    function baselineVersion() external pure returns (uint32);
    function baselineClassCount() external pure returns (uint8);

    /// @notice Axis and minimum dependency mask of Baseline class `classId` (1..baselineClassCount()).
    function baselineClass(uint8 classId) external pure returns (uint8 axis, uint256 dependencies);
}
