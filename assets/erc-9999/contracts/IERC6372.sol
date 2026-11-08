// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @dev ERC-6372 contract clock.
interface IERC6372 {
    function clock() external view returns (uint48);

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view returns (string memory);
}
