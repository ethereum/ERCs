// SPDX-License-Identifier: CC0-1.0
// src/MockUVAOracle.sol
pragma solidity ^0.8.24;

import {IConversionOracle} from "./IConversionOracle.sol";
import {IConversionOracleHistory} from "./IConversionOracleHistory.sol";
import {FreshnessHistory} from "./oracles/FreshnessHistory.sol";

/// @dev TEST MOCK ONLY: set() is public, so anyone can move the rate or flood
///      the history (257 observations in one block would make the history walk
///      fail closed and block default). Production indices use the attested or
///      Chainlink adapters.
contract MockUVAOracle is IConversionOracle, IConversionOracleHistory {
    uint256 public rate;
    uint64 public asOf;
    uint64[] public observationTimes;

    constructor(uint256 initialRate) {
        set(initialRate);
    }

    error InvalidRate();

    function set(uint256 newRate) public {
        if (newRate == 0) revert InvalidRate(); // history stores timestamps only, so every entry must be usable
        rate = newRate;
        asOf = uint64(block.timestamp);
        observationTimes.push(asOf);
    }

    function latestRate() external view returns (uint256, uint64) {
        return (rate, asOf);
    }

    function continuouslyFresh(uint64 from, uint64 to, uint64 tolerance) external view returns (bool) {
        return FreshnessHistory.walkStored(observationTimes, from, to, tolerance);
    }
}
