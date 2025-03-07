// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import {I_Data} from "./interfaces/I_Data.sol";

contract _Data {
	address immutable staticCallTransfer;
	
	constructor(address _staticCallTransfer) {
		staticCallTransfer = _staticCallTransfer;
	}
	
    function _data_(address logicContract, bytes memory _data) external returns (bytes memory) {
    	require(msg.sender == staticCallTransfer,"_Data: only Static Call");
        (bool success, bytes memory result) = logicContract.delegatecall(
            _data
            );
        require(success, "_Data: _data_ failed");
        return result;
    }
}