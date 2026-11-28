// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AUF valuation profile arithmetic (reference)
/// @notice Fixed-point (18 decimals) reference arithmetic for the four valuation profiles of Section 14.4.
///         The library fixes the formulas; the semantics of inputs (interest, snapshot, assessment boundary,
///         coverage) are carried by the valuation receipt, not by this code.
library AUFValuationLib {
    uint256 internal constant WAD = 1e18;

    error AUF_LengthMismatch();
    error AUF_ProbabilitiesNotNormalized(uint256 sum);
    error AUF_EmptyInput();

    /// @notice Net equity: sum(assets) - sum(liabilities). May be negative. (14.4.1)
    /// @dev Positions without a usable price must be excluded by the caller and listed as missing in the receipt.
    function netEquity(int256[] memory assets, int256[] memory liabilities) internal pure returns (int256 value) {
        for (uint256 i = 0; i < assets.length; i++) value += assets[i];
        for (uint256 i = 0; i < liabilities.length; i++) value -= liabilities[i];
    }

    /// @notice Realized net cash flow over a window: inflow - outflow. An observation result, not a value. (14.4.2)
    function realizedNetCashFlow(uint256[] memory inflows, uint256[] memory outflows) internal pure returns (int256 value) {
        for (uint256 i = 0; i < inflows.length; i++) value += int256(inflows[i]);
        for (uint256 i = 0; i < outflows.length; i++) value -= int256(outflows[i]);
    }

    /// @notice Finite-horizon DCF: sum_{t=1..n} c_t/(1+r)^t + T/(1+r)^n. (14.4.3)
    /// @param cashflows Net cash flows at the end of periods 1..n, 18-decimal fixed point.
    /// @param rateWad Per-period discount rate, 18-decimal fixed point (0.1e18 = 10%).
    /// @param terminalValue Terminal value received at the end of period n, 18-decimal fixed point.
    function finiteHorizonDCF(int256[] memory cashflows, uint256 rateWad, int256 terminalValue)
        internal
        pure
        returns (int256 value)
    {
        if (cashflows.length == 0) revert AUF_EmptyInput();
        uint256 factor = WAD; // (1+r)^-t
        for (uint256 t = 0; t < cashflows.length; t++) {
            factor = (factor * WAD) / (WAD + rateWad);
            value += (cashflows[t] * int256(factor)) / int256(WAD);
        }
        value += (terminalValue * int256(factor)) / int256(WAD);
    }

    /// @notice Conditional payoff: (sum_j p_j * x_j) / (1+r)^n. (14.4.4)
    /// @param payoffs Scenario payoffs, 18-decimal fixed point.
    /// @param probabilitiesWad Scenario probabilities, 18-decimal fixed point; must sum to exactly 1e18.
    /// @param rateWad Per-period discount rate, 18-decimal fixed point.
    /// @param periods Number of periods until resolution.
    function conditionalPayoff(
        int256[] memory payoffs,
        uint256[] memory probabilitiesWad,
        uint256 rateWad,
        uint256 periods
    ) internal pure returns (int256 value) {
        if (payoffs.length == 0) revert AUF_EmptyInput();
        if (payoffs.length != probabilitiesWad.length) revert AUF_LengthMismatch();
        uint256 sum;
        int256 expectation;
        for (uint256 j = 0; j < payoffs.length; j++) {
            sum += probabilitiesWad[j];
            expectation += (payoffs[j] * int256(probabilitiesWad[j])) / int256(WAD);
        }
        if (sum != WAD) revert AUF_ProbabilitiesNotNormalized(sum);
        uint256 factor = WAD;
        for (uint256 t = 0; t < periods; t++) {
            factor = (factor * WAD) / (WAD + rateWad);
        }
        value = (expectation * int256(factor)) / int256(WAD);
    }
}
