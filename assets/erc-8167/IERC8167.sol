// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.30;

interface IERC8167 {
    // REQUIRED
    event SetDelegate(bytes4 indexed selector, address indexed delegate);

    // REQUIRED
    function implementation(bytes4 selector) external view returns (address);

    // RECOMMENDED
    function selectors() external view returns (bytes4[] memory);

    // RECOMMENDED
    error FunctionNotFound(bytes4 selector);
}
