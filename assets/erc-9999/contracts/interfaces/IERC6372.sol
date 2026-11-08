// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC6372 {
    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
