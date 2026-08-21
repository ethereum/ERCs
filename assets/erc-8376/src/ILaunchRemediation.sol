// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AbuseReport, ClaimStatus, ContainmentAction} from "./LaunchAbuseTypes.sol";

/// @title Bonds, claims, adjudication and refund execution.
interface ILaunchRemediation {
    event BondPosted(bytes32 indexed launchId, uint256 amount);
    event BondReleased(bytes32 indexed launchId, uint256 amount);
    event BondSlashed(bytes32 indexed launchId, uint256 amount, bytes32 claimId);
    event ClaimOpened(bytes32 indexed claimId, bytes32 indexed launchId, address claimant, uint256 bond);
    event ClaimContested(bytes32 indexed claimId, address respondent, string evidenceURI);
    event ClaimSettled(bytes32 indexed claimId, uint256 amount);
    event ClaimAdjudicated(bytes32 indexed claimId, ClaimStatus outcome, uint256 award);
    event RemedyExecuted(bytes32 indexed claimId, uint256 fromEscrow, uint256 fromBond);
    event ContainmentApplied(bytes32 indexed launchId, ContainmentAction action, uint64 until);
    event DetectorRewarded(bytes32 indexed claimId, address indexed detector, uint256 amount);

    function postBond(bytes32 launchId) external payable;
    function requiredBond(uint256 targetRaise) external view returns (uint256);

    function openClaim(bytes32 launchId, bytes32 reportId, string calldata evidenceURI)
        external
        payable
        returns (bytes32 claimId);

    /// @notice Register a report and open a claim atomically, so the deployer
    ///         cannot act in the gap between submission and freeze.
    function submitAndClaim(AbuseReport calldata report, string calldata evidenceURI)
        external
        payable
        returns (bytes32 reportId, bytes32 claimId);

    function contest(bytes32 claimId, string calldata evidenceURI) external;

    /// @notice Close a claim by agreement, without adjudication.
    function settle(bytes32 claimId, uint256 amount) external payable;

    function adjudicate(bytes32 claimId, ClaimStatus outcome, uint256 award) external;

    function executeRemedy(bytes32 claimId) external returns (uint256 fromEscrow, uint256 fromBond);

    function getClaim(bytes32 claimId)
        external
        view
        returns (bytes32 launchId, address claimant, ClaimStatus status, uint256 award);

    /// @notice Pull the detector's share of an executed remedy.
    /// @dev MUST revert unless the claim is Executed. MUST pay the detector
    ///      recorded against the report the claim referenced, never the caller
    ///      and never the party that relayed an atomic submission.
    ///      Where the share is reserved out of a bond rather than moved, the
    ///      reservation MUST be netted off every later payout from that bond,
    ///      or a subsequent upheld claim will spend it.
    function claimDetectorReward(bytes32 claimId) external returns (uint256 amount);

    function bondOf(bytes32 launchId) external view returns (uint256);
    function contestWindow()          external view returns (uint64);
    function bondCooldown()           external view returns (uint64);
    function feeBps()                 external view returns (uint16);

    /// @notice Share of a successful restitution paid to the detector whose
    ///         report supported the claim. MUST NOT exceed feeBps().
    function detectorFeeBps()         external view returns (uint16);
}
