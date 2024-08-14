// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {IDataPointRegistry} from "./interfaces/IDataPointRegistry.sol";

/**
 * @title DataPointRegistry contract
 * @notice Contract for managing the creation, transfer and access control of DataPoints
 */
contract DataPointRegistry is IDataPointRegistry {
    /**
     * @notice DataPoint access data
     * @param owner Owner of the DataPoint
     * @param isAdmin Mapping of isAdmin status for each account
     */
    struct DPAccessData {
        address owner;
        mapping(address => bool) isAdmin;
    }

    /// @dev Counter for DataPoint allocation
    uint256 private counter;

    /// @dev Access data for each DataPoint
    mapping(DataPoint => DPAccessData) private accessData;

    /// @inheritdoc IDataPointRegistry
    function isAdmin(DataPoint dp, address account) public view returns (bool) {
        return accessData[dp].isAdmin[account];
    }

    /// @inheritdoc IDataPointRegistry
    function allocate(address owner) external payable returns (DataPoint) {
        if (msg.value > 0) revert NativeCoinDepositIsNotAccepted();
        uint256 newCounter = ++counter;
        if (newCounter > type(uint32).max) revert CounterOverflow();
        DataPoint dp = DataPoints.encode(address(this), uint32(newCounter));
        DPAccessData storage dpd = accessData[dp];
        dpd.owner = owner;
        dpd.isAdmin[owner] = true;
        emit DataPointAllocated(dp, owner);
        return dp;
    }

    /// @inheritdoc IDataPointRegistry
    function transferOwnership(DataPoint dp, address newOwner) external {
        DPAccessData storage dpd = accessData[dp];
        address currentOwner = dpd.owner;
        if (msg.sender != currentOwner) revert InvalidDataPointOwner(dp, msg.sender);
        dpd.owner = newOwner;
        emit DataPointOwnershipTransferred(dp, currentOwner, newOwner);
    }

    /// @inheritdoc IDataPointRegistry
    function grantAdminRole(DataPoint dp, address account) external returns (bool) {
        DPAccessData storage dpd = accessData[dp];
        if (msg.sender != dpd.owner) revert InvalidDataPointOwner(dp, msg.sender);
        if (!isAdmin(dp, account)) {
            dpd.isAdmin[account] = true;
            emit DataPointAdminGranted(dp, account);
            return true;
        }
        return false;
    }

    /// @inheritdoc IDataPointRegistry
    function revokeAdminRole(DataPoint dp, address account) external returns (bool) {
        DPAccessData storage dpd = accessData[dp];
        if (msg.sender != dpd.owner) revert InvalidDataPointOwner(dp, msg.sender);
        if (isAdmin(dp, account)) {
            dpd.isAdmin[account] = false;
            emit DataPointAdminRevoked(dp, account);
            return true;
        }
        return false;
    }
}
