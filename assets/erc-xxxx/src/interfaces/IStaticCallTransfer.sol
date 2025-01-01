// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

interface IStaticCallTransfer {

    /**
     * @dev Retrieves custom data from a data contract using a static call to a logic contract.
     * @param dataContract The address of the data contract.
     * @param logicContract The address of the logic contract.
     * @param _data The data to be passed to the logic contract.
     * @return _re The result of the static call to the logic contract.
     */
    function getCustomData(
        address dataContract,
        address logicContract,
        bytes memory _data
    ) external returns (bytes memory _re);
}