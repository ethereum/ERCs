// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Periodic allowance and reserved capacity
/// @notice Interface of the two optional entitlement profiles. In these profiles a unit of the
/// series is a right. An active right yields an allowance of denomination units in every period;
/// consumption is deducted from the allowance of the period in which the hold was placed, and
/// the right itself persists. The reference ledger does not implement this interface.
interface IAITOPeriodic {
    event Activated(uint256 indexed seriesId, address indexed holder, uint256 rights, uint64 effectivePeriod);
    event Deactivated(uint256 indexed seriesId, address indexed holder, uint256 rights, uint64 effectivePeriod);

    /// @notice Activate `rights` rights of the caller. They yield allowance from the next period boundary
    /// and cannot be transferred while active.
    function activate(uint256 seriesId, uint256 rights) external;

    /// @notice Deactivate `rights` active rights of the caller. Takes effect at the next period boundary;
    /// rights whose allowance still backs an unsettled request stay locked until it is settled or released.
    function deactivate(uint256 seriesId, uint256 rights) external;

    /// @notice The period that contains `timestamp`.
    function periodOf(uint256 seriesId, uint64 timestamp)
        external
        view
        returns (uint64 index, uint64 start, uint64 end);

    /// @notice Rights of `holder` that yield allowance in period `index`.
    function activeRightsOf(uint256 seriesId, address holder, uint64 index) external view returns (uint256);

    /// @notice Allowance of `holder` in period `index`: granted, already deducted, and currently held.
    function allowanceOf(uint256 seriesId, address holder, uint64 index)
        external
        view
        returns (uint256 granted, uint256 used, uint256 held);
}
