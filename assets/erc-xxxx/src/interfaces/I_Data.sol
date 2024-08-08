// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

interface I_Data {
    /**
     * @dev Executes a data function on a logic contract.
     * @param logicContract The address of the logic contract.
     * @param _data The data to be executed on the logic contract.
     * @return _re The result of executing the data function.
     */
    function _data_(address logicContract, bytes memory _data) external returns (bytes memory _re);
}