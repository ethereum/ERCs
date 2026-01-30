// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title IERC5679Ext20 — ERC-5679 mint/burn for ERC-20
/// @notice Standard interface for minting and burning ERC-20 tokens
interface IERC5679Ext20 {
    function mint(address to, uint256 amount, bytes calldata data) external;
    function burn(address from, uint256 amount, bytes calldata data) external;
}

/// @title IERC8063 — Access control introspection for membership tokens
/// @notice Extends ERC-20 + ERC-5679 with permission checks for minting and burning
interface IERC8063 is IERC165 {
    /// @notice Returns true if `operator` is permitted to mint (add members)
    function canMint(address operator) external view returns (bool);

    /// @notice Returns true if `operator` is permitted to burn `from`'s membership
    function canBurn(address operator, address from) external view returns (bool);
}

/// @title IERC8063Aliases — Optional convenience interface
/// @notice Friendly function names wrapping ERC-20 + ERC-5679 operations
interface IERC8063Aliases {
    /// @notice Returns true if `account` is a member (balanceOf >= 1)
    function isMember(address account) external view returns (bool);

    /// @notice Returns current member count (totalSupply)
    function getMemberCount() external view returns (uint256);

    /// @notice Adds `account` as a member — wraps mint(account, 1, "")
    function addMember(address account) external;

    /// @notice Removes `account` from membership — wraps burn(account, 1, "")
    function removeMember(address account) external;

    /// @notice Caller voluntarily leaves — wraps burn(msg.sender, 1, "")
    function leaveGroup() external;

    /// @notice Transfer membership to another address — wraps transfer(to, 1)
    function transferMembership(address to) external;
}
