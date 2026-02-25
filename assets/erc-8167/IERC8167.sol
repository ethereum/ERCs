// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.30;

// ERC-8167: Modular Dispatch Proxy
// A modular dispatch proxy MUST use `delegatecall` to relay the entire calldata to the delegate corresponding to the first four bytes of the calldata

// IERC8167 functions SHOULD be implemented by delegates rather than in the proxy
interface IERC8167 {
    // REQUIRED
    // Emitted when assigning a delegate logic module to a selector
    // An address(0) delegate signals removal
    event SetDelegate(bytes4 indexed selector, address indexed delegate);

    // REQUIRED
    // Returns the delegate for the selector, using address(0) for function not found
    function implementation(bytes4 selector) external view returns (address);

    // RECOMMENDED
    // Surfaces the ABI
    // SHOULD return all function selectors with implementations
    function selectors() external view returns (bytes4[] memory);

    // RECOMMENDED
    // If the delegate for that selector is not set, the proxy MUST revert, and SHOULD revert with FunctionNotFound
    error FunctionNotFound(bytes4 selector);
}
