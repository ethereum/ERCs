// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {SignalProbe} from "../src/SignalProbe.sol";
import {Powers} from "../src/LaunchAbuseTypes.sol";

contract MockERC20 {
    string public name = "Mock";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev USDT-style: transfers succeed but return nothing at all.
contract NoReturnERC20 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; totalSupply += amount; }
    function approve(address s_, uint256 a) external { allowance[msg.sender][s_] = a; }
    function transfer(address to, uint256 a) external {
        balanceOf[msg.sender] -= a; balanceOf[to] += a;
    }
    function transferFrom(address f, address t, uint256 a) external {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a;
    }
}

/// @dev A token with no privileged entry points at all.
contract PlainToken {
    mapping(address => uint256) public balanceOf;
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev A token retaining mint, upgrade and seize: every dangerous power.
contract PoweredToken {
    function mint(address, uint256) external {}
    function upgradeTo(address) external {}
    function seize(address, uint256) external {}
    function pause() external {}
}

contract Erc20AndProbeTest is TestBase {
    using SignalProbe for address;

    LaunchDirectory internal directory;
    LaunchEscrow    internal escrow;
    MockERC20       internal asset;

    address internal deployer = address(0xD1);
    address internal alice    = address(0xA1);
    address internal bob      = address(0xB2);

    bytes32 internal id;
    uint64  internal start;
    uint64  internal end;

    // The test contract acts as both venue and remediation.
    function setUp() public {
        directory = new LaunchDirectory();
        escrow    = new LaunchEscrow(address(this), directory);
        asset     = new MockERC20();

        asset.mint(address(this), 1_000 ether);

        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        asset.transfer(address(escrow), 100 ether); // venue delivers, then records
        id = escrow.registerLaunch(
            address(0x70), deployer, address(asset), 100 ether, start, end
        );
    }

    // Settlement in an ERC-20 works end to end, which a VIRTUAL-paired or
    // USDC-paired venue requires.
    function test_erc20SettlementFullCycle() public {
        asset.transfer(address(escrow), 100 ether);
        escrow.recordPurchase(id, alice, 60 ether, 60);
        escrow.recordPurchase(id, bob, 40 ether, 40);

        assertEq(escrow.escrowedProceeds(id), 100 ether, "proceeds not escrowed");
        assertEq(asset.balanceOf(address(escrow)), 200 ether, "escrow balance wrong");

        vm.warp(start + 15 days);
        uint256 released = escrow.releaseProceeds(id);
        assertEq(released, 50 ether, "midpoint vest wrong");
        assertEq(asset.balanceOf(deployer), 50 ether, "deployer not paid in asset");

        escrow.openRefund(id, 0);
        assertEq(escrow.entitlementOf(id, alice), 30 ether, "alice pro-rata");
        assertEq(escrow.entitlementOf(id, bob),   20 ether, "bob pro-rata");

        vm.prank(alice);
        escrow.claimRefund(id);
        assertEq(asset.balanceOf(alice), 30 ether, "alice not refunded in asset");
    }

    // Bond is held and paid in the launch asset, not in native value.
    function test_erc20BondDrawnForShortfall() public {
        asset.transfer(address(escrow), 10 ether);
        escrow.recordPurchase(id, alice, 10 ether, 10);
        assertEq(escrow.bondOf(id), 100 ether, "bond not recorded");

        escrow.openRefund(id, 40 ether); // draw from bond on top of escrow
        assertEq(escrow.bondOf(id), 60 ether, "bond not drawn");
        assertEq(escrow.entitlementOf(id, alice), 50 ether, "pool should be escrow plus bond");
    }

    function test_nativeValueRejectedOnErc20Launch() public {
        vm.expectRevert();
        escrow.recordPurchase{value: 1 ether}(id, alice, 1 ether, 1);
    }

    // --- signal probe -------------------------------------------------------

    // Privileged powers are derivable from bytecode, so a detector does not
    // have to be trusted for this signal.
    function test_probeDetectsDangerousPowers() public {
        PoweredToken powered = new PoweredToken();
        uint16 mask = SignalProbe.privilegedPowers(address(powered));

        assertTrue(mask & Powers.MINT != 0, "mint not detected");
        assertTrue(mask & Powers.UPGRADE != 0, "upgrade not detected");
        assertTrue(mask & Powers.SEIZE != 0, "seize not detected");
        assertTrue(mask & Powers.PAUSE != 0, "pause not detected");
        assertTrue(mask & Powers.DANGEROUS != 0, "dangerous mask empty");
    }

    function test_probeCleanTokenHasNoPowers() public {
        PlainToken plain = new PlainToken();
        uint16 mask = SignalProbe.privilegedPowers(address(plain));
        assertEq(mask & Powers.DANGEROUS, 0, "clean token flagged as dangerous");
    }

    function test_probeEmptyAccountIsClean() public view {
        assertEq(SignalProbe.privilegedPowers(address(0xBEEF)), 0, "EOA reported powers");
    }

    // Protective share, and the unavailability sentinel when supply is zero.
    function test_probeLockedShare() public {
        MockERC20 lp = new MockERC20();
        lp.mint(address(0xdead), 800 ether); // burned
        lp.mint(alice, 200 ether);

        address[] memory sinks = new address[](1);
        sinks[0] = address(0xdead);
        assertEq(SignalProbe.lockedShare(address(lp), sinks), 8000, "locked share wrong");

        MockERC20 empty = new MockERC20();
        assertEq(
            SignalProbe.lockedShare(address(empty), sinks),
            type(uint16).max,
            "zero supply must be unavailable, not fully protected"
        );
    }

    // SCSTG, Component-Specific Security: a token that returns nothing from
    // `transfer` must still settle. USDT is the canonical example.
    function test_noReturnTokenSettles() public {
        NoReturnERC20 usdtLike = new NoReturnERC20();
        usdtLike.mint(address(this), 1_000 ether);
        usdtLike.transfer(address(escrow), 10 ether);

        bytes32 id2 = escrow.registerLaunch(
            address(0x71), deployer, address(usdtLike), 10 ether, start, end
        );
        usdtLike.transfer(address(escrow), 40 ether);
        escrow.recordPurchase(id2, alice, 40 ether, 40);
        assertEq(usdtLike.balanceOf(address(escrow)), 50 ether, "escrow did not receive");

        vm.warp(start + 15 days);
        escrow.releaseProceeds(id2);
        assertEq(usdtLike.balanceOf(deployer), 20 ether, "deployer not paid in no-return token");
    }

    // SCSTG, Denial of Service: caller-supplied arrays are bounded.
    function test_probeRejectsOversizedArrays() public {
        MockERC20 lp = new MockERC20();
        lp.mint(alice, 1 ether);
        address[] memory many = new address[](33);
        vm.expectRevert();
        this.probeLocked(address(lp), many);
    }

    function probeLocked(address lp, address[] memory sinks) external view returns (uint16) {
        return SignalProbe.lockedShare(lp, sinks);
    }

    function test_probeLiquidityRemoved() public pure {
        assertEq(SignalProbe.liquidityRemoved(100 ether, 40 ether), 6000, "60% removed");
        assertEq(SignalProbe.liquidityRemoved(100 ether, 100 ether), 0, "nothing removed");
        assertEq(SignalProbe.liquidityRemoved(0, 0), type(uint16).max, "no peak is unavailable");
    }

    receive() external payable {}
}
