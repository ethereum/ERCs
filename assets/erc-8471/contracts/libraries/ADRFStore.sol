// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  ADRFStore — storage record of the dispute registry, shared with its modules (see ADRFStorage)
library ADRFStore {
    struct Data {
        uint256 nonce;
        mapping(bytes32 => T.Binding) bindings;
        mapping(bytes32 => mapping(bytes32 => bool)) authorizedEffect;
        mapping(bytes32 => mapping(address => bool)) executor;
        mapping(bytes32 => mapping(address => bool)) beneficiary;
        mapping(bytes32 => T.CaseHeader) cases;
        mapping(bytes32 => T.CaseClock) clocks;
        mapping(bytes32 => T.SubQuestion[]) subs;
        mapping(bytes32 => mapping(uint32 => T.Finding)) findings;
        mapping(bytes32 => mapping(uint32 => T.RoundRecord)) rounds;
        mapping(bytes32 => T.Ruling) rulings;
        mapping(bytes32 => mapping(bytes32 => T.Enactment)) enactments;
        mapping(bytes32 => bytes32) activeCase;
        mapping(bytes32 => bytes32) finalCase;
    }

    function newId(Data storage s) internal returns (bytes32) {
        s.nonce += 1;
        return keccak256(abi.encode(block.chainid, address(this), s.nonce));
    }

    function now64() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    function exclusivityKey(address source, bytes32 obligationRef, bytes32 proposition) internal pure returns (bytes32) {
        return keccak256(abi.encode(source, obligationRef, proposition));
    }

    function objectKey(T.ObjectRef memory object) internal pure returns (bytes32) {
        return keccak256(abi.encode(object));
    }

    function supportsIface(address target, bytes4 interfaceId) internal view returns (bool) {
        if (target.code.length == 0) return false;
        (bool ok, bytes memory ret) = target.staticcall{gas: 30_000}(abi.encodeWithSelector(0x01ffc9a7, interfaceId));
        return ok && ret.length >= 32 && abi.decode(ret, (bool));
    }
}
