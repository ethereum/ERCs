---
eip: xxxx
title: Access Control Registry
description: The AccessControlRegistry contract standardizes access control management by allowing registration, unregistration, role assignment, and role revocation for contracts, ensuring secure and transparent role management.
author: 
discussions-to: 
status: Draft
type: Standards Track
category: ERC
created: 
---

## Abstract

The Access Control Registry (ACR) standard defines a universal interface for managing role-based access control across multiple smart contracts. This standard introduces a centralized registry where contracts can register themselves and designate an administrator responsible for managing roles within their contract. The ACR provides functionality to grant and revoke roles for specific accounts, either individually or in bulk, ensuring that only authorized users can perform specific actions within a contract.This EIP introduces an on-chain registry system that a decentralized protocol may use to manage access controls for their smart contracts.

The core of the standard includes:

- **Registration and Unregistration**: Contracts can register with the ACR, specifying an admin who can manage roles within the contract. Contracts can also be unregistered when they are no longer active.

- **Role Management**: Admins can grant or revoke roles for accounts, either individually or in batches, ensuring fine-grained control over who can perform what actions within a contract.

- **Role Verification**: Any account can verify if another account has a specific role in a registered contract, providing transparency and facilitating easier integration with other systems.

By centralizing access control management, the ACR standard aims to reduce redundancy, minimize errors in access control logic, and provide a clear and standardized approach to role management across smart contracts. This improves security and maintainability, making it easier for developers to implement robust access control mechanisms in their applications.

## Motivation

The need for a standardized access control mechanism across Ethereum smart contracts is paramount. Current practices involve bespoke implementations, leading to redundancy and potential security flaws. By providing a unified interface for registering contracts and managing roles, this standard simplifies development, ensures consistency, and enhances security. It facilitates easier integration and auditing, fostering a more robust and interoperable ecosystem.

The advantages of using the provided system might be:

Structured smart contracts management via specialized contracts.
Ad-hoc access-control provision of a protocol.
Ability to specify custom access control rules to maintain the protocol.

## Specification

The `AccessControlRegistry` contract provides a standardized interface for managing access control in Ethereum smart contracts. It includes functions to register and unregister contracts, grant and revoke roles for specific contracts, and check if an account has a particular role in a registered contract. Events are emitted for contract registration, unregistration, role grants, and role revocations, ensuring transparency and traceability of access control changes.

Additionally, the AccessControlRegistry MUST reject the registration of zero addresses.

```solidity
pragma solidity 0.8.23;

interface IAccessControlRegistry {

    // Contains information about a registered contract.
    // @param isActive Indicates whether the contract is active.
    // @param admin The address of the admin for the registered contract.
    struct contractInfo {
        bool isActive;
        address admin;
    }

    // Emitted when a contract is registered.
    // @param _contract The address of the registered contract.
    // @param _admin The address of the admin for the registered contract.
    event ContractRegistered(address indexed _contract, address indexed _admin);

    // Emitted when a contract is unregistered.
    // @param _contract The address of the unregistered contract.
    event ContractUnregistered(address indexed _contract);

    // Emitted when a role is granted to an account for a contract.
    // @param targetContract The address of the contract.
    // @param role The role being granted.
    // @param account The address of the account.
    event RoleGranted(
        address indexed targetContract,
        bytes32 indexed role,
        address indexed account
    );

    // Emitted when a role is revoked from an account for a contract.
    // @param targetContract The address of the contract.
    // @param role The role being revoked.
    // @param account The address of the account.
    event RoleRevoked(
        address indexed targetContract,
        bytes32 indexed role,
        address indexed account
    );

    // Registers a contract with the given admin.
    // @param _contract The address of the contract to register.
    // @param _admin The address of the admin for the registered contract.
    function registerContract(address _contract, address _admin) external;

    // Unregisters a contract.
    // @param _contract The address of the contract to unregister.
    function unRegisterContract(address _contract) external;

    // Grants roles to multiple accounts for multiple contracts.
    // @param targetContracts An array of contract addresses to which roles will be granted.
    // @param roles An array of roles to be granted.
    // @param accounts An array of accounts to be granted the roles.
    function grantRole(
        address[] memory targetContracts,
        bytes32[] memory roles,
        address[] memory accounts
    ) external;

    // Revokes roles from multiple accounts for multiple contracts.
    // @param targetContracts An array of contract addresses from which roles will be revoked.
    // @param roles An array of roles to be revoked.
    // @param accounts An array of accounts from which the roles will be revoked.
    function revokeRole(
        address[] memory targetContracts,
        bytes32[] memory roles,
        address[] memory accounts
    ) external;

    // Checks if an account has a specific role for a contract.
    // @param targetContract The address of the contract.
    // @param account The address of the account.
    // @param role The role to check.
    // @return True if the account has the role for the contract, false otherwise.
    function hasRole(
        address targetContract,
        address account,
        bytes32 role
    ) external view returns (bool);

    // Gets the information of a registered contract.
    // @param _contract The address of the contract to get the information.
    // @return isActive Whether the contract is active.
    // @return admin The address of the admin for the contract.
    // MUST revert if the registered contract doesn't exist`
    function getContractInfo(
        address _contract
    ) external view returns (bool isActive, address admin);
}

