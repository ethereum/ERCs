// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Interface for ERC-20 based implementations.
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

    /// @notice Error reverted when an account is not allowed to transact. 
    /// @param account The address of the account which is not allowed for transfers.
    error ERC7943CannotTransact(address account);

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
    /// @return result True if the transfer executed correctly, false otherwise.
    function forcedTransfer(address from, address to, uint256 amount) external returns(bool result);

    /// @notice Changes the frozen status of `amount` tokens belonging to `account`.
    /// This overwrites the current value, similar to an `approve` function.
    /// @dev Requires specific authorization. Frozen tokens cannot be transferred by the account.
    /// @param account The address of the account whose tokens are to be frozen/unfrozen.
    /// @param amount The amount of tokens to freeze. It can be greater than account balance.
    /// @return result True if the freezing executed correctly, false otherwise.
    function setFrozenTokens(address account, uint256 amount) external returns(bool result);

    /// @notice Checks if a specific account is allowed to transact according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param account The address to check.
    /// @return allowed True if the account is allowed, false otherwise.
    function canTransact(address account) external view returns (bool allowed);

    /// @notice Checks the frozen status/amount.
    /// @param account The address of the account.
    /// @dev It could return an amount higher than the account's balance.
    /// @return amount The amount of tokens currently frozen for `account`.
    function getFrozenTokens(address account) external view returns (uint256 amount);

    /// @notice Checks if a transfer is currently possible according to token rules. It enforces validations on the frozen tokens.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits and other policy-defined restrictions.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens. 
    /// @param amount The amount being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function canTransfer(address from, address to, uint256 amount) external view returns (bool allowed);
}

/// @notice Interface for ERC-721 based implementations.
interface IERC7943NonFungible is IERC165 {
    /// @notice Emitted when `tokenId` is taken from one address and transferred to another.
    /// @param from The address from which `tokenId` is taken.
    /// @param to The address to which seized `tokenId` is transferred.
    /// @param tokenId The ID of the token being transferred.
    event ForcedTransfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @notice Emitted when `setFrozenTokens` is called, changing the frozen status of `tokenId` for `account`.
    /// @param account The address of the account whose `tokenId` is subjected to freeze/unfreeze.
    /// @param tokenId The ID of the token subjected to freeze/unfreeze.
    /// @param frozenStatus Whether `tokenId` has been frozen or unfrozen.
    event Frozen(address indexed account, uint256 indexed tokenId, bool indexed frozenStatus);

    /// @notice Error reverted when an account is not allowed to transact. 
    /// @param account The address of the account which is not allowed for transfers.
    error ERC7943CannotTransact(address account);

    /// @notice Error reverted when a transfer is not allowed according to internal rules. 
    /// @param from The address from which tokens are being sent.
    /// @param to The address to which tokens are being sent.
    /// @param tokenId The id of the token being sent.
    error ERC7943CannotTransfer(address from, address to, uint256 tokenId);

    /// @notice Error reverted when a transfer is attempted from `account` with a `tokenId` which has been previously frozen.
    /// @param account The address holding the token with `tokenId`.
    /// @param tokenId The Id of the token being frozen and unavailable to be transferred. 
    error ERC7943InsufficientUnfrozenBalance(address account, uint256 tokenId);

    /// @notice Takes `tokenId` from one address and transfers it to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `tokenId` is taken.
    /// @param to The address that receives `tokenId`.
    /// @param tokenId The ID of the token being transferred.
    /// @return result True if the transfer executed correctly, false otherwise.
    function forcedTransfer(address from, address to, uint256 tokenId) external returns(bool result);

    /// @notice Changes the frozen status of `tokenId` belonging to an `account`.
    /// This overwrites the current value, similar to an `approve` function.
    /// @dev Requires specific authorization. Frozen tokens cannot be transferred by the account.
    /// @param account The address of the account whose tokens are to be frozen/unfrozen.
    /// @param tokenId The ID of the token to freeze/unfreeze.
    /// @param frozenStatus Whether `tokenId` is being frozen or not. 
    /// @return result True if the freezing executed correctly, false otherwise.
    function setFrozenTokens(address account, uint256 tokenId, bool frozenStatus) external returns(bool result);

