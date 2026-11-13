// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title Minimal view surface of an ERC-8004 Identity Registry used by AID
/// @notice Only the two views AID needs. Any ERC-8004 Identity Registry satisfies this.
interface IERC8004Identity {
    /// @dev ERC-721 ownerOf; MUST revert for a non-existent (burned / never minted) agentId
    function ownerOf(uint256 agentId) external view returns (address);

    /// @dev ERC-8004 agent wallet (payment receiver). address(0) when unset.
    function getAgentWallet(uint256 agentId) external view returns (address);
}
