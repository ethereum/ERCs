// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;
import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {SaleVenue} from "../src/SaleVenue.sol";

/// @dev Regression: the identifier is predictable from public inputs, so the
///      directory must bind a listing to the escrow the identifier commits to.
contract DirectorySquatTest is TestBase {
    function test_squattingIsRejected() public {
        LaunchDirectory d = new LaunchDirectory();
        LaunchEscrow e = new LaunchEscrow(address(this), d);
        SaleVenue v = new SaleVenue(e);

        address token = address(0x11);
        address deployer = address(0xD1);

        // Every input is public: chain id, escrow address, token, deployer, nonce 0.
        bytes32 predicted = e.deriveLaunchId(token, deployer, 0);

        // An attacker cannot squat it: the identifier does not recompute to them.
        vm.prank(address(0xBAD));
        vm.expectRevert();
        d.list(predicted, token, deployer, address(0xBAD), 0);

        // The real registration proceeds, and the record attributes correctly.
        bytes32 id = v.open(token, deployer, uint64(block.timestamp), uint64(block.timestamp + 1 days), 1);
        assertTrue(id == predicted, "identifier mismatch");
        assertTrue(d.escrowOf(id) == address(e), "record misattributed");
    }
}
