// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ISlippageBoundedSwap, SlippagePolicy} from "./ISlippageBoundedSwap.sol";
import {IERC7726} from "./IERC7726.sol";
import {IERC20Minimal} from "./IERC20Minimal.sol";

uint256 constant BPS = 10_000;
bytes4 constant ERC165_ID = 0x01ffc9a7;

/// @title SlippageBoundedSwap
/// @notice Reference implementation of the reference-relative slippage floor. The route execution is
/// left as an internal hook (`_route`) so any router can inherit this guard. The guard measures the
/// realized output as the executor's tokenOut balance delta across the route, so the route cannot
/// report a favourable number the guard would trust.
abstract contract SlippageBoundedSwap is ISlippageBoundedSwap {
    /// @dev Execute the swap described by `routeData`, delivering the output token to `address(this)`.
    /// It MUST NOT be trusted to report the amount; the guard measures the balance delta itself.
    /// Implementers wire this to their venue (a DEX call, an aggregator route, etc.).
    function _route(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata routeData
    ) internal virtual;

    /// @inheritdoc ISlippageBoundedSwap
    function swapWithPolicy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SlippagePolicy calldata policy,
        bytes calldata routeData
    ) external returns (uint256 amountOut) {
        if (policy.expectedCostBps > BPS || policy.maxDeviationBps > BPS) {
            revert InvalidPolicy(policy.expectedCostBps, policy.maxDeviationBps);
        }

        // The reference is ALWAYS read from the oracle at execution time, never from the caller.
        // The oracle is expected to enforce freshness and revert when it cannot give a reliable quote.
        uint256 referenceOut = IERC7726(policy.quoteOracle).getQuote(amountIn, tokenIn, tokenOut);

        // referenceOut is a mid price. Discount the known cost (fee + impact) to get the achievable
        // output, then apply the adverse-only tolerance on top of that.
        uint256 expectedOut = referenceOut * (BPS - policy.expectedCostBps) / BPS;
        uint256 referenceFloor = expectedOut * (BPS - policy.maxDeviationBps) / BPS;
        uint256 floor = referenceFloor > policy.hardFloor ? referenceFloor : policy.hardFloor;

        // Measure the realized output on-chain. Whatever routeData does, the guard only trusts the
        // executor's own tokenOut balance increase, so the route cannot report a number it did not pay.
        uint256 balanceBefore = IERC20Minimal(tokenOut).balanceOf(address(this));
        _route(tokenIn, tokenOut, amountIn, routeData);
        amountOut = IERC20Minimal(tokenOut).balanceOf(address(this)) - balanceBefore;

        if (amountOut < floor) revert SlippageExceeded(amountOut, floor);
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(ISlippageBoundedSwap).interfaceId || interfaceId == ERC165_ID;
    }
}
