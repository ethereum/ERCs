// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

/// @dev OZ Library version has been tested with version 5.0.0.
import {Proxy as OZProxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Dictionary} from "./Dictionary.sol";

/**
    @title Proxy Contract
    @dev This is the reference implementation for ERC-7546 Proxy Contract.
    @dev In this reference implementation, the transfer functionality inherits from the OpenZeppelin contracts.
 */
contract Proxy is OZProxy {
    /*************
        Storage
     *************/
    /**
     * @dev The only storage slot explicitly used within the Proxy Contract is for holding the Dictionary Contract address.
     * @dev This slot is the keccak-256 hash of "erc7546.proxy.dictionary" subtracted by 1.
     */
    bytes32 internal constant DICTIONARY_SLOT = 0x267691be3525af8a813d30db0c9e2bad08f63baecf6dceb85e2cf3676cff56f4;

    constructor(address dictionary, bytes memory _data) payable {
        _upgradeDictionaryToAndCall(dictionary, _data);
    }


    /***********
        Event
     ***********/
    event DictionaryUpgraded(address dictionary);


    /************************
        Internal Functions
     ************************/
    /**
     * @dev In this reference implementation, we use the OZ library to extract storage slot values as addresses.
     */
    function _getDictionary() internal view returns (address) {
        return StorageSlot.getAddressSlot(DICTIONARY_SLOT).value;
    }

    /**
     * @dev Override an internal function that returns the destination address to utilize the forwarding functionality of the OZ contract's Proxy.
     */
    function _implementation() internal view override returns (address) {
        return Dictionary(_getDictionary()).getImplementation(msg.sig);
    }

    function _upgradeDictionaryToAndCall(address newDictionary, bytes memory data) internal {
        /// @dev In this reference implementation, we've omitted it for simplicity,
        ///      but it's recommended to implement a check to ensure the Dictionary Contract is indeed a contract.
        StorageSlot.getAddressSlot(DICTIONARY_SLOT).value = newDictionary;
        emit DictionaryUpgraded(newDictionary);

        /// @dev Similarly, it is recommended to verify that it is non-payable before proceeding with the initialization process,
        ///      though this has been omitted in this case.
        if (data.length > 0) {
            Address.functionDelegateCall(Dictionary(newDictionary).getImplementation(bytes4(data)), data);
        }
    }
}
