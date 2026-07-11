// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev An interface for ERC-7641, an ERC-20 extension that integrates a revenue-sharing mechanism, ensuring tokens intrinsically represent a share of a communal revenue pool
 */
interface IERC7641 is IERC20 {
    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return The amount of revenue token claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) external view returns (uint256);

    /**
     * @dev A function for token holder to claim ETH based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id
     */
    function claim(uint256 snapshotId) external;

    /**
     * @dev A function to snapshot the token balance and the claimable revenue token balance
     * @return The snapshot id
     * @notice Should have `require` to avoid ddos attack
     */
    function snapshot() external returns (uint256);

    /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint256 amount) external view returns (uint256);

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(uint256 amount) external;
}
