// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC7726} from "../IERC7726.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice A real ERC-7726 adapter over a single Chainlink price feed for one (base, quote) pair.
/// @dev Demonstrates a genuine, independent reference source for the slippage guard. It reverts on a
/// stale or non-positive answer, which is exactly the freshness behaviour ERC-7726 consumers rely on,
/// so the swap guard does not need its own staleness field. Chainlink is independent of the venue
/// being traded, so it is a valid reference (a spot price from the traded pool would not be).
contract ChainlinkQuoteOracle is IERC7726 {
    AggregatorV3Interface public immutable feed;
    address public immutable base;
    address public immutable quote;
    uint8 public immutable baseDecimals;
    uint8 public immutable quoteDecimals;
    uint256 public immutable maxStaleness; // seconds; 0 disables the check

    error UnsupportedPair(address base, address quote);
    error StaleReference(uint256 updatedAt);
    error BadAnswer(int256 answer);

    constructor(
        address _feed,
        address _base,
        address _quote,
        uint8 _baseDecimals,
        uint8 _quoteDecimals,
        uint256 _maxStaleness
    ) {
        feed = AggregatorV3Interface(_feed);
        base = _base;
        quote = _quote;
        baseDecimals = _baseDecimals;
        quoteDecimals = _quoteDecimals;
        maxStaleness = _maxStaleness;
    }

    /// @inheritdoc IERC7726
    function getQuote(uint256 baseAmount, address _base, address _quote) external view returns (uint256) {
        if (_base != base || _quote != quote) revert UnsupportedPair(_base, _quote);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert BadAnswer(answer);
        if (maxStaleness != 0 && block.timestamp - updatedAt > maxStaleness) revert StaleReference(updatedAt);

        uint256 price = uint256(answer);
        uint8 feedDecimals = feed.decimals();
        // quoteAmount = baseAmount * price * 10^quoteDecimals / (10^feedDecimals * 10^baseDecimals)
        return baseAmount * price * (10 ** quoteDecimals) / (10 ** feedDecimals) / (10 ** baseDecimals);
    }
}
