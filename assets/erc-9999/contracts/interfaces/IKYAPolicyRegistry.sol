// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYATypes} from "./IKYATypes.sol";

/// @title ERC-KYA Policy Registry (base)
/// @notice Gives relying-party policies an on-chain id so two agents can reference
///         "we transact under policy P" in a KYAChallenge. The base interface stores a pointer
///         and a hash only; on-chain evaluation is a separate OPTIONAL interface.
interface IKYAPolicyRegistry is IKYATypes {
    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash);

    /// @notice policyId = keccak256(abi.encode(msg.sender, policyHash, nonce)).
    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);

    function getPolicy(bytes32 policyId) external view returns (address owner, string memory policyURI, bytes32 policyHash);
}

/// @title ERC-KYA Policy Evaluator (OPTIONAL extension)
/// @notice Mirrors a policy descriptor's top-level `allOf` on-chain and evaluates it with
///         `IKYARegistry.check`. Implementations MAY omit this interface entirely.
interface IKYAPolicyEvaluator is IKYATypes {
    struct Rule {
        bytes32 schemeId;
        uint8 minLevel;
        address[] issuers;
    }

    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external
        returns (bytes32 policyId);

    function getRules(bytes32 policyId) external view returns (Rule[] memory);

    /// @notice true iff every on-chain rule passes `IKYARegistry.check`. Reverts KYA_NoOnchainRules
    ///         if the policy has no stored rules and KYA_PolicyNotFound if it does not exist.
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool);
}
