// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC7620 {
    // Registers a new service provider
    function registerServiceProvider(address serviceProvider) external;

    // Deregisters a service provider
    function deregisterServiceProvider(address serviceProvider) external;

    // Allows users to pre-authorize a service provider to deduct funds up to a certain limit
    function authorizeServiceProvider(address serviceProvider, uint256 amount) external;

    // Revokes authorization for a service provider to deduct funds
    function revokeAuthorization(address serviceProvider) external;

    // Deducts funds from the user's pre-authorized amount, including a reference ID for the transaction
    function deductFunds(address user, uint256 amount, string memory referenceId) external;

    // Allows users to deposit funds into the contract, including a reference ID for the transaction
    function depositFunds(uint256 amount, string memory referenceId) external;

    // Returns the authorized amount for a service provider
    function authorizedAmount(address user, address serviceProvider) external view returns (uint256);

    // Checks if a service provider is registered
    function isServiceProviderRegistered(address serviceProvider) external view returns (bool);
}
