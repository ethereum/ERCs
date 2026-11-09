// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  IAgentIdentityRegistry — the two views of the address-anchored agent identity draft (AID)
///         the agent adapter reads. Any registry conforming to that draft satisfies this.
interface IAgentIdentityRegistry {
    enum State { DORMANT, ACTIVE, STALE, RETIRED }

    function state(address anchor) external view returns (State);
    function documentURI(address anchor) external view returns (string memory uri, bytes32 digest);
}
