// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import {_Data} from "../_Data.sol";

contract Dapp is _Data {

    address private private_data;
    
    constructor(address _staticCallTransfer) _Data(_staticCallTransfer) {
        private_data = msg.sender;
    }


}