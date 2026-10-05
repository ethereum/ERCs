// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {IERC1271} from "./SpendGrantTypes.sol";

/// @notice The Signatures rules of the ERC, shared by the registry (for the principal over `grantHash`)
/// and by executors that accept delegate-signed authorizations (for the delegate over the authorization
/// digest).
/// @dev No code: a strict 65-byte secp256k1 signature that recovers `signer`. An EIP-7702 delegation
/// designator (exactly 23 bytes, 0xef0100 prefix): strict ECDSA for the account's own key first, then
/// ERC-1271 against the delegated code. Any other code: ERC-1271 only, never an ECDSA fallback. The
/// ERC-1271 call is a STATICCALL and must return exactly the 32-byte left-aligned magic value.
library SpendGrantSignature {
    uint256 internal constant SECP256K1_HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice Whether `sig` is valid for `signer` over `digest` under the Signatures rules.
    function isValid(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        if (signer == address(0)) return false;
        uint256 codeLen = signer.code.length;
        if (codeLen == 0) return recover(digest, sig) == signer;
        if (codeLen == 23 && isDelegationDesignator(signer) && recover(digest, sig) == signer) return true;
        return isValidErc1271(signer, digest, sig);
    }

    /// @notice Strict secp256k1 recovery: 65 bytes `r || s || v`, `v` in {27, 28}, `s` in the lower half.
    /// Returns zero for anything else, so a zero result is never a match.
    function recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28) return address(0);
        if (uint256(s) == 0 || uint256(s) > SECP256K1_HALF_ORDER) return address(0);
        return ecrecover(digest, v, r, s);
    }

    /// @notice ERC-1271 `isValidSignature` over a STATICCALL; valid only on exactly 32 returned bytes equal
    /// to the left-aligned magic value.
    function isValidErc1271(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        (bool ok, bytes memory ret) = signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (digest, sig)));
        if (!ok || ret.length != 32) return false;
        return abi.decode(ret, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
    }

    /// @notice Whether `account`'s code is exactly an EIP-7702 delegation designator.
    /// @dev Callers check `code.length == 23` first so the EXTCODECOPY is paid only when it can matter.
    function isDelegationDesignator(address account) internal view returns (bool) {
        bytes memory code = account.code;
        return code.length == 23 && code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }
}
