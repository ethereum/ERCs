// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IERC1404Restriction — token-agnostic ERC-1404 restriction interface.
///
/// @notice The two ERC-1404 restriction functions, extracted from `IERC20`.
///
/// A contract implementing *only* this interface is a standalone compliance /
/// rule engine: it answers "is this transfer allowed?" and never itself moves
/// or holds tokens. A token (ERC-20, ERC-777, …) consults it inside its
/// transfer path. See `EXAMPLE_ERC_1404.md`.
interface IERC1404Restriction {
    /// @notice Returns a restriction code for a proposed transfer, or 0 if unrestricted.
    /// @param from  Sender address.
    /// @param to    Recipient address.
    /// @param value Token amount to transfer.
    /// @return      Restriction code; 0 means the transfer is allowed.
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);

    /// @notice Returns the human-readable message corresponding to a restriction code.
    /// @param restrictionCode  Code returned by `detectTransferRestriction`.
    /// @return                 Human-readable description of the restriction.
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
}
