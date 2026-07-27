// SPDX-License-Identifier: CC0-1.0
// src/oracles/ChainlinkConversionOracle.sol
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "../IConversionOracle.sol";

/// @notice Subconjunto minimo de AggregatorV3Interface (declarado
///         localmente para no depender del paquete de Chainlink).
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Adapta un feed Chainlink-compatible a IConversionOracle.
/// @dev rate = cuantas base units del payment asset equivalen a 1e18
///      unidades de cuenta: rate = answer * 10^payDecimals / 10^feedDecimals.
///      No enforza staleness: esa politica vive en el lease
///      (maxOracleStaleness), no en el adaptador.
contract ChainlinkConversionOracle is IConversionOracle {
    using Math for uint256;

    AggregatorV3Interface public immutable feed;
    uint8 public immutable feedDecimals;
    uint8 public immutable paymentAssetDecimals;

    error InvalidAnswer();
    error IncompleteRound();

    constructor(address feed_, uint8 paymentAssetDecimals_) {
        feed = AggregatorV3Interface(feed_);
        feedDecimals = feed.decimals();
        paymentAssetDecimals = paymentAssetDecimals_;
    }

    function latestRate() external view returns (uint256 rate, uint64 asOf) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidAnswer();
        if (updatedAt == 0) revert IncompleteRound();

        rate = uint256(answer).mulDiv(10 ** paymentAssetDecimals, 10 ** feedDecimals);
        asOf = uint64(updatedAt);
    }
}
