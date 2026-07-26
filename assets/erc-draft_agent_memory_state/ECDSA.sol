// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Minimal, dependency-free ECDSA recovery with malleability guard.
/// @dev Mirrors the well-known OpenZeppelin behavior but kept inline so the
///      reference suite builds offline (no `forge install`).
library ECDSA {
    error InvalidSignatureLength();
    error InvalidSignatureS();
    error InvalidSignature();

    /// @dev Recover the signer of `digest` from a 65-byte `signature`.
    function recover(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignatureLength();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        // Reject the upper range of s to prevent signature malleability (EIP-2).
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignatureS();
        }
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
        return signer;
    }
}
