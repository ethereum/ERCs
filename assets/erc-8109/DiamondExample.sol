// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33;

/**
 * @title Example implementation of a diamond for ERC-8109 Diamonds, Simplified
 *
 * @author Nick Mudge <nick@perfectabstractions.com>, X/Github/Telegram: @mudgen
 */
contract Diamond {

    /**
     * @notice Thrown when a non-owner attempts an action restricted to owner.
     */
    error OwnerUnauthorizedAccount();

    bytes32 constant OWNER_STORAGE_POSITION = keccak256("erc8109.owner");

    /**
     * @notice Storage for owner of the diamond.
     *
     * @custom:storage-location erc8042:erc8109.owner
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

     bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("erc8109.diamond");

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
     * @custom:storage-location erc8042:erc8109.diamond
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
    
    error NoBytecodeAtAddress(address _contractAddress, string _message);
    error NoSelectorsProvidedForFacet(address _facet);
    error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
    
    struct FacetFunctions {
        address facet;
        bytes4[] selectors;
    }      

    /**
     * @notice Diamond constructor adds external functions to the diamond 
     *         and initializes storage variables.
     *
     * @dev The `facetAddress` and `functionFacetPairs` functions must be
     *      added. Other external functions should be added.
     *   
     *      Other parameters can be added to this constructor.
     *      Other storage variables can be initialized in this
     *      constructor.
     *
     *      This constructor is just an example. You can add to it with
     *      your own initialization.
     *
     * @param _addFunctions Selectors to add, grouped by facet.
     * @param _owner        Owner of the diamond, used for authentication.
     */
    constructor(FacetFunctions[] memory _addFunctions, address _owner) {
        DiamondStorage storage s = getDiamondStorage();

        // Adding functions
        for(uint256 i; i < _addFunctions.length; i++) {
            address facet = _addFunctions[i].facet;
            bytes4[] memory functionSelectors = _addFunctions[i].selectors;
            if (facet.code.length == 0) {
                revert NoBytecodeAtAddress(facet, "Diamond constructor: Add facet has no code");
            }
            if(functionSelectors.length == 0) {
                revert NoSelectorsProvidedForFacet(facet);
            }
            uint32 selectorPosition = uint32(s.selectors.length);
            for (uint256 selectorIndex; selectorIndex < functionSelectors.length; selectorIndex++) {
                bytes4 selector = functionSelectors[selectorIndex];
                address oldFacet = s.facetAndPosition[selector].facet;
                if (oldFacet != address(0)) {
                    revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
                }
                s.facetAndPosition[selector] = FacetAndPosition(facet, selectorPosition);
                s.selectors.push(selector);
                selectorPosition++;
                emit DiamondFunctionAdded(selector, facet);
            }
        }

        getOwnerStorage().owner = _owner;

        // Other storage variables can be initialized here:
        // ...
        // ...
        // ...

        // Optionally you can emit metadata.
        // emit DiamondMetadata(tag, data)
    }

    error FunctionNotFound(bytes4 _selector);

    /**
     * @notice 1. Finds facet associated with msg.sig
     *         2. Executes function call on facet using delegatecall.
     *         3. Returns function call return data or revert data.
     */
    fallback() external payable {
        DiamondStorage storage s = getDiamondStorage();
        // Get facet from function selector
        address facet = s.facetAndPosition[msg.sig].facet;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }
        // Execute external function on facet using delegatecall and return any value.
        assembly {
            // Copy function selector and any arguments from calldata to memory.
            calldatacopy(0, 0, calldatasize())
            // Execute function call using the facet.
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // Copy all return data from the previous call into memory.
            returndatacopy(0, 0, returndatasize())
            // Return any return value or error back to the caller.
            switch result
            case 0 {revert(0, returndatasize())}
            default {return (0, returndatasize())}
        }
    }
    
    receive() external payable {}
}