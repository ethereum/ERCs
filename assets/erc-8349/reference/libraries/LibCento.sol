// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CentoStorage as CS } from "../structs/CentoStorage.sol";
import { bitmap256 } from "../libraries/LibBitmap.sol";

/// @title Cento Library
/// @notice Core library for accessing and managing the shared `CentoStorage`.
/// @dev Provides helpers for ownership management, facet installation,
/// storage access, and storage migrations.
library LibCento {

    /// @dev ERC-7201 namespace backing the shared `CentoStorage` layout.
    bytes32 constant BASE_SLOT = 0x69f90de95fb99742e875407e8b95a22f11141a7a0ca101bc562658f163a85b00;

    /// @notice Emitted when protocol ownership changes.
    /// @param previousOwner Previous protocol owner.
    /// @param newOwner New protocol owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted after a storage migration completes successfully.
    /// @param migrator Storage migration contract.
    event StorageMigrationSucceeded(address indexed migrator);

    /// @notice Attempted to remove a facet from an unoccupied routing slot.
    error ZeroFacetForEmptySlot();
    /// @notice Attempted to install the router as one of its own facets.
    error RouterAsFacetForbidden();
    /// @notice Caller is not the protocol owner.
    /// @param caller Unauthorized caller.
    error NotContractOwner(address caller);
    /// @notice Target address has no runtime code or is an EOA.
    /// @param target Target address.
    error NoCodeOrEOA(address target);
    /// @notice Target address is an EIP-7702 delegated EOA.
    /// @param account Target address.
    error Is7702EOA(address account);
    /// @notice Storage migration failed without returning a revert reason.
    /// @param migrator Storage migration contract.
    error StorageMigrationFailed(address migrator);

    /// @notice Returns the shared `CentoStorage`.
    /// @return cs Reference to the core protocol storage namespace.
    /// @dev Uses the ERC-7201 storage namespace assigned to `CentoStorage`.
    function _cs() internal pure returns (CS storage cs) {
        bytes32 position = BASE_SLOT;
        assembly { cs.slot := position }
    }

    /// @notice Installs, replaces, or removes a facet.
    /// @param index Routing index.
    /// @param facet New facet address.
    /// @param bitmap Current routing bitmap.
    /// @return Updated routing bitmap.
    /// @dev Installing a facet marks the slot as occupied.
    /// Removing a facet clears the slot.
    /// @dev Reverts if:
    /// - removing a facet from an empty slot - `ZeroFacetForEmptySlot`;
    /// - installing the router itself - `RouterAsFacetForbidden`;
    /// - installing an empty contract, an EOA, or EIP-7702 delegated EOA - `_isNotEoa`.
    function setFacet(uint8 index, address facet, bitmap256 bitmap) internal returns (bitmap256) {
        CS storage cs = _cs();
        bool occupied = bitmap.isSlotOccupied(index);
        if (!occupied && facet == address(0)) revert ZeroFacetForEmptySlot();
        if (facet == address(this)) revert RouterAsFacetForbidden();
        if (facet != address(0)) {
            _isNotEoa(facet);
            if (!occupied) bitmap = bitmap.fillSlotAt(index);
        } else bitmap = bitmap.clearSlotAt(index);
        cs.facets[index] = facet;
        return bitmap;
    }

    /// @notice Returns the current protocol owner.
    function contractOwner() internal view returns (address owner_) {
        CS storage cs = _cs();
        owner_ = cs.contractOwner;
    }
    
    /// @notice Ensures the caller is the protocol owner.
    /// @dev Reverts with `NotContractOwner` otherwise.
    function enforceIsContractOwner() internal view {
        if (msg.sender != _cs().contractOwner) revert NotContractOwner(msg.sender);
    }

    /// @notice Transfers protocol ownership.
    /// @param _newOwner New owner address.
    /// @dev Emits `OwnershipTransferred`.
    function setContractOwner(address _newOwner) internal {
        CS storage cs = _cs();
        address previousOwner = cs.contractOwner;
        cs.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /// @dev Ensures the target is a deployed contract.
    /// Reverts with `NoCodeOrEOA` for EOAs or empty contracts,\
    /// or with `Is7702EOA` for EIP-7702 delegated EOAs.
    function _isNotEoa(address a) private view {
        uint256 size;
        assembly { size := extcodesize(a) }
        if (size == 0) revert NoCodeOrEOA(a);
        bytes3 prefix;
        assembly ("memory-safe") {
            extcodecopy(a, 0x00, 0, 3)
            prefix := mload(0x00)
        }
        if (prefix == 0xef0100) revert Is7702EOA(a);
    }

    /// @notice Executes a storage migration.
    /// @param migrator Migration contract.
    /// @param _calldata Encoded migration call.
    /// @dev Executes the migration using delegatecall within the router storage\
    ///      context. Emits `StorageMigrationSucceeded` upon success.\
    ///      Target contract is expected to be trusted to execute in router storage context.
    /// @dev Reverts with the original revert data when available.\ 
    ///      Otherwise reverts with `StorageMigrationFailed`
    function storageMigration(address migrator, bytes memory _calldata) internal {
        if (migrator == address(0)) return;
        _isNotEoa(migrator);
        (bool success, bytes memory returndata) = migrator.delegatecall(_calldata);
        if (!success) {
            if (returndata.length > 0) assembly ("memory-safe") {
                revert(add(returndata, 32), mload(returndata))
            }
            revert StorageMigrationFailed(migrator);
        }
        emit StorageMigrationSucceeded(migrator);
    }
}
