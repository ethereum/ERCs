// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {SpendGrant} from "../src/MandateTypes.sol";
import {MandateHash} from "../src/MandateHash.sol";

contract HashHarness {
    function domainSeparator(address registry) external view returns (bytes32) {
        return MandateHash.domainSeparator(block.chainid, registry);
    }

    function hashStruct(SpendGrant calldata grant) external pure returns (bytes32) {
        return MandateHash.hashStruct(grant);
    }

    function digest(uint256 chainId, address registry, SpendGrant calldata grant) external pure returns (bytes32) {
        return MandateHash.digest(chainId, registry, grant);
    }
}
