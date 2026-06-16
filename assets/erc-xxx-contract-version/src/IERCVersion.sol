// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERCVersion {
    /// @notice Returns the implementation version string.
    /// @return The version value, for example "1.0.0".
    function version() external view returns (string memory);
}
