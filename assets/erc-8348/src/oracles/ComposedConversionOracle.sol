// SPDX-License-Identifier: CC0-1.0
// src/oracles/ComposedConversionOracle.sol
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "../IConversionOracle.sol";
import {AggregatorV3Interface} from "./ChainlinkConversionOracle.sol";

/// @notice Composes two Chainlink-compatible feeds into a single
///         IConversionOracle (e.g. UVA/ARS x ARS/USD to settle a
///         UVA-indexed lease in USDC).
/// @dev asOf = min(asOf of both feeds): the freshness of a composition is
///      that of its oldest input, never better than its worst component.
contract ComposedConversionOracle is IConversionOracle {
    using Math for uint256;

    // S1-02: same defensive bound as ChainlinkConversionOracle, applied
    // to both composed feeds.
    uint8 internal constant MAX_SANE_DECIMALS = 30;

    AggregatorV3Interface public immutable feedA;
    AggregatorV3Interface public immutable feedB;
    uint8 public immutable feedADecimals;
    uint8 public immutable feedBDecimals;
    bool public immutable invertB;
    uint8 public immutable paymentAssetDecimals;

    error InvalidAnswer();
    error IncompleteRound();
    error DecimalsOutOfRange();
    error DecimalsChanged();

    constructor(address feedA_, address feedB_, bool invertB_, uint8 paymentAssetDecimals_) {
        feedA = AggregatorV3Interface(feedA_);
        feedB = AggregatorV3Interface(feedB_);
        uint8 fdA = feedA.decimals();
        uint8 fdB = feedB.decimals();
        if (fdA > MAX_SANE_DECIMALS || fdB > MAX_SANE_DECIMALS) revert DecimalsOutOfRange(); // S1-02
        feedADecimals = fdA;
        feedBDecimals = fdB;
        invertB = invertB_;
        paymentAssetDecimals = paymentAssetDecimals_;
    }

    function latestRate() external view returns (uint256 rate, uint64 asOf) {
        (uint256 normA, uint256 updatedAtA) = _normalized(feedA, feedADecimals);
        (uint256 normB, uint256 updatedAtB) = _normalized(feedB, feedBDecimals);

        // S2-08: explicit guard before dividing, instead of relying on the
        // implicit guard (division by zero) that Math.mulDiv already has
        // internally — same error criterion as the rest of the
        // contract (invalid feed = InvalidAnswer, regardless of which
        // step detected it).
        if (invertB && normB == 0) revert InvalidAnswer();

        // Both normalized to 1e18 before composing; invertB divides
        // instead of multiplying when the second feed is quoted in the
        // opposite direction to the one needed (e.g. USD/ARS instead of ARS/USD).
        uint256 composed1e18 = invertB ? normA.mulDiv(1e18, normB) : normA.mulDiv(normB, 1e18);

        rate = composed1e18.mulDiv(10 ** paymentAssetDecimals, 1e18);
        asOf = uint64(Math.min(updatedAtA, updatedAtB));
    }

    function _normalized(AggregatorV3Interface feed_, uint8 feedDecimals_)
        internal
        view
        returns (uint256 norm, uint256 updatedAt)
    {
        // S2-02: same criterion as ChainlinkConversionOracle — re-read and
        // compare decimals() on every read, cheap compared with the risk
        // of silent mis-scaling if the wrapped feed changes
        // convention after deployment.
        if (feed_.decimals() != feedDecimals_) revert DecimalsChanged();

        (, int256 answer,, uint256 updatedAt_,) = feed_.latestRoundData();
        if (answer <= 0) revert InvalidAnswer();
        if (updatedAt_ == 0) revert IncompleteRound();
        norm = uint256(answer).mulDiv(1e18, 10 ** feedDecimals_);
        updatedAt = updatedAt_;
    }
}