    /// @notice Checks if a specific account is allowed to transact according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param account The address to check.
    /// @return allowed True if the account is allowed, false otherwise.
    function canTransact(address account) external view returns (bool allowed);

    /// @notice Checks the frozen status of a specific `tokenId`.
    /// @dev It could return true even if account does not hold the token.
    /// @param account The address of the account.
    /// @param tokenId The ID of the token.
    /// @return frozenStatus Whether `tokenId` is currently frozen for `account`.
    function getFrozenTokens(address account, uint256 tokenId) external view returns (bool frozenStatus);

    /// @notice Checks if a transfer is currently possible according to token rules. It enforces validations on the frozen tokens.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits and other policy-defined restrictions.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens. 
    /// @param tokenId The ID of the token being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function canTransfer(address from, address to, uint256 tokenId) external view returns (bool allowed);
}

/// @notice Interface for ERC-1155 based implementations.
interface IERC7943MultiToken is IERC165 {
    /// @notice Emitted when tokens are taken from one address and transferred to another.
    /// @param from The address from which tokens were taken.
    /// @param to The address to which seized tokens were transferred.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount seized.
    event ForcedTransfer(address indexed from, address indexed to, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when `setFrozenTokens` is called, changing the frozen `amount` of `tokenId` tokens for `account`.
    /// @param account The address of the account whose tokens are being frozen.
    /// @param tokenId The ID of the token being frozen.
    /// @param amount The amount of tokens frozen after the change.
    event Frozen(address indexed account, uint256 indexed tokenId, uint256 amount);

    /// @notice Error reverted when an account is not allowed to transact. 
    /// @param account The address of the account which is not allowed for transfers.
    error ERC7943CannotTransact(address account);

    /// @notice Error reverted when a transfer is not allowed according to internal rules. 
    /// @param from The address from which tokens are being sent.
    /// @param to The address to which tokens are being sent.
    /// @param tokenId The id of the token being sent.
    /// @param amount The amount sent.
    error ERC7943CannotTransfer(address from, address to, uint256 tokenId, uint256 amount);

    /// @notice Error reverted when a transfer is attempted from `account` with an `amount` of `tokenId` less than or equal to its balance, but greater than its unfrozen balance.
    /// @param account The address holding the `amount` of `tokenId` tokens.
    /// @param tokenId The Id of the token being transferred. 
    /// @param amount The amount of `tokenId` tokens being transferred.
    /// @param unfrozen The amount of tokens that are unfrozen and available to transfer.
    error ERC7943InsufficientUnfrozenBalance(address account, uint256 tokenId, uint256 amount, uint256 unfrozen);

    /// @notice Takes tokens from one address and transfers them to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `amount` is taken.
    /// @param to The address that receives `amount`.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount to force transfer.
    /// @return result True if the transfer executed correctly, false otherwise.
    function forcedTransfer(address from, address to, uint256 tokenId, uint256 amount) external returns(bool result);

    /// @notice Changes the frozen status of `amount` of `tokenId` tokens belonging to an `account`.
    /// This overwrites the current value, similar to an `approve` function.
    /// @dev Requires specific authorization. Frozen tokens cannot be transferred by the account.
    /// @param account The address of the account whose tokens are to be frozen/unfrozen.
    /// @param tokenId The ID of the token to freeze/unfreeze.
    /// @param amount The amount of tokens to freeze.
    /// @return result True if the freezing executed correctly, false otherwise.
    function setFrozenTokens(address account, uint256 tokenId, uint256 amount) external returns(bool result);

    /// @notice Checks if a specific account is allowed to transact according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param account The address to check.
    /// @return allowed True if the account is allowed, false otherwise.
    function canTransact(address account) external view returns (bool allowed);

    /// @notice Checks the frozen status/amount of a specific `tokenId`.
    /// @dev It could return an amount higher than the account's balance.
    /// @param account The address of the account.
    /// @param tokenId The ID of the token.
    /// @return amount The amount of `tokenId` tokens currently frozen for `account`.
    function getFrozenTokens(address account, uint256 tokenId) external view returns (uint256 amount);

    /// @notice Checks if a transfer is currently possible according to token rules. It enforces validations on the frozen tokens.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits and other policy-defined restrictions.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens. 
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function canTransfer(address from, address to, uint256 tokenId, uint256 amount) external view returns (bool allowed);
}
