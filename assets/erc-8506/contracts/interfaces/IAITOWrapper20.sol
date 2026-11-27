// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title ERC-20 carrier for one series of AI inference entitlements
/// @notice Every wrapped token is backed by native units locked in the wrapper.
/// Wrapped tokens cannot be consumed; they are unwrapped first.
interface IAITOWrapper20 {
    event Wrapped(address indexed from, address indexed to, uint256 units);
    event Unwrapped(address indexed from, address indexed to, uint256 units);

    /// @notice The home ledger of the wrapped series.
    function ledger() external view returns (address);

    /// @notice The wrapped series.
    function seriesId() external view returns (uint256);

    /// @notice Wrapped base units minted per native unit.
    function unitScale() external view returns (uint256);

    /// @notice Native units currently locked in the wrapper.
    function lockedUnits() external view returns (uint256);

    /// @notice Whether the wrapped series has passed its `validUntil`.
    function expired() external view returns (bool);

    /// @notice Lock `units` native units of the caller and mint `units * unitScale` wrapped tokens to `to`.
    /// The caller MUST have approved the wrapper as operator on the ledger.
    function wrap(uint256 units, address to) external;

    /// @notice Burn `units * unitScale` wrapped tokens of the caller and send `units` native units to `to`.
    function unwrap(uint256 units, address to) external;
}
