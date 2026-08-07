// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {LaunchRemediation} from "./LaunchRemediation.sol";
import {ClaimStatus} from "./LaunchAbuseTypes.sol";

/// @title An n-of-m adjudicator.
/// @notice The adjudicator is the most concentrated trust in this design: it can
///         uphold a fabricated claim or reject a valid one. A single externally
///         owned account makes that trust a single key, so this is the minimum
///         a deployment should stand up in its place.
///
///         Every approval carries a reasoning URI, and the outcome is part of
///         what members approve. Members cannot be added or removed: a committee
///         whose membership can change is a committee whose membership can be
///         captured without anyone observing the moment.
contract CommitteeAdjudicator {
    LaunchRemediation public immutable remediation;
    uint256 public immutable threshold;

    mapping(address => bool) public isMember;
    address[] private _members;

    /// @dev Keyed by the full decision, so approving an outcome is never
    ///      transferable to a different one.
    mapping(bytes32 => uint256) public approvals;
    mapping(bytes32 => mapping(address => bool)) public approvedBy;
    mapping(bytes32 => bool) public executed;

    event Approved(bytes32 indexed decision, address indexed member, string reasoning);
    event Executed(bytes32 indexed decision, bytes32 indexed claimId, ClaimStatus outcome, uint256 award);

    error NotMember(address caller);
    error AlreadyApproved(bytes32 decision, address member);
    error AlreadyExecuted(bytes32 decision);

    modifier onlyMember() {
        if (!isMember[msg.sender]) revert NotMember(msg.sender);
        _;
    }

    constructor(LaunchRemediation remediation_, address[] memory members_, uint256 threshold_) {
        require(address(remediation_) != address(0), "zero remediation");
        require(members_.length > 0, "no members");
        require(threshold_ > 1 && threshold_ <= members_.length, "threshold out of range");

        for (uint256 i = 0; i < members_.length; ++i) {
            address m = members_[i];
            require(m != address(0), "zero member");
            require(!isMember[m], "duplicate member");
            isMember[m] = true;
            _members.push(m);
        }
        remediation = remediation_;
        threshold = threshold_;
    }

    function members() external view returns (address[] memory) {
        return _members;
    }

    /// @notice The identity of a decision: a claim, an outcome and an award.
    function decisionId(bytes32 claimId, ClaimStatus outcome, uint256 award)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(claimId, outcome, award));
    }

    /// @notice Approve a decision, executing it once the threshold is reached.
    /// @param reasoning where the member's reasoning is published, so a decision
    ///        can be argued with rather than merely obeyed
    function approve(
        bytes32 claimId,
        ClaimStatus outcome,
        uint256 award,
        string calldata reasoning
    ) external onlyMember {
        bytes32 d = decisionId(claimId, outcome, award);
        if (executed[d]) revert AlreadyExecuted(d);
        if (approvedBy[d][msg.sender]) revert AlreadyApproved(d, msg.sender);

        approvedBy[d][msg.sender] = true;
        uint256 count = approvals[d] + 1;
        approvals[d] = count;
        emit Approved(d, msg.sender, reasoning);

        if (count >= threshold) {
            executed[d] = true;
            emit Executed(d, claimId, outcome, award);
            remediation.adjudicate(claimId, outcome, award);
        }
    }

    /// @notice Exclude a deployer-linked buyer, on the same threshold.
    function approveMarkLinked(bytes32 launchId, address account) external onlyMember {
        bytes32 d = keccak256(abi.encode("markLinked", launchId, account));
        if (executed[d]) revert AlreadyExecuted(d);
        if (approvedBy[d][msg.sender]) revert AlreadyApproved(d, msg.sender);

        approvedBy[d][msg.sender] = true;
        uint256 count = approvals[d] + 1;
        approvals[d] = count;

        if (count >= threshold) {
            executed[d] = true;
            remediation.markLinked(launchId, account);
        }
    }

    /// @notice Slash the detector behind a resolved claim, on the same threshold.
    function approveSlashDetector(bytes32 claimId, uint256 amount) external onlyMember {
        bytes32 d = keccak256(abi.encode("slash", claimId, amount));
        if (executed[d]) revert AlreadyExecuted(d);
        if (approvedBy[d][msg.sender]) revert AlreadyApproved(d, msg.sender);

        approvedBy[d][msg.sender] = true;
        uint256 count = approvals[d] + 1;
        approvals[d] = count;

        if (count >= threshold) {
            executed[d] = true;
            remediation.slashReportingDetector(claimId, amount);
        }
    }
}
