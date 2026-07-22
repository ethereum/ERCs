// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IReclaimableIdentityAccount — optional factory-bound reclaim extension
/// @notice While the identifier is unclaimed and past `reclaimableAfter`,
///         `reclaimTo` is authorized for `execute`. The configuration is
///         established by the factory at deployment — identically regardless
///         of who triggers deployment — and can never be changed.
interface IReclaimableIdentityAccount {
    /// @notice The address authorized for `execute` while the identifier is unclaimed.
    ///         address(0) means reclaim is disabled for this account.
    function reclaimTo() external view returns (address);

    /// @notice The timestamp after which the reclaim authority becomes active.
    function reclaimableAfter() external view returns (uint256);
}
