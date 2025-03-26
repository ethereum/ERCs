// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IData {

    function canGetAsset() external view returns (uint);

    function changeDataFunction(uint _after_can_receive_asset) external;

    function getFunctionCallTimes(bytes4 selector) external view returns (uint256);

    function getContractCallTimes() external view returns (uint256);
}