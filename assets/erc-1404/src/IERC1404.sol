// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title IERC1404 — Simple Restricted Token Standard (EIP-1404)
interface IERC1404 is IERC20 {
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
