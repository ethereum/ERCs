// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IERC5679Ext20 — ERC-5679 mint/burn for ERC-20
/// @notice Standard interface for minting and burning ERC-20 tokens
interface IERC5679Ext20 {
    function mint(address to, uint256 amount, bytes calldata data) external;
    function burn(address from, uint256 amount, bytes calldata data) external;
}

/// @title IERC8063 — Membership token with threshold-based access control
/// @notice Extends ERC-20 + ERC-5679 with membership semantics and access control introspection
interface IERC8063 {
    /// @notice Returns true if `account` holds at least `threshold` tokens
    /// @param account The address to check
    /// @param threshold Minimum balance required for membership at this tier
    function isMember(address account, uint256 threshold) external view returns (bool);

    /// @notice Returns true if `operator` is permitted to mint tokens
    function canMint(address operator) external view returns (bool);

    /// @notice Returns true if `operator` is permitted to burn `from`'s tokens
    function canBurn(address operator, address from) external view returns (bool);
}

/// @notice Optional convenience interface with friendly function names
interface IERC8063Aliases {
    /// @notice Returns current member count (accounts with balance > 0)
    /// @dev This may be expensive to compute; consider tracking separately
    function getMemberCount() external view returns (uint256);

    /// @notice Adds tokens to `account` — wraps mint(account, amount, "")
    function addMember(address account, uint256 amount) external;

    /// @notice Burns caller's tokens — wraps burn(msg.sender, amount, "")
    function leaveGroup(uint256 amount) external;

    /// @notice Burns all of caller's tokens — wraps burn(msg.sender, balanceOf(msg.sender), "")
    function leaveGroupFully() external;
}
