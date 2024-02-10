// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC7620 {
    // Allows service providers to register themselves
    function registerServiceProvider(address serviceProvider) external;

    // Allows service providers to deregister themselves
    function deregisterServiceProvider(address serviceProvider) external;

    // Allows users to pre-authorize a service provider to deduct funds up to a certain limit
    function authorizeServiceProvider(address serviceProvider, uint256 amount) external;

    // Revokes authorization for a service provider to deduct funds
    function revokeAuthorization(address serviceProvider) external;

    // Deducts funds from the user's pre-authorized amount
    function deductFunds(address user, uint256 amount) external;

    // Allows users to deposit funds into the contract
    function depositFunds(uint256 amount) external;

    // View authorized amount for a service provider
    function authorizedAmount(address user, address serviceProvider) external view returns (uint256);

    // Check if a service provider is registered
    function isServiceProviderRegistered(address serviceProvider) external view returns (bool);
}