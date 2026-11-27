// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IAddressAnchoredIdentity — the subset of an address-anchored agent identity registry
///         used by the identity-state eligibility module: the on-chain state of an anchor
///         (0 DORMANT, 1 ACTIVE, 2 STALE, 3 RETIRED). Informative: the module, not the swarm
///         registry, depends on it.
interface IAddressAnchoredIdentity {
    function state(address anchor) external view returns (uint8);
}
