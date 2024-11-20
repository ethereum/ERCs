// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-7818: Expirable ERC20
 * @dev Interface for creating expirable ERC20 tokens.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC7818 is IERC20 {
    /**
     * @dev Retrieves the balance of a specific `identifier` owned by an account.
     * @param account The address of the account.
     * @param identifier The Identifier "MAY" represents an epoch, round, period, or token identifier.
     * @return uint256 The balance of the specified `identifier`.
     * @notice `identifier` "MUST" represent a unique identifier, and its meaning "SHOULD"
     * align with how contract maintain the `epoch` in the implementing contract.
     */
    function balanceOf(
        address account,
        uint256 identifier
    ) external view returns (uint256);

    /**
     * @dev Retrieves the current epoch of the contract.
     * @return uint256 The current epoch of the token contract,
     * often used for determining active/expired states.
     */
    function epoch() external view returns (uint256);

    /**
     * @dev Retrieves the duration a token remains valid.
     * @return uint256 The validity duration.
     * @notice `duration` "MUST" specify the token's validity period.
     * The implementing contract "SHOULD" clearly document,
     * whether the unit is blocks or time in seconds.
     */
    function duration() external view returns (uint256);

    /**
     * @dev Checks whether a specific `identifier` is expired.
     * @param identifier The Identifier "MAY" represents an epoch, round, period, or token identifier.
     * @return bool True if the token is expired, false otherwise.
     * @notice Implementing contracts "MUST" define the logic for determining expiration,
     * typically by comparing the current `epoch()` with the given `identifier`.
     */
    function expired(uint256 identifier) external view returns (bool);

    /**
     * @dev Transfers a specific `identifier` and value to a recipient.
     * @param to The recipient address.
     * @param identifier The Identifier "MAY" represents an epoch, round, period, or token identifier.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, false or reverted if give `identifier` it's expired.
     * @notice The transfer "MUST" revert if the token `identifier` is expired.
     */
    function transfer(
        address to,
        uint256 identifier,
        uint256 value
    ) external returns (bool);

    /**
     * @dev Transfers a specific `identifier` and value from one account to another.
     * @param from The sender's address.
     * @param to The recipient's address.
     * @param identifier The Identifier "MAY" represents an epoch, round, period, or token identifier.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, false or reverted if give `identifier` it's expired.
     * @notice The transfer "MUST" revert if the token `identifier` is expired.
     */
    function transferFrom(
        address from,
        address to,
        uint256 identifier,
        uint256 value
    ) external returns (bool);
}
