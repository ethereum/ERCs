// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Helper} from "./utils/Helper.sol";

import {Dictionary} from "../src/Dictionary.sol";

/**
 *  @title A test to verify that the Dictionary Contract meets the specifications of the ERC-7546 standard.
 *
 *  Dictionary Specs
 *    (1) getImplementation(bytes4 functionSelector)
 *          MUST return Function Implementation Contract address.
 *    (2) setImplementation(bytes4 functionSelector, address implementation)
 *      (2-1) SHOULD add new function selectors and their corresponding Function Implementation Contract addresses to the mapping.
 *      (2-2) SHOULD update
 *      (2-3) SHOULD be communicated through an event (or log).
 *    (3) supportsInterface(bytes4 interfaceID) defined in ERC-165
 *          is RECOMMENDED to indicate which interfaces are supported by the contracts referenced in the mapping.
 *    (4) supportsInterfaces()
 *          is RECOMMENDED to return a list of registered interfaceIDs
 */
contract DictionarySpecTest is Test, Dictionary {
    Dictionary internal dictionary = Dictionary(address(this));
    constructor() Dictionary(address(this)) {} /// @dev Set this test contract address as the owner


    /**--------------------------
        (1) getImplementation
    ----------------------------*/
    //  (1) Positive
    function test_getImplementation_Success_ReturnCorrectAddress(bytes4 _fuzz_functionSelector, address _fuzz_implementation) public {
        implementations[_fuzz_functionSelector] = _fuzz_implementation;

        address returnAddress = dictionary.getImplementation(_fuzz_functionSelector);

        assertEq(returnAddress, _fuzz_implementation);
    }

    //  (1) Negative
    function test_getImplementation_Invalid_ReturnZeroAddress(bytes4 _fuzz_set_functionSelector, bytes4 _fuzz_request_functionSelector, address _fuzz_implementation) public {
        implementations[_fuzz_set_functionSelector] = _fuzz_implementation;

        vm.assume(_fuzz_request_functionSelector != _fuzz_set_functionSelector);
        address returnAddress = dictionary.getImplementation(_fuzz_request_functionSelector);

        assertEq(returnAddress, address(0));
    }


    /**--------------------------
        (2) setImplementation
    ----------------------------*/
    function _execute_setImplementation_WithContractAddr(bytes4 functionSelector, address implementation) internal {
        Helper.assertContract(implementation);
        dictionary.setImplementation(functionSelector, implementation);
    }

    //  (2-1) Positive
    function test_setImplementation_Success_AddToMapping(bytes4 _fuzz_functionSelector, address _fuzz_implementation) public {
        _execute_setImplementation_WithContractAddr(_fuzz_functionSelector, _fuzz_implementation);
        assertEq(implementations[_fuzz_functionSelector], _fuzz_implementation);
    }

    //  (2-2) Positive
    function test_setImplementation_Success_UpdateMapping(bytes4 _fuzz_functionSelector, address _fuzz_implementation, address _fuzz_newImplementation) public {
        test_setImplementation_Success_AddToMapping(_fuzz_functionSelector, _fuzz_implementation);
        _execute_setImplementation_WithContractAddr(_fuzz_functionSelector, _fuzz_newImplementation);
        assertEq(implementations[_fuzz_functionSelector], _fuzz_newImplementation);
    }

    //  (2-3) Positive
    function test_setImplementation_Success_EmitCorrectEvent(bytes4 _fuzz_functionSelector, address _fuzz_implementation) public {
        vm.expectEmit();
        emit ImplementationUpgraded(_fuzz_functionSelector, _fuzz_implementation);
        _execute_setImplementation_WithContractAddr(_fuzz_functionSelector, _fuzz_implementation);
    }

    //  (2) Negative
    function test_setImplementation_Revert_InvalidImplementation_WhenNonContract(bytes4 _fuzz_functionSelector, address _fuzz_implementation) public {
        vm.assume(_fuzz_implementation.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(Dictionary.InvalidImplementation.selector, _fuzz_implementation));
        dictionary.setImplementation(_fuzz_functionSelector, _fuzz_implementation);
    }


    /**--------------------------
        (3) supportsInterface
    ----------------------------*/
    //  (3) Positive
    function test_supportsInterface_Success_ReturnTrue(bytes4 _fuzz_functionSelector, address _fuzz_implementation) public {
        vm.assume(_fuzz_implementation != address(0));
        implementations[_fuzz_functionSelector] = _fuzz_implementation;
        assertTrue(dictionary.supportsInterface(_fuzz_functionSelector));
    }

    //  (3) Negative
    function test_supportsInterface_Invalid_ReturnFalse_WhenNotSet(bytes4 _fuzz_functionSelector) public {
        assertFalse(dictionary.supportsInterface(_fuzz_functionSelector));
    }


    /**---------------------------
        (4) supportsInterfaces
    -----------------------------*/
    // (4) Positive
    function test_supportsInterfaces_Success_ReturnCorrectSelectors(bytes4[] calldata _fuzz_functionSelectors) public {
        Helper.assumeUnique(_fuzz_functionSelectors);
        for (uint i; i < _fuzz_functionSelectors.length; ++i) {
            functionSelectorList.push(_fuzz_functionSelectors[i]);
        }

        bytes4[] memory interfaces = dictionary.supportsInterfaces();

        assertEq(
            keccak256(abi.encodePacked(_fuzz_functionSelectors)),
            keccak256(abi.encodePacked(interfaces))
        );
    }

    // (4) Negative
    function test_supportsInterfaces_Invalid_ReturnUnexpectedSelectors(bytes4 _fuzz_inputSelector, bytes4 _fuzz_expectedSelector) public {
        functionSelectorList.push(_fuzz_inputSelector);

        vm.assume(_fuzz_inputSelector != _fuzz_expectedSelector);

        bytes4[] memory interfaces = dictionary.supportsInterfaces();
        bytes4[] memory expectedInterfaces = new bytes4[](1);
        expectedInterfaces[0] = _fuzz_expectedSelector;

        assertNotEq(
            keccak256(abi.encodePacked(expectedInterfaces)),
            keccak256(abi.encodePacked(interfaces))
        );
    }
}
