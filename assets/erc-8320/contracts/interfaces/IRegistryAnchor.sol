// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IRegistryAnchor
/// @notice Asset-side interface. An asset implements this to approve the registries that hold claims for it.
///         A consumer MUST rely on a registry's claim for an asset only if the asset approves that registry.
interface IRegistryAnchor is IERC165 {
    /// @notice Emitted by `setRegistry`.
    /// @param registry Registry address.
    /// @param asset Asset contract address.
    /// @param approved Whether the registry is approved.
    event RegistrySet(address indexed registry, address indexed asset, bool approved);

    /// @notice Approves or removes a registry for this asset.
    /// @dev MUST revert unless the caller is the asset contract's owner or administrator.
    /// @param registry Registry address.
    /// @param approved Whether the registry is approved.
    function setRegistry(address registry, bool approved) external;

    /// @notice Returns registries known by this asset.
    /// @return Registry addresses known by this asset.
    function getRegistries() external view returns (address[] memory);

    /// @notice Checks whether this asset approves a registry.
    /// @param registry Registry address.
    /// @return True if `registry` is approved by this asset.
    function isRegistryApproved(address registry) external view returns (bool);
}
