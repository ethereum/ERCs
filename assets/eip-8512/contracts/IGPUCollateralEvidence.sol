// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IGPUCollateralEvidence {
    /// A servicer's assertion about one period of one collateral.
    struct Report {
        uint64 periodStart;
        uint64 periodEnd;
        uint32 devicesReported; // devices with at least one committed statement
        uint32 devicesAttested; // devices with a committed hw-attestation statement claiming checksPassed > 0
        uint64 servedSeconds;   // GPU-seconds, summed over the selected statement of each reported device
        uint64 missedSeconds;
        uint64 unknownSeconds;
        bytes32 statementRoot;
    }

    event DevicePledged(address indexed servicer, bytes32 indexed collateralId, bytes32 indexed deviceKey);
    event DeviceReleased(address indexed servicer, bytes32 indexed collateralId, bytes32 indexed deviceKey);
    event Reported(address indexed servicer, bytes32 indexed collateralId, Report report, string uri);

    /// Pledge devices under the caller's collateral.
    function pledge(bytes32 collateralId, bytes32[] calldata deviceKeys) external;

    /// Release devices from the caller's collateral.
    function release(bytes32 collateralId, bytes32[] calldata deviceKeys) external;

    /// Record the caller's report for one period of its collateral.
    /// `uri` locates the statement envelopes the report commits to.
    function report(bytes32 collateralId, Report calldata r, string calldata uri) external;

    /// Number of active pledges of a device key, across all servicers and collateral.
    function pledgeCount(bytes32 deviceKey) external view returns (uint256);

    /// The active pledge of a device key at `index`, in no defined order.
    function pledgeAt(bytes32 deviceKey, uint256 index)
        external view returns (address servicer, bytes32 collateralId, uint64 pledgedAt);

    /// Whether `deviceKey` is actively pledged under the servicer's collateral.
    function isPledged(address servicer, bytes32 collateralId, bytes32 deviceKey) external view returns (bool);

    /// Number of devices actively pledged under the servicer's collateral.
    function deviceCount(address servicer, bytes32 collateralId) external view returns (uint256);

    /// The latest report under the servicer's collateral. `reportedAt` is zero when there is none.
    function latestReport(address servicer, bytes32 collateralId)
        external view returns (Report memory r, uint64 reportedAt);
}
