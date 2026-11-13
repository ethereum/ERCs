// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";
import {IERC8004Identity} from "./interfaces/IERC8004Identity.sol";

/// @title  ERC8004Eligibility — a member must be a registered agent (reference v0.2)
/// @notice An account declares the agent it acts for; the declaration is accepted only if the
///         account is the agent's owner or its agent wallet at that moment. `isEligible` re-reads
///         the same predicate live, so a transfer of the agent or a change of its wallet makes a
///         later `challenge` suspend the member. The module stores no claim about trust: it binds
///         a seat to an identity and nothing more. Compose it with assertion or state modules for
///         trust conditions.
contract ERC8004Eligibility is IEligibility {
    IERC8004Identity public immutable identity;
    mapping(address => uint256) public agentOf;   // account => declared agentId (0 = none)

    event AgentDeclared(address indexed account, uint256 indexed agentId);

    constructor(IERC8004Identity identity_) {
        require(address(identity_) != address(0), "ERC8004Eligibility: zero registry");
        identity = identity_;
    }

    function declareAgent(uint256 agentId) external {
        require(agentId != 0 && _controls(msg.sender, agentId), "ERC8004Eligibility: not the agent's owner or wallet");
        agentOf[msg.sender] = agentId;
        emit AgentDeclared(msg.sender, agentId);
    }

    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        uint256 agentId = agentOf[account];
        return agentId != 0 && _controls(account, agentId);
    }

    function _controls(address account, uint256 agentId) private view returns (bool) {
        (bool ok, bytes memory ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.ownerOf.selector, agentId));
        if (!ok || ret.length != 32) return false;
        if (abi.decode(ret, (address)) == account) return true;
        (ok, ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.getAgentWallet.selector, agentId));
        return ok && ret.length == 32 && abi.decode(ret, (address)) == account;
    }
}