```

## Rationale

The IAccessControlRegistry interface aims to provide a standardized way to manage access control across multiple contracts within the ecosystem. By defining a clear structure and set of events, this interface helps streamline the process of registering, unregistering, and managing roles for contracts. The rationale for each function and event is as follows:

### Contract Registration and Unregistration

**registerContract(address _contract, address _admin)**: This function allows the registration of a new contract along with its admin address. This is crucial for initializing the access control settings for a contract and ensuring that there is an accountable admin who can manage roles and permissions.

**unRegisterContract(address _contract)**: This function enables the removal of a contract from the registry. Unregistering a contract is important when a contract is no longer in use or needs to be decommissioned to prevent unauthorized access.

### Role Management

**grantRole(address[] memory targetContracts, bytes32[] memory roles, address[] memory accounts)**: This function allows the assignment of roles to multiple accounts for multiple contracts in a single transaction. This bulk operation is designed to reduce the gas costs and simplify the process of role assignment in large systems with numerous contracts and users.

**revokeRole(address[] memory targetContracts, bytes32[] memory roles, address[] memory accounts)**: Similar to grantRole, this function facilitates the revocation of roles from multiple accounts across multiple contracts in a single transaction. This ensures efficient management of permissions, especially in scenarios where many users need their roles updated simultaneously.

### Role Checking

**hasRole(address targetContract, address account, bytes32 role)**: This view function allows the verification of whether a particular account holds a specific role for a given contract. This is essential for ensuring that operations requiring specific permissions are performed only by authorized users.

### Contract Information Retrieval

**getContractInfo(address _contract)**: This function provides the ability to retrieve the status and admin information of a registered contract. It enhances transparency and allows administrators and users to easily query the status and management of any contract within the registry.

### Events

**ContractRegistered(address indexed _contract, address indexed _admin)**: Emitted when a new contract is registered, this event ensures that there is a public record of contract registrations, facilitating auditability and transparency.

**ContractUnregistered(address indexed _contract)**: Emitted when a contract is unregistered, this event serves to notify the system and its users of the removal of a contract from the registry, which is critical for maintaining an up-to-date and accurate registry.

**RoleGranted(address indexed targetContract, bytes32 indexed role, address indexed account)**: Emitted when a role is granted to an account, this event provides a public log that can be used to track role assignments and changes, ensuring that role grants are transparent and verifiable.

**RoleRevoked(address indexed targetContract, bytes32 indexed role, address indexed account)**: Emitted when a role is revoked from an account, this event similarly ensures that role revocations are publicly logged and traceable, supporting robust access control management.

### Design Decisions
There are a few design decisions that have to be explicitly specified to ensure the functionality, security, and efficiency of the IAccessControlRegistry:

#### Decentralized Contract Registration

**No Central Owner**: There is no central owner who can register contracts. This design choice promotes decentralization and ensures that individual contracts are responsible for their own registration and management.

#### Contract-Only Registration

**Contract Call Restriction**: The registerContract function can only be called by other contracts (require(msg.sender != tx.origin)). This prevents individual accounts from manipulating the registration process, ensuring that only legitimate contracts can register themselves.

#### Efficient Storage and Lookup

**Mapping Utilization**: The use of mappings for storing contract information (mapping(address => contractInfo) private contracts) and role assignments (mapping(address => mapping(address => mapping(bytes32 => bool))) private _contractRoles) ensures efficient storage and lookup. This is crucial for maintaining performance in a large-scale system with numerous contracts and roles.

#### Role Management Flexibility

**Bulk Operations**: Functions like grantRole and revokeRole allow for the assignment and revocation of roles to multiple accounts for multiple contracts in a single transaction. This bulk operation reduces gas costs and simplifies the process of role management in large systems.

#### Robust Security Measures

**Admin-Only Operations**: Functions that modify the state, such as unRegisterContract, _grantRole, and _revokeRole, are restricted to contract admins. This ensures that only authorized personnel can manage contracts and roles, reducing the risk of unauthorized changes.

**Valid Address Checks**: The validAddress modifier ensures that addresses are non-zero, preventing potential issues with null addresses which could lead to unintended behavior or security vulnerabilities.

**Active Contract Checks**: The onlyActiveContract modifier ensures that actions are only performed on active contracts, preventing operations on inactive or unregistered contracts.

#### Transparent Auditing

**Event Logging**: Emitting events for each significant action (registration, unregistration, role granting, and revocation) provides a transparent log that can be monitored and audited. This helps detect and respond to unauthorized or suspicious activities promptly.

## Reference Implementation

```solidity
pragma solidity 0.8.23;

import "./IAccessControlRegistry.sol";

