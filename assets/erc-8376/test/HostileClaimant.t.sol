// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;
import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {AbuseReport, SignalVector, ClaimStatus, Patterns} from "../src/LaunchAbuseTypes.sol";

/// @dev A claimant that refuses payment.
contract HostileClaimant {
    function open(LaunchRemediation r, bytes32 id, bytes32 rep) external payable returns (bytes32) {
        return r.openClaim{value: msg.value}(id, rep, "x");
    }
    receive() external payable { revert("no"); }
}

/// @dev Regression: a claimant that refuses payment must not be able to block
///      the state transitions that owe it. Payouts credit; collection is a pull.
contract HostileClaimantTest is TestBase {
    LaunchDirectory d; LaunchRemediation rem; LaunchAbuseRegistry reg; LaunchEscrow e; SaleVenue v;
    address adj = address(0xAD); address dep = address(0xD1); address det = address(0xDE);
    bytes32 id; uint64 start;

    function setUp() public {
        d = new LaunchDirectory();
        rem = new LaunchRemediation(adj, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        e = new LaunchEscrow(address(rem), d);
        rem.initialize(e, reg);
        v = new SaleVenue(e);
        start = uint64(block.timestamp);
        id = v.open{value: 5 ether}(address(0x70), dep, start, uint64(block.timestamp + 30 days), 1);
        vm.deal(det, 10 ether);
        vm.prank(det); reg.bondDetector{value: 1 ether}();
    }

    function test_hostileClaimantCannotBlockResolution() public {
        AbuseReport memory r;
        r.patternId = Patterns.HARD_RUG; r.launchId = id; r.token = address(0x70);
        r.deployer = dep; r.linkedAddresses = new address[](0);
        r.abuseScore = 95; r.confidence = 90; r.launchedAt = start;
        r.vectorVersion = 1;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0,0,0,0,0,6000,7000,9000,0x0011,2,0,0);
        r.evidenceRoot = keccak256("e"); r.evidenceURI = "ipfs://e";
        vm.prank(det); bytes32 rep = reg.submitReport(r);

        HostileClaimant h = new HostileClaimant();
        vm.deal(address(h), 1 ether);
        bytes32 cid = h.open{value: 0.1 ether}(rem, id, rep);

        // Settling succeeds: the claimant is credited, not paid.
        vm.deal(dep, 10 ether);
        vm.prank(dep);
        rem.settle{value: 1 ether}(cid, 1 ether);

        (, , ClaimStatus st, ) = rem.getClaim(cid);
        assertTrue(st == ClaimStatus.Settled, "settle was blocked");
        assertEq(rem.withdrawable(address(h)), 1.1 ether, "claimant not credited");

        // The hostile claimant simply cannot collect what it is owed.
        vm.prank(address(h));
        vm.expectRevert();
        rem.withdraw();
    }
}
