// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./BaseAwardMechanism.sol";

/// @notice award.uniform-price: lowest `units` bids win, all paid min(b(units+1), reserve).
///         If there is no (units+1)-th bid the price is the reserve.
///         Scoped to one unit per bidder; see the ERC's Rationale.
contract UniformPriceAward is BaseAwardMechanism {
    function mechanismId() external pure returns (bytes4) {
        return bytes4(keccak256("award.uniform-price"));
    }

    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external
        pure
        returns (Award[] memory out)
    {
        require(reserve > 0 && units > 0, "bad terms");
        Bid[] memory s = _sorted(bids);
        uint256 k = _winnerCount(s, reserve, units);
        if (k == 0) return out;
        uint256 price = reserve;
        // The clearing price is the first excluded bid, if one exists below the reserve.
        if (s.length > units && s[units].amount < price) {
            price = s[units].amount;
        }
        out = new Award[](k);
        for (uint256 i = 0; i < k; i++) {
            out[i] = Award(s[i].bidder, price);
        }
    }
}
