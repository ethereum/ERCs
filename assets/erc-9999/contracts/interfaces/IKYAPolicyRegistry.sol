// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYATypes} from "./IKYATypes.sol";

/// @title ERC-KYA Policy Registry (minimal)
/// @notice Gives relying-party policies an on-chain id so two agents can reference
///         "we transact under policy P" in a KYAChallenge. On-chain evaluation is OPTIONAL.
interface IKYAPolicyRegistry is IKYATypes {
    struct Rule {
        bytes32 schemeId;
        uint8 minLevel;
        address[] issuers;
    }

    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash);

    /// @notice policyId = keccak256(abi.encode(msg.sender, policyHash, nonce)).
    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);

    /// @notice OPTIONAL: register with an on-chain `allOf` rule set mirroring the descriptor's top-level allOf.
    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external
        returns (bytes32 policyId);

    function getPolicy(bytes32 policyId) external view returns (address owner, string memory policyURI, bytes32 policyHash);

    /// @notice OPTIONAL: true iff every on-chain rule passes `IKYARegistry.check`. Reverts if no rules stored.
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool);
}
