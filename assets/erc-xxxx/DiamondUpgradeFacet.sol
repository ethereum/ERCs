
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33;

/**
 * @title Reference implementation for upgrade function for
 *        ERC-XXXX Diamonds, Simplified
 *
 * @author Nick Mudge <nick@perfectabstractions.com>, X/Github/Telegram: @mudgen
 *
 * @dev Compile this with the Solidity optimizer enabled or 
 *      you may get a "stack too deep" error.
 */
contract DiamondUpgradeFacet {
    /**
     * @notice Thrown when a non-owner attempts an action restricted to owner.
     */
    error OwnerUnauthorizedAccount();

    bytes32 constant OWNER_STORAGE_POSITION = keccak256("ercXXXX.owner");

    /**
     * @custom:storage-location erc8042:ercXXXX.owner
     */
    struct OwnerStorage {
        address owner;
    }

    /**
     * @notice Returns a pointer to the owner storage struct.
     * @dev Uses inline assembly to access the storage slot defined by STORAGE_POSITION.
     * @return s The OwnerStorage struct in storage.
     */
    function getOwnerStorage() internal pure returns (OwnerStorage storage s) {
        bytes32 position = OWNER_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
    
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("ercXXXX.diamond");

    /**
     * @notice Data stored for each function selector
     * @dev Facet address of function selector
     *      Position of selector in the 'bytes4[] selectors' array
     */
    struct FacetAndPosition {
        address facet;
        uint32 position;
    }

    /**
     * @custom:storage-location erc8042:ercXXXX.diamond
     */
    struct DiamondStorage {
        mapping(bytes4 functionSelector => FacetAndPosition) facetAndPosition;
        /**
         * Array of all function selectors that can be called in the diamond
         */
        bytes4[] selectors;
    }

    function getDiamondStorage() internal pure returns (DiamondStorage storage s) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /**
    * @notice Emitted when a function is added to a diamond.
    *
    * @param _selector The function selector being added.
    * @param _facet    The facet address that will handle calls to `_selector`.
    */
    event DiamondFunctionAdded(bytes4 indexed _selector, address indexed _facet);

    /**
    * @notice Emitted when changing the facet that will handle calls to a function.
    * 
    * @param _selector The function selector being affected.
    * @param _oldFacet The facet address previously responsible for `_selector`.
    * @param _newFacet The facet address that will now handle calls to `_selector`.
    */
    event DiamondFunctionReplaced(
        bytes4 indexed _selector,
        address indexed _oldFacet,
        address indexed _newFacet
    );

    /**
    * @notice Emitted when a function is removed from a diamond.
    *
    * @param _selector The function selector being removed.
    * @param _oldFacet The facet address that previously handled `_selector`.
    */
    event DiamondFunctionRemoved(
        bytes4 indexed _selector, 
        address indexed _oldFacet
    );

    /**
    * @notice Emitted when a diamond's constructor function or function from a
    *         facet makes a `delegatecall`. This event is optional.
    * 
    * @param _contract     The contract address where the function is.
    * @param _functionCall The function call, including function selector and 
    *                      any arguments.
    */
    event DiamondDelegateCall(address indexed _contract, bytes _functionCall);

    /**
    * @notice Emitted to record information about a diamond.
    * @dev    This event is optional and records any arbitrary metadata. 
    *         The format of `_tag` and `_data` are not specified by the 
    *         standard.
    *
    * @param _tag   Arbitrary metadata, such as a release version.
    * @param _data  Arbitrary metadata.
    */
    event DiamondMetadata(bytes32 indexed _tag, bytes _data);

    /**
    * @notice The functions below detect and revert with the following errors.
    */
    error NoSelectorsProvidedForFacet(address _facet);
    error NoBytecodeAtAddress(address _contractAddress, string _message);
    error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
    error CannotReplaceFunctionThatDoesNotExist(bytes4 _selector);
    error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
    error CannotReplaceFunctionWithTheSameFacet(bytes4 _selector);
    error InitializationFunctionReverted(address _init, bytes _functionCall);

    function addFunctions(address _facet, bytes4[] calldata _functionSelectors) internal {
        DiamondStorage storage s = getDiamondStorage();
        if (_facet.code.length == 0) {
            revert NoBytecodeAtAddress(_facet, "DiamondUpgradeFacet: Add facet has no code");
        }
        if( _functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacet(_facet);
        }
        uint32 selectorPosition = uint32(s.selectors.length);
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacet = s.facetAndPosition[selector].facet;
            if (oldFacet != address(0)) {
                revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
            }
            s.facetAndPosition[selector] = FacetAndPosition(_facet, selectorPosition);
            s.selectors.push(selector);
            selectorPosition++;
            emit DiamondFunctionAdded(selector, _facet);
        }
    }

    function replaceFunctions(address _facet, bytes4[] calldata _functionSelectors) internal {
        DiamondStorage storage s = getDiamondStorage();
        if (_facet.code.length == 0) {
            revert NoBytecodeAtAddress(_facet, "DiamondUpgradeFacet: Replace facet has no code");
        }
        if( _functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacet(_facet);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacet = s.facetAndPosition[selector].facet;
            if (oldFacet == _facet) {
                revert CannotReplaceFunctionWithTheSameFacet(selector);
            }
            if (oldFacet == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExist(selector);
            }
            /**
             * replace old facet address
             */
            s.facetAndPosition[selector].facet = _facet;
            emit DiamondFunctionReplaced(selector, oldFacet, _facet);
        }
    }

    function removeFunctions(bytes4[] calldata _functionSelectors) internal {
        DiamondStorage storage s = getDiamondStorage();
        uint256 selectorCount = s.selectors.length;
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            FacetAndPosition memory oldFacetAndPosition = s.facetAndPosition[selector];
            address oldFacet = oldFacetAndPosition.facet;
            if (oldFacet == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }
            /**
             * replace selector with last selector
             */
            selectorCount--;
            if (oldFacetAndPosition.position != selectorCount) {
                bytes4 lastSelector = s.selectors[selectorCount];
                s.selectors[oldFacetAndPosition.position] = lastSelector;
                s.facetAndPosition[lastSelector].position = oldFacetAndPosition.position;
            }
            /**
             * delete last selector
             */
            s.selectors.pop();
            delete s.facetAndPosition[selector];
            emit DiamondFunctionRemoved(selector, oldFacet);
        }
    }            
    
    struct FacetFunctions {
        address facet;
        bytes4[] selectors;
    }  

    /**
    * @notice Upgrade the diamond by adding, replacing, or removing functions.
    *
    * @dev
    * - `_addFunctions` maps new selectors to their facet implementations.
    * - `_replaceFunctions` updates existing selectors to new facet addresses.
    * - `_removeFunctions` removes selectors from the diamond.
    *
    * Functions are first added, then replaced, then removed.
    *
    * `delegatecall` is made to `_init` with `_functionCall` for initialization.
    * The `DiamondStateModified` event is emitted.
    * However, if `_init` is zero, no `delegatecall` is made and no 
    * `DiamondStateModified` event is emitted.
    *
    * If _tag is none zero or if _metadata size is greater than zero then the
    * `DiamondMetadata` event is emitted with that data.
    *
    * All the parameters of this function are optional.
    *
    * @param _addFunctions     Selectors to add, grouped by facet.
    * @param _replaceFunctions Selectors to replace, grouped by facet.
    * @param _removeFunctions  Selectors to remove.
    * @param _init             Optional initialization contract (zero to skip).
    * @param _functionCall     Optional function call for the initialization.
    * @param _tag              Optional arbitrary metadata, such as release version.
    * @param _metadata         Optional arbitrary data.
    */
    function upgradeDiamond(
        FacetFunctions[] calldata _addFunctions,
        FacetFunctions[] calldata _replaceFunctions,
        bytes4[] calldata _removeFunctions,           
        address _init,
        bytes calldata _functionCall,
        bytes32 _tag,
        bytes calldata _metadata
    ) external {
        if (getOwnerStorage().owner != msg.sender) {
            revert OwnerUnauthorizedAccount();
        }
        for(uint256 i; i < _addFunctions.length; i++) {
            addFunctions(_addFunctions[i].facet, _addFunctions[i].selectors);
        }
        for(uint256 i; i < _replaceFunctions.length; i++) {
            replaceFunctions(_replaceFunctions[i].facet, _replaceFunctions[i].selectors);
        }
        removeFunctions(_removeFunctions);  
        if(_init != address(0)) {
            if (_init.code.length == 0) {
                revert NoBytecodeAtAddress(_init, "DiamondUpgradeFacet: _init address no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_functionCall);
            if (!success) {
                if (error.length > 0) {
                    /*
                    * bubble up error
                    */
                    assembly ("memory-safe") {
                        revert(add(error, 0x20), mload(error))
                    }
                } else {
                    revert InitializationFunctionReverted(_init, _functionCall);
                }
            }
            emit DiamondDelegateCall(_init, _functionCall);
        }
        if(_tag != 0 || _metadata.length > 0) {
            emit DiamondMetadata(_tag, _metadata);
        }             
    }
}