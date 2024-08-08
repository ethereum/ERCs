// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/DataPoints.sol";

/**
 * @title Data Index interface
 * @notice The interface defines functions to manage the access control of DataManagers to
 *         DataPoints as well as to the data related to these DataPoints in specific dataObjects
 */
interface IDataIndex {
   /**
     * @notice Verifies if DataManager is allowed to write in specific DataPoint
     * @param dp Identifier of the DataPoint
     * @param dm Address of DataManager
     * @return if write access is allowed
     */
    function isApprovedDataManager(DataPoint dp, address dm) external view returns (bool);

    /**
     * @notice Defines if DataManager is allowed to write in specific DataPoint
     * @param dp Identifier of the DataPoint
     * @param dm Address of DataManager
     * @param approved if DataManager should be approved for the DataPoint
     * @dev Function SHOULD be restricted to DataPoint maintainer only
     */
    function allowDataManager(DataPoint dp, address dm, bool approved) external;

    /**
     * @notice Reads stored data
     * @param dobj Identifier of DataObject
     * @param dp Identifier of the DataPoint
     * @param operation Read operation to execute on the data
     * @param data Operation-specific data
     * @return Operation-specific data
     */
    function read(address dobj, DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory);

    /**
     * @notice Stores data
     * @param dobj Identifier of DataObject
     * @param dp Identifier of the DataPoint
     * @param operation Write operation to execute on the data
     * @param data Operation-specific data
     * @return Operation-specific data (can be empty)
     * @dev Function SHOULD be restricted to allowed DMs only
     */
    function write(address dobj, DataPoint dp, bytes4 operation, bytes calldata data) external returns (bytes memory);
}
