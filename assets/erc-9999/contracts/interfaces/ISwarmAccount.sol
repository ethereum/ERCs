// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ISwarmAccount — the account a swarm acts and holds value through (skeleton v0.1)
/// @notice A swarm account is bound to exactly one swarm of exactly one registry instance.
///         It is the address a counterparty deals with: the fulfiller of record on a task
///         tender, the holder of attached assets, the payer of allocations. How it executes
///         calls and distributes value is a profile; the kernel only verifies the binding
///         when `setAccount` is called (`account.swarmId() == swarmId && account.registry() == registry`).
interface ISwarmAccount {
    function swarmId() external view returns (bytes32);
    function registry() external view returns (address);
}
