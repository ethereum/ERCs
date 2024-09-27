// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../utils/DataPoints.sol";

/**
 * @title ID Manager Interface
 * @notice Interface defines functions to build DataIndex user identifiers and get information about them
 */
interface IIDManager {
    /**
     * @notice Provides DataIndex id for a specific account for a specific DataPoint
     * @param account Address of the user
     * @param dp DataPoint the id should be linked with
     * @return DataIndex identifier
     * @dev If no token available, this function REVERTS
     */
    function diid(address account, DataPoint dp) external view returns (bytes32);

    /**
     * @notice Provides information about owner of specific DataIndex id
     * @param diid DataIndex id to get info for
     * @return chainid of owner's address
     * @return owner's address
     */
    function ownerOf(bytes32 diid) external view returns (uint32, address);
}
