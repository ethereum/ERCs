// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IERC8004Identity — the subset of the ERC-8004 Identity Registry used by the agent
///         identity eligibility module: ERC-721 ownership and the agent wallet.
interface IERC8004Identity {
    function ownerOf(uint256 agentId) external view returns (address);
    function getAgentWallet(uint256 agentId) external view returns (address);
}
