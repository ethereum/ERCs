// SPDX-License-Identifier: CC0-1.0
// test/mocks/MockAggregator.sol
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/oracles/ChainlinkConversionOracle.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public decimalsValue;

    constructor(uint8 decimals_) {
        decimalsValue = decimals_;
    }

    function setAnswer(int256 newAnswer) external {
        answer = newAnswer;
    }

    function setUpdatedAt(uint256 newUpdatedAt) external {
        updatedAt = newUpdatedAt;
    }

    function setDecimals(uint8 newDecimals) external {
        decimalsValue = newDecimals;
    }

    function decimals() external view returns (uint8) {
        return decimalsValue;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        return (0, answer, 0, updatedAt, 0);
    }
}
