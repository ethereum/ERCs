// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./BaseAwardMechanism.sol";

/// @notice award.posted-price: every bid at or below the reserve is an acceptance of the reserve
///         as the price. The earliest `units` acceptances in commit order win, each paid the reserve.
/// @dev The only incentive-compatible rule when the target fixes the payment (allocation-only
///      integrations): with a fixed price, the chance of winning cannot depend on the amount bid
///      below it. The amount carries no information beyond "accept"; bidders SHOULD bid the reserve.
contract PostedPriceAward is BaseAwardMechanism {
    function mechanismId() external pure returns (bytes4) {
        return bytes4(keccak256("award.posted-price"));
    }

    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external
        pure
        returns (Award[] memory out)
    {
        require(reserve > 0 && units > 0, "bad terms");
        uint256 k;
        Award[] memory tmp = new Award[](units < bids.length ? units : bids.length);
        for (uint256 i = 0; i < bids.length && k < units; i++) {
            if (bids[i].amount <= reserve) {
                tmp[k++] = Award(bids[i].bidder, reserve);
            }
        }
        out = new Award[](k);
        for (uint256 i = 0; i < k; i++) {
            out[i] = tmp[i];
        }
    }
}
