// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;
import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {SaleVenue} from "../src/SaleVenue.sol";

/// @dev Regression tests for findings from the security pass. Each of these
///      passed as an exploit before the fix.
contract SecurityRegressionTest is TestBase {
    LaunchDirectory d; LaunchEscrow e; SaleVenue v1; SaleVenue v2;
    address alice = address(0xA1); address bob = address(0xB2);
    bytes32 id1; bytes32 id2;
    function setUp() public {
        d = new LaunchDirectory();
        e = new LaunchEscrow(address(this), d);
        v1 = new SaleVenue(e); v2 = new SaleVenue(e);
        id1 = v1.open(address(0x11), address(0xD1), uint64(block.timestamp), uint64(block.timestamp+30 days), 1);
        id2 = v2.open(address(0x22), address(0xD2), uint64(block.timestamp), uint64(block.timestamp+30 days), 1);
        vm.deal(alice, 100 ether); vm.deal(bob, 100 ether);
    }
    // FINDING (critical): shrinking the pro-rata denominator after the pool
    // opened let one buyer draw 15 ether from a 10 ether pool, taking the
    // excess from a different launch's escrowed funds.
    function test_denominatorFrozenOncePoolOpens() public {
        // Launch 2 is an innocent bystander holding 50 ether.
        vm.prank(bob); v2.buy{value: 50 ether}();
        // Launch 1 has two buyers, 10 ether total.
        vm.prank(alice); v1.buy{value: 5 ether}();
        vm.prank(bob);   v1.buy{value: 5 ether}();

        e.openRefund(id1, 0);                 // pool = 10 ether, denominator = 10 ether
        uint256 pool = 10 ether;
        uint256 escrowBefore = address(e).balance;

        vm.prank(bob); e.claimRefund(id1);    // bob legitimately takes his 5

        // Every path that moves the denominator is now closed once refunding.
        vm.expectRevert();
        e.markLinked(id1, bob);

        vm.prank(alice); e.claimRefund(id1);

        uint256 paidOut = escrowBefore - address(e).balance;
        assertLe(paidOut, pool, "pool was over-drawn");
        assertEq(paidOut, pool, "pool should pay out exactly once");
        // Launch 2's funds are untouched.
        assertEq(e.escrowedProceeds(id2), 50 ether, "bystander launch was raided");
    }

    // The other two denominator paths are closed too.
    function test_purchaseAndSaleBlockedOncePoolOpens() public {
        vm.prank(alice); v1.buy{value: 5 ether}();
        e.openRefund(id1, 0);

        vm.prank(bob);
        vm.expectRevert();
        v1.buy{value: 1 ether}();

        vm.expectRevert();
        v1.reportSale(alice, 1 ether);
    }
}
