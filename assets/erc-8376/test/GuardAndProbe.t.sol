// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {SignalProbe} from "../src/SignalProbe.sol";
import {Powers} from "../src/LaunchAbuseTypes.sol";

/// @dev A deployer that tries to re-enter while being paid.
contract ReentrantDeployer {
    LaunchEscrow public escrow;
    bytes32 public id;
    bool public reentryAttempted;
    bool public reentryBlocked;

    function arm(LaunchEscrow e, bytes32 i) external { escrow = e; id = i; }

    receive() external payable {
        if (address(escrow) == address(0)) return;
        reentryAttempted = true;
        try escrow.releaseProceeds(id) { reentryBlocked = false; }
        catch { reentryBlocked = true; }
    }
}

contract Logic {
    function mint(address, uint256) external {}
}

contract Tok2 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

contract GuardAndProbeTest is TestBase {
    LaunchDirectory internal dir;
    LaunchEscrow    internal esc;
    SaleVenue       internal ven;

    address internal alice = address(0xA1);
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        esc = new LaunchEscrow(address(this), dir);
        ven = new SaleVenue(esc);
        start = uint64(block.timestamp);
        vm.deal(alice, 100 ether);
    }

    // --- the lock actually fires -------------------------------------------

    /// The guard was added on the strength of an argument. This proves it.
    function test_reentrancyGuardBlocksReentry() public {
        ReentrantDeployer d = new ReentrantDeployer();
        bytes32 id = ven.open(address(0x70), address(d), start, start + 30 days, 1);
        d.arm(esc, id);

        vm.prank(alice); ven.buy{value: 10 ether}();
        vm.warp(start + 15 days);

        esc.releaseProceeds(id); // pays the deployer, which re-enters on receive

        assertTrue(d.reentryAttempted(), "the deployer never tried to re-enter");
        assertTrue(d.reentryBlocked(), "reentry was NOT blocked");
        assertEq(address(d).balance, 5 ether, "deployer should be paid once, not twice");
    }

    // --- proxy resolution ---------------------------------------------------

    /// EIP-1167 clones are resolved from bytecode, with no getter to call.
    function test_probeResolvesMinimalProxy() public {
        Logic logic = new Logic();
        address clone = _clone(address(logic));

        (address impl, bool isProxy, bool resolved) = _resolve(clone);
        assertTrue(isProxy, "clone not recognized as a proxy");
        assertTrue(resolved, "clone should resolve");
        assertTrue(impl == address(logic), "clone resolved to the wrong target");

        (uint16 mask, bool exact) = SignalProbe.powersOf(clone);
        assertTrue(exact, "clone should be exact");
        assertTrue(mask & Powers.UPGRADE != 0, "a clone is upgradeable by its deployer");
        assertTrue(mask & Powers.MINT != 0, "implementation powers not followed through the clone");
    }

    function _resolve(address t) internal view returns (address, bool, bool) {
        return SignalProbe.implementationOf(t);
    }

    function _clone(address target) internal returns (address addr) {
        bytes20 t = bytes20(target);
        assembly {
            let p := mload(0x40)
            mstore(p, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(p, 0x14), t)
            mstore(add(p, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            addr := create(0, p, 0x37)
        }
    }

    // --- remaining probe surface -------------------------------------------

    function test_sellRatioPaths() public {
        Tok2 t = new Tok2();
        address[] memory wallets = new address[](1);
        wallets[0] = alice;

        // No allocation is unknowable, not clean.
        assertEq(SignalProbe.sellRatio(address(t), wallets, 0), type(uint16).max, "zero allocation");

        // Holding everything means nothing sold.
        t.mint(alice, 100 ether);
        assertEq(SignalProbe.sellRatio(address(t), wallets, 100 ether), 0, "nothing sold");

        // Holding more than allocated also reads as nothing sold.
        assertEq(SignalProbe.sellRatio(address(t), wallets, 50 ether), 0, "surplus holding");

        // Half gone.
        vm.prank(alice); t.transfer(address(0xDEAD), 50 ether);
        assertEq(SignalProbe.sellRatio(address(t), wallets, 100 ether), 5000, "half sold");
    }

    function test_sellRatioRejectsOversizedArray() public {
        Tok2 t = new Tok2();
        address[] memory many = new address[](33);
        vm.expectRevert();
        this.probeSell(address(t), many, 1 ether);
    }

    function probeSell(address t, address[] memory w, uint256 a) external view returns (uint16) {
        return SignalProbe.sellRatio(t, w, a);
    }

    function test_toBpsEdges() public pure {
        assertEq(SignalProbe.toBps(0, 0), type(uint16).max, "zero denominator is unknowable");
        assertEq(SignalProbe.toBps(1, 2), 5000, "half");
        assertEq(SignalProbe.toBps(5, 1), 10000, "saturates at full");
    }

    function test_implementationOfPlainAccounts() public view {
        (address a, bool p, bool r) = _resolve(address(0xBEEF)); // no code
        assertTrue(a == address(0xBEEF), "EOA should resolve to itself");
        assertTrue(!p, "EOA is not a proxy");
        assertTrue(r, "EOA resolves");
    }

    receive() external payable {}
}
