// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  SignatureChecker — ECDSA (EOA) or ERC-1271 (contract account) validation.
/// @notice Minimal, dependency-free. Rejects high-s ECDSA signatures and v not in {27, 28}.
///         For contract accounts the ERC-1271 result may depend on the account's state and
///         on time; acceptance time is the block in which the ballot batch is submitted.
library SignatureChecker {
    bytes4 internal constant ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    function isValid(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        if (signer == address(0)) return false;
        if (signer.code.length > 0) {
            (bool ok, bytes memory ret) = signer.staticcall(
                abi.encodeWithSelector(ERC1271_MAGIC, digest, signature)
            );
            return ok && ret.length == 32 && abi.decode(ret, (bytes4)) == ERC1271_MAGIC;
        }
        if (signature.length != 65) return false;
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (uint256(s) > HALF_N) return false;
        if (v != 27 && v != 28) return false;
        address rec = ecrecover(digest, v, r, s);
        return rec != address(0) && rec == signer;
    }
}
