// SPDX-License-Identifier: CC0-1.0
// src/oracles/ChainlinkConversionOracle.sol
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "../IConversionOracle.sol";

/// @notice Minimal subset of AggregatorV3Interface (declared
///         locally to avoid depending on the Chainlink package).
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Adapts a Chainlink-compatible feed to IConversionOracle.
/// @dev rate = how many base units of the payment asset equal 1e18
///      units of account: rate = answer * 10^payDecimals / 10^feedDecimals.
///      Does not enforce staleness: that policy lives in the lease
///      (maxOracleStaleness), not in the adapter.
contract ChainlinkConversionOracle is IConversionOracle {
    using Math for uint256;

    // S1-02: defensive bound on feedDecimals — well above
    // any real feed (all use <=18), it leaves ample room so
    // that `10 ** feedDecimals` combined with `10 ** paymentAssetDecimals`
    // in latestRate()'s mulDiv never comes close to overflowing
    // uint256 (~1.16e77 en 10^77).
    uint8 internal constant MAX_SANE_DECIMALS = 30;

    AggregatorV3Interface public immutable feed;
    uint8 public immutable feedDecimals;
    uint8 public immutable paymentAssetDecimals;

    error InvalidAnswer();
    error IncompleteRound();
    error DecimalsOutOfRange();
    error DecimalsChanged();

    constructor(address feed_, uint8 paymentAssetDecimals_) {
        feed = AggregatorV3Interface(feed_);
        uint8 fd = feed.decimals();
        if (fd > MAX_SANE_DECIMALS) revert DecimalsOutOfRange(); // S1-02
        feedDecimals = fd;
        paymentAssetDecimals = paymentAssetDecimals_;
    }

    function latestRate() external view returns (uint256 rate, uint64 asOf) {
        // S2-02: the wrapped feed "should" be Chainlink-compatible with
        // immutable decimals (as the contract's NatSpec
        // documents), but there is no way to enforce that on-chain other than
        // reading it again and comparing. Cost: one extra staticcall per
        // read — cheap (decimals() is a trivial view on any
        // real feed) compared with the risk it closes: silent mis-scaling
        // with no revert or event if the wrapped feed changes convention.
        if (feed.decimals() != feedDecimals) revert DecimalsChanged();

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidAnswer();
        if (updatedAt == 0) revert IncompleteRound();

        rate = uint256(answer).mulDiv(10 ** paymentAssetDecimals, 10 ** feedDecimals);
        asOf = uint64(updatedAt);
    }
}
