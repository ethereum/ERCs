// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Facet } from "../structs/Facet.sol";

/// @title Observability Interface
/// @notice Interface for querying the current protocol configuration.
/// @dev The IObservability interface identifier is `0x1c60a259`.
interface IObservability {

    /// @notice Returns all installed facet addresses.
    /// @return Array of installed facet addresses.
    function getFacets() external view returns (address[] memory);

    /// @notice Returns all installed facet entries.
    /// @dev Each entry contains both the routing index and facet address.
    /// @return Array of installed facet entries.
    function getFacetEntries() external view returns (Facet[] memory);

    /// @notice Returns the facet installed at a routing index.
    /// @param index Routing index.
    /// @return Facet address, or the zero address if the slot is empty.
    function getFacetAt(uint8 index) external view returns (address);

    /// @notice Returns the number of installed facets.
    /// @return Number of occupied routing slots.
    function getFacetCount() external view returns (uint16);

    /// @notice Returns the first available routing slot.
    /// @return Index of the first unoccupied routing slot.
    /// @dev Reverts if all routing slots are occupied.
    function getFirstFreeSlot() external view returns (uint8);
}
