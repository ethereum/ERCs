// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./BaseAwardMechanism.sol";

/// @notice award.first-price: lowest `units` bids win, each paid its own bid.
contract FirstPriceAward is BaseAwardMechanism {
    function mechanismId() external pure returns (bytes4) {
        return bytes4(keccak256("award.first-price"));
    }

    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external
        pure
        returns (Award[] memory out)
    {
        require(reserve > 0 && units > 0, "bad terms");
        Bid[] memory s = _sorted(bids);
        uint256 k = _winnerCount(s, reserve, units);
        out = new Award[](k);
        for (uint256 i = 0; i < k; i++) {
            out[i] = Award(s[i].bidder, s[i].amount);
        }
    }
}
