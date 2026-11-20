// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IAwardMechanism
/// @notice A pure allocation-and-pricing rule: maps revealed bids to an award.
/// @dev Mechanisms are stateless by design. See the ERC text for the six
///      conditions `award` must satisfy.
interface IAwardMechanism {
    struct Bid {
        address bidder;
        uint256 amount; // price asked, in the tender's unit of account
    }

    struct Award {
        address winner;
        uint256 price; // price paid to this winner
    }

    /// @notice Canonical identifier of the rule, e.g. bytes4(keccak256("award.vickrey")).
    function mechanismId() external pure returns (bytes4);

    /// @notice Compute the award from revealed bids.
    /// @dev MUST be pure. Bids are passed in commit order. An empty return means no award.
    /// @param bids    Revealed bids in commit order.
    /// @param reserve Highest acceptable price. MUST be > 0.
    /// @param units   Number of identical units to award. MUST be >= 1.
    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external
        pure
        returns (Award[] memory);
}
