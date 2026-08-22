// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Minimal ERC-20 surface, so the asset folder needs no external imports.
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
