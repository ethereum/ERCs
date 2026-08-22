// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice Slippage policy: a reference oracle, the known cost that separates the mid-price
/// reference from an achievable output, an adverse-only shortfall tolerance, and an absolute floor.
/// @dev The reference from an ERC-7726 oracle is a mid price with no fee or price impact. Folding
/// fee, impact, and drift into a single tolerance rebuilds the wide band this proposal is meant to
/// shrink, so the two costs are separated: `expectedCostBps` is the known, non-adversarial discount
/// from the mid (pool fee plus modeled impact for the size), and `maxDeviationBps` is the adverse
/// movement tolerated on top of the expected output.
struct SlippagePolicy {
    address quoteOracle;      // an ERC-7726 oracle for (tokenIn, tokenOut); MUST enforce freshness
    uint32  expectedCostBps;  // known non-adversarial cost vs the mid reference (fee + impact), <= 10_000
    uint32  maxDeviationBps;  // adverse-only shortfall tolerance beyond the expected output, <= 10_000
    uint256 hardFloor;        // absolute minimum output accepted regardless of the reference
}

/// @notice Reference-Relative Slippage Bounds — a swap whose output floor is derived from a live
/// ERC-7726 reference price at execution time rather than a static sign-time minimum.
interface ISlippageBoundedSwap {
    /// @dev Realized output (measured as the executor's tokenOut balance delta) fell below the floor.
    error SlippageExceeded(uint256 realizedOut, uint256 floor);
    /// @dev expectedCostBps or maxDeviationBps exceeded 10_000.
    error InvalidPolicy(uint32 expectedCostBps, uint32 maxDeviationBps);

    /// @notice Execute a swap whose output floor is derived from `policy` at execution time.
    /// @dev An implementation:
    ///  - MUST read the reference at execution via `IERC7726(policy.quoteOracle).getQuote(amountIn,
    ///    tokenIn, tokenOut)` and MUST NOT accept a reference supplied by the caller.
    ///  - MUST revert `InvalidPolicy` if `expectedCostBps > 10_000` or `maxDeviationBps > 10_000`.
    ///  - MUST compute
    ///      expectedOut = referenceOut * (10_000 - expectedCostBps) / 10_000,
    ///      referenceFloor = expectedOut * (10_000 - maxDeviationBps) / 10_000,
    ///      floor = max(referenceFloor, hardFloor).
    ///  - MUST measure `amountOut` as the executor's actual tokenOut balance increase across the
    ///    route, never a value the route reports, and MUST revert `SlippageExceeded` if it is below
    ///    the floor.
    ///  - `routeData` is an opaque execution hint. It MUST NOT influence the token pair, the
    ///    recipient of the measured balance, or the measured `amountOut`.
    /// @return amountOut the measured tokenOut received by the executor.
    function swapWithPolicy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SlippagePolicy calldata policy,
        bytes calldata routeData
    ) external returns (uint256 amountOut);
}
