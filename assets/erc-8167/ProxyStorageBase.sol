// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.30;

contract ProxyStorageBase {
    struct SelectorInfo {
        address delegate;
        uint96 index;
    }

    struct ProxyAdminStorage {
        mapping(bytes4 selector => SelectorInfo info) selectorInfo;
        bytes4[] selectors;
    }

    function adminStorage() internal pure returns (ProxyAdminStorage storage sudo) {
        // 0xf3435b31e1c1e77c1a
        uint256 s = uint72(bytes9(keccak256("erc8167.admin.delegates")));
        assembly ("memory-safe") {
            sudo.slot := s
        }
    }
}
