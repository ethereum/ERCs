---
eip: 77xx
title: Deferred Token Transfer
description: Allows users to schedule ERC20 token transfers for withdrawal at a specified future time, enabling time-locked payments.
author: Chen Liaoyuan (@chenly)
discussions-to: https://ethereum-magicians.org/t/erc-76xx-deferred-token-transfer/25601
status: Draft
type: Standards Track
category: ERC
created: 2024-06-09
---

## Abstract

The standard enables users to deposit [ERC-20](./eip-20.md) tokens that can be withdrawn by a specified beneficiary at a future timestamp. Each deposit is assigned a unique ID and includes details such as the beneficiary, token type, amount, timestamp, and withdrawal status. 

### Motivation

Sometimes, we need deferred payments in various scenarios, such as vesting schedules, escrow services, or timed rewards. By providing a secure and reliable mechanism for time-locked token transfers, this contract ensures that tokens are transferred only after a specified timestamp is reached. This facilitates structured and delayed payments, adding an extra layer of security and predictability to token transfers. This mechanism is particularly useful for situations where payments need to be conditional on the passage of time.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Implementers of this standard **MUST** have all of the following functions:

```solidity
pragma solidity ^0.8.0;

interface IDeferredTokenTransfer {
    // Struct to store deposit information
    struct Deposit {
        address beneficiary;
        address token;
        uint256 amount;
        uint256 timestamp;
        bool withdrawn;
    }

    /**
     * @notice Create a new deposit
     * @param _beneficiary The address that will receive the tokens
     * @param _token The address of the ERC20 token
     * @param _amount The amount of tokens to deposit
     * @param _timestamp The timestamp when the tokens can be withdrawn
     * @return The ID of the created deposit
     */
    function deposit(
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint256 _timestamp
    ) external returns (uint256);

    /**
     * @notice Withdraw tokens from a deposit
     * @param _depositId The ID of the deposit to withdraw from
     */
    function withdraw(uint256 _depositId) external;

    /**
     * @notice Get details of a deposit
     * @param _depositId The ID of the deposit to retrieve
     * @return beneficiary The address that will receive the tokens
     * @return token The address of the ERC20 token
     * @return amount The amount of tokens deposited
     * @return timestamp The timestamp when the tokens can be withdrawn
     * @return withdrawn Whether the tokens have been withdrawn
     */
    function deposits(uint256 _depositId) external view returns (address beneficiary, address token, uint256 amount, uint256 timestamp, bool withdrawn);

    // Events to log deposit creation and withdrawal
    event DepositCreated(uint256 depositId, address indexed beneficiary, uint256 amount, uint256 timestamp);
    event TokensWithdrawn(uint256 depositId, address indexed beneficiary, uint256 amount);
}
```

## Rationale

The design of the Deferred Token Transfer contract aims to provide a straightforward and secure method for handling time-locked token transfers. The following considerations were made during its development:

1. **Simplicity and Usability**: The contract interface is designed to be simple and intuitive, making it easy for users to create deposits and for beneficiaries to withdraw tokens once the conditions are met.

2. **Security**: By leveraging OpenZeppelin's SafeERC20 library, the contract ensures secure token transfers, preventing common vulnerabilities associated with ERC20 transfers. Additionally, the contract includes checks to prevent multiple withdrawals of the same deposit.

3. **Flexibility**: The contract supports various ERC20 tokens, allowing users to create deposits with any standard ERC20 token. This flexibility makes it suitable for a wide range of use cases.

4. **Event Logging**: Events are emitted for both deposit creation and token withdrawal. This provides transparency and allows easy tracking of contract activities, which is crucial for auditability and user confidence.

5. **Conditional Payments**: By implementing a time-lock mechanism, the contract ensures that tokens are only transferred after a specific timestamp. This feature is essential for use cases like vesting schedules, escrow arrangements, and timed rewards, where payments need to be delayed until certain conditions are met.

---

## Reference Implementation

```solidity
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DeferredTokenTransfer {
    using SafeERC20 for IERC20;

    // Struct to store deposit information
    struct Deposit {
        address beneficiary;
        address token;
        uint256 amount;
        uint256 timestamp;
        bool withdrawn;
    }

    // Mapping to store deposits by ID
    mapping(uint256 => Deposit) public deposits;

    // Counter for deposit IDs
    uint256 public depositId = uint256(0);

    // Events to log deposit creation and withdrawal
    event DepositCreated(uint256 depositId, address indexed beneficiary, uint256 amount, uint256 timestamp);
    event TokensWithdrawn(uint256 depositId, address indexed beneficiary, uint256 amount);

    // Constructor
    constructor() {}

    /**
     * @notice Create a new deposit
     * @param _beneficiary The address that will receive the tokens
     * @param _token The address of the ERC20 token
     * @param _amount The amount of tokens to deposit
     * @param _timestamp The timestamp when the tokens can be withdrawn
     * @return The ID of the created deposit
     */
    function deposit(
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint256 _timestamp
    ) external returns (uint256) {
        require(_amount > 0, "Invalid deposit amount");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        depositId++;

        deposits[depositId] = Deposit({
            beneficiary: _beneficiary,
            token: _token,
            amount: _amount,
            timestamp: _timestamp,
            withdrawn: false
        });

        emit DepositCreated(depositId, _beneficiary, _amount, _timestamp);
        return depositId;
    }

    /**
     * @notice Withdraw tokens from a deposit
     * @param _depositId The ID of the deposit to withdraw from
     */
    function withdraw(uint256 _depositId) external {
        Deposit storage _deposit = deposits[_depositId];
        require(_deposit.amount > 0, "Invalid deposit ID");
        require(block.timestamp >= _deposit.timestamp, "Current time is before withdrawal time");
        require(_deposit.beneficiary == msg.sender, "Wrong beneficiary");
        require(!_deposit.withdrawn, "Tokens already withdrawn");

        _deposit.withdrawn = true;
        IERC20(_deposit.token).safeTransfer(msg.sender, _deposit.amount);

        emit TokensWithdrawn(_depositId, msg.sender, _deposit.amount);
    }

    /**
     * @notice Get details of a deposit
     * @param _depositId The ID of the deposit to retrieve
     * @return beneficiary The address that will receive the tokens
     * @return token The address of the ERC20 token
     * @return amount The amount of tokens deposited
     * @return timestamp The timestamp when the tokens can be withdrawn
     * @return withdrawn Whether the tokens have been withdrawn
     */
    function deposits(uint256 _depositId) external view returns (address beneficiary, address token, uint256 amount, uint256 timestamp, bool withdrawn) {
        Deposit storage _deposit = deposits[_depositId];
        return (_deposit.beneficiary, _deposit.token, _deposit.amount, _deposit.timestamp, _deposit.withdrawn);
    }
}
```

## Security Considerations

TBD

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
