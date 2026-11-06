// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./BaseAwardMechanism.sol";

/// @notice award.vickrey: single unit, lowest bid wins, paid min(second-lowest bid, reserve).
///         With one valid bid the price is the reserve.
contract VickreyAward is BaseAwardMechanism {
    function mechanismId() external pure returns (bytes4) {
        return bytes4(keccak256("award.vickrey"));
    }

    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external
        pure
        returns (Award[] memory out)
    {
        require(reserve > 0, "bad terms");
        require(units == 1, "vickrey: units must be 1");
        Bid[] memory s = _sorted(bids);
        if (s.length == 0 || s[0].amount > reserve) {
            return out; // empty: no award
        }
        uint256 price = reserve;
        if (s.length > 1 && s[1].amount < price) {
            price = s[1].amount;
        }
        out = new Award[](1);
        out[0] = Award(s[0].bidder, price);
    }
}
