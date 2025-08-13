// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockERC1271 - simple mock for ERC-1271 signatures
contract MockERC1271 {
    bytes32 public allowedHash;
    bytes   public allowedSig;

    function set(bytes32 h, bytes calldata s) external {
        allowedHash = h;
        allowedSig = s;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (hash == allowedHash && keccak256(signature) == keccak256(allowedSig)) {
            return 0x1626ba7e; // ERC1271 magic value
        }
        return 0xffffffff;
    }
}
