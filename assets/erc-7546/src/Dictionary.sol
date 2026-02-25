// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.22;

/// @dev OZ Library version has been tested with version 5.0.0.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
    @title Dictionary Contract
    @dev This is the reference implementation for ERC-7546 Dictionary Contract.
 */
contract Dictionary is Ownable, IERC165 {
    /**********************
        Storage & Event
     **********************/
    mapping(bytes4 functionSelector => address implementation) implementations; // MUST
    event ImplementationUpgraded(bytes4 functionSelector, address implementation); // SHOULD
    error InvalidImplementation(address implementation); // OPTIONAL
    bytes4[] functionSelectorList; // RECOMMENDED

    constructor(address owner) Ownable(owner) {}


    /***************
        Functions
     ***************/
    function getImplementation(bytes4 functionSelector) external view returns(address implementation) {
        implementation = implementations[functionSelector];
    }

    function setImplementation(bytes4 functionSelector, address implementation) external onlyOwner {
        /// @notice Mismatch Function Selector in Security Considerations section
        if (implementation.code.length == 0) {
            revert InvalidImplementation(implementation);
        }

        // In the case of a new functionSelector, add to the functionSelectorList.
        bool _hasSetFunctionSelector;
        bytes4[] memory _functionSelectorList = functionSelectorList;
        for (uint i; i < _functionSelectorList.length; ++i) {
            if (functionSelector == _functionSelectorList[i]) {
                _hasSetFunctionSelector = true;
            }
        }
        if (!_hasSetFunctionSelector) functionSelectorList.push(functionSelector);

        // Add the pair of functionSelector and implementation address to the mapping.
        implementations[functionSelector] = implementation;

        // Notify the change of the mapping.
        emit ImplementationUpgraded(functionSelector, implementation);
    }

    /// @dev The interfaceId equals to the function selector
    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return implementations[interfaceId] != address(0);
    }

    function supportsInterfaces() external view returns (bytes4[] memory) {
        return functionSelectorList;
    }

}
