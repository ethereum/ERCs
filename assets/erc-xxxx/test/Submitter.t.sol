// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {AbuseReport, SignalVector, Patterns} from "../src/LaunchAbuseTypes.sol";

/// @dev Key rotation for detectors. A hot key that signs submissions must be
///      replaceable without moving the bond or discarding the detector's record,
///      because otherwise a compromise is permanent.
contract SubmitterTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    SaleVenue           internal ven;

    address internal det  = address(0xDE);   // holds the bond
    address internal hot  = address(0xA07);  // signs submissions
    address internal hot2 = address(0xB0B);  // the replacement
    address internal dep  = address(0xD1);
    address internal token = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(address(0xAD), address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        ven = new SaleVenue(esc);

        start = uint64(block.timestamp);
        id = ven.open{value: 5 ether}(token, dep, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(det, 10 ether);
        vm.prank(det); reg.bondDetector{value: 1 ether}();
    }

    function _rep(uint8 s) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG; r.launchId = id; r.token = token; r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = s; r.confidence = 90; r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0,0,0,0,0,6000,7000,9000,0x0011,2,0,0);
        r.evidenceRoot = keccak256("e"); r.evidenceURI = "ipfs://e";
    }

    /// A report signed by the hot key is attributed to the bonded detector.
    function test_submissionIsAttributedToTheBondedDetector() public {
        vm.prank(det); reg.setSubmitter(hot);
        assertTrue(reg.principalOf(hot) == det, "hot key does not resolve to the detector");

        vm.prank(hot);
        bytes32 rid = reg.submitReport(_rep(95));
        assertTrue(reg.detectorOf(rid) == det, "report attributed to the hot key");
        assertEq(reg.detectorBond(hot), 0, "the hot key holds no bond");
    }

    /// Rotation retires a compromised key and leaves everything else in place.
    function test_rotationRetiresTheOldKey() public {
        vm.prank(det); reg.setSubmitter(hot);
        vm.prank(hot); reg.submitReport(_rep(95));

        vm.prank(det); reg.setSubmitter(hot2);

        assertTrue(reg.principalOf(hot) == hot, "old key still resolves to the detector");
        assertTrue(reg.principalOf(hot2) == det, "new key does not resolve");
        assertEq(reg.detectorBond(det), 1 ether, "bond moved during rotation");

        // The compromised key can no longer publish under the detector.
        vm.prank(hot);
        vm.expectRevert();
        reg.submitReport(_rep(80));

        // The replacement can.
        vm.prank(hot2);
        bytes32 rid = reg.submitReport(_rep(80));
        assertTrue(reg.detectorOf(rid) == det, "new key not attributed to the detector");
    }

    /// Revocation leaves the detector able to publish directly.
    function test_revocationLeavesTheDetectorIntact() public {
        vm.prank(det); reg.setSubmitter(hot);
        vm.prank(det); reg.setSubmitter(address(0));

        assertTrue(reg.principalOf(hot) == hot, "revoked key still resolves");
        vm.prank(det);
        bytes32 rid = reg.submitReport(_rep(95));
        assertTrue(reg.detectorOf(rid) == det, "detector cannot publish after revoking");
    }

    /// Only the bonded detector may retract, whichever key filed the report.
    function test_retractionFollowsThePrincipal() public {
        vm.prank(det); reg.setSubmitter(hot);
        vm.prank(hot); bytes32 rid = reg.submitReport(_rep(95));

        vm.prank(address(0xBAD));
        vm.expectRevert();
        reg.retractReport(rid, "not mine");

        vm.prank(hot); reg.retractReport(rid, "recomputed");
        assertTrue(!reg.isLive(rid), "retraction by the authorized key failed");
    }

    function test_submitterGuards() public {
        // An unbonded address cannot delegate.
        vm.prank(address(0xBAD));
        vm.expectRevert();
        reg.setSubmitter(hot);

        // One key cannot serve two detectors.
        vm.deal(address(0xC0), 10 ether);
        vm.prank(address(0xC0)); reg.bondDetector{value: 1 ether}();
        vm.prank(det); reg.setSubmitter(hot);
        vm.prank(address(0xC0));
        vm.expectRevert();
        reg.setSubmitter(hot);

        // A bonded detector cannot be made someone else's submitter.
        vm.prank(det);
        vm.expectRevert();
        reg.setSubmitter(address(0xC0));
    }

    receive() external payable {}
}
