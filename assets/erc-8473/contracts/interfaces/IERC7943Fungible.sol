// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev Copied verbatim from ERC-7943 (Final), fungible variant.
interface IERC7943Fungible is IERC165 {
    /// @notice Emitted when tokens are taken from one address and transferred to another.
    /// @param from The address from which tokens were taken.
    /// @param to The address to which seized tokens were transferred.
    /// @param amount The amount seized.
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when `setFrozenTokens` is called, changing the frozen `amount` of tokens for `account`.
    /// @param account The address of the account whose tokens are being frozen.
    /// @param amount The amount of tokens frozen after the change.
    event Frozen(address indexed account, uint256 amount);

    /// @notice Error reverted when an account is not allowed to send tokens.
    /// @param account The address of the account which is not allowed to send.
    error ERC7943CannotSend(address account);

    /// @notice Error reverted when an account is not allowed to receive tokens.
    /// @param account The address of the account which is not allowed to receive.
    error ERC7943CannotReceive(address account);

    /// @notice Error reverted when a transfer is not allowed according to internal rules.
    /// @param from The address from which tokens are being sent.
    /// @param to The address to which tokens are being sent.
    /// @param amount The amount sent.
    error ERC7943CannotTransfer(address from, address to, uint256 amount);

    /// @notice Error reverted when a transfer is attempted from `account` with an `amount` less than or equal to its balance, but greater than its unfrozen balance.
    /// @param account The address holding the tokens.
    /// @param amount The amount being transferred.
    /// @param unfrozen The amount of tokens that are unfrozen and available to transfer.
    error ERC7943InsufficientUnfrozenBalance(address account, uint256 amount, uint256 unfrozen);

    /// @notice Takes tokens from one address and transfers them to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `amount` is taken.
    /// @param to The address that receives `amount`.
    /// @param amount The amount to force transfer.
    /// @return result True if the transfer executed correctly. Reverts on failure.
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool result);

    /// @notice Changes the frozen status of `amount` tokens belonging to `account`.
    /// @dev Overwrites the current value, similar to an `approve` function.
    /// Requires specific authorization. Frozen tokens cannot be transferred by the account.
    /// @param account The address of the account whose tokens are to be frozen.
    /// @param amount The amount of tokens to freeze. It can be greater than the account balance.
    /// @return result True if the freezing executed correctly. Reverts on failure.
    function setFrozenTokens(address account, uint256 amount) external returns (bool result);

    /// @notice Checks if a specific account is allowed to send tokens according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param account The address to check.
    /// @return allowed True if the account is allowed to send, false otherwise.
    function canSend(address account) external view returns (bool allowed);

    /// @notice Checks if a specific account is allowed to receive tokens according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param account The address to check.
    /// @return allowed True if the account is allowed to receive, false otherwise.
    function canReceive(address account) external view returns (bool allowed);

    /// @notice Checks the frozen status/amount.
    /// @param account The address of the account.
    /// @dev It could return an amount higher than the account's balance.
    /// @return amount The amount of tokens currently frozen for `account`.
    function getFrozenTokens(address account) external view returns (uint256 amount);

    /// @notice Checks if a transfer is currently possible according to token rules. It enforces validations on the frozen tokens.
    /// @dev This can involve checks like allowlists, blocklists, transfer limits, and other policy-defined restrictions.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens.
    /// @param amount The amount being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function canTransfer(address from, address to, uint256 amount) external view returns (bool allowed);
}
