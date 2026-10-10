// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {IERC1271} from "./SpendGrantTypes.sol";

/// @notice The Signatures rules of the ERC, shared by the registry (for the principal over `grantHash`)
/// and by executors that accept delegate-signed authorizations (for the delegate over the authorization
/// digest).
/// @dev No code: a strict 65-byte secp256k1 signature, and the recovered signer is whoever it is. An
/// EIP-7702 delegation designator (exactly 23 bytes, 0xef0100 prefix): the account's own key first, then
/// ERC-1271 against the delegated code. Any other code: ERC-1271 only, never an ECDSA fallback. The
/// ERC-1271 call is a STATICCALL that copies at most one word back, and it must return exactly 32 bytes
/// equal to the left-aligned magic value.
library SpendGrantSignature {
    uint256 internal constant SECP256K1_HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice Whether `sig` authenticates `signer` over `digest` under the Signatures rules.
    function isValid(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        return signer != address(0) && authenticate(signer, digest, sig) == signer;
    }

    /// @notice Who `sig` authenticates over `digest` when `expected` is the party that should have signed:
    /// the recovered signer for an address without code (zero when the signature is malformed), or
    /// `expected` itself when its own EIP-7702 key or its ERC-1271 accepts, else zero. A caller compares
    /// the result with the party it needs, or passes it on to the registry to compare.
    function authenticate(address expected, bytes32 digest, bytes calldata sig) internal view returns (address) {
        uint256 codeLen = expected.code.length;
        if (codeLen == 0) return recover(digest, sig);
        if (codeLen == 23 && isDelegationDesignator(expected) && recover(digest, sig) == expected) return expected;
        return isValidErc1271(expected, digest, sig) ? expected : address(0);
    }

    /// @notice Strict secp256k1 recovery: 65 bytes `r || s || v`, `v` in {27, 28}, `s` in the lower half.
    /// Returns zero for anything else, so a zero result is never a match.
    function recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
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
    /// @dev Only the first word of the return data is copied, into scratch space, so a validator that
    /// returns a huge payload cannot push the caller out of gas and swallow its reason.
    function isValidErc1271(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        bytes memory data = abi.encodeCall(IERC1271.isValidSignature, (digest, sig));
        bool ok;
        uint256 size;
        bytes32 word;
        assembly ("memory-safe") {
            ok := staticcall(gas(), signer, add(data, 32), mload(data), 0, 32)
            size := returndatasize()
            word := mload(0)
        }
        return ok && size == 32 && word == bytes32(IERC1271.isValidSignature.selector);
    }

    /// @notice Whether `account`'s code is exactly an EIP-7702 delegation designator.
    /// @dev Callers check `code.length == 23` first so the EXTCODECOPY is paid only when it can matter.
    function isDelegationDesignator(address account) internal view returns (bool) {
        bytes memory code = account.code;
        return code.length == 23 && code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }
}
