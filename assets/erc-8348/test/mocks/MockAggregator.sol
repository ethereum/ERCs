// SPDX-License-Identifier: CC0-1.0
// test/mocks/MockAggregator.sol
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/oracles/ChainlinkConversionOracle.sol";

/// @dev setAnswer/setUpdatedAt edit the latest round in place (legacy test
///      helpers). pushRound appends a new round, as a real feed does, so
///      getRoundData can walk the history. Round ids start at 1 within phase 1.
contract MockAggregator is AggregatorV3Interface {
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint256 internal constant PHASE = uint256(1) << 64;

    Round[] internal rounds;
    uint8 public decimalsValue;

    constructor(uint8 decimals_) {
        decimalsValue = decimals_;
        rounds.push(Round(0, 0));
    }

    function answer() external view returns (int256) {
        return rounds[rounds.length - 1].answer;
    }

    function updatedAt() external view returns (uint256) {
        return rounds[rounds.length - 1].updatedAt;
    }

    function setAnswer(int256 newAnswer) external {
        rounds[rounds.length - 1].answer = newAnswer;
    }

    function setUpdatedAt(uint256 newUpdatedAt) external {
        rounds[rounds.length - 1].updatedAt = newUpdatedAt;
    }

    function pushRound(int256 newAnswer, uint256 newUpdatedAt) external {
        rounds.push(Round(newAnswer, newUpdatedAt));
    }

    function setDecimals(uint8 newDecimals) external {
        decimalsValue = newDecimals;
    }

    function decimals() external view returns (uint8) {
        return decimalsValue;
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint256 idx = uint256(roundId) - PHASE - 1; // reverts below round 1
        require(idx < rounds.length, "no data present");
        Round storage r = rounds[idx];
        return (roundId, r.answer, r.updatedAt, r.updatedAt, roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return getRoundData(uint80(PHASE + rounds.length));
    }
}
