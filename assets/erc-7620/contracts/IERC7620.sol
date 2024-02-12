// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.20;

interface IERC7620 {
    // Events
    event ServiceProviderRegistered(address serviceProvider); // Event emitted when a service provider is registered
    event ServiceProviderDeregistered(address serviceProvider); // Event emitted when a service provider is deregistered
    event AuthorizationUpdated(address indexed user, address indexed serviceProvider, uint256 newAuthorizedAmount); // Event emitted when authorization amount is updated
    event FundsDeducted(address indexed user, address indexed serviceProvider, uint256 amount, string referenceId); // Event emitted when funds are deducted
    event Deposited(address indexed user, uint256 amount); // Event emitted when funds are deposited
    event AuthorizationRevoked(address indexed user, address indexed serviceProvider); // Event emitted when authorization is revoked
    event Withdrawal(address indexed user, uint256 amount); // Event emitted when funds are withdrawn

    // External functions
    function registerServiceProvider(address serviceProvider) external; // Registers a new service provider
    function deregisterServiceProvider(address serviceProvider) external; // Deregisters a service provider
    function authorizeServiceProvider(address serviceProvider, uint256 amount) external; // Allows users to authorize a service provider to deduct funds
    function revokeAuthorization(address serviceProvider) external; // Revokes authorization for a service provider to deduct funds
    function deductAuthorizedFunds(address user, uint256 amount, string calldata referenceId) external; // Deducts funds from the user's pre-authorized amount
    function deposit(uint256 amount) external; // Allows users to deposit funds into the contract
    function withdraw(uint256 amount) external; // Allows users to withdraw remaining balance

    // View functions
    function authorizedAmount(address user, address serviceProvider) external view returns (uint256); // Returns the authorized amount for a user and service provider
    function isServiceProviderRegistered(address serviceProvider) external view returns (bool); // Checks if a service provider is registered
    function remainingBalance(address user) external view returns (uint256); // Returns the remaining balance for a user
}