contract AccessControlRegistry is IAccessControlRegistry {

    // Mapping to store contract information
    mapping(address => contractInfo) private contracts;
    
    // Mapping to store roles associated with contracts and accounts
    mapping(address => mapping(address => mapping(bytes32 => bool))) private _contractRoles;

    // Modifier to ensure that the caller is the admin of the contract
    modifier onlyAdmin(address _contract) {
        require(msg.sender == contracts[_contract].admin, "Msg Sender is not admin");
        _;
    }

    // Modifier to ensure that the contract is active
    modifier onlyActiveContract(address _contract) {
        require(contracts[_contract].isActive, "Contract not registered");
        _;
    }

    // Modifier to validate that the address is not zero
    modifier validAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    // @notice Registers a contract with the given admin.
    // @param _contract The address of the contract to register.
    // @param _admin The address of the admin for the registered contract.
    function registerContract(address _contract, address _admin) 
        public 
        validAddress(_contract) 
        validAddress(_admin) 
    {
        require(msg.sender != tx.origin, "Only contracts can call this function");
        require(contracts[_contract].admin == address(0) || contracts[_contract].admin == _admin, "Contract admin already defined");
        contracts[_contract].isActive = true;
        contracts[_contract].admin = _admin;
        emit ContractRegistered(_contract, _admin);
    }

    // @notice Unregisters a contract.
    // @param _contract The address of the contract to unregister.
    function unRegisterContract(address _contract) 
        public 
        onlyAdmin(_contract) 
        onlyActiveContract(_contract) 
    {
        contracts[_contract].isActive = false;
        emit ContractUnregistered(_contract);
    }

    // @notice Grants roles to multiple accounts for multiple contracts.
    // @param targetContracts An array of contract addresses to which roles will be granted.
    // @param roles An array of roles to be granted.
    // @param accounts An array of accounts to be granted the roles.
    function grantRole(
        address[] memory targetContracts,
        bytes32[] memory roles,
        address[] memory accounts
    ) 
        public 
    {
        require(
            targetContracts.length == roles.length &&
            roles.length == accounts.length,
            "Array lengths do not match"
        );

        for (uint256 i = 0; i < roles.length; i++) {
            _grantRole(targetContracts[i], roles[i], accounts[i]);
        }
    }

    // @notice Revokes roles from multiple accounts for multiple contracts.
    // @param targetContracts An array of contract addresses from which roles will be revoked.
    // @param roles An array of roles to be revoked.
    // @param accounts An array of accounts from which the roles will be revoked.
    function revokeRole(
        address[] memory targetContracts,
        bytes32[] memory roles,
        address[] memory accounts
    ) 
        public 
    {
        require(
            targetContracts.length == roles.length &&
            roles.length == accounts.length,
            "Array lengths do not match"
        );

        for (uint256 i = 0; i < roles.length; i++) {
            _revokeRole(targetContracts[i], roles[i], accounts[i]);
        }
    }

    // @notice Checks if an account has a specific role for a contract.
    // @param targetContract The address of the contract.
    // @param account The address of the account.
    // @param role The role to check.
    // @return True if the account has the role for the contract, false otherwise.
    function hasRole(address targetContract, address account, bytes32 role) 
        public 
        view 
        onlyActiveContract(targetContract) 
        returns (bool) 
    {
        return _contractRoles[targetContract][account][role];
    }

    // @notice Gets the information of a registered contract.
    // @param _contract The address of the contract to get the information.
    // @return isActive Whether the contract is active.
    // @return admin The address of the admin for the contract.
    function getContractInfo(address _contract)
        public
        view
        returns (bool isActive, address admin)
    {
        contractInfo memory info = contracts[_contract];
        return (info.isActive, info.admin);
    }

    // @notice Internal function to grant a role to an account for a contract.
    // @param targetContract The address of the contract.
    // @param role The role to grant.
    // @param account The address of the account.
    function _grantRole(
        address targetContract,
        bytes32 role,
        address account
    ) 
        internal 
        onlyAdmin(targetContract) 
        onlyActiveContract(targetContract) 
        validAddress(account) 
    {
        _contractRoles[targetContract][account][role] = true;
        emit RoleGranted(targetContract, role, account);
    }

    // @notice Internal function to revoke a role from an account for a contract.
    // @param targetContract The address of the contract.
    // @param role The role to revoke.
    // @param account The address of the account.
    function _revokeRole(
        address targetContract,
        bytes32 role,
        address account
    ) 
        internal 
        onlyAdmin(targetContract) 
        onlyActiveContract(targetContract) 
        validAddress(account) 
    {
        require(_contractRoles[targetContract][account][role], "Role already revoked");
        _contractRoles[targetContract][account][role] = false;
        emit RoleRevoked(targetContract, role, account);
    }
}

```

## Security Considerations

The AccessControlRegistry implements several security measures to ensure the integrity and reliability of the access control system:

**Admin-Only Restrictions**: By limiting state-modifying functions to contract admins, the system prevents unauthorized users from making critical changes.

**Contract-Only Registration**: Ensuring that only contracts can register themselves prevents misuse by individual accounts.

**Valid Address Checks**: By requiring non-zero addresses, the system avoids potential vulnerabilities associated with null addresses.

**Active Contract Checks**: Operations are restricted to active contracts, reducing the risk of interacting with deprecated or unregistered contracts.

**Event Logging**: Comprehensive event logging supports transparency and auditability, allowing for effective monitoring and detection of unauthorized actions.


## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).