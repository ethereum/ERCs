// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC1271 {
    /// @dev MUST return 0x1626ba7e when the signature is valid for `hash`.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
}
