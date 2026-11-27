// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Facet } from "../structs/Facet.sol";

/// @title Facet Manager Interface
/// @notice Interface for atomic protocol upgrades.
/// @dev The IFacetManager interface identifier is `0x5378f98e`.
interface IFacetManager {
    
    /// @notice Atomically updates the protocol configuration.
    /// @param setF Facets to install, replace, or remove.
    /// @param addI ERC interface identifiers to register.
    /// @param remI ERC interface identifiers to unregister.
    /// @param migrator Optional storage migration contract.
    /// @param _calldata Encoded migration calldata.
    /// @dev Executes all routing and interface updates before performing
    ///      an optional storage migration.
    function atomicUpdate(
        Facet[] calldata setF, 
        bytes4[] calldata addI, 
        bytes4[] calldata remI,
        address migrator, 
        bytes calldata _calldata
    ) external;

    /// @notice Emitted after an atomic protocol update.
    /// @param setF Updated facet assignments.
    /// @param addI Registered interface identifiers.
    /// @param remI Unregistered interface identifiers.
    /// @param migrator Storage migration contract.
    /// @param _calldata Migration calldata.
    event AtomicUpdate(Facet[] setF, bytes4[] addI, bytes4[] remI, address migrator, bytes _calldata);
}
