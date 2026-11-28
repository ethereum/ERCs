//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { cloneContract } from "./Utilities.sol";

contract CloneFactory {
    event Cloned(address indexed clonedInstance);

    function clone(address implementation) public returns (address) {
        address cloneInstance = cloneContract(implementation);
        emit Cloned(cloneInstance);
        return cloneInstance;
    }

    function cloneWithInit(address implementation, bytes memory initData) public returns (address) {
        // todo: extract selector and data; call via yul; wrap in try catch
        (initData);
        address cloneInstance = cloneContract(implementation);
        emit Cloned(cloneInstance);
        return cloneInstance;
    }
}
