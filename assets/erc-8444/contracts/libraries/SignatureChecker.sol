// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC1271} from "../interfaces/IERC1271.sol";

/// @title  Signature verification for EOAs (ECDSA, low-s, v in {27,28}) and contract accounts (ERC-1271).
library SignatureChecker {
    bytes4 private constant _MAGIC = 0x1626ba7e;
    uint256 private constant _HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    function isValid(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        if (signer == address(0)) return false;
        if (signer.code.length > 0) {
            (bool ok, bytes memory ret) =
                signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, digest, signature));
            return ok && ret.length == 32 && abi.decode(ret, (bytes4)) == _MAGIC;
        }
        if (signature.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (uint256(s) > _HALF_N) return false;
        if (v != 27 && v != 28) return false;
        address recovered = ecrecover(digest, v, r, s);
        return recovered != address(0) && recovered == signer;
    }
}
