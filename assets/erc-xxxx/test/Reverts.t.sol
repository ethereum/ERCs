// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {AbuseReport, SignalVector, ClaimStatus, Patterns} from "../src/LaunchAbuseTypes.sol";

contract Tk {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @dev Exercises the guard conditions. These are the paths that run when
///      something has already gone wrong, which is where every fund-loss bug
///      found in this codebase has lived.
contract RevertsTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    SaleVenue           internal ven;
    Tk                  internal tok;

    address internal adj = address(0xAD);
    address internal dep = address(0xD1);
    address internal det = address(0xDE);
    address internal alice = address(0xA1);
    address internal bob = address(0xB2);
    address internal token = address(0x70);

    bytes32 internal id;
    uint64  internal start;
    uint64  internal end;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(adj, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        ven = new SaleVenue(esc);
        tok = new Tk();

        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        id = ven.open{value: 5 ether}(token, dep, start, end, 1);

        vm.deal(alice, 500 ether);
        vm.deal(bob, 500 ether);
        vm.deal(det, 50 ether);
        vm.deal(dep, 500 ether);
        vm.prank(det); reg.bondDetector{value: 1 ether}();
    }

    function _rep(uint8 s, uint8 c) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG; r.launchId = id; r.token = token; r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = s; r.confidence = c; r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0,0,0,0,0,6000,7000,9000,0x0011,2,0,0);
        r.evidenceRoot = keccak256("e"); r.evidenceURI = "ipfs://e";
    }

    function _claim() internal returns (bytes32 rid, bytes32 cid) {
        vm.prank(det); rid = reg.submitReport(_rep(95, 90));
        vm.prank(alice); cid = rem.openClaim{value: 0.1 ether}(id, rid, "x");
    }

    // --- directory ----------------------------------------------------------

    function test_directoryRejectsDuplicateListing() public {
        vm.expectRevert();
        dir.list(id, token, dep, address(ven), 0);
    }

    // --- venue --------------------------------------------------------------

    function test_venueRejectsZeroPrice() public {
        SaleVenue v2 = new SaleVenue(esc);
        vm.expectRevert();
        v2.open(token, dep, start, end, 0);
    }

    function test_venueRejectsReopen() public {
        vm.expectRevert();
        ven.open(token, dep, start, end, 1);
    }

    function test_venueRejectsZeroValueBuy() public {
        vm.prank(alice);
        vm.expectRevert();
        ven.buy{value: 0}();
    }

    // --- escrow: registration ----------------------------------------------

    function test_rejectsBackwardsSchedule() public {
        SaleVenue v2 = new SaleVenue(esc);
        vm.expectRevert();
        v2.open(token, dep, end, start, 1);
    }

    function test_rejectsOverlongReleasePeriod() public {
        SaleVenue v2 = new SaleVenue(esc);
        vm.expectRevert();
        v2.open(token, dep, start, start + 91 days, 1);
    }

    function test_rejectsNativeValueOnErc20Launch() public {
        vm.expectRevert();
        esc.registerLaunch{value: 1 ether}(token, dep, address(tok), 1 ether, start, end);
    }

    function test_rejectsBondNotDelivered() public {
        // No tokens transferred in beforehand.
        vm.expectRevert();
        esc.registerLaunch(token, dep, address(tok), 10 ether, start, end);
    }

    // The convenience wrapper cannot mismatch, since it passes msg.value as the
    // bond. The explicit form can, and must reject it.
    function test_rejectsBondValueMismatch() public {
        vm.expectRevert();
        esc.registerLaunch{value: 1 ether}(token, dep, address(0), 2 ether, start, end);
    }

    // --- escrow: unknown launch and access ---------------------------------

    function test_unknownLaunchReverts() public {
        bytes32 ghost = bytes32(uint256(0xdead));
        vm.expectRevert();
        esc.releaseProceeds(ghost);
        vm.expectRevert();
        esc.claimRefund(ghost);
        vm.expectRevert();
        esc.topUpBond{value: 1}(ghost, 1);
    }

    function test_recordSaleRequiresVenue() public {
        vm.prank(alice);
        vm.expectRevert();
        esc.recordSale(id, alice, 1 ether);
    }

    function test_remediationOnlyPathsRejectOthers() public {
        vm.startPrank(alice);
        vm.expectRevert(); esc.freezeLaunch(id, bytes32(0));
        vm.expectRevert(); esc.unfreeze(id);
        vm.expectRevert(); esc.openRefund(id, 0);
        vm.expectRevert(); esc.augmentRefund(id, 0);
        vm.expectRevert(); esc.releaseBond(id, alice, 0);
        vm.expectRevert(); esc.markLinked(id, alice);
        vm.expectRevert(); esc.sweepUnclaimed(id, alice);
        vm.stopPrank();
    }

    // --- escrow: release and refund guards ---------------------------------

    function test_releaseBeforeAnythingVests() public {
        vm.prank(alice); ven.buy{value: 1 ether}();
        vm.expectRevert(); // nothing has vested yet
        esc.releaseProceeds(id);
    }

    function test_claimRefundBeforePoolOpens() public {
        vm.prank(alice); ven.buy{value: 1 ether}();
        vm.prank(alice);
        vm.expectRevert();
        esc.claimRefund(id);
    }

    function test_refundExpiresAfterClaimPeriod() public {
        vm.prank(alice); ven.buy{value: 4 ether}();
        (, bytes32 cid) = _claim();
        vm.prank(adj); rem.adjudicate(cid, ClaimStatus.Upheld, 4 ether);
        rem.executeRemedy(cid);

        vm.warp(block.timestamp + 181 days);
        vm.prank(alice);
        vm.expectRevert();
        esc.claimRefund(id);
    }

    function test_sweepGuards() public {
        vm.prank(alice); ven.buy{value: 4 ether}();
        (, bytes32 cid) = _claim();

        // Not refunding yet.
        vm.prank(address(rem));
        vm.expectRevert();
        esc.sweepUnclaimed(id, alice);

        vm.prank(adj); rem.adjudicate(cid, ClaimStatus.Upheld, 4 ether);
        rem.executeRemedy(cid);

        // Claim period still open.
        vm.prank(address(rem));
        vm.expectRevert();
        esc.sweepUnclaimed(id, alice);

        // Zero recipient.
        vm.warp(block.timestamp + 181 days);
        vm.prank(address(rem));
        vm.expectRevert();
        esc.sweepUnclaimed(id, address(0));

        // Now it works, and the residue is gone.
        vm.prank(address(rem));
        uint256 swept = esc.sweepUnclaimed(id, bob);
        assertTrue(swept > 0, "nothing swept");
        assertEq(esc.unclaimedRefund(id), 0, "residue remains");

        vm.prank(address(rem));
        vm.expectRevert(); // nothing left
        esc.sweepUnclaimed(id, bob);
    }

    function test_doubleRefundOpenRejected() public {
        vm.prank(alice); ven.buy{value: 4 ether}();
        vm.prank(address(rem)); esc.openRefund(id, 0);
        vm.prank(address(rem));
        vm.expectRevert();
        esc.openRefund(id, 0);
    }

    function test_augmentBeforeOpenRejected() public {
        vm.prank(address(rem));
        vm.expectRevert();
        esc.augmentRefund(id, 0);
    }

    function test_bondExceededRejected() public {
        vm.prank(address(rem));
        vm.expectRevert();
        esc.releaseBond(id, alice, 100 ether);
        vm.prank(address(rem));
        vm.expectRevert();
        esc.openRefund(id, 100 ether);
    }

    function test_releaseBondZeroRecipient() public {
        vm.prank(address(rem));
        vm.expectRevert();
        esc.releaseBond(id, address(0), 1);
    }

    function test_markLinkedTwiceRejected() public {
        vm.prank(alice); ven.buy{value: 1 ether}();
        vm.prank(address(rem)); esc.markLinked(id, alice);
        vm.prank(address(rem));
        vm.expectRevert();
        esc.markLinked(id, alice);
    }

    function test_freezeUnfreezableState() public {
        vm.prank(alice); ven.buy{value: 4 ether}();
        vm.prank(address(rem)); esc.openRefund(id, 0);
        vm.prank(address(rem));
        vm.expectRevert(); // already refunding
        esc.freezeLaunch(id, bytes32(0));
    }

    function test_releaseWhileRefundingRejected() public {
        vm.prank(alice); ven.buy{value: 4 ether}();
        vm.prank(address(rem)); esc.openRefund(id, 0);
        vm.warp(start + 15 days);
        vm.expectRevert();
        esc.releaseProceeds(id);
    }

    // --- registry -----------------------------------------------------------

    function test_registryValidation() public {
        vm.startPrank(det);
        AbuseReport memory r = _rep(101, 90);
        vm.expectRevert(); reg.submitReport(r);          // score > 100

        r = _rep(95, 101);
        vm.expectRevert(); reg.submitReport(r);          // confidence > 100

        r = _rep(95, 90); r.windowEnd = start - 1;
        vm.expectRevert(); reg.submitReport(r);          // window ends before launch

        r = _rep(95, 90); r.evidenceRoot = bytes32(0);
        vm.expectRevert(); reg.submitReport(r);          // no evidence commitment

        r = _rep(95, 90); r.launchId = bytes32(0);
        vm.expectRevert(); reg.submitReport(r);          // no subject launch

        r = _rep(95, 90); r.deployer = address(0);
        vm.expectRevert(); reg.submitReport(r);          // no subject deployer
        vm.stopPrank();
    }

    function test_duplicateReportRejected() public {
        vm.prank(det); reg.submitReport(_rep(95, 90));
        vm.prank(det);
        vm.expectRevert();
        reg.submitReport(_rep(95, 90));
    }

    function test_retractGuards() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(95, 90));

        vm.prank(alice);
        vm.expectRevert(); // not the detector
        reg.retractReport(rid, "x");

        vm.prank(det); reg.retractReport(rid, "x");
        vm.prank(det);
        vm.expectRevert(); // already retracted
        reg.retractReport(rid, "x");

        vm.expectRevert(); // unknown report
        reg.retractReport(bytes32(uint256(0xbeef)), "x");
    }

    function test_getUnknownReportReverts() public {
        vm.expectRevert();
        reg.getReport(bytes32(uint256(0xbeef)));
    }

    function test_slashGuards() public {
        vm.prank(alice);
        vm.expectRevert(); // not remediation
        reg.slashDetector(det, 1, bytes32(0), alice);

        vm.prank(address(rem));
        vm.expectRevert(); // zero recipient
        reg.slashDetector(det, 1, bytes32(0), address(0));

        vm.prank(address(rem));
        vm.expectRevert(); // more than the bond
        reg.slashDetector(det, 100 ether, bytes32(0), alice);
    }

    function test_staleReportIsNotLive() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(95, 90));
        assertTrue(reg.isLive(rid), "should be live");
        vm.warp(block.timestamp + 31 days);
        assertTrue(!reg.isLive(rid), "should have gone stale");
        (uint8 s, , ) = reg.activeScore(id);
        assertEq(s, 0, "stale report still scoring");
    }

    function test_corroborationWithNoReports() public view {
        (uint8 s, uint8 c, uint256 n) = reg.corroboratedScore(id, 2);
        assertEq(s, 0, "score from nothing");
        assertEq(c, 0, "confidence from nothing");
        assertEq(n, 0, "detectors from nothing");
    }

    function test_corroborationZeroMinFallsBackToActive() public {
        vm.prank(det); reg.submitReport(_rep(95, 90));
        (uint8 s, , ) = reg.corroboratedScore(id, 0);
        assertEq(s, 95, "zero minimum should read the active score");
    }

    // --- remediation --------------------------------------------------------

    function test_constructorGuards() public {
        vm.expectRevert();
        new LaunchRemediation(adj, address(0xFE), 10_001, 0, 0); // bondBps out of range
        vm.expectRevert();
        new LaunchRemediation(address(0), address(0xFE), 5000, 0, 0); // zero adjudicator
    }

    function test_initializeGuards() public {
        LaunchRemediation r2 = new LaunchRemediation(adj, address(0xFE), 5000, 0, 0);
        vm.prank(alice);
        vm.expectRevert(); // not the deployer
        r2.initialize(esc, reg);

        vm.expectRevert(); // zero addresses
        r2.initialize(LaunchEscrow(payable(address(0))), reg);

        r2.initialize(esc, reg);
        vm.expectRevert(); // already initialized
        r2.initialize(esc, reg);
    }

    function test_claimBondTooSmall() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(95, 90));
        vm.prank(alice);
        vm.expectRevert();
        rem.openClaim{value: 0.01 ether}(id, rid, "x");
    }

    function test_claimOnUnknownReport() public {
        vm.prank(alice);
        vm.expectRevert();
        rem.openClaim{value: 0.1 ether}(id, bytes32(uint256(0xbeef)), "x");
    }

    function test_claimWithNoLiveReport() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(95, 90));
        vm.prank(det); reg.retractReport(rid, "withdrawn");
        vm.prank(alice);
        vm.expectRevert();
        rem.openClaim{value: 0.1 ether}(id, rid, "x");
    }

    function test_claimWithZeroConfidenceRejected() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(95, 0));
        vm.prank(alice);
        vm.expectRevert();
        rem.openClaim{value: 0.1 ether}(id, rid, "x");
    }

    function test_contestGuards() public {
        (, bytes32 cid) = _claim();

        vm.prank(alice);
        vm.expectRevert(); // not the deployer
        rem.contest(cid, "x");

        vm.warp(block.timestamp + 4 days);
        vm.prank(dep);
        vm.expectRevert(); // window closed
        rem.contest(cid, "x");
    }

    function test_contestSucceedsThenBlocksRepeat() public {
        (, bytes32 cid) = _claim();
        vm.prank(dep); rem.contest(cid, "evidence");
        vm.prank(dep);
        vm.expectRevert(); // no longer Open
        rem.contest(cid, "again");
    }

    function test_settleGuards() public {
        (, bytes32 cid) = _claim();
        vm.prank(alice);
        vm.expectRevert(); // not the deployer
        rem.settle{value: 1 ether}(cid, 1 ether);

        vm.prank(dep);
        vm.expectRevert(); // value mismatch
        rem.settle{value: 1 ether}(cid, 2 ether);
    }

    function test_adjudicateGuards() public {
        (, bytes32 cid) = _claim();

        vm.prank(alice);
        vm.expectRevert(); // not the adjudicator
        rem.adjudicate(cid, ClaimStatus.Upheld, 1);

        vm.prank(adj);
        vm.expectRevert(); // outcome must be Upheld or Rejected
        rem.adjudicate(cid, ClaimStatus.Expired, 0);

        vm.prank(adj); rem.adjudicate(cid, ClaimStatus.Upheld, 1 ether);
        vm.prank(adj);
        vm.expectRevert(); // already resolved
        rem.adjudicate(cid, ClaimStatus.Rejected, 0);
    }

    function test_executeBeforeUpheldRejected() public {
        (, bytes32 cid) = _claim();
        vm.expectRevert();
        rem.executeRemedy(cid);
    }

    function test_expireGuards() public {
        (, bytes32 cid) = _claim();
        vm.expectRevert(); // not yet expired
        rem.expire(cid);

        vm.warp(block.timestamp + 15 days);
        rem.expire(cid);
        vm.expectRevert(); // already expired
        rem.expire(cid);
    }

    function test_markLinkedRequiresAdjudicator() public {
        vm.prank(alice);
        vm.expectRevert();
        rem.markLinked(id, alice);
    }

    function test_slashReportingDetectorGuards() public {
        (, bytes32 cid) = _claim();

        vm.prank(alice);
        vm.expectRevert(); // not the adjudicator
        rem.slashReportingDetector(cid, 1);

        vm.prank(adj);
        vm.expectRevert(); // claim not resolved against the report
        rem.slashReportingDetector(cid, 1);

        vm.prank(adj);
        vm.expectRevert(); // unknown claim
        rem.slashReportingDetector(bytes32(uint256(0xbeef)), 1);

        vm.prank(adj); rem.adjudicate(cid, ClaimStatus.Rejected, 0);
        vm.prank(adj); rem.slashReportingDetector(cid, 0.5 ether);
        assertEq(reg.detectorBond(det), 0.5 ether, "detector not slashed");
    }

    function test_withdrawNothingOwed() public {
        vm.prank(alice);
        vm.expectRevert();
        rem.withdraw();
    }

    function test_requiredBondAndViews() public view {
        assertEq(rem.requiredBond(100 ether), 50 ether, "bond ratio");
        assertEq(rem.requiredBond(0), 1 ether, "bond floor");
        assertEq(rem.contestWindow(), 72 hours, "contest window");
        assertEq(rem.bondCooldown(), 30 days, "bond cooldown");
        assertEq(rem.feeBps(), 250, "fee");
        assertEq(rem.bondOf(id), 5 ether, "bond passthrough");
        assertEq(uint256(rem.advisedAction(id)), 0, "no report means no action");
    }

    function test_escrowViews() public view {
        assertEq(esc.maxFreezeDuration(), 14 days, "freeze duration");
        assertTrue(esc.assetOf(id) == address(0), "native launch");
        assertTrue(esc.deployerOf(id) == dep, "deployer");
        assertTrue(!esc.isExcluded(id, alice), "nobody excluded yet");
        assertTrue(esc.supportsInterface(0x01ffc9a7), "erc165");
        assertEq(esc.nextNonce(token, dep), 1, "nonce advanced");
        assertEq(esc.accountedOf(address(tok)), 0, "no tokens accounted");
        assertEq(reg.reportCount(id), 0, "no reports");
        assertEq(reg.minDetectorBond(), 1 ether, "min bond");
        assertEq(reg.maxReportAge(), 30 days, "max age");
        assertEq(reg.openingBlocks(), 20, "opening blocks");
        assertTrue(dir.isListed(id), "listed");
    }

    receive() external payable {}
}
