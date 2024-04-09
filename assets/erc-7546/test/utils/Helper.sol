// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

import {Vm} from "forge-std/Vm.sol";
import {Dummy} from "./Dummy.sol";

Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

library Helper {
    function isReserved(address addr) internal pure returns(bool) {
        return
            addr == address(1) ||
            addr == address(2) ||
            addr == address(3) ||
            addr == address(4) ||
            addr == address(5) ||
            addr == address(6) ||
            addr == address(7) ||
            addr == address(8) ||
            addr == address(9) ||
            addr == 0x4e59b44847b379578588920cA78FbF26c0B4956C ||
            addr == 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D ||
            addr == 0x000000000000000000636F6e736F6c652e6c6f67;
    }

    function assumeNotReserved(address addr) internal pure {
        vm.assume(!isReserved(addr));
    }

    function assertContract(address addr) internal {
        assumeNotReserved(addr);
        if (addr.code.length == 0) {
            vm.etch(addr, type(Dummy).runtimeCode);
        }
    }

    function assumeUnique(bytes4[] calldata selectors) internal pure {
        bool isNotUnique;
        for (uint i; i < selectors.length; ++i) {
            for (uint j = i + 1; j < selectors.length; ++j) {
                if (selectors[i] == selectors[j]) {
                    isNotUnique = true;
                }
            }
        }
        vm.assume(!isNotUnique);
    }

    function bytes32ToAddress(bytes32 value) internal pure returns(address) {
        return address(uint160(uint256(value)));
    }

    function addressToBytes32(address value) internal pure returns(bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
