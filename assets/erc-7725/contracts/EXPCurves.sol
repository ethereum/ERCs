// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEXPCurves} from "./IEXPCurves.sol";
import {exp} from "@prb/math/src/sd59x18/Math.sol";
import {wrap, unwrap} from "@prb/math/src/sd59x18/Casting.sol";

/**
 * @title Exponential Curves
 * @author https://github.com/0xneves
 * @notice This smart contract implements an advanced exponential curve formula designed to
 * handle various time-based events such as token vesting, game mechanics, unlock schedules,
 * and other timestamp-dependent actions. The core functionality is driven by an exponential
 * curve formula that allows for smooth, nonlinear transitions over time, providing a more
 * sophisticated and flexible approach compared to linear models.
 */
abstract contract EXPCurves is IEXPCurves {
  /**
   * @notice The initial timeframe is invalid.
   *
   * Requirements:
   *
   * - Must be less than or equal to the current timestamp
   * - Must be less than the final timestamp.
   */
  error EXPCurveInvalidInitialTimeframe();

  /**
   * @notice The curvature factor is invalid.
   *
   * Requirements:
   *
   * - It cannot be zero
   * - The curvature cannot be bigger than 10000 or smaller than -10000 (2 decimals precision)
   *
   * NOTE: Cannot be bigger than type uint of value 133 while using regular unix timestamps.
   * For negative values it can go way further than type int of value -133, but there is no
   * need to go that far.
   */
  error EXPCurveInvalidCurvature();

  /**
   * @dev See {IEXPCurves-expcurve}.
   */
  function expcurve(
    uint32 currentTimeframe,
    uint32 initialTimeframe,
    uint32 finalTimeframe,
    int16 curvature,
    bool ascending
  ) public pure virtual returns (int256) {
    if (initialTimeframe > currentTimeframe)
      revert EXPCurveInvalidInitialTimeframe();
    if (initialTimeframe >= finalTimeframe)
      revert EXPCurveInvalidInitialTimeframe();
    if (curvature == 0 || curvature > 10_000 || curvature < -10_000)
      revert EXPCurveInvalidCurvature();
    if (currentTimeframe > finalTimeframe) {
      return ascending ? int(100 * 1e18) : int(0);
    }
    // Calculate the Time Delta and Total Time Interval
    int256 td = int(uint256(currentTimeframe - initialTimeframe));
    int256 tti = int(uint256(finalTimeframe - initialTimeframe));

    // Calculate the Time Elapsed Ratio
    int256 ter = unwrap(wrap(td) / wrap(tti));
    int256 cs; // Curve Scaling
    if (ascending) {
      cs = (curvature * int(ter)) / 100;
    } else {
      cs = (curvature * (1e18 - int(ter))) / 100;
    }

    // Calculate the Exponential Decay
    int256 expo = unwrap(exp(wrap(cs))) - 1e18;
    // Calculate the Final Exponential Scaling
    int256 fes = unwrap(exp(wrap(int(curvature) * 1e16))) - 1e18;

    // Normalize the Exponential Decay
    return unwrap(wrap(expo) / wrap(fes)) * 100;
  }
}
