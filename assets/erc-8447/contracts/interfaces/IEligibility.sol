// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IEligibility — eligibility module consulted by a swarm registry (skeleton v0.1)
/// @notice A role may bind one module. The registry calls `isEligible` at admission (a `false`
///         or a revert refuses the admission) and on `challenge` (a `false` suspends the
///         member with cause INELIGIBLE; a revert changes nothing — an unevaluable predicate
///         is not a failed one). Modules are expected to read trust-assertion registries,
///         agent identity registries, agent identity-and-reputation registries, allowlists,
///         or compositions of these. The kernel attaches no meaning to how they decide.
interface IEligibility {
    /// @param swarmId the swarm the role belongs to
    /// @param roleId  the role being checked
    /// @param account the candidate or member
    function isEligible(bytes32 swarmId, bytes32 roleId, address account) external view returns (bool);
}
