// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYASchemeRegistry} from "./interfaces/IKYASchemeRegistry.sol";
import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IKYAPolicyRegistry, IKYAPolicyEvaluator} from "./interfaces/IKYAPolicyRegistry.sol";
import {IKYAVerifier} from "./interfaces/IKYAVerifier.sol";

/// @dev Helper exposing ERC-165 interface ids for the test vectors.
contract InterfaceIds {
    function schemeRegistry() external pure returns (bytes4) { return type(IKYASchemeRegistry).interfaceId; }
    function kyaRegistry() external pure returns (bytes4) { return type(IKYARegistry).interfaceId; }
    function policyRegistry() external pure returns (bytes4) { return type(IKYAPolicyRegistry).interfaceId; }
    function policyEvaluator() external pure returns (bytes4) { return type(IKYAPolicyEvaluator).interfaceId; }
    function verifier() external pure returns (bytes4) { return type(IKYAVerifier).interfaceId; }
}
