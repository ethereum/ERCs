// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IGPUCollateralEvidence} from "./IGPUCollateralEvidence.sol";

/// @title GPUCollateralEvidence
/// @notice Minimal, permissionless, non-upgradeable ERC-8512 pledge index and report registry.
contract GPUCollateralEvidence is IGPUCollateralEvidence {
    error AlreadyPledged(bytes32 deviceKey);
    error NotPledged(bytes32 deviceKey);
    error IndexOutOfBounds(uint256 index, uint256 length);
    error InvalidPeriod();
    error InvalidDeviceCounts();
    error InvalidSecondsTotal();
    error OverlappingPeriod();

    struct Pledge {
        address servicer;
        bytes32 collateralId;
        uint64 pledgedAt;
    }

    struct StoredReport {
        Report data;
        uint64 reportedAt;
    }

    mapping(bytes32 => Pledge[]) private _pledges;
    mapping(address => mapping(bytes32 => mapping(bytes32 => uint256))) private _pledgeIndexPlusOne;
    mapping(address => mapping(bytes32 => uint256)) private _deviceCount;
    mapping(address => mapping(bytes32 => StoredReport)) private _latestReports;

    /// @inheritdoc IGPUCollateralEvidence
    function pledge(bytes32 collateralId, bytes32[] calldata deviceKeys) external {
        uint256 len = deviceKeys.length;
        uint64 ts = uint64(block.timestamp);
        mapping(bytes32 => uint256) storage indexMap = _pledgeIndexPlusOne[msg.sender][collateralId];

        for (uint256 i = 0; i < len; ++i) {
            bytes32 key = deviceKeys[i];
            if (indexMap[key] != 0) revert AlreadyPledged(key);

            Pledge[] storage list = _pledges[key];
            list.push(Pledge({servicer: msg.sender, collateralId: collateralId, pledgedAt: ts}));
            indexMap[key] = list.length; // 1-based index

            emit DevicePledged(msg.sender, collateralId, key);
        }

        _deviceCount[msg.sender][collateralId] += len;
    }

    /// @inheritdoc IGPUCollateralEvidence
    function release(bytes32 collateralId, bytes32[] calldata deviceKeys) external {
        uint256 len = deviceKeys.length;
        mapping(bytes32 => uint256) storage indexMap = _pledgeIndexPlusOne[msg.sender][collateralId];

        for (uint256 i = 0; i < len; ++i) {
            bytes32 key = deviceKeys[i];
            uint256 idxPlusOne = indexMap[key];
            if (idxPlusOne == 0) revert NotPledged(key);

            Pledge[] storage list = _pledges[key];
            uint256 idx = idxPlusOne - 1;
            uint256 lastIdx = list.length - 1;

            if (idx != lastIdx) {
                Pledge memory moved = list[lastIdx];
                list[idx] = moved;
                _pledgeIndexPlusOne[moved.servicer][moved.collateralId][key] = idx + 1;
            }

            list.pop();
            delete indexMap[key];

            emit DeviceReleased(msg.sender, collateralId, key);
        }

        _deviceCount[msg.sender][collateralId] -= len;
    }

    /// @inheritdoc IGPUCollateralEvidence
    function report(bytes32 collateralId, Report calldata r, string calldata uri) external {
        // Rule 1: periodStart < periodEnd <= block.timestamp
        if (r.periodStart >= r.periodEnd || uint256(r.periodEnd) > block.timestamp) {
            revert InvalidPeriod();
        }

        // Rule 2: devicesAttested <= devicesReported <= deviceCount(msg.sender, collateralId)
        uint256 activeDevices = _deviceCount[msg.sender][collateralId];
        if (uint256(r.devicesAttested) > uint256(r.devicesReported) || uint256(r.devicesReported) > activeDevices) {
            revert InvalidDeviceCounts();
        }

        // Rule 3: servedSeconds + missedSeconds + unknownSeconds == devicesReported * (periodEnd - periodStart)
        uint256 lhs = uint256(r.servedSeconds) + uint256(r.missedSeconds) + uint256(r.unknownSeconds);
        uint256 rhs = uint256(r.devicesReported) * (uint256(r.periodEnd) - uint256(r.periodStart));
        if (lhs != rhs) {
            revert InvalidSecondsTotal();
        }

        // Rule 4: first report, non-overlapping subsequent period, or exact period replacement
        StoredReport storage latest = _latestReports[msg.sender][collateralId];
        if (latest.reportedAt != 0) {
            bool isNext = r.periodStart >= latest.data.periodEnd;
            bool isReplacement = r.periodStart == latest.data.periodStart && r.periodEnd == latest.data.periodEnd;
            if (!isNext && !isReplacement) {
                revert OverlappingPeriod();
            }
        }

        latest.data = r;
        latest.reportedAt = uint64(block.timestamp);

        emit Reported(msg.sender, collateralId, r, uri);
    }

    /// @inheritdoc IGPUCollateralEvidence
    function pledgeCount(bytes32 deviceKey) external view returns (uint256) {
        return _pledges[deviceKey].length;
    }

    /// @inheritdoc IGPUCollateralEvidence
    function pledgeAt(bytes32 deviceKey, uint256 index)
        external
        view
        returns (address servicer, bytes32 collateralId, uint64 pledgedAt)
    {
        Pledge[] storage list = _pledges[deviceKey];
        if (index >= list.length) revert IndexOutOfBounds(index, list.length);
        Pledge storage p = list[index];
        return (p.servicer, p.collateralId, p.pledgedAt);
    }

    /// @inheritdoc IGPUCollateralEvidence
    function isPledged(address servicer, bytes32 collateralId, bytes32 deviceKey) external view returns (bool) {
        return _pledgeIndexPlusOne[servicer][collateralId][deviceKey] != 0;
    }

    /// @inheritdoc IGPUCollateralEvidence
    function deviceCount(address servicer, bytes32 collateralId) external view returns (uint256) {
        return _deviceCount[servicer][collateralId];
    }

    /// @inheritdoc IGPUCollateralEvidence
    function latestReport(address servicer, bytes32 collateralId)
        external
        view
        returns (Report memory r, uint64 reportedAt)
    {
        StoredReport storage latest = _latestReports[servicer][collateralId];
        return (latest.data, latest.reportedAt);
    }
}
