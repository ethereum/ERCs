// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IERC165
/// @notice Minimal, dependency-free ERC-165 interface (EIP-165).
/// @dev    Declared locally so the canonical ERC surface compiles with no
///         external dependencies. Semantically identical to the OpenZeppelin
///         and reference EIP-165 declarations; the interface id is the same
///         (`0x01ffc9a7`).
interface IERC165 {
    /// @notice Query whether the contract implements an interface.
    /// @param  interfaceId The interface identifier, per ERC-165.
    /// @return True iff the contract implements `interfaceId` and
    ///         `interfaceId != 0xffffffff`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

