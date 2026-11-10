// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice A public tax schedule. A deduction policy reads it once per task, at creation,
///         so a later rate change never reaches a task already created.
interface ITaxSchedule {
    /// @notice The tax on payouts in `asset`.
    /// @return treasury The address the tax is owed to.
    /// @return bps      The rate in basis points; zero means no tax.
    function taxOf(address asset) external view returns (address treasury, uint16 bps);
}
