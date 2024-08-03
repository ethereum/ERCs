// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/DataPoints.sol";
import "./IDataIndex.sol";

/**
 * @title Data Object Interface
 * @notice Interface defines functions to manage the DataIndex implementation and the data
 *         stored in DataObjects and associated with DataPoints
 */
interface IDataObject {
    /**
     * @notice Reads stored data
     * @param dp Identifier of the DataPoint
     * @param operation Read operation to execute on the data
     * @param data Operation-specific data
     * @return Operation-specific data
     */
    function read(DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory);

    /**
     * @notice Store data
     * @param dp Identifier of the DataPoint
     * @param operation Read operation to execute on the data
     * @param data Operation-specific data
     * @return Operation-specific data (can be empty)
     */
    function write(DataPoint dp, bytes4 operation, bytes calldata data) external returns (bytes memory);

    /**
     * @notice Sets DataIndex Implementation
     * @param dp Identifier of the DataPoint
     * @param newImpl address of the new DataIndex implementation
     */
    function setDIImplementation(DataPoint dp, IDataIndex newImpl) external;
}
