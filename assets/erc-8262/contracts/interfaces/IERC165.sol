// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title IERC165 -- Standard interface detection (EIP-165)
/// @dev Vendored to avoid a dependency on OpenZeppelin for a single 4-byte selector.
interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in EIP-165
    /// @return True if the contract implements `interfaceId` and `interfaceId` is not 0xffffffff
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
