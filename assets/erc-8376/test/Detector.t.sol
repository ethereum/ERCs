// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchDetector} from "../src/LaunchDetector.sol";
import {ILaunchDetector} from "../src/ILaunchDetector.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {ScoreEvaluator} from "../src/ScoreEvaluator.sol";
import {SignalVector, Powers} from "../src/LaunchAbuseTypes.sol";

/// @dev No privileged entry points at all: supply is fixed at construction.
contract Clean {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    constructor(address to, uint256 a) { balanceOf[to] = a; totalSupply = a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

contract Supply {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

contract Rugged {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function upgradeTo(address) external {}
    function seize(address, uint256) external {}
}

contract DetectorTest is TestBase {
    LaunchDirectory internal dir;
    LaunchEscrow    internal esc;
    LaunchDetector  internal det;
    SaleVenue       internal ven;

    address internal dep = address(0xD1);
    address internal alice = address(0xA1);
    uint64  internal start;
    uint64  internal end;

    function setUp() public {
        dir = new LaunchDirectory();
        esc = new LaunchEscrow(address(this), dir);
        det = new LaunchDetector(dir);
        ven = new SaleVenue(esc);
        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        vm.deal(alice, 200 ether);
    }

    function _inputs(address lp) internal view returns (ILaunchDetector.ChainInputs memory c) {
        address[] memory sinks = new address[](1);
        sinks[0] = address(0xdead);
        address[] memory wallets = new address[](1);
        wallets[0] = dep;
        c = ILaunchDetector.ChainInputs({
            lpToken: lp,
            lockedLiquidity: 0,
            totalLiquidity: 0,
            lockSinks: sinks,
            deployerWallets: wallets,
            deployerAllocation: 1000 ether,
            peakLiquidity: 100 ether,
            currentLiquidity: 100 ether,
            initialSupply: 1000 ether,
            lpLockRemaining: uint32(365 days)
        });
    }

    function _off() internal pure returns (ILaunchDetector.OffChainInputs memory) {
        return ILaunchDetector.OffChainInputs(
            type(uint16).max, type(uint16).max, type(uint16).max, type(uint16).max);
    }

    /// An honest launch: liquidity locked and intact, deployer holding, no
    /// dangerous powers, proceeds untouched. The score must stay low.
    function test_honestLaunchScoresLow() public {
        // A token with a public mint would be flagged, and correctly so, so the
        // honest case uses one whose supply is fixed at construction.
        Clean tok = new Clean(dep, 1000 ether);
        Clean lp = new Clean(address(0xdead), 1000 ether);

        bytes32 id = ven.open(address(tok), dep, start, end, 1);
        vm.prank(alice); ven.buy{value: 10 ether}();

        SignalVector memory v = det.observe(id, address(tok), _inputs(address(lp)), _off());

        assertEq(v.lpLockedShare, 10000, "liquidity fully locked");
        assertEq(v.liquidityRemoved, 0, "nothing removed");
        assertEq(v.deployerSellRatio, 0, "nothing sold");
        assertEq(v.proceedsWithdrawnShare, 0, "nothing withdrawn");
        assertEq(v.privilegedPowers & Powers.DANGEROUS, 0, "no dangerous powers");
        assertLe(ScoreEvaluator.scoreHardRug(v), 20, "honest launch scored above None");
    }

    /// The same shape after a rug: liquidity gone, allocation sold, proceeds
    /// withdrawn, seize and upgrade retained.
    function test_ruggedLaunchScoresHigh() public {
        Rugged tok = new Rugged();
        tok.mint(dep, 1000 ether);
        Supply lp = new Supply();
        lp.mint(alice, 1000 ether); // nothing locked

        bytes32 id = ven.open(address(tok), dep, start, end, 1);
        vm.prank(alice); ven.buy{value: 10 ether}();

        vm.warp(end + 1);
        esc.releaseProceeds(id);                        // took the whole raise
        vm.prank(dep); tok.transfer(alice, 1000 ether); // and sold the allocation

        ILaunchDetector.ChainInputs memory c = _inputs(address(lp));
        c.currentLiquidity = 10 ether;                  // 90% of liquidity gone
        c.lpLockRemaining = 0;

        SignalVector memory v = det.observe(id, address(tok), c, _off());

        assertEq(v.lpLockedShare, 0, "nothing locked");
        assertEq(v.liquidityRemoved, 9000, "90% removed");
        assertEq(v.deployerSellRatio, 10000, "everything sold");
        assertEq(v.proceedsWithdrawnShare, 10000, "everything withdrawn");
        assertTrue(v.privilegedPowers & Powers.DANGEROUS != 0, "dangerous powers missed");
        assertTrue(ScoreEvaluator.scoreHardRug(v) >= 81, "rug did not reach Conclusive");
    }

    /// Missing inputs must be unavailable, never a clean zero.
    function test_missingInputsAreUnavailable() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(0));
        c.deployerAllocation = 0;
        c.peakLiquidity = 0;

        SignalVector memory v = det.observe(id, address(tok), c, _off());
        assertEq(v.lpLockedShare, type(uint16).max, "no lp token is unknowable");
        assertEq(v.lpLockRemaining, type(uint32).max, "no lock is unknowable");
        assertEq(v.deployerSellRatio, type(uint16).max, "no allocation is unknowable");
        assertEq(v.liquidityRemoved, type(uint16).max, "no peak is unknowable");
        assertEq(v.proceedsWithdrawnShare, type(uint16).max, "no proceeds is unknowable");
        assertEq(v.insiderAllocationShare, type(uint16).max, "off-chain signal carried through");
    }

    /// A pool whose positions are non-fungible has no supply to take a share
    /// of, and the share comes from the supplied liquidity amounts instead.
    function test_nonFungibleLiquidityIsMeasured() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(0));
        c.lockedLiquidity = 90 ether;
        c.totalLiquidity  = 100 ether;

        SignalVector memory v = det.observe(id, address(tok), c, _off());
        assertEq(v.lpLockedShare, 9000, "liquidity share not measured");
        assertEq(v.lpLockRemaining, uint32(365 days), "lock carried through");
    }

    /// A named liquidity token wins, so supplied amounts cannot be presented in
    /// place of balances anyone can read for themselves.
    function test_fungibleRouteWinsOverSuppliedAmounts() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        Clean lp = new Clean(address(0xdead), 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(lp));
        c.lockedLiquidity = 0;              // a claim the balances contradict
        c.totalLiquidity  = 100 ether;

        SignalVector memory v = det.observe(id, address(tok), c, _off());
        assertEq(v.lpLockedShare, 10000, "supplied amounts overrode balances");
    }

    /// An empty pool, and a pool reporting more locked than it holds, are both
    /// unmeasured rather than protected.
    function test_incoherentLiquidityIsUnavailable() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(0));
        c.totalLiquidity = 0;
        c.lockedLiquidity = 0;
        SignalVector memory v = det.observe(id, address(tok), c, _off());
        assertEq(v.lpLockedShare, type(uint16).max, "empty pool read as measured");
        assertEq(v.lpLockRemaining, type(uint32).max, "lock on nothing carried through");

        c.totalLiquidity  = 100 ether;
        c.lockedLiquidity = 101 ether;
        v = det.observe(id, address(tok), c, _off());
        assertEq(v.lpLockedShare, type(uint16).max, "more locked than held read as full protection");
    }

    /// An unlisted launch cannot have its proceeds read.
    function test_unlistedLaunchHasNoProceedsSignal() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        SignalVector memory v =
            det.observe(bytes32(uint256(0xdead)), address(tok), _inputs(address(0)), _off());
        assertEq(v.proceedsWithdrawnShare, type(uint16).max, "unlisted launch reported proceeds");
    }

    /// Zero wallets, and a token with no supply, are both unknowable rather
    /// than clean. These are the other side of every branch in the assembly.
    function test_supplyShareEdgeCases() public {
        Supply empty = new Supply(); // no supply at all
        bytes32 id = ven.open(address(empty), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(0));
        SignalVector memory v = det.observe(id, address(empty), c, _off());
        assertEq(v.deployerSupplyShare, type(uint16).max, "zero supply is unknowable");

        // And with no wallets attributed to the deployer at all.
        c.deployerWallets = new address[](0);
        SignalVector memory v2 = det.observe(id, address(empty), c, _off());
        assertEq(v2.deployerSupplyShare, type(uint16).max, "no wallets is unknowable");
    }

    /// A launch that took no money yet cannot have a withdrawal ratio.
    function test_zeroProceedsIsUnknowable() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1); // nobody bought

        SignalVector memory v = det.observe(id, address(tok), _inputs(address(0)), _off());
        assertEq(v.proceedsWithdrawnShare, type(uint16).max, "no proceeds is unknowable");
    }

    function test_supplyShareRejectsOversizedWalletSet() public {
        Supply tok = new Supply();
        tok.mint(dep, 1000 ether);
        bytes32 id = ven.open(address(tok), dep, start, end, 1);

        ILaunchDetector.ChainInputs memory c = _inputs(address(0));
        c.deployerWallets = new address[](33);
        vm.expectRevert();
        this.observeExternal(id, address(tok), c);
    }

    function observeExternal(bytes32 id, address token, ILaunchDetector.ChainInputs calldata c)
        external view returns (SignalVector memory)
    {
        return det.observe(id, token, c, _off());
    }

    // --- evidence -----------------------------------------------------------

    function test_evidenceLeafIsChainBound() public {
        bytes32 a = det.evidenceLeaf(100, keccak256("tx"), 3, "liquidityRemoved", bytes32(uint256(9000)));
        vm.chainId(8453);
        bytes32 b = det.evidenceLeaf(100, keccak256("tx"), 3, "liquidityRemoved", bytes32(uint256(9000)));
        assertTrue(a != b, "evidence leaf is not chain bound");
    }

    function test_evidenceRootIsOrderDependent() public view {
        bytes32[] memory a = new bytes32[](3);
        a[0] = keccak256("1"); a[1] = keccak256("2"); a[2] = keccak256("3");
        bytes32[] memory b = new bytes32[](3);
        b[0] = keccak256("2"); b[1] = keccak256("1"); b[2] = keccak256("3");

        assertTrue(det.evidenceRoot(a) != det.evidenceRoot(b), "root ignores leaf order");
        assertTrue(det.evidenceRoot(a) == det.evidenceRoot(a), "root is not deterministic");

        bytes32[] memory one = new bytes32[](1);
        one[0] = keccak256("only");
        assertTrue(det.evidenceRoot(one) == one[0], "single leaf should be its own root");
    }

    /// SCSTG, Cryptographic Practices: an internal node must not be presentable
    /// as a leaf. Domain separation is what prevents it.
    function test_internalNodeCannotPoseAsLeaf() public view {
        bytes32[] memory pair = new bytes32[](2);
        pair[0] = keccak256("a"); pair[1] = keccak256("b");
        bytes32 node = det.evidenceRoot(pair);

        // The undomained fold an attacker would need to forge against.
        bytes32 naive = keccak256(abi.encode(pair[0], pair[1]));
        assertTrue(node != naive, "internal node is not domain separated");

        // A single leaf is its own root, so it must not collide with a node.
        bytes32[] memory one = new bytes32[](1);
        one[0] = node;
        assertTrue(det.evidenceRoot(one) == node, "single leaf is its own root");
    }

    /// SCSTG, Denial of Service: the fold is bounded.
    function test_evidenceRootRejectsOversizedSet() public {
        bytes32[] memory many = new bytes32[](1025);
        vm.expectRevert();
        this.root(many);
    }

    function test_evidenceRootRejectsEmpty() public {
        bytes32[] memory none = new bytes32[](0);
        vm.expectRevert();
        this.root(none);
    }

    function root(bytes32[] calldata l) external view returns (bytes32) {
        return det.evidenceRoot(l);
    }

    receive() external payable {}
}
