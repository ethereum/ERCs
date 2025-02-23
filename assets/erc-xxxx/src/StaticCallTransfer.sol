// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import "./interfaces/IStaticCallTransfer.sol";
import {I_Data} from "./interfaces/I_Data.sol";

contract StaticCallTransfer is IStaticCallTransfer {
    function transferStaticCall(address to, bytes memory data) public view returns (bytes memory _re) {

        assembly {
            let size := mload(data)
            let ptr := add(data, 0x20)
            let result := staticcall(gas(), to, ptr, size, 0, 0)
            let size2 := returndatasize()
            _re := mload(0x40)
            mstore(0x40, add(_re, add(size2, 0x20)))
            mstore(_re, size2)
            returndatacopy(add(_re, 0x20), 0, size2)
            switch result
            case 0 {
                revert(0, 0)
            }
        }
        _re = abi.decode(_re, (bytes));
    }

    function getCustomData(address dataContract, address logicContract, bytes memory _data) external view returns (bytes memory _re) {
        bytes memory data = abi.encodeWithSelector(I_Data._data_.selector, logicContract, _data);
        return transferStaticCall(dataContract, data);
    }
}