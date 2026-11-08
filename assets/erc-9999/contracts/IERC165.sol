// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @dev ERC-165 standard interface detection.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
