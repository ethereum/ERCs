// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import {IData} from "../interfaces/IData.sol";

contract Data is IData {

    uint public canGetAsset;

    function changeDataFunction(uint _after_can_receive_asset) external {
        canGetAsset = _after_can_receive_asset;

        bytes4 selector = IData.changeDataFunction.selector;

        addFunctionCallTimes(selector);
        addContractCallTimes();
    }

    function addFunctionCallTimes(bytes4 selector) internal {
        assembly {
            let i := tload(selector)
            i := add(i, 1)
            tstore(selector, i)
        }
    }

    function addContractCallTimes() internal {
        address self = address(this);

        assembly {
            let i := tload(self)
            i := add(i, 1)
            tstore(self, i)
        }
    }

    function getFunctionCallTimes(bytes4 selector) external view override returns (uint256 i) {

        assembly {
            i := tload(selector)
        }
    }

    function getContractCallTimes() external view override returns (uint256 i) {
        address self = address(this);

        assembly {
            i := tload(self)
        }
    }
}