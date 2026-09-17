// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Mandate} from "../src/MandateTypes.sol";
import {MandateHash} from "../src/MandateHash.sol";

contract HashHarness {
    function domainSeparator(address registry) external view returns (bytes32) {
        return MandateHash.domainSeparator(block.chainid, registry);
    }

    function hashStruct(Mandate calldata mandate) external pure returns (bytes32) {
        return MandateHash.hashStruct(mandate);
    }

    function digest(uint256 chainId, address registry, Mandate calldata mandate) external pure returns (bytes32) {
        return MandateHash.digest(chainId, registry, mandate);
    }
}
