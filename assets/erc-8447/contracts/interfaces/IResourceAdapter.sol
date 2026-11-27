// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IResourceAdapter — optional verifier for one resource kind (reference v0.2)
/// @notice The kernel accepts any (kind, anchor, digest, digestKind) on `attach`. A deployment
///         MAY bind an adapter per kind so that an anchored resource is checked live at attach
///         time: that the anchor exists, who controls it, and that the committed digest and
///         digest kind equal what the anchored contract reports (for a token-bound executable
///         skill, its package digest and the algorithm its standard fixes). Adapters MUST NOT
///         revert from these views; a missing anchor is reported as `exists == false`, a zero
///         controller and zero digests.
interface IResourceAdapter {
    function kind() external view returns (bytes32);
    function exists(uint256 chainId, address target, uint256 id) external view returns (bool);
    function controllerOf(uint256 chainId, address target, uint256 id) external view returns (address);
    function digestOf(uint256 chainId, address target, uint256 id) external view returns (bytes32 digest, bytes32 digestKind);
}
