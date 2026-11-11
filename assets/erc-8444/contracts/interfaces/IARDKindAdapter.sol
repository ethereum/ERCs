// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  ARD Onchain — kind adapter interface
/// @notice One adapter per kind. The kernel asks the adapter whether an anchor exists, who
///         controls it, whether it is backed (the L2 test) and which provenance value it carries.
///         The kernel stores none of this. Adapters MUST NOT revert from these views: a missing or
///         burned anchor is reported as `exists == false`, `controllerOf == address(0)`,
///         `backed == false`, `anchorHint == 0`.
interface IARDKindAdapter {
    /// @return the kind id served by this adapter, keccak256("ard-onchain.kind.<name>")
    function kind() external view returns (bytes32);

    /// @notice Whether (target, id) is a live anchor of this kind.
    function exists(address target, uint256 id) external view returns (bool);

    /// @notice The address with authority over the anchor right now.
    function controllerOf(address target, uint256 id) external view returns (address);

    /// @notice The L2 test: the value behind the anchor is live (an open escrow, an active identity).
    function backed(address target, uint256 id) external view returns (bool);

    /// @notice A value a resolver cross-checks against the descriptor's provenance; 0 if none.
    function anchorHint(address target, uint256 id) external view returns (bytes32);
}
