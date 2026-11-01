// SPDX-License-Identifier: CC0-1.0
// src/MockUVAOracle.sol
pragma solidity ^0.8.24;

import {IConversionOracle} from "./IConversionOracle.sol";

contract MockUVAOracle is IConversionOracle {
    uint256 public rate;
    uint64 public asOf;

    constructor(uint256 initialRate) {
        set(initialRate);
    }

    function set(uint256 newRate) public {
        rate = newRate;
        asOf = uint64(block.timestamp);
    }

    function latestRate() external view returns (uint256, uint64) {
        return (rate, asOf);
    }
}
