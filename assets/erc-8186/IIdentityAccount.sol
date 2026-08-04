// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IIdentityAccount
/// @notice Per-identifier account that the registered owner can execute calls through.
interface IIdentityAccount {
    /// @notice Forward an arbitrary call from this account's address.
    /// @dev    MUST allow if ownerOf(id) == msg.sender.
    ///         MUST revert otherwise, unless the optional reclaim extension
    ///         authorizes the caller (see IReclaimableIdentityAccount).
    ///         MUST revert if the inner call fails.
    /// @param  target The contract to call.
    /// @param  data   The calldata to send.
    /// @param  value  The ETH value to forward.
    /// @return The return data from the call.
    function execute(address target, bytes calldata data, uint256 value)
        external
        returns (bytes memory);

    /// @notice The identifier this account is bound to.
    function id() external view returns (bytes32);

    /// @notice The ERC-8185 registry this account resolves ownership against.
    function registry() external view returns (address);
}
