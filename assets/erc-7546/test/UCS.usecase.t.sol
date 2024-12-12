// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {Helper} from "./utils/Helper.sol";

import {Dictionary} from "../src/Dictionary.sol";
import {Proxy} from "../src/Proxy.sol";


/**
    @title A test to verify that the UCS Contracts meet the specifications of the ERC-7546 standard.
 */
contract UCSTest is Test {
    address internal dictionary = address(new Dictionary(address(this)));
    address internal proxy = address(new Proxy(address(dictionary), ""));
    address internal setNumber = address(new SetNumber());
    address internal increment = address(new Increment());

    // Examples of use cases for UCS
    function test_Success_SetNumber_Increment() public {
        Dictionary(dictionary).setImplementation(SetNumber.setNumber.selector, setNumber);
        Dictionary(dictionary).setImplementation(Increment.increment.selector, increment);

        SetNumber(proxy).setNumber(1);
        assertEq(uint256(vm.load(proxy, Storage.NUMBER_LOCATION)), 1);

        Increment(proxy).increment();
        assertEq(uint256(vm.load(proxy, Storage.NUMBER_LOCATION)), 2);
    }

}


/**--------------------------------------
    Function Implementation Contracts
----------------------------------------*/
contract SetNumber {
    function setNumber(uint256 newNumber) external {
        Storage.$Number().number = newNumber;
    }
}

contract Increment {
    function increment() external {
        Storage.$Number().number++;
    }

}

/// @dev A storage layout library that complies with ERC-7201
library Storage {
    /// @custom:storage-location erc7201:ucs.number
    struct Number {
        uint256 number;
    }

    bytes32 internal constant NUMBER_LOCATION = 0x195bfe4afb41e751f04052ceae97d1c65636c4235a909f5215b550e46ae35500;
    function $Number() internal pure returns(Number storage ref) {
        assembly { ref.slot := NUMBER_LOCATION }
    }
}
