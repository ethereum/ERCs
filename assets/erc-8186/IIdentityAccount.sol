// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IIdentityAccount
/// @notice Per-identifier account that the registered owner can execute calls through.
interface IIdentityAccount {
    /// @notice Execute an arbitrary call through this account.
    /// @dev    Only the registered owner of the associated identifier may call this.
    /// @param  target The contract to call.
    /// @param  data   The calldata to send.
    /// @param  value  The ETH value to forward.
    /// @return The return data from the call.
    function execute(address target, bytes calldata data, uint256 value)
        external
        returns (bytes memory);
}
