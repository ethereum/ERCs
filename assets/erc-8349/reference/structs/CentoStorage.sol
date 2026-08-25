// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { bitmap256 } from "../libraries/LibBitmap.sol";

/// @title Cento Storage
/// @notice Shared storage layout used by the `CentoRouter` and its core facets.
/// @dev Stored under a dedicated ERC-7201 namespace and accessed\ 
///      through `LibCento._cs()`, commonly imported as `lc._cs()`.
struct CentoStorage {
    /// @dev Facet table indexed by routing index.
    address[256] facets;
    /// @dev Bitmap tracking occupied facet slots.
    bitmap256 indexBitmap;
    /// @dev Current protocol owner.
    address contractOwner;
    /// @dev Registry of supported ERC interface identifiers.
    mapping(bytes4 => bool) supportedInterfaces;
}
