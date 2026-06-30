// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IReclaimableIdentityAccount
/// @notice Optional extension for fund reclaim while an identity is unclaimed.
interface IReclaimableIdentityAccount {
    event ReclaimSet(bytes32 indexed id, address indexed reclaimTo, uint256 reclaimableAfter);

    /// @notice Set (or update) the reclaim address and deadline.
    /// @dev    When reclaimTo is unset, any caller may set it. After that, only
    ///         the current reclaimTo may update it. Must revert while claimed.
    function setReclaim(address reclaimTo_, uint256 reclaimableAfter_) external;

    function reclaimTo() external view returns (address);
    function reclaimableAfter() external view returns (uint256);
}
