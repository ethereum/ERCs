// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../IAwardMechanism.sol";

/// @notice Shared ERC-165 plumbing and a stable ascending sort for the normative mechanisms.
abstract contract BaseAwardMechanism is IAwardMechanism {
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(IAwardMechanism).interfaceId || id == 0x01ffc9a7;
    }

    /// @dev Stable insertion sort by amount, ascending. Stability is what makes
    ///      "ties go to the earlier commit" hold, since bids arrive in commit order.
    function _sorted(Bid[] calldata bids) internal pure returns (Bid[] memory s) {
        uint256 n = bids.length;
        s = new Bid[](n);
        for (uint256 i = 0; i < n; i++) {
            Bid memory b = bids[i];
            uint256 j = i;
            while (j > 0 && s[j - 1].amount > b.amount) {
                s[j] = s[j - 1];
                j--;
            }
            s[j] = b;
        }
    }

    /// @dev Number of leading sorted bids at or below the reserve, capped at units.
    function _winnerCount(Bid[] memory s, uint256 reserve, uint256 units) internal pure returns (uint256 k) {
        while (k < s.length && k < units && s[k].amount <= reserve) {
            k++;
        }
    }
}
