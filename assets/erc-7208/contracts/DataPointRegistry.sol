// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {IDataPointRegistry} from "./interfaces/IDataPointRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title DataPointRegistry contract
 * @notice Contract for managing the creation, transfer and access control of DataPoints
 */
contract DataPointRegistry is IDataPointRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev DataPoint access data
     * @param owner Owner of the DataPoint
     * @param admins Mapping of admins for the DataPoint
     */
    struct DPAccessData {
        address owner;
        EnumerableSet.AddressSet admins;
    }

    /// @dev Counter for DataPoint allocation
    uint256 private _counter;

    /// @dev Access data for each DataPoint
    mapping(DataPoint => DPAccessData) private _accessData;

    /// @inheritdoc IDataPointRegistry
    function isAdmin(DataPoint dp, address account) public view returns (bool) {
        return _accessData[dp].admins.contains(account);
    }

    /// @inheritdoc IDataPointRegistry
    function allocate(address owner) external payable returns (DataPoint) {
        if (owner == address(0)) revert InvalidOwnerAddress(owner);
        if (msg.value > 0) revert NativeCoinDepositIsNotAccepted();

        uint256 newCounter;
        unchecked {
            newCounter = ++_counter;
        }

        if (newCounter > type(uint32).max) revert CounterOverflow();
        DataPoint dp = DataPoints.encode(address(this), uint32(newCounter));
        DPAccessData storage dpd = _accessData[dp];
        dpd.owner = owner;
        dpd.admins.add(owner);
        emit DataPointAllocated(dp, owner);
        return dp;
    }

    /// @inheritdoc IDataPointRegistry
    function transferOwnership(DataPoint dp, address newOwner) external {
        DPAccessData storage dpd = _accessData[dp];
        address currentOwner = dpd.owner;
        if (msg.sender != currentOwner) revert InvalidDataPointOwner(dp, msg.sender);
        dpd.owner = newOwner;
        _cleanAdmins(dpd.admins);
        dpd.admins.add(newOwner);
        emit DataPointOwnershipTransferred(dp, currentOwner, newOwner);
    }

    /// @inheritdoc IDataPointRegistry
    function grantAdminRole(DataPoint dp, address account) external returns (bool) {
        DPAccessData storage dpd = _accessData[dp];
        if (msg.sender != dpd.owner) revert InvalidDataPointOwner(dp, msg.sender);

        bool added = dpd.admins.add(account);
        if (added) {
            emit DataPointAdminGranted(dp, account);
            return true;
        }
        return false;
    }

    /// @inheritdoc IDataPointRegistry
    function revokeAdminRole(DataPoint dp, address account) external returns (bool) {
        DPAccessData storage dpd = _accessData[dp];
        if (msg.sender != dpd.owner) revert InvalidDataPointOwner(dp, msg.sender);

        bool removed = dpd.admins.remove(account);
        if (removed) {
            emit DataPointAdminRevoked(dp, account);
            return true;
        }
        return false;
    }

    function _cleanAdmins(EnumerableSet.AddressSet storage admins) private {
        uint256 length = admins.length();
        address[] memory accounts = admins.values();
        for (uint256 i; i < length; i++) {
            admins.remove(accounts[i]);
        }
    }
}