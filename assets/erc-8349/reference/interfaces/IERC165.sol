// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ERC-165 Interface Detection Standard
/// @notice Interface for the ERC-165 standard.
/// @dev The interface identifier is `0x01ffc9a7`.
interface IERC165 {
    /// @notice Returns whether the contract implements an interface.
    /// @param interfaceId ERC-165 interface identifier.
    /// @return `true` if the contract implements `interfaceID` and
    ///  `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}