// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC8512Lib
/// @notice Pure helpers for ERC-8512 device keys, statement Merkle roots, and EIP-712 digests.
library ERC8512Lib {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant STATEMENT_TYPEHASH = keccak256("Statement(bytes32 statementId)");
    bytes32 internal constant NAME_HASH = keccak256("GPU Collateral Evidence");
    bytes32 internal constant VERSION_HASH = keccak256("1");

    error UnsortedOrDuplicateStatementIds();

    /// @notice Derive an ERC-8512 device key.
    function deviceKey(uint16 pciVendorId, uint8 idType, bytes memory idBytes) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("ERC8512.device", pciVendorId, idType, idBytes));
    }

    /// @notice Hash a statement identifier into a Merkle leaf.
    function statementLeaf(bytes32 statementId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x00), statementId));
    }

    /// @notice Hash two sibling Merkle nodes into a parent node.
    function hashPair(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x01), left, right));
    }

    /// @notice Compute the ERC-8512 statement Merkle root over strictly ascending statement identifiers.
    /// @dev Returns bytes32(0) for an empty array; reverts if not strictly ascending.
    function statementRoot(bytes32[] memory sortedIds) internal pure returns (bytes32) {
        uint256 len = sortedIds.length;
        if (len == 0) return bytes32(0);

        bytes32[] memory level = new bytes32[](len);
        for (uint256 i = 0; i < len; ++i) {
            if (i > 0 && sortedIds[i] <= sortedIds[i - 1]) {
                revert UnsortedOrDuplicateStatementIds();
            }
            level[i] = statementLeaf(sortedIds[i]);
        }

        while (len > 1) {
            uint256 pairs = len / 2;
            for (uint256 i = 0; i < pairs; ++i) {
                level[i] = hashPair(level[2 * i], level[2 * i + 1]);
            }
            uint256 nextLen = pairs;
            if (len % 2 == 1) {
                level[nextLen] = level[len - 1];
                nextLen += 1;
            }
            len = nextLen;
        }

        return level[0];
    }

    /// @notice Compute the ERC-8512 EIP-712 domain separator.
    function domainSeparator(uint256 chainId, address registry) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, registry));
    }

    /// @notice Compute the ERC-8512 EIP-712 digest for Statement(bytes32 statementId).
    function statementDigest(uint256 chainId, address registry, bytes32 statementId) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(STATEMENT_TYPEHASH, statementId));
        return keccak256(abi.encodePacked(bytes2(0x1901), domainSeparator(chainId, registry), structHash));
    }
}
