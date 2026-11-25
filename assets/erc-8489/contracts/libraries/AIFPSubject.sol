// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPSubject
/// @notice Canonical subject references. A subject reference is keccak256 of the UTF-8 bytes of the
///         canonical string `<scheme>:<domain>:<identifier>`:
///
///           eip155-address:<chainId>:<0x + 40 lowercase hex>
///           erc8004:<chainId>:<0x + 40 lowercase hex registry>:<agentId decimal>
///           did:<method>:<method-specific-id as given>
///           ext:<namespace lowercase>:<opaque identifier>
///
///         There is no second encoding: an address is never left-padded into bytes32.
library AIFPSubject {
    bytes16 private constant HEX = "0123456789abcdef";

    function fromCanonical(string memory canonical) internal pure returns (bytes32) {
        return keccak256(bytes(canonical));
    }

    function canonicalAddress(uint256 chainId, address account) internal pure returns (string memory) {
        return string(abi.encodePacked("eip155-address:", toDecimal(chainId), ":", toHexAddress(account)));
    }

    function fromAddress(uint256 chainId, address account) internal pure returns (bytes32) {
        return keccak256(bytes(canonicalAddress(chainId, account)));
    }

    /// @dev Reference of an account on the current chain.
    function self(address account) internal view returns (bytes32) {
        return fromAddress(block.chainid, account);
    }

    function canonicalERC8004(uint256 chainId, address registry, uint256 agentId) internal pure returns (string memory) {
        return string(
            abi.encodePacked("erc8004:", toDecimal(chainId), ":", toHexAddress(registry), ":", toDecimal(agentId))
        );
    }

    function fromERC8004(uint256 chainId, address registry, uint256 agentId) internal pure returns (bytes32) {
        return keccak256(bytes(canonicalERC8004(chainId, registry, agentId)));
    }

    function canonicalDID(string memory method, string memory methodSpecificId) internal pure returns (string memory) {
        return string(abi.encodePacked("did:", method, ":", methodSpecificId));
    }

    function fromDID(string memory method, string memory methodSpecificId) internal pure returns (bytes32) {
        return keccak256(bytes(canonicalDID(method, methodSpecificId)));
    }

    function canonicalExt(string memory namespace_, string memory identifier) internal pure returns (string memory) {
        return string(abi.encodePacked("ext:", namespace_, ":", identifier));
    }

    function fromExt(string memory namespace_, string memory identifier) internal pure returns (bytes32) {
        return keccak256(bytes(canonicalExt(namespace_, identifier)));
    }

    function toDecimal(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexAddress(address account) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        uint160 value = uint160(account);
        for (uint256 i = 41; i > 1; i--) {
            buffer[i] = HEX[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
