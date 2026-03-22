// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33;

/**
 * @title Reference implementation for introspection functions for
 *        ERC-8109 Diamonds, Simplified
 *
 * @author Nick Mudge <nick@perfectabstractions.com>, X/Github/Telegram: @mudgen
 */
contract DiamondInspectFacet {

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("erc8109.diamond");

    /**
     * @notice Data stored for each function selector.
     *
     * @dev Facet address of function selector.
     *      Position of selector in the 'bytes4[] selectors' array.
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
         * Array of all function selectors that can be called in the diamond.
         */
        bytes4[] selectors;
    }


    /**
     * @notice Retrieves the diamond's storage struct from its fixed position.
     *
     * @dev Uses inline assembly to access the storage slot directly.
     * @return s The `DiamondStorage` struct stored at `DIAMOND_STORAGE_POSITION`.
     */
    function getStorage() internal pure returns (DiamondStorage storage s) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /** @notice Gets the facet that handles the function selector.
     *
     *  @dev If facet is not found return address(0).
     *  @param _functionSelector The function selector.
     *  @return The facet address associated with the function selector.
     */
    function facetAddress(bytes4 _functionSelector) external view returns (address) {
        return getStorage().facetAndPosition[_functionSelector].facet;
    }
    
    struct FunctionFacetPair {
        bytes4 selector;
        address facet;
    }

    /**
     * @notice Returns an array of all function selectors and their corresponding facet addresses.
     *
     * @dev Iterates through the diamond's stored selectors and pairs each with its facet.
     * @return pairs An array of `FunctionFacetPair` structs, each containing a selector and its facet address.
     */
    function functionFacetPairs() external view returns(FunctionFacetPair[] memory pairs) {
        DiamondStorage storage s  = getStorage();
        uint256 length = s.selectors.length;
        pairs = new FunctionFacetPair[](length);
        for(uint i; i < length; i++){
            bytes4 selector = s.selectors[i];
            pairs[i] = FunctionFacetPair(selector, s.facetAndPosition[selector].facet);
        }
    }
}