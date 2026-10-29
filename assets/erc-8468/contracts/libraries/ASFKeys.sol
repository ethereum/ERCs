// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  ASFKeys — reference derivation of subject and scope keys
/// @notice subjectKey = keccak256(UTF-8(subject reference string)); scopeKey = keccak256(UTF-8(JCS(scope object))).
///         This library derives the two reference strings a consumer can compute on chain without a JSON
///         canonicalizer: the account reference "eip155:<chainId>:<0x + lowercase hex address>" and the
///         canonical form of the one-member scope object {"ref":"<reference>"}.
library ASFKeys {
    bytes16 private constant HEX = "0123456789abcdef";

    /// @notice "eip155:<chainId>:<address>" with the address in lowercase hexadecimal.
    function accountRef(uint256 chainId, address account) internal pure returns (string memory) {
        return string(abi.encodePacked("eip155:", _decimal(chainId), ":", _hex(account)));
    }

    /// @notice keccak256 of the account reference for the current chain.
    function accountSubjectKey(address account) internal view returns (bytes32) {
        return keccak256(bytes(accountRef(block.chainid, account)));
    }

    /// @notice JCS form of {"ref": ref} and its key. Scope objects with more members need an off-chain
    ///         canonicalizer; their keys are computed once and passed in as bytes32.
    function refScopeKey(string memory ref) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked('{"ref":"', ref, '"}'));
    }

    function _hex(address a) private pure returns (string memory) {
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        uint160 v = uint160(a);
        for (uint256 i = 41; i > 1; i--) {
            out[i] = HEX[v & 0xf];
            v >>= 4;
        }
        return string(out);
    }

    function _decimal(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        for (uint256 t = v; t > 0; t /= 10) len++;
        bytes memory out = new bytes(len);
        while (v > 0) {
            out[--len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(out);
    }
}
