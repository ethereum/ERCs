// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYATypes} from "./IKYATypes.sol";

/// @title ERC-KYA Policy Registry (base)
/// @notice Gives relying-party policies an on-chain id so two agents can reference
///         "we transact under policy P" in a KYAChallenge. The base interface stores a pointer
///         and a hash only; on-chain evaluation is a separate OPTIONAL interface.
interface IKYAPolicyRegistry is IKYATypes {
    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash, bytes32 rulesHash);

    /// @notice policyId = keccak256(abi.encode(msg.sender, policyHash, rulesHash, nonce)), where rulesHash is
    ///         the commitment to the on-chain executable projection (0x0 when the policy has none).
    ///         One policyId therefore identifies one policy document AND one exact executable projection.
    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);

    function getPolicy(bytes32 policyId)
        external
        view
        returns (address owner, string memory policyURI, bytes32 policyHash, bytes32 rulesHash);
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

    /// @notice Registers a policy together with its executable projection. The projection subset this
    ///         interface supports is exactly: a top-level conjunction (allOf) of rules over ordered-level
    ///         schemes, each with a minLevel and a non-empty issuer list. Nothing else (anyOf, categorical
    ///         equality, anchor restrictions) can be expressed here; a descriptor advertising this
    ///         projection MUST carry the same rulesHash and MUST NOT rely on unsupported conditions.
    ///         rulesHash = keccak256(abi.encode(allOf)) (canonical ABI encoding of the Rule[]).
    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external
        returns (bytes32 policyId);

    function getRules(bytes32 policyId) external view returns (Rule[] memory);

    /// @notice Pure helper: the rulesHash for a projection.
    function rulesHashOf(Rule[] calldata allOf) external pure returns (bytes32);

    /// @notice true iff every on-chain rule passes `IKYARegistry.check`. Reverts KYA_NoOnchainRules
    ///         if the policy has no stored rules and KYA_PolicyNotFound if it does not exist.
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool);
}
