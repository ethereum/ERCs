// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Helper} from "./utils/Helper.sol";

import {Proxy} from "../src/Proxy.sol";
import {Dictionary} from "../src/Dictionary.sol";

/**
 *  @title A test to verify that the Proxy Contract meets the specifications of the ERC-7546 standard.
 *
 *  Proxy Specs
 *    (1) Dictionary Contract address
 *      (1-1) SHOULD be stored in the storage slot `0x267691be3525af8a813d30db0c9e2bad08f63baecf6dceb85e2cf3676cff56f4`,
 *        (1-1-1) obtained as `bytes32(uint256(keccak256('erc7546.proxy.dictionary')) - 1)`
 *      (1-2) SHOULD emit events `event DictionaryUpgraded(address dictionary)`
 *            when the dictionary address changed
 *    For every invocation made via
 *    (2) `CALL`
 *    (3) `STATICCALL`
 *      (2&3-1) MUST call the Dictionary Contract `getImplementation(bytes4 functionSelector)`
 *              to retrieve the Function Contract address corresponding to its calldata
 *      (2&3-2) MUST perform a delegatecall to the Function Contract address
 */
contract ProxySpecTest is Test, Proxy {
    address internal proxy = address(this);
    constructor() Proxy(address(this), "") {}
    /// @dev Calls that normally would be handled by the receive function, having a value but no data, are also forwarded


    /**------------------------------------
        (1) Dictionary Contract address
    --------------------------------------*/
    //  (1.1) Positive
    function test_storeDictionaryAddr_Success_StoreInCorrectSlot() public {
        address dictionaryAddr = Helper.bytes32ToAddress(vm.load(address(this), Proxy.DICTIONARY_SLOT));
        assertEq(dictionaryAddr, address(this));
    }

    //  (1.1.1) Positive
    function test_SlotIsObtainedAsERC1967Style() public {
        bytes32 slot = DICTIONARY_SLOT;
        assertEq(slot, 0x267691be3525af8a813d30db0c9e2bad08f63baecf6dceb85e2cf3676cff56f4);
        assertEq(slot, bytes32(uint256(keccak256('erc7546.proxy.dictionary')) - 1));
    }

    //  (1.2) Positive
    /// @dev The function _upgradeDictionaryToAndCall is solely responsible for changing the dictionary address.
    function test_upgradeDictionaryAndCall_Success_EmitCorrectEvent(address _fuzz_dictionary) public {
        vm.expectEmit();
        emit DictionaryUpgraded(_fuzz_dictionary);
        _upgradeDictionaryToAndCall(_fuzz_dictionary, "");
    }


    /**-------------------------------------------------
        (2&3-1) Call To Dictionary GetImplementation
    ---------------------------------------------------*/
    function _expectCallDictionaryGetImplementation(address _fuzz_dictionary, bytes calldata _fuzz_data) internal {
        Helper.assumeNotReserved(_fuzz_dictionary);
        vm.store(address(this), DICTIONARY_SLOT, Helper.addressToBytes32(_fuzz_dictionary));
        vm.expectCall(_fuzz_dictionary, abi.encodeCall(Dictionary.getImplementation, bytes4(_fuzz_data)));
    }

    //  (2-1) CALL Positive
    function test_CALL_Success_CallDictionaryGetImplementation(address _fuzz_dictionary, bytes calldata _fuzz_data, uint256 _fuzz_value) public {
        _expectCallDictionaryGetImplementation(_fuzz_dictionary, _fuzz_data);
        vm.deal(proxy, _fuzz_value);
        proxy.call{value: _fuzz_value}(_fuzz_data);
    }

    //  (3-1) STATICCALL Positive
    function test_STATICCALL_Success_CallDictionaryGetImplementation(address _fuzz_dictionary, bytes calldata _fuzz_data) public {
        _expectCallDictionaryGetImplementation(_fuzz_dictionary, _fuzz_data);
        proxy.staticcall(_fuzz_data);
    }


    /**-----------------------------------------------------------------
        (2&3-2) Delegatecall To the Function Implementation Contract
    -------------------------------------------------------------------*/
    function _expectDelegatecallToImplementation(address dictionary, address implementation, bytes memory data) internal {
        vm.assume(dictionary != implementation);

        Helper.assumeNotReserved(dictionary);
        vm.store(address(this), DICTIONARY_SLOT, Helper.addressToBytes32(dictionary));
        vm.mockCall(dictionary, abi.encodeCall(Dictionary.getImplementation, bytes4(data)), abi.encode(implementation));

        Helper.assumeNotReserved(implementation);
        vm.assume(data.length >= 4);
        vm.expectCall(implementation, data);
    }

    //  (2-2) CALL Positive
    function test_CALL_Success_DelegatecallToImplementation(address _fuzz_dictionary, address _fuzz_implementation, bytes calldata _fuzz_data, uint256 _fuzz_value) public {
        _expectDelegatecallToImplementation(_fuzz_dictionary, _fuzz_implementation, _fuzz_data);
        vm.deal(proxy, _fuzz_value);
        proxy.call{value: _fuzz_value}(_fuzz_data);
    }

    //  (3-2) STATICCALL Positive
    function test_STATICCALL_Success_DelegatecallToImplementation(address _fuzz_dictionary, address _fuzz_implementation, bytes calldata _fuzz_data) public {
        _expectDelegatecallToImplementation(_fuzz_dictionary, _fuzz_implementation, _fuzz_data);
        proxy.staticcall(_fuzz_data);
    }
}
