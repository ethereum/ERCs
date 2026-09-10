// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC7726} from "../../src/IERC7726.sol";

/// @notice Settable ERC-7726 mock. quoteAmount = baseAmount * rate / 1e18.
/// A rate of 1e18 makes the reference output equal to the input amount, which keeps the
/// slippage-floor arithmetic easy to read in the tests.
contract MockQuoteOracle is IERC7726 {
    uint256 public rate = 1e18;
    bool public shouldRevert;

    function setRate(uint256 r) external {
        rate = r;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function getQuote(uint256 baseAmount, address, address) external view returns (uint256) {
        require(!shouldRevert, "oracle: no fresh quote");
        return baseAmount * rate / 1e18;
    }
}
