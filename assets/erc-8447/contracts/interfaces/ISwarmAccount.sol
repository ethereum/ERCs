// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ISwarmAccount — the account a swarm acts and holds value through (reference v0.3)
/// @notice A swarm account is bound to exactly one swarm of exactly one registry instance.
///         It is the address a counterparty deals with: the fulfiller of record on a task
///         tender, the holder of attached assets, the payer of allocations. While the swarm
///         lives, only accounts the registry reports as authorized for REPRESENT act through
///         it. After dissolution nobody is authorized for anything, so the account answers
///         "who may act then" by its own rule: `recoveryAddress()` names the one account that
///         may act once the swarm is DISSOLVED (zero: nobody, whatever is left stays). The
///         kernel verifies the binding when `setAccount` is called
///         (`account.swarmId() == swarmId && account.registry() == registry`).
interface ISwarmAccount {
    function swarmId() external view returns (bytes32);
    function registry() external view returns (address);
    function recoveryAddress() external view returns (address);
}
