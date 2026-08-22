// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";

/// @dev The escrow trusts the venue on purchases and sales. These cover what
///      that trust means for the venue's own callers, and the accounting that
///      decides how a refund pool is divided.
contract VenueGuardsTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    SaleVenue           internal ven;

    address internal adj     = address(0xAD);
    address internal dep     = address(0xD1);
    address internal alice   = address(0xA1);
    address internal mallory = address(0xBAD);
    address internal token   = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(adj, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        ven = new SaleVenue(esc); // this contract is the operator

        start = uint64(block.timestamp);
        id = ven.open{value: 5 ether}(token, dep, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(alice, 100 ether);
        vm.deal(mallory, 100 ether);
    }

    /// @dev A sale report shrinks the buyer's net contribution and the refund
    ///      denominator with it. Left open to anyone, it zeroes a chosen
    ///      buyer's entitlement and hands their share to whoever is left.
    function test_reportSaleIsOperatorOnly() public {
        vm.prank(alice);
        ven.buy{value: 9 ether}();
        vm.prank(mallory);
        ven.buy{value: 1 ether}();

        vm.prank(mallory);
        vm.expectPartialRevert(SaleVenue.NotOperator.selector);
        ven.reportSale(alice, 9 ether);

        assertEq(esc.netContributionOf(id, alice), 9 ether, "alice's contribution was reduced");
        assertEq(esc.totalNetPaid(id), 10 ether, "the denominator was reduced");
    }

    /// @dev Whoever opens the launch names the deployer, the schedule and the
    ///      bond, and every later purchase settles under those terms.
    function test_openIsOperatorOnly() public {
        SaleVenue fresh = new SaleVenue(esc);
        vm.prank(mallory);
        vm.expectPartialRevert(SaleVenue.NotOperator.selector);
        fresh.open(token, mallory, start, start, 1);
    }

    /// @dev A buyer whose realised value already exceeds what they paid nets to
    ///      zero. A further purchase must not add gross value to the
    ///      denominator, or it scales down every other buyer's share and
    ///      strands that much of the pool.
    function test_denominatorTracksNetNotGross() public {
        vm.prank(alice);
        ven.buy{value: 1 ether}();
        ven.reportSale(alice, 3 ether); // exited for more than she paid

        assertEq(esc.netContributionOf(id, alice), 0, "alice should net to zero");
        assertEq(esc.totalNetPaid(id), 0, "denominator should be empty");

        vm.prank(alice);
        ven.buy{value: 2 ether}(); // total paid 3, total realised 3

        assertEq(esc.netContributionOf(id, alice), 0, "alice still nets to zero");
        assertEq(esc.totalNetPaid(id), 0, "gross purchase entered the denominator");
    }

    /// @dev And the ordinary case still accumulates.
    function test_denominatorAccumulatesNormally() public {
        vm.prank(alice);
        ven.buy{value: 4 ether}();
        ven.reportSale(alice, 1 ether);
        vm.prank(alice);
        ven.buy{value: 2 ether}();

        // paid 6, realised 1
        assertEq(esc.netContributionOf(id, alice), 5 ether, "net contribution wrong");
        assertEq(esc.totalNetPaid(id), 5 ether, "denominator wrong");
    }
}
