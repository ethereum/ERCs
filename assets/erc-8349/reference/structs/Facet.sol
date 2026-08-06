// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Facet
/// @notice Describes a facet routing assignment.
/// @dev Used to install, replace, or remove a facet at a routing index.
struct Facet {
    /// @dev Routing index.
    uint8 index;
    /// @dev Facet contract address.
    address facet;
}