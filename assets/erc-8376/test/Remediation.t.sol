// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {LaunchGuard} from "../src/LaunchGuard.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {AbuseReport, SignalVector, ClaimStatus, ContainmentAction, LaunchState, Patterns}
    from "../src/LaunchAbuseTypes.sol";

/// @dev End-to-end remediation: cases 12 and 13, plus the full claim lifecycle
///      that was unreachable while the remediation contract did not exist.
contract RemediationTest is TestBase {
    LaunchDirectory     internal directory;
    LaunchRemediation   internal remediation;
    LaunchAbuseRegistry internal registry;
    LaunchEscrow        internal escrow;
    LaunchGuard         internal guard;
    SaleVenue           internal venue;

    address internal adjudicator = address(0xAD);
    address internal feeSink     = address(0xFE);
    address internal deployer    = address(0xD1);
    address internal detector    = address(0xDE);
    address internal alice       = address(0xA1);
    address internal bob         = address(0xB2);
    address internal token       = address(0x70);

    bytes32 internal id;
    uint64  internal start;
    uint64  internal end;

    function setUp() public {
        directory   = new LaunchDirectory();
        // 50% bond ratio, 1 ether floor, corroboration required above 50 ether.
        remediation = new LaunchRemediation(adjudicator, feeSink, 5000, 1 ether, 50 ether);
        registry    = new LaunchAbuseRegistry(address(remediation));
        escrow      = new LaunchEscrow(address(remediation), directory);
        remediation.initialize(escrow, registry);
        guard       = new LaunchGuard(registry);
        venue       = new SaleVenue(escrow);

        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        id = venue.open{value: 5 ether}(token, deployer, start, end, 1);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(detector, 100 ether);
        vm.deal(deployer, 100 ether);

        vm.prank(detector);
        registry.bondDetector{value: 1 ether}();
    }

    function _report(uint8 score, uint8 confidence) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG;
        r.launchId = id;
        r.token = token;
        r.deployer = deployer;
        r.linkedAddresses = new address[](0);
        r.abuseScore = score;
        r.confidence = confidence;
        r.vectorVersion = 1;
        r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0, 0, 0, 0, 0, 6000, 7000, 9000, 0x0011, 2, 0, 0);
        r.evidenceRoot = keccak256("evidence");
        r.evidenceURI = "ipfs://evidence";
    }

    function _buy(address who, uint256 amount) internal {
        vm.prank(who);
        venue.buy{value: amount}();
    }

    function _fileClaim(uint8 score) internal returns (bytes32 reportId, bytes32 claimId) {
        vm.prank(detector);
        reportId = registry.submitReport(_report(score, 90));
        vm.prank(alice);
        claimId = remediation.openClaim{value: 0.1 ether}(id, reportId, "ipfs://claim");
    }

    // Full path: report, claim, uphold, execute, buyers pull their refunds.
    function test_fullRemedyPath() public {
        _buy(alice, 6 ether);
        _buy(bob, 4 ether);

        vm.warp(start + 15 days);
        escrow.releaseProceeds(id); // 5 ether vested out, 5 ether still escrowed

        (, bytes32 claimId) = _fileClaim(95);
        assertTrue(escrow.stateOf(id) == LaunchState.Frozen, "claim did not freeze the launch");

        vm.prank(adjudicator);
        remediation.adjudicate(claimId, ClaimStatus.Upheld, 5 ether);
        remediation.executeRemedy(claimId);

        assertTrue(escrow.stateOf(id) == LaunchState.Refunding, "refund not opened");

        uint256 before = alice.balance;
        vm.prank(alice);
        escrow.claimRefund(id);
        // Alice paid 6 of 10, so she takes 60% of the 5 ether pool.
        assertEq(alice.balance - before, 3 ether, "alice pro-rata wrong");
    }

    // 12. A rejected claim forfeits the claimant's bond and unfreezes the launch.
    function test_12_rejectedClaimForfeitsBond() public {
        _buy(alice, 10 ether);
        (, bytes32 claimId) = _fileClaim(95);

        uint256 aliceBefore = alice.balance;
        uint256 deployerBefore = deployer.balance;

        vm.prank(adjudicator);
        remediation.adjudicate(claimId, ClaimStatus.Rejected, 0);

        (, , ClaimStatus status, ) = remediation.getClaim(claimId);
        assertTrue(status == ClaimStatus.Rejected, "not rejected");
        assertEq(alice.balance, aliceBefore, "claimant bond was returned");
        assertEq(remediation.withdrawable(deployer), 0.05 ether, "deployer not credited");
        vm.prank(deployer);
        remediation.withdraw();
        assertEq(deployer.balance - deployerBefore, 0.05 ether, "deployer not compensated");
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "launch still frozen");

        vm.warp(start + 15 days);
        assertTrue(escrow.releaseProceeds(id) > 0, "release still blocked");
    }

    // 13. The guard never reverts, whatever it is asked.
    function test_13_guardNeverReverts() public {
        (ContainmentAction a1, uint8 s1, ) = guard.checkLaunch(bytes32(uint256(0xdead)));
        assertTrue(a1 == ContainmentAction.None, "unknown launch should advise None");
        assertEq(s1, 0, "unknown launch should score 0");

        (ContainmentAction a2, , ) = guard.checkLaunch(id);
        assertTrue(a2 == ContainmentAction.None, "no report should advise None");

        _fileClaim(95);
        (ContainmentAction a3, uint8 s3, ) = guard.checkLaunch(id);
        assertEq(s3, 95, "score not surfaced");
        assertTrue(a3 == ContainmentAction.Freeze, "95/90 should advise Freeze");

        // A guard pointed at a contract that is not a registry still answers.
        LaunchGuard broken = new LaunchGuard(LaunchAbuseRegistry(payable(address(escrow))));
        (ContainmentAction a4, , ) = broken.checkLaunch(id);
        assertTrue(a4 == ContainmentAction.None, "broken registry should fail open");
    }

    // Refund is never automatic: a maximal report alone opens nothing.
    function test_noAutomaticRefundFromReportAlone() public {
        _buy(alice, 10 ether);
        vm.prank(detector);
        registry.submitReport(_report(100, 100));
        assertTrue(escrow.stateOf(id) != LaunchState.Refunding, "report alone opened a refund");
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "report alone froze the launch");
    }

    // A claim below the score threshold cannot be opened at all.
    function test_lowScoreCannotClaim() public {
        vm.prank(detector);
        bytes32 rid = registry.submitReport(_report(40, 90));
        vm.prank(alice);
        vm.expectRevert();
        remediation.openClaim{value: 0.1 ether}(id, rid, "ipfs://claim");
    }

    // Settling bilaterally closes the claim without the adjudicator.
    function test_settleWithoutAdjudicator() public {
        _buy(alice, 10 ether);
        (, bytes32 claimId) = _fileClaim(95);

        uint256 before = alice.balance;
        vm.prank(deployer);
        remediation.settle{value: 2 ether}(claimId, 2 ether);
        vm.prank(alice);
        remediation.acceptSettlement(claimId, 2 ether);

        (, , ClaimStatus status, ) = remediation.getClaim(claimId);
        assertTrue(status == ClaimStatus.Settled, "not settled");
        // Settlement plus the returned claim bond, collected by pull.
        vm.prank(alice);
        remediation.withdraw();
        assertEq(alice.balance - before, 2.1 ether, "claimant not paid");
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "still frozen after settlement");
    }

    // An offer stands until it is taken. A deployer may withdraw it before
    // acceptance, and the claim survives the withdrawal unchanged.
    function test_settlementOfferWithdrawnBeforeAcceptance() public {
        _buy(alice, 10 ether);
        (, bytes32 claimId) = _fileClaim(95);

        uint256 before = deployer.balance;
        vm.prank(deployer);
        remediation.settle{value: 2 ether}(claimId, 2 ether);

        vm.prank(deployer);
        remediation.withdrawSettlementOffer(claimId);
        vm.prank(deployer);
        remediation.withdraw();
        assertEq(deployer.balance, before, "offer not returned to the deployer");

        // Nothing is left to accept, and the claim is untouched.
        vm.prank(alice);
        vm.expectRevert();
        remediation.acceptSettlement(claimId, 2 ether);

        (, , ClaimStatus status, ) = remediation.getClaim(claimId);
        assertTrue(status == ClaimStatus.Open, "withdrawal closed the claim");
        assertTrue(escrow.stateOf(id) == LaunchState.Frozen, "withdrawal unfroze the launch");
    }

    // Only the deployer who posted an offer may take it back.
    function test_settlementOfferWithdrawableOnlyByDeployer() public {
        _buy(alice, 10 ether);
        (, bytes32 claimId) = _fileClaim(95);

        vm.prank(deployer);
        remediation.settle{value: 2 ether}(claimId, 2 ether);

        vm.prank(alice);
        vm.expectRevert();
        remediation.withdrawSettlementOffer(claimId);
    }

    // An unadjudicated claim must not freeze a launch forever.
    function test_claimExpiresAndUnfreezes() public {
        _buy(alice, 10 ether);
        (, bytes32 claimId) = _fileClaim(95);

        vm.warp(block.timestamp + 15 days);
        remediation.expire(claimId);

        (, , ClaimStatus status, ) = remediation.getClaim(claimId);
        assertTrue(status == ClaimStatus.Expired, "not expired");
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "still frozen after expiry");
    }

    // Self-purchase dilution: a deployer-linked buyer is removed from the pool
    // denominator, so honest buyers are made whole rather than merely undiluted.
    function test_linkedBuyerExcludedFromPool() public {
        _buy(alice, 5 ether);
        _buy(bob, 5 ether); // bob is secretly the deployer

        assertEq(escrow.totalNetPaid(id), 10 ether, "denominator before exclusion");

        (, bytes32 claimId) = _fileClaim(95);
        vm.prank(adjudicator);
        remediation.markLinked(id, bob);
        assertEq(escrow.totalNetPaid(id), 5 ether, "linked buyer not removed");

        vm.prank(adjudicator);
        remediation.adjudicate(claimId, ClaimStatus.Upheld, 10 ether);
        remediation.executeRemedy(claimId);

        assertEq(escrow.entitlementOf(id, bob), 0, "linked buyer drew a refund");
        assertEq(escrow.entitlementOf(id, alice), 10 ether, "alice not made whole");
    }

    // Detector bonding is a precondition for publishing at all.
    function test_unbondedDetectorCannotReport() public {
        vm.prank(bob);
        vm.expectRevert();
        registry.submitReport(_report(90, 90));
    }

    // A retracted report stops backing new claims.
    function test_retractedReportCannotBeClaimed() public {
        vm.prank(detector);
        bytes32 rid = registry.submitReport(_report(95, 90));
        vm.prank(detector);
        registry.retractReport(rid, "recomputed, was wrong");

        vm.prank(alice);
        vm.expectRevert();
        remediation.openClaim{value: 0.1 ether}(id, rid, "ipfs://claim");
    }

    receive() external payable {}
}
