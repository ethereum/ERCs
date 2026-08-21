// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchState} from "../src/LaunchAbuseTypes.sol";

/// @dev Conformance cases 6 through 11 from the Test Cases section.
///      The test contract acts as the remediation contract, so it may freeze
///      and open refunds. Nothing else can.
contract LaunchEscrowTest is TestBase {
    LaunchDirectory internal directory;
    LaunchEscrow    internal escrow;
    SaleVenue       internal venue;
    address internal token = address(0x70);

    address internal deployer = address(0xD1);
    address internal alice    = address(0xA1);
    address internal bob      = address(0xB2);
    address internal carol    = address(0xC3);

    bytes32 internal id;
    uint64  internal start;
    uint64  internal end;

    function setUp() public {
        directory = new LaunchDirectory();
        escrow    = new LaunchEscrow(address(this), directory);
        venue     = new SaleVenue(escrow);

        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        id = venue.open(token, deployer, start, end, 1);

        vm.deal(alice, 100 ether);
        vm.deal(bob,   100 ether);
        vm.deal(carol, 100 ether);
    }

    function _buy(address who, uint256 amount) internal {
        vm.prank(who);
        venue.buy{value: amount}();
    }

    // 6. Release follows the schedule, and repeated calls in one block yield nothing.
    function test_06_releaseSchedule() public {
        _buy(alice, 10 ether);

        vm.warp(start + 15 days);
        uint256 released = escrow.releaseProceeds(id);
        assertEq(released, 5 ether, "midpoint should vest half");
        assertEq(deployer.balance, 5 ether, "deployer underpaid");

        // A second call in the same block has nothing left to give.
        vm.expectRevert();
        escrow.releaseProceeds(id);

        vm.warp(end);
        uint256 rest = escrow.releaseProceeds(id);
        assertEq(rest, 5 ether, "remainder should vest at end");
        assertEq(escrow.escrowedProceeds(id), 0, "escrow should be empty");
    }

    // 7. Freezing halts release, and a freeze that is never adjudicated lapses.
    function test_07_freezeHaltsThenLapses() public {
        _buy(alice, 10 ether);
        vm.warp(start + 15 days);

        escrow.freezeLaunch(id, bytes32(uint256(1)));
        assertTrue(escrow.stateOf(id) == LaunchState.Frozen, "not frozen");

        vm.expectRevert();
        escrow.releaseProceeds(id);

        // Indefinite freezing would be a censorship primitive, so it expires.
        vm.warp(start + 15 days + 15 days);
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "freeze did not lapse");
        uint256 got = escrow.releaseProceeds(id);
        assertTrue(got > 0, "release still blocked after lapse");
    }

    // 8. Refunds are never automatic: only the remediation contract can open one.
    function test_08_noAutomaticRefund() public {
        _buy(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        escrow.openRefund(id, 0);

        vm.prank(alice);
        vm.expectRevert();
        escrow.claimRefund(id);
    }

    // 9. Pro-rata refunds are exact and drain the pool without residue.
    function test_09_proRataExact() public {
        _buy(alice, 1 ether);
        _buy(bob,   2 ether);
        _buy(carol, 7 ether);

        vm.warp(start + 15 days);
        escrow.releaseProceeds(id); // 5 ether out, 5 ether escrowed
        escrow.openRefund(id, 0);

        assertEq(escrow.entitlementOf(id, alice), 0.5 ether, "alice");
        assertEq(escrow.entitlementOf(id, bob),   1.0 ether, "bob");
        assertEq(escrow.entitlementOf(id, carol), 3.5 ether, "carol");

        uint256 before = alice.balance;
        vm.prank(alice);
        escrow.claimRefund(id);
        assertEq(alice.balance - before, 0.5 ether, "alice not paid");

        // Claiming twice pays nothing further.
        vm.prank(alice);
        vm.expectRevert();
        escrow.claimRefund(id);
    }

    // 10. A buyer who already exited profitably draws nothing, and must not
    //     dilute the buyers still holding.
    function test_10_netContribution() public {
        _buy(alice, 1 ether);
        _buy(bob,   2 ether);
        _buy(carol, 7 ether);

        // Carol sold her whole allocation for more than she paid.
        venue.reportSale(carol, 8 ether);
        assertEq(escrow.netContributionOf(id, carol), 0, "carol still has net contribution");

        vm.warp(start + 15 days);
        escrow.releaseProceeds(id);
        escrow.openRefund(id, 0);

        assertEq(escrow.entitlementOf(id, carol), 0, "exited buyer drew a refund");

        // Remaining buyers split the pool between them: 5 * 1/3 and 5 * 2/3.
        assertEq(escrow.entitlementOf(id, alice), uint256(5 ether) / 3, "alice share");
        assertEq(escrow.entitlementOf(id, bob),   uint256(10 ether) / 3, "bob share");
    }

    // 11. Opening a refund pool is O(1) in the number of buyers. Measured at a
    //     realistic launch size rather than a token one: a push distribution
    //     over this many buyers would not fit in a block.
    function test_11_openRefundIsConstantGas() public {
        for (uint256 i = 1; i <= 2000; ++i) {
            address buyer = address(uint160(0x1000 + i));
            vm.deal(buyer, 1 ether);
            _buy(buyer, 1 ether);
        }

        vm.warp(start + 15 days);
        escrow.releaseProceeds(id);

        uint256 gasBefore = gasleft();
        escrow.openRefund(id, 0);
        uint256 used = gasBefore - gasleft();

        assertLt(used, 60_000, "openRefund is not constant gas");
    }

    // 14. A holder of only a token address can reach the launch, which is the
    //     precondition for consulting a guard before buying.
    function test_14_resolveLaunchFromTokenAddress() public view {
        bytes32[] memory found = directory.launchesOf(token);
        assertEq(found.length, 1, "token did not resolve to a launch");
        assertTrue(found[0] == id, "resolved to the wrong launch");

        assertTrue(directory.escrowOf(id) == address(escrow), "escrow mismatch");
        assertTrue(directory.venueOf(id) == address(venue), "venue mismatch");
        assertTrue(directory.deployerOf(id) == deployer, "deployer mismatch");
        assertTrue(directory.tokenOf(id) == token, "token mismatch");
    }

    // 15. The identifier is independently derivable, so two implementations
    //     agree on what to call a launch and reports stay portable.
    function test_15_launchIdIsDerivable() public view {
        assertTrue(escrow.deriveLaunchId(token, deployer, 0) == id, "derivation mismatch");
    }

    // 16. A relaunch of the same token by the same deployer gets a fresh id
    //     rather than colliding with its predecessor.
    function test_16_relaunchGetsDistinctId() public {
        SaleVenue venue2 = new SaleVenue(escrow);
        bytes32 id2 = venue2.open(token, deployer, start, end, 1);

        assertTrue(id2 != id, "relaunch collided with the original");
        assertEq(directory.launchesOf(token).length, 2, "both launches should be listed");
        assertEq(directory.launchesBy(deployer).length, 2, "deployer history incomplete");
    }

    // 18. The identifier is bound to its chain, so an id minted on one network
    //     cannot collide with or be replayed against a launch on another.
    function test_18_launchIdIsChainBound() public {
        bytes32 here = escrow.deriveLaunchId(token, deployer, 0);
        vm.chainId(8453); // Base
        bytes32 onBase = escrow.deriveLaunchId(token, deployer, 0);
        assertTrue(here != onBase, "launchId is not chain-bound");
    }

    // 17. Serial-deployer analysis is available on-chain without off-chain linkage.
    function test_17_deployerHistory() public view {
        bytes32[] memory history = directory.launchesBy(deployer);
        assertEq(history.length, 1, "deployer history missing");
    }

    // The escrow may only be funded through the venue's accounting path.
    function test_recordPurchaseRequiresVenue() public {
        vm.prank(alice);
        vm.expectRevert();
        escrow.recordPurchase{value: 1 ether}(id, alice, 1 ether, 1);
    }

    receive() external payable {}
}
