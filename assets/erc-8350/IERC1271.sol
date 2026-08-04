// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Standard signature validation interface implemented by contract wallets.
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}
