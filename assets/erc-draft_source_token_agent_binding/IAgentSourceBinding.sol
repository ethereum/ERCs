// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IAgentSourceBinding — Source-Token Agent Binding for ERC-8004
/// @notice Minimal interface for an ERC-8004 agent identity registry bound to a
///         single source ERC-721 collection. Holders of the bound collection
///         bridge a token they own into an agent identity. The source token is
///         recorded at registration as permanent provenance and is never locked
///         or transferred; live ownership is exposed as a separate, re-checkable
///         view.
/// @dev ERC-165 interface id: 0x27eba962 (XOR of the five function selectors below).
///      A compliant registry MUST also implement ERC-721 and ERC-8004.
interface IAgentSourceBinding is IERC165 {
    /// @notice Emitted once, at registration, binding an agent to its source token.
    /// @dev MUST be emitted exactly once per `agentId` and MUST NOT be emitted again.
    event SourceNFTLinked(
        uint256 indexed agentId,
        address indexed sourceContract,
        uint256 sourceTokenId
    );

    /// @notice The source ERC-721 collection this registry is bound to.
    /// @dev MUST be immutable for the life of the registry.
    function boundCollection() external view returns (address);

    /// @notice Register an agent derived from `sourceTokenId` of `boundCollection`.
    /// @dev MUST revert unless `IERC721(boundCollection).ownerOf(sourceTokenId) == msg.sender`.
    ///      MUST mint a new agent identity (ERC-721) to `msg.sender`.
    ///      MUST record `(boundCollection, sourceTokenId)` as immutable provenance.
    ///      MUST emit `SourceNFTLinked`.
    ///      MUST NOT lock, escrow, or transfer the source token.
    /// @param sourceTokenId The token id in `boundCollection` to derive the agent from.
    /// @return agentId The newly minted agent identity.
    function registerWithSource(uint256 sourceTokenId)
        external
        payable
        returns (uint256 agentId);

    /// @notice The immutable source token an agent was derived from.
    /// @dev MUST revert if `agentId` does not exist or has no source binding.
    function getSourceNFT(uint256 agentId)
        external
        view
        returns (address sourceContract, uint256 sourceTokenId);

    /// @notice Whether `agentId` has a recorded source binding.
    function hasSourceNFT(uint256 agentId) external view returns (bool);

    /// @notice Whether the source token is still under the control of `agentId`.
    /// @dev Live check via `ownerOf`. Returns true if `ownerOf(sourceToken)` is any of:
    ///      (a) the current owner of `agentId` (direct, non-custodial holding);
    ///      (b) the agent's CANONICAL ERC-6551 token-bound account (sovereignty); or
    ///      (c) the binding contract itself (source escrowed under the binding).
    ///      (b) is pinned: the account from the ERC-6551 registry
    ///      0x000000006551c19487814612e58FE06813775758 using the implementation and salt
    ///      the binding registry declares — not "any TBA of the agent", since a token
    ///      is the base of unboundedly many CREATE2-derived accounts. The registry MUST
    ///      make that implementation and salt determinable.
    ///      A bare `ownerOf(sourceToken) == ownerOf(agentId)` check is non-conformant —
    ///      it force-fails the TBA / binding-custody (sovereignty) patterns.
    ///      MUST NOT rely on cached ownership. Reverts for a non-existent `agentId`
    ///      (per ERC-721 `ownerOf`); returns false (not revert) when the source token
    ///      no longer exists.
    function isSourceNFTOwnershipValid(uint256 agentId) external view returns (bool);
}
