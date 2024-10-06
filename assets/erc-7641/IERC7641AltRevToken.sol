// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC7641.sol";

/**
 * @dev An optional extension of the ERC-7641 standard that accepts other ERC-20 revenue tokens into the contract with corresponding claim function
 */
interface IERC7641AltRevToken is IERC7641 {
    /**
     * @dev A function to calculate the amount of ERC-20 claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @param token The address of the revenue token
     * @return The amount of revenue token claimable
     */
    function claimableERC20(address account, uint256 snapshotId, address token) external view returns (uint256);

    /**
     * @dev A function to calculate the amount of ERC-20 redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @param token The address of the revenue token
     * @return The amount of revenue token redeemable
     */
    function redeemableERC20OnBurn(uint256 amount, address token) external view returns (uint256);
}