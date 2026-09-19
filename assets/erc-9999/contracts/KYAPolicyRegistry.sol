// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYAPolicyRegistry, IKYAPolicyEvaluator} from "./interfaces/IKYAPolicyRegistry.sol";
import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @title KYAPolicyRegistry — reference implementation (base + optional evaluator)
contract KYAPolicyRegistry is IKYAPolicyRegistry, IKYAPolicyEvaluator, IERC165 {
    struct PolicyRec {
        address owner;
        string policyURI;
        bytes32 policyHash;
        bool exists;
    }

    IKYARegistry public immutable kyaRegistry;

    mapping(bytes32 => PolicyRec) private _policies;
    mapping(bytes32 => Rule[]) private _rules;
    mapping(address => uint256) private _nonces;

    constructor(address kyaRegistry_) {
        kyaRegistry = IKYARegistry(kyaRegistry_);
    }

    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId) {
        policyId = _register(policyURI, policyHash);
    }

    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external
        returns (bytes32 policyId)
    {
        policyId = _register(policyURI, policyHash);
        for (uint256 i = 0; i < allOf.length; i++) {
            if (allOf[i].issuers.length == 0) revert KYA_EmptyIssuers();
            _rules[policyId].push(allOf[i]);
        }
    }

    function getPolicy(bytes32 policyId) external view returns (address owner, string memory policyURI, bytes32 policyHash) {
        PolicyRec storage p = _policies[policyId];
        if (!p.exists) revert KYA_PolicyNotFound(policyId);
        return (p.owner, p.policyURI, p.policyHash);
    }

    function getRules(bytes32 policyId) external view returns (Rule[] memory) {
        return _rules[policyId];
    }

    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool) {
        if (!_policies[policyId].exists) revert KYA_PolicyNotFound(policyId);
        Rule[] storage rules = _rules[policyId];
        if (rules.length == 0) revert KYA_NoOnchainRules(policyId);
        for (uint256 i = 0; i < rules.length; i++) {
            if (!kyaRegistry.check(subject, rules[i].schemeId, rules[i].minLevel, rules[i].issuers)) return false;
        }
        return true;
    }

    function _register(string calldata policyURI, bytes32 policyHash) internal returns (bytes32 policyId) {
        uint256 nonce = _nonces[msg.sender]++;
        policyId = keccak256(abi.encode(msg.sender, policyHash, nonce));
        _policies[policyId] = PolicyRec({owner: msg.sender, policyURI: policyURI, policyHash: policyHash, exists: true});
        emit PolicyRegistered(policyId, msg.sender, policyURI, policyHash);
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IKYAPolicyRegistry).interfaceId || interfaceId == type(IKYAPolicyEvaluator).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
