// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title Pausable -- Emergency pause mechanism
/// @dev Inheriting contracts get paused state, whenNotPaused modifier, and pause/unpause.
///      Requires an onlyOwner modifier from the inheriting contract.
abstract contract Pausable {
    bool public paused;

    error ContractPaused();
    error ContractNotPaused();

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /// @notice Pause the contract
    function pause() external virtual;

    /// @notice Unpause the contract
    function unpause() external virtual;
}
