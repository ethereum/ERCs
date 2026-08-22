// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {CommitteeAdjudicator} from "../src/CommitteeAdjudicator.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {AbuseReport, SignalVector, ClaimStatus, LaunchState, Patterns}
    from "../src/LaunchAbuseTypes.sol";

/// @dev The spec says a deployment SHOULD NOT put adjudication behind one key.
///      This is the reference committee that satisfies it.
contract CommitteeAdjudicatorTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    CommitteeAdjudicator internal committee;
    SaleVenue           internal ven;

    address internal m1 = address(0xC1);
    address internal m2 = address(0xC2);
    address internal m3 = address(0xC3);
    address internal dep = address(0xD1);
    address internal det = address(0xDE);
    address internal alice = address(0xA1);
    address internal token = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        address predicted = _create(address(this), 5);
        rem = new LaunchRemediation(predicted, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);

        address[] memory ms = new address[](3);
        ms[0] = m1; ms[1] = m2; ms[2] = m3;
        committee = new CommitteeAdjudicator(rem, ms, 2);
        require(address(committee) == predicted, "committee address mismatch");

        ven = new SaleVenue(esc);
        start = uint64(block.timestamp);
        id = ven.open{value: 5 ether}(token, dep, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(alice, 100 ether);
        vm.deal(det, 10 ether);
        vm.prank(det); reg.bondDetector{value: 1 ether}();
    }

    function _create(address d, uint8 n) internal pure returns (address) {
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xd6), bytes1(0x94), d, bytes1(n))))));
    }

    function _claim() internal returns (bytes32 cid) {
        AbuseReport memory r;
        r.patternId = Patterns.HARD_RUG; r.launchId = id; r.token = token; r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = 95; r.confidence = 90; r.launchedAt = start;
        r.vectorVersion = 1;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0,0,0,0,0,6000,7000,9000,0x0011,2,0,0);
        r.evidenceRoot = keccak256("e"); r.evidenceURI = "ipfs://e";

        vm.prank(det); bytes32 rid = reg.submitReport(r);
        vm.prank(alice); cid = rem.openClaim{value: 0.1 ether}(id, rid, "ipfs://claim");
    }

    /// One member is not enough; the second carries it.
    function test_thresholdRequiredBeforeAnyEffect() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();

        vm.prank(m1);
        committee.approve(cid, ClaimStatus.Upheld, 5 ether, "ipfs://reasoning-m1");

        (, , ClaimStatus s1, ) = rem.getClaim(cid);
        assertTrue(s1 == ClaimStatus.Open, "one approval must not decide");

        vm.prank(m2);
        committee.approve(cid, ClaimStatus.Upheld, 5 ether, "ipfs://reasoning-m2");

        (, , ClaimStatus s2, uint256 award) = rem.getClaim(cid);
        assertTrue(s2 == ClaimStatus.Upheld, "threshold did not decide");
        assertEq(award, 5 ether, "award not carried");
    }

    /// Approving one outcome never counts toward a different one.
    function test_approvalIsBoundToTheOutcome() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();

        vm.prank(m1); committee.approve(cid, ClaimStatus.Upheld, 5 ether, "a");
        vm.prank(m2); committee.approve(cid, ClaimStatus.Rejected, 0, "b");

        (, , ClaimStatus s, ) = rem.getClaim(cid);
        assertTrue(s == ClaimStatus.Open, "split votes decided something");
        assertEq(committee.approvals(committee.decisionId(cid, ClaimStatus.Upheld, 5 ether)), 1, "u");
        assertEq(committee.approvals(committee.decisionId(cid, ClaimStatus.Rejected, 0)), 1, "r");
    }

    function test_nonMemberCannotApprove() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();
        vm.prank(alice);
        vm.expectRevert();
        committee.approve(cid, ClaimStatus.Upheld, 1 ether, "x");
    }

    function test_memberCannotApproveTwice() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();
        vm.prank(m1); committee.approve(cid, ClaimStatus.Upheld, 5 ether, "a");
        vm.prank(m1);
        vm.expectRevert();
        committee.approve(cid, ClaimStatus.Upheld, 5 ether, "again");
    }

    /// The remediation contract accepts nothing from a member directly.
    function test_membersHaveNoDirectAuthority() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();
        vm.prank(m1);
        vm.expectRevert();
        rem.adjudicate(cid, ClaimStatus.Upheld, 5 ether);
    }

    function test_constructorGuards() public {
        address[] memory ms = new address[](2);
        ms[0] = m1; ms[1] = m2;

        vm.expectRevert(); // a threshold of one is a single key with extra steps
        new CommitteeAdjudicator(rem, ms, 1);

        vm.expectRevert(); // more approvals than members can never be reached
        new CommitteeAdjudicator(rem, ms, 3);

        address[] memory dup = new address[](2);
        dup[0] = m1; dup[1] = m1;
        vm.expectRevert(); // one key holding two seats is not two-of-two
        new CommitteeAdjudicator(rem, dup, 2);
    }

    /// Excluding a deployer-linked buyer takes the same threshold as a verdict.
    function test_markLinkedNeedsTheThreshold() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        _claim();

        vm.prank(m1); committee.approveMarkLinked(id, alice);
        assertTrue(!esc.isExcluded(id, alice), "one approval excluded a buyer");

        vm.prank(m2); committee.approveMarkLinked(id, alice);
        assertTrue(esc.isExcluded(id, alice), "threshold did not exclude");

        vm.prank(m3);
        vm.expectRevert(); // already executed
        committee.approveMarkLinked(id, alice);
    }

    function test_markLinkedRejectsNonMembersAndRepeats() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        _claim();

        vm.prank(alice);
        vm.expectRevert();
        committee.approveMarkLinked(id, alice);

        vm.prank(m1); committee.approveMarkLinked(id, alice);
        vm.prank(m1);
        vm.expectRevert();
        committee.approveMarkLinked(id, alice);
    }

    /// Slashing the detector behind a rejected claim, on the same threshold.
    function test_slashDetectorNeedsTheThreshold() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();

        vm.prank(m1); committee.approve(cid, ClaimStatus.Rejected, 0, "a");
        vm.prank(m2); committee.approve(cid, ClaimStatus.Rejected, 0, "b");

        uint256 before = reg.detectorBond(det);
        vm.prank(m1); committee.approveSlashDetector(cid, 0.4 ether);
        assertEq(reg.detectorBond(det), before, "one approval slashed a detector");

        vm.prank(m2); committee.approveSlashDetector(cid, 0.4 ether);
        assertEq(reg.detectorBond(det), before - 0.4 ether, "threshold did not slash");

        vm.prank(alice);
        vm.expectRevert();
        committee.approveSlashDetector(cid, 0.4 ether);
    }

    function test_slashRejectsRepeatApproval() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        bytes32 cid = _claim();
        vm.prank(m1); committee.approve(cid, ClaimStatus.Rejected, 0, "a");
        vm.prank(m2); committee.approve(cid, ClaimStatus.Rejected, 0, "b");

        vm.prank(m1); committee.approveSlashDetector(cid, 0.2 ether);
        vm.prank(m1);
        vm.expectRevert();
        committee.approveSlashDetector(cid, 0.2 ether);
    }

    function test_membershipIsFixed() public view {
        address[] memory ms = committee.members();
        assertEq(ms.length, 3, "membership");
        assertEq(committee.threshold(), 2, "threshold");
        assertTrue(committee.isMember(m1) && committee.isMember(m2) && committee.isMember(m3), "members");
        assertTrue(!committee.isMember(alice), "outsider");
    }

    receive() external payable {}
}
