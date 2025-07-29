// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IData} from "../interfaces/IData.sol";

contract BeAttacked {

    address public data_contract;

    constructor(address _data_contract) {
        data_contract = _data_contract;
    }

    function getAsset() external view returns (uint) {
        bytes4 selector = IData.changeDataFunction.selector;
        //union lock
        require(IData(data_contract).getFunctionCallTimes(selector) == 0, "refuse reentry");
        return IData(data_contract).canGetAsset();
    }
}