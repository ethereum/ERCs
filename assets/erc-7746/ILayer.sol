// SPDX-License-Identifier: CC0-1.0
pragma solidity =0.8.20;

interface ILayer {
    function beforeCall(
        bytes memory configuration,
        bytes4 selector,
        address sender,
        uint256 value,
        bytes memory data
    ) external returns (bytes memory);

    function afterCall(
        bytes memory configuration,
        bytes4 selector,
        address sender,
        uint256 value,
        bytes memory data,
        bytes memory beforeCallResult
    ) external;
}
