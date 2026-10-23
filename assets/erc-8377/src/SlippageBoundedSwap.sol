// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC7726} from "./IERC7726.sol";
import {IERC20Minimal} from "./IERC20Minimal.sol";

uint256 constant BPS = 10_000;
bytes4 constant ERC165_ID = 0x01ffc9a7;

/// @notice Slippage policy: a reference oracle, the known cost that separates the mid-price
/// reference from an achievable output, an adverse-only shortfall tolerance, an absolute floor, and
/// the time past which the intent to trade expires.
/// @dev The reference from an ERC-7726 oracle is a mid price with no fee or price impact. Folding
/// fee, impact, and drift into a single tolerance rebuilds the wide band this proposal is meant to
/// shrink, so the two costs are separated: `expectedCostBps` is the known, non-adversarial discount
/// from the mid (pool fee plus modeled impact for the size), and `maxDeviationBps` is the adverse
/// movement tolerated on top of the expected output. `deadline` bounds a different staleness. The
/// floor never goes stale, but the decision to trade at all does, and no reference-relative bound
/// can catch that.
struct SlippagePolicy {
    address quoteOracle;      // an ERC-7726 oracle for (tokenIn, tokenOut); MUST enforce freshness
    uint32  expectedCostBps;  // known non-adversarial cost vs the mid reference (fee + impact), <= 10_000
    uint32  maxDeviationBps;  // adverse-only shortfall tolerance beyond the expected output, <= 10_000
    uint256 hardFloor;        // absolute minimum output accepted regardless of the reference
    uint256 deadline;         // unix seconds past which the intent expires; 0 means unbounded
}

/// @notice Reference-Relative Slippage Bounds — a swap whose output floor is derived from a live
/// ERC-7726 reference price at execution time rather than a static sign-time minimum.
interface ISlippageBoundedSwap {
    /// @dev Realized output (measured as the recipient's tokenOut balance delta) fell below the floor.
    error SlippageExceeded(uint256 realizedOut, uint256 floor);
    /// @dev expectedCostBps or maxDeviationBps exceeded 10_000.
    error InvalidPolicy(uint32 expectedCostBps, uint32 maxDeviationBps);
    /// @dev The recipient was the zero address, which no balance check can protect.
    error InvalidRecipient();
    /// @dev The intent expired: `block.timestamp` is past a non-zero `policy.deadline`.
    error DeadlineExpired(uint256 deadline, uint256 timestamp);

    /// @notice Execute a swap whose output floor is derived from `policy` at execution time.
    /// @dev An implementation:
    ///  - MUST revert `InvalidPolicy` if `expectedCostBps > 10_000` or `maxDeviationBps > 10_000`.
    ///  - MUST revert `InvalidRecipient` if `recipient` is the zero address.
    ///  - MUST revert `DeadlineExpired` if `deadline != 0 && block.timestamp > deadline`, before the
    ///    reference is read and before the route runs, so an expired intent does not depend on an
    ///    oracle read succeeding. A zero `deadline` is unbounded.
    ///  - MUST read the reference at execution via `IERC7726(policy.quoteOracle).getQuote(amountIn,
    ///    tokenIn, tokenOut)` and MUST NOT accept a reference supplied by the caller.
    ///  - MUST compute
    ///      expectedOut = referenceOut * (10_000 - expectedCostBps) / 10_000,
    ///      referenceFloor = expectedOut * (10_000 - maxDeviationBps) / 10_000,
    ///      floor = max(referenceFloor, hardFloor).
    ///  - MUST measure `amountOut` as `recipient`'s actual tokenOut balance increase across the
    ///    route, never a value the route reports, and MUST revert `SlippageExceeded` if it is below
    ///    the floor. The bound is on what the recipient received. An executor sitting in the path may
    ///    forward output or take a fee, so measuring the executor would bound the wrong account.
    ///  - `routeData` is an opaque execution hint. It MUST NOT influence the token pair, the
    ///    `recipient`, or the measured `amountOut`.
    /// @param  recipient the account whose tokenOut balance the floor is enforced against.
    /// @return amountOut the measured tokenOut received by `recipient`.
    function swapWithPolicy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        SlippagePolicy calldata policy,
        bytes calldata routeData
    ) external returns (uint256 amountOut);
}

/// @title SlippageBoundedSwap
/// @notice Reference implementation of the reference-relative slippage floor. The route execution is
/// left as an internal hook (`_route`) so any router can inherit this guard. The guard measures the
/// realized output as the recipient's tokenOut balance delta across the route, so the route cannot
/// report a favourable number the guard would trust.
abstract contract SlippageBoundedSwap is ISlippageBoundedSwap {
    /// @dev Execute the swap described by `routeData`, delivering the output token to `recipient`.
    /// It MUST NOT be trusted to report the amount; the guard measures the balance delta itself.
    /// Implementers wire this to their venue (a DEX call, an aggregator route, etc.).
    function _route(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        bytes calldata routeData
    ) internal virtual;

    /// @inheritdoc ISlippageBoundedSwap
    function swapWithPolicy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        SlippagePolicy calldata policy,
        bytes calldata routeData
    ) external returns (uint256 amountOut) {
        if (policy.expectedCostBps > BPS || policy.maxDeviationBps > BPS) {
            revert InvalidPolicy(policy.expectedCostBps, policy.maxDeviationBps);
        }
        if (recipient == address(0)) revert InvalidRecipient();

        // An expired intent is rejected before anything else can fail or succeed. A live reference
        // keeps the floor honest, but it cannot tell that the caller decided to trade days ago.
        if (policy.deadline != 0 && block.timestamp > policy.deadline) {
            revert DeadlineExpired(policy.deadline, block.timestamp);
        }

        // The reference is ALWAYS read from the oracle at execution time, never from the caller.
        // The oracle is expected to enforce freshness and revert when it cannot give a reliable quote.
        uint256 referenceOut = IERC7726(policy.quoteOracle).getQuote(amountIn, tokenIn, tokenOut);

        // referenceOut is a mid price. Discount the known cost (fee + impact) to get the achievable
        // output, then apply the adverse-only tolerance on top of that.
        uint256 expectedOut = referenceOut * (BPS - policy.expectedCostBps) / BPS;
        uint256 referenceFloor = expectedOut * (BPS - policy.maxDeviationBps) / BPS;
        uint256 floor = referenceFloor > policy.hardFloor ? referenceFloor : policy.hardFloor;

        // Measure the realized output on-chain, at the account the bound is about. The executor is
        // just the caller: it can forward output, take a fee, or sit in the path, so measuring its
        // balance would bound the wrong account.
        uint256 balanceBefore = IERC20Minimal(tokenOut).balanceOf(recipient);
        _route(tokenIn, tokenOut, amountIn, recipient, routeData);
        amountOut = IERC20Minimal(tokenOut).balanceOf(recipient) - balanceBefore;

        if (amountOut < floor) revert SlippageExceeded(amountOut, floor);
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(ISlippageBoundedSwap).interfaceId || interfaceId == ERC165_ID;
    }
}
