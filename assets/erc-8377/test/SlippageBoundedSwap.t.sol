// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SlippageBoundedSwap, ISlippageBoundedSwap, SlippagePolicy} from "../src/SlippageBoundedSwap.sol";
import {MockQuoteOracle} from "./mocks/MockQuoteOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @dev Concrete test router: `_route` delivers a settable amount of the real output token to the
/// recipient, standing in for a venue fill. The guard measures the balance delta, so the settled
/// number has to actually be paid, not merely reported.
contract TestSwap is SlippageBoundedSwap {
    uint256 public nextOut;
    bool public keepOutput;

    function setNextOut(uint256 v) external {
        nextOut = v;
    }

    /// @dev Deliver to the executor instead of the recipient, standing in for a router that
    /// forwards nothing, takes the whole output as a fee, or simply sits in the path.
    function setKeepOutput(bool v) external {
        keepOutput = v;
    }

    function _route(address, address tokenOut, uint256, address recipient, bytes calldata)
        internal
        override
    {
        MockERC20(tokenOut).mint(keepOutput ? address(this) : recipient, nextOut);
    }
}

contract SlippageBoundedSwapTest is Test {
    address internal constant RECIPIENT = address(0xBEEF);
    TestSwap internal swapc;
    MockQuoteOracle internal oracle;
    MockERC20 internal tokenOutTok;
    address internal tokenIn = address(0x1111);
    address internal tokenOut;

    function setUp() public {
        swapc = new TestSwap();
        oracle = new MockQuoteOracle(); // rate 1e18 => referenceOut == amountIn
        tokenOutTok = new MockERC20();
        tokenOut = address(tokenOutTok);
    }

    function _policy(uint32 expectedCostBps, uint32 maxDeviationBps, uint256 hardFloor)
        internal
        view
        returns (SlippagePolicy memory)
    {
        return _policyBy(expectedCostBps, maxDeviationBps, hardFloor, 0);
    }

    function _policyBy(uint32 expectedCostBps, uint32 maxDeviationBps, uint256 hardFloor, uint256 deadline)
        internal
        view
        returns (SlippagePolicy memory)
    {
        return SlippagePolicy({
            quoteOracle: address(oracle),
            expectedCostBps: expectedCostBps,
            maxDeviationBps: maxDeviationBps,
            hardFloor: hardFloor,
            deadline: deadline
        });
    }

    function test_passesWithinTolerance() public {
        // referenceOut 1000, no expected cost, 1% adverse tolerance => floor 990; realized 995 passes.
        swapc.setNextOut(995);
        uint256 out = swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
        assertEq(out, 995);
    }

    function test_revertsBelowFloor() public {
        // floor 990; realized 989 reverts.
        swapc.setNextOut(989);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(989), uint256(990))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
    }

    function test_expectedCostAndAdverseToleranceStack() public {
        // referenceOut 1000 mid. expectedCost 2% => expectedOut 980. adverse 1% => floor 970.
        // This is the two-field split: the known cost is not spent as adverse headroom.
        swapc.setNextOut(970);
        uint256 out = swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(200, 100, 0), "");
        assertEq(out, 970);

        // One unit below the stacked floor reverts.
        swapc.setNextOut(969);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(969), uint256(970))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(200, 100, 0), "");
    }

    function test_hardFloorTakesOverWhenHigher() public {
        // reference floor 990, hardFloor 996 => effective floor 996; realized 995 reverts.
        swapc.setNextOut(995);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(995), uint256(996))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 996), "");
    }

    function test_referenceIsLiveNotCallerSupplied() public {
        // Moving the oracle rate moves the floor with it, proving the reference is read at execution.
        oracle.setRate(2e18); // referenceOut 2000, 1% floor => 1980
        swapc.setNextOut(1979);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(1979), uint256(1980))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
    }

    function test_adversarialSandwich() public {
        // A sandwich: the reference stays a fresh mid at 1000, the caller budgets 0.3% cost and 0.5%
        // adverse tolerance (floor = 1000 * 0.997 * 0.995 = 992). An attacker moves the pool so the
        // fill lands at 991, one below the adverse floor, and the swap must revert rather than settle.
        swapc.setNextOut(991);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(991), uint256(992))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(30, 50, 0), "");

        // The same policy settles when the fill stays within the adverse band.
        swapc.setNextOut(992);
        uint256 out = swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(30, 50, 0), "");
        assertEq(out, 992);
    }

    function test_routeCannotReportUnpaidOutput() public {
        // The route delivers nothing but the guard measures a zero balance delta, so a claimed fill
        // cannot pass. Proves the floor is checked against real balance, not a route-reported number.
        swapc.setNextOut(0);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, uint256(0), uint256(990))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
    }

    function test_revertsOnInvalidPolicy() public {
        swapc.setNextOut(1000);
        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.InvalidPolicy.selector, uint32(10_001), uint32(100))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(10_001, 100, 0), "");

        vm.expectRevert(
            abi.encodeWithSelector(ISlippageBoundedSwap.InvalidPolicy.selector, uint32(0), uint32(10_001))
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 10_001, 0), "");
    }

    function test_bubblesOracleRevert() public {
        oracle.setShouldRevert(true);
        swapc.setNextOut(1000);
        vm.expectRevert(bytes("oracle: no fresh quote"));
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
    }

    function test_supportsInterface() public view {
        // Pins the value the specification states, so a change to the interface cannot go unnoticed.
        assertEq(type(ISlippageBoundedSwap).interfaceId, bytes4(0x41b46b60), "interface id moved");
        assertTrue(swapc.supportsInterface(0x41b46b60));
        assertTrue(swapc.supportsInterface(type(ISlippageBoundedSwap).interfaceId));
        assertTrue(swapc.supportsInterface(0x01ffc9a7));
        assertFalse(swapc.supportsInterface(0xffffffff));
    }

    // The bound is on what the recipient received. An executor that keeps the output cannot
    // satisfy it, which is the whole reason the measurement moved off the executor.
    function test_executorKeepingOutputCannotSatisfyTheFloor() public {
        swapc.setNextOut(1000);
        swapc.setKeepOutput(true);
        vm.expectRevert(abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, 0, 990));
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policy(0, 100, 0), "");
        assertEq(MockERC20(tokenOut).balanceOf(RECIPIENT), 0, "recipient received nothing");
    }

    // A live reference is immune to price drift, so it says nothing about how old the decision to
    // trade is. The deadline is the only thing that bounds a stale intent.
    function test_revertsPastTheDeadline() public {
        vm.warp(1_000_000);
        swapc.setNextOut(995);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISlippageBoundedSwap.DeadlineExpired.selector, uint256(999_999), uint256(1_000_000)
            )
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policyBy(0, 100, 0, 999_999), "");
    }

    // The intent expires before the reference is read: the oracle would revert here too, and the
    // deadline error is what surfaces.
    function test_deadlineIsCheckedBeforeTheOracleRead() public {
        vm.warp(1_000_000);
        oracle.setShouldRevert(true);
        swapc.setNextOut(995);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISlippageBoundedSwap.DeadlineExpired.selector, uint256(999_999), uint256(1_000_000)
            )
        );
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policyBy(0, 100, 0, 999_999), "");
    }

    // The deadline is the last block that still settles, not the first that rejects.
    function test_atTheDeadlineStillSettles() public {
        vm.warp(1_000_000);
        swapc.setNextOut(995);
        uint256 out =
            swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policyBy(0, 100, 0, 1_000_000), "");
        assertEq(out, 995);
    }

    // Zero is unbounded, so a policy that sets no deadline behaves exactly as before.
    function test_zeroDeadlineIsUnbounded() public {
        vm.warp(4_000_000_000);
        swapc.setNextOut(995);
        uint256 out = swapc.swapWithPolicy(tokenIn, tokenOut, 1000, RECIPIENT, _policyBy(0, 100, 0, 0), "");
        assertEq(out, 995);
    }

    function test_revertsOnZeroRecipient() public {
        swapc.setNextOut(1000);
        vm.expectRevert(ISlippageBoundedSwap.InvalidRecipient.selector);
        swapc.swapWithPolicy(tokenIn, tokenOut, 1000, address(0), _policy(0, 100, 0), "");
    }
}
