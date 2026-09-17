// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {AssetLimit, SpendGrant} from "./MandateTypes.sol";

/// @dev EIP-712 hashing for Portable Spend Grants. encodeType is frozen in the ERC.
library MandateHash {
    // Exact encodeType (no spaces) as specified.
    bytes32 internal constant SPEND_GRANT_TYPEHASH = keccak256(
        "SpendGrant(address principal,address delegate,uint8 recipientMode,address recipient,uint8 assetCombine,uint64 windowSeconds,AssetLimit[] assets,uint64 validAfter,uint64 validUntil,uint256 salt,bytes32 renderingHash)AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)"
    );

    bytes32 internal constant ASSET_LIMIT_TYPEHASH =
        keccak256("AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)");

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant NAME_HASH = keccak256("SpendGrant");
    bytes32 internal constant VERSION_HASH = keccak256("1");

    function domainSeparator(uint256 chainId, address registry) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, registry));
    }

    function hashAssetLimit(AssetLimit memory a) internal pure returns (bytes32) {
        return keccak256(abi.encode(ASSET_LIMIT_TYPEHASH, a.asset, a.maxPerCall, a.maxPerWindow, a.maxTotal));
    }

    /// @dev keccak256 of the concatenation of element struct hashes (no offset or length).
    function hashAssets(AssetLimit[] memory assets) internal pure returns (bytes32) {
        uint256 n = assets.length;
        bytes memory packed = new bytes(n * 32);
        for (uint256 i = 0; i < n; i++) {
            bytes32 elementHash = hashAssetLimit(assets[i]);
            assembly {
                mstore(add(add(packed, 32), mul(i, 32)), elementHash)
            }
        }
        return keccak256(packed);
    }

    function hashStruct(SpendGrant memory m) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SPEND_GRANT_TYPEHASH,
                m.principal,
                m.delegate,
                m.recipientMode,
                m.recipient,
                m.assetCombine,
                m.windowSeconds,
                hashAssets(m.assets),
                m.validAfter,
                m.validUntil,
                m.salt,
                m.renderingHash
            )
        );
    }

    function digest(uint256 chainId, address registry, SpendGrant memory m) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", domainSeparator(chainId, registry), hashStruct(m)));
    }
}
