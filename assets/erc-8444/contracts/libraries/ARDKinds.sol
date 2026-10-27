// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  Kind identifiers
/// @notice A kind is a value posture, never a payload format. kindId = keccak256("ard-onchain.kind.<name>").
library ARDKinds {
    bytes32 internal constant SKILL    = keccak256("ard-onchain.kind.skill");    // offer, supply side
    bytes32 internal constant TASK     = keccak256("ard-onchain.kind.task");     // tender, demand side
    bytes32 internal constant AGENT    = keccak256("ard-onchain.kind.agent");    // subject
    bytes32 internal constant REGISTRY = keccak256("ard-onchain.kind.registry"); // index

    // Reserved names (not defined by the ERC): "assertion", "policy", "market".

    function kindId(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("ard-onchain.kind.", name));
    }
}
