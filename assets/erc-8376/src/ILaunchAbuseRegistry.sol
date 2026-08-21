// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AbuseReport} from "./LaunchAbuseTypes.sol";

/// @title Publication and query of launch abuse reports.
/// @notice A report is a bonded claim by an accountable party, never a fact.
interface ILaunchAbuseRegistry {
    event AbuseReported(
        bytes32 indexed reportId,
        bytes32 indexed launchId,
        bytes32 indexed patternId,
        address detector,
        uint8   abuseScore,
        uint8   confidence
    );
    event ReportRetracted(bytes32 indexed reportId, string reason);
    event DetectorBonded(address indexed detector, uint256 amount);
    event SubmitterSet(address indexed detector, address indexed submitter);
    event DetectorSlashed(address indexed detector, uint256 amount, bytes32 claimId);
    event DetectorPoolFunded(address indexed from, uint256 amount);

    /// @notice Authorize a hot key to submit on the caller's behalf, or revoke
    ///         with the zero address. Rotation retires a compromised key without
    ///         moving the bond or losing the detector's record.
    function setSubmitter(address submitter) external;

    /// @notice The detector a caller submits as.
    function principalOf(address caller) external view returns (address);

    /// @dev reportId MUST equal keccak256(abi.encode(report, principal)).
    function submitReport(AbuseReport calldata report) external returns (bytes32 reportId);

    /// @notice Submit on behalf of `detector`. Caller MUST be the remediation
    ///         contract. Accountability follows the detector, not the caller.
    function submitReportFor(AbuseReport calldata report, address detector)
        external
        returns (bytes32 reportId);

    function retractReport(bytes32 reportId, string calldata reason) external;

    function getReport(bytes32 reportId)
        external
        view
        returns (AbuseReport memory report, address detector, uint64 submittedAt);

    /// @notice Highest-scoring live report for a launch.
    function activeScore(bytes32 launchId)
        external
        view
        returns (uint8 abuseScore, uint8 confidence, bytes32 reportId);

    function minDetectorBond() external view returns (uint256);
    function maxReportAge()    external view returns (uint64);
    function openingBlocks()   external view returns (uint32);
}
