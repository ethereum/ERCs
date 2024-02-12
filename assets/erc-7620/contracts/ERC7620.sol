// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC7620 is ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public payToken; // ERC20 token used for payments
    mapping(address => uint256) private _remainingBalance; // User -> Remaining Balance for Authorization
    mapping(address => mapping(address => uint256)) private _authorizedAmounts; // User -> (Service Provider -> Authorized Amount)
    mapping(address => bool) public registeredServiceProviders; // Registered service providers

    // Event definitions
    event ServiceProviderRegistered(address serviceProvider);
    event ServiceProviderDeregistered(address serviceProvider);
    event AuthorizationUpdated(address indexed user, address indexed serviceProvider, uint256 newAuthorizedAmount);
    event FundsDeducted(address indexed user, address indexed serviceProvider, uint256 amount, string referenceId);
    event Deposited(address indexed user, uint256 amount);
    event AuthorizationRevoked(address indexed user, address indexed serviceProvider);
    event Withdrawal(address indexed user, uint256 amount);

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
        uint256 remaining_balance = _remainingBalance[msg.sender];
        uint256 authorized_amount = _authorizedAmounts[msg.sender][serviceProvider];
        
        if (authorized_amount == 0) {
            require(remaining_balance >= amount, "Insufficient remaining balance for authorization");
            _remainingBalance[msg.sender] = remaining_balance.sub(amount);
        } else {
            require(authorized_amount != amount, "Authorized amount unchanged");
            if (amount > authorized_amount) {
                uint256 increaseAmount = amount.sub(authorized_amount);
                require(_remainingBalance[msg.sender] >= increaseAmount, "Insufficient remaining balance for authorization increase");
                _remainingBalance[msg.sender] = remaining_balance.sub(increaseAmount);
            } else {
                uint256 decreaseAmount = authorized_amount.sub(amount);
                _remainingBalance[msg.sender] = remaining_balance.add(decreaseAmount);
            }
        }
        
        _authorizedAmounts[msg.sender][serviceProvider] = amount;
        emit AuthorizationUpdated(msg.sender, serviceProvider, amount);
    }

    // Revokes authorization for a service provider to deduct funds
    function revokeAuthorization(address serviceProvider) external {
        uint256 authorized_amount = _authorizedAmounts[msg.sender][serviceProvider];
        require(authorized_amount > 0, "No authorization found");
        _authorizedAmounts[msg.sender][serviceProvider] = 0;
        _remainingBalance[msg.sender] = _remainingBalance[msg.sender].add(authorized_amount);
        emit AuthorizationRevoked(msg.sender, serviceProvider);
    }

    // Deducts funds from the user's pre-authorized amount
    function deductAuthorizedFunds(address user, uint256 amount, string calldata referenceId) external {
        require(registeredServiceProviders[msg.sender], "Only registered service providers can deduct funds");
        require(_authorizedAmounts[user][msg.sender] >= amount, "Insufficient authorized amount");
        _authorizedAmounts[user][msg.sender] = _authorizedAmounts[user][msg.sender].sub(amount);
        require(payToken.transfer(msg.sender, amount), "Failed to transfer funds");
        emit FundsDeducted(user, msg.sender, amount, referenceId);
    }

    // Allows users to deposit funds into the contract
    function deposit(uint256 amount) external {
        require(payToken.transferFrom(msg.sender, address(this), amount), "Failed to transfer funds");
        _remainingBalance[msg.sender] = _remainingBalance[msg.sender].add(amount);
        emit Deposited(msg.sender, amount);
    }

    // Allows users to withdraw remaining balance
    function withdraw(uint256 amount) external {
        require(amount <= _remainingBalance[msg.sender], "Insufficient balance");
        _remainingBalance[msg.sender] = _remainingBalance[msg.sender].sub(amount);
        require(payToken.transfer(msg.sender, amount), "Failed to transfer funds");
        emit Withdrawal(msg.sender, amount);
    }

    // View authorized amount
    function authorizedAmount(address user, address serviceProvider) external view returns (uint256) {
        return _authorizedAmounts[user][serviceProvider];
    }

    // Check if a service provider is registered
    function isServiceProviderRegistered(address serviceProvider) external view returns (bool) {
        return registeredServiceProviders[serviceProvider];
    }

    // View remaining balance
    function remainingBalance(address user) external view returns (uint256) {
        return _remainingBalance[user];
    }
}
