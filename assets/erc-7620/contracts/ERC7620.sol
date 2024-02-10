// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC7620 is ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public payToken; // ERC20 token used for payments
    mapping(address => mapping(address => uint256)) private _authorizedAmounts; // User -> (Service Provider -> Authorized Amount)
    mapping(address => bool) public registeredServiceProviders; // Registered service providers

    // Event definitions
    event ServiceProviderRegistered(address serviceProvider);
    event ServiceProviderDeregistered(address serviceProvider);
    event AuthorizationUpdated(address indexed user, address indexed serviceProvider, uint256 newAuthorizedAmount);
    event FundsDeducted(address indexed user, address indexed serviceProvider, uint256 amount, string referenceId);
    event FundsDeposited(address indexed user, uint256 amount);
    event AuthorizationRevoked(address indexed user, address indexed serviceProvider);

    constructor(address payTokenAddress) {
        require(payTokenAddress != address(0), "Invalid token address");
        payToken = IERC20(payTokenAddress);
    }

    // Register a new service provider
    function registerServiceProvider(address serviceProvider) external {
        require(!registeredServiceProviders[serviceProvider], "Service provider already registered");
        registeredServiceProviders[serviceProvider] = true;
        emit ServiceProviderRegistered(serviceProvider);
    }

    // Deregister a service provider
    function deregisterServiceProvider(address serviceProvider) external {
        require(registeredServiceProviders[serviceProvider], "Service provider not registered");
        registeredServiceProviders[serviceProvider] = false;
        emit ServiceProviderDeregistered(serviceProvider);
    }

    // Allows users to pre-authorize a service provider to deduct funds up to a certain limit
    function authorizeServiceProvider(address serviceProvider, uint256 amount) external {
        require(registeredServiceProviders[serviceProvider], "Service provider not registered");
        _authorizedAmounts[msg.sender][serviceProvider] = amount;
        emit AuthorizationUpdated(msg.sender, serviceProvider, amount);
    }

    // Revokes authorization for a service provider to deduct funds
    function revokeAuthorization(address serviceProvider) external {
        require(_authorizedAmounts[msg.sender][serviceProvider] > 0, "No authorization found");
        _authorizedAmounts[msg.sender][serviceProvider] = 0;
        emit AuthorizationRevoked(msg.sender, serviceProvider);
    }

    // Deducts funds from the user's pre-authorized amount
    function deductFunds(address user, uint256 amount, string memory referenceId) external {
        require(registeredServiceProviders[msg.sender], "Only registered service providers can deduct funds");
        require(_authorizedAmounts[user][msg.sender] >= amount, "Insufficient authorized amount");

        _authorizedAmounts[user][msg.sender] = _authorizedAmounts[user][msg.sender].sub(amount);
        require(payToken.transferFrom(user, address(this), amount), "Failed to transfer funds");

        emit FundsDeducted(user, msg.sender, amount, referenceId);
    }

    // Allows users to deposit funds into the contract
    function depositFunds(uint256 amount) external {
        require(payToken.transferFrom(msg.sender, address(this), amount), "Failed to transfer funds");
        emit FundsDeposited(msg.sender, amount);
    }

    // View authorized amount
    function authorizedAmount(address user, address serviceProvider) external view returns (uint256) {
        return _authorizedAmounts[user][serviceProvider];
    }

    // Check if a service provider is registered
    function isServiceProviderRegistered(address serviceProvider) external view returns (bool) {
        return registeredServiceProviders[serviceProvider];
    }
}
