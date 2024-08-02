// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../utils/DataPoints.sol";

/**
 * @title Data Point Registry Interface
 * @notice Interface defines functions to manage creation, transfer and access control of DataPoints
 */
interface IDataPointRegistry {
    /**
     * @notice Event emitted when a DataPoint is allocated
     * @param dp DataPoint identifier
     * @param owner Owner of the DataPoint
     */
    event DataPointAllocated(DataPoint indexed dp, address owner);

    /**
     * @notice Event emitted when ownership of a DataPoint is transferred
     * @param dp DataPoint identifier
     * @param previousOwner Previous owner
     * @param newOwner New owner
     */
    event DataPointOwnershipTransferred(DataPoint indexed dp, address previousOwner, address newOwner);

    /**
     * @notice Event emitted when Admin role is granted
     * @param dp DataPoint identifier
     * @param account Account granted with Admin role
     */
    event DataPointAdminGranted(DataPoint indexed dp, address account);

    /**
     * @notice Event emitted when Admin role is revoked
     * @param dp DataPoint identifier
     * @param account Account revoked from Admin role
     */
    event DataPointAdminRevoked(DataPoint indexed dp, address account);

    /// @dev Error thrown when DataPoint allocation counter overflows
    error CounterOverflow();

    /// @dev Error thrown when native coin is sent in allocation
    error NativeCoinDepositIsNotAccepted();

    /**
     * @notice Error thrown when caller is not the owner of the DataPoint
     * @param dp DataPoint identifier
     * @param owner Invalid owner
     */
    error InvalidDataPointOwner(DataPoint dp, address owner);

    /**
     * @notice Verifies if an address has an Admin role for a DataPoint
     * @param dp DataPoint
     * @param account Account to verify
     */
    function isAdmin(DataPoint dp, address account) external view returns (bool);

    /**
     * @notice Allocates a DataPoint to an owner
     * @param owner Owner of the new DataPoint
     * @dev Owner SHOULD be granted Admin role during allocation
     */
    function allocate(address owner) external payable returns (DataPoint);

    /**
     * @notice Transfers ownership of a DataPoint to a new owner
     * @param dp DataPoint identifier
     * @param newOwner New owner
     */
    function transferOwnership(DataPoint dp, address newOwner) external;

    /**
     * @notice Grant permission to grant/revoke other roles on the DataPoint inside an DataIndex Implementation
     * This is useful if DataManagers are deployed during lifecycle of the application.
     * @param dp DataPoint identifier
     * @param account New admin
     * @return If the role was granted (otherwise account already had the role)
     */
    function grantAdminRole(DataPoint dp, address account) external returns (bool);

    /**
     * @notice Revoke permission to grant/revoke other roles on the DataPoint inside an DataIndex Implementation
     * @param dp DataPoint identifier
     * @param account Old admin
     * @dev If an owner revokes Admin role from himself, he can add it again
     * @return If the role was revoked (otherwise account didn't had the role)
     */
    function revokeAdminRole(DataPoint dp, address account) external returns (bool);
}
