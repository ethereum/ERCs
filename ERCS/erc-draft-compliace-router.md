---
eip: 0
title: Universal Compliance Router for Real-World Asset (RWA) Security Tokens
author: Deepanshu Tyagi @deepanshu179
discussions-to: https://ethereum-magicians.org/t/universal-compliance-router-for-rwa-security-tokens/XXXX
status: Draft
type: Standards Track
category: ERC
created: 2025
requires: 165
---
## Simple Summary

A modular and extensible smart contract standard designed to aggregate compliance checks across multiple on-chain modules, enabling jurisdiction-aware enforcement for tokenized real-world assets (RWAs) and unlocking the network effects of blockchain technology.

## Abstract

This EIP introduces a `UniversalComplianceRouter` contract that acts as a universal compliance layer for RWA security tokens. It allows dynamic registration of compliance modules, each associated with a function selector. The router performs aggregated compliance checks by invoking these modules with user-specific parameters such as jurisdiction using staticcall method. This enables flexible, composable, and upgradable compliance enforcement across jurisdictions and asset classes.

## Motivation

Tokenized RWAs such as real estate, equities, and bonds must comply with jurisdictional regulations (e.g., KYC/AML, accredited investor status). Hardcoding compliance logic into token contracts is inflexible and non-scalable. This EIP proposes a universal router that:

- Supports modular compliance logic
- Enables jurisdiction-specific enforcement
- Allows dynamic updates to compliance rules
- Promotes reuse of compliance modules across ecosystems

## Specification

Note: The interface and implementation below can be extended to include KYC levels and other KYC/AML checks as parameters in the isCompliant function. The core idea is to allow the registration of compliance frameworks or sub-proxies within the Universal Compliance Router, each exposing a unified callable selector for a specific category of compliance contracts.The registered sub-router/proxy or compliance contract counts in the Universal Compliance Router should be optimized to reduce the computational cost associated with looping operations.

### High level Architecture

TBD

### Interface

```solidity

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IUniversalComplianceRouter
/// @notice Interface for a modular compliance router supporting general and jurisdiction-aware compliance contracts
interface IUniversalComplianceRouter {
    /// @notice Emitted when a general compliance contract is registered
    /// @param contractAddress The address of the registered contract
    /// @param selector The function selector used for compliance checks
    event GeneralComplianceContractRegistered(address indexed contractAddress, bytes4 selector);

    /// @notice Emitted when a jurisdiction-aware compliance contract is registered
    /// @param contractAddress The address of the registered contract
    /// @param selector The function selector used for compliance checks
    event JurisdictionAwareComplianceContractRegistered(address indexed contractAddress, bytes4 selector);

    /// @notice Emitted when a compliance contract is removed
    /// @param contractAddress The address of the removed contract
    event ComplianceContractRemoved(address indexed contractAddress);

    /// @notice Registers a general compliance contract
    /// @param contractAddress The address of the compliance contract
    /// @param selector The function selector (e.g., isCompliant(address))
    function registerGeneralComplianceContract(address contractAddress, bytes4 selector) external;

    /// @notice Registers a jurisdiction-aware compliance contract
    /// @param contractAddress The address of the compliance contract
    /// @param selector The function selector (e.g., isCompliant(address, bytes32))
    function registerJurisdictionComplianceContract(address contractAddress, bytes4 selector) external;

    /// @notice Removes a compliance contract from the registry
    /// @param contractAddress The address of the contract to remove
    function removeComplianceContract(address contractAddress) external;

    /// @notice Checks if a user is compliant with any general compliance contract
    /// @param user The address of the user to check
    /// @return True if compliant with any general contract, false otherwise
    function isCompliant(address user) external view returns (bool);

    /// @notice Checks if a user is compliant with any jurisdiction-aware compliance contract
    /// @param user The address of the user
    /// @param jurisdiction The jurisdiction identifier (e.g., country code)
    /// @return True if compliant with any jurisdiction-aware contract, false otherwise
    function isCompliant(address user, bytes32 jurisdiction) external view returns (bool);

    /// @notice Returns the number of general compliance contracts
    /// @return The number of general compliance contracts registered
    function getGeneralComplianceContractCount() external view returns (uint);

    /// @notice Returns the number of jurisdiction-aware compliance contracts
    /// @return The number of jurisdiction-aware compliance contracts registered
    function getJurisdictionAwareContractCount() external view returns (uint);
}
```

### Refrence Implmentation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ComplianceRouter
/// @notice A modular router for managing and verifying compliance across general and jurisdiction-aware contracts
contract UniversalComplianceRouter {
    address public owner;

    // Mapping for general compliance contracts: address => function selector
    mapping(address => bytes4) public generalComplianceContracts;
    address[] public generalComplianceContractList;

    // Mapping for jurisdiction-aware compliance contracts: address => function selector
    mapping(address => bytes4) public jurisdictionAwareComplianceContracts;
    address[] public jurisdictionAwareContractList;

    /// @notice Emitted when a general compliance contract is registered
    event GeneralComplianceContractRegistered(address indexed contractAddress, bytes4 selector);

    /// @notice Emitted when a jurisdiction-aware compliance contract is registered
    event JurisdictionAwareComplianceContractRegistered(address indexed contractAddress, bytes4 selector);

    /// @notice Emitted when a compliance contract is removed
    event ComplianceContractRemoved(address indexed contractAddress);

    /// @notice Restricts function access to the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    /// @notice Sets the deployer as the owner
    constructor() {
        owner = msg.sender;
    }

    // ========== REGISTRATION FUNCTIONS ==========

    /// @notice Registers a general compliance contract
    /// @param contractAddress The address of the compliance contract
    /// @param selector The function selector (e.g., isCompliant(address))
    function registerGeneralComplianceContract(address contractAddress, bytes4 selector) external onlyOwner {
        require(contractAddress != address(0), "Invalid address");
        require(generalComplianceContracts[contractAddress] == 0x0, "Already registered");

        generalComplianceContracts[contractAddress] = selector;
        generalComplianceContractList.push(contractAddress);

        emit GeneralComplianceContractRegistered(contractAddress, selector);
    }

    /// @notice Registers a jurisdiction-aware compliance contract
    /// @param contractAddress The address of the compliance contract
    /// @param selector The function selector (e.g., isCompliant(address, bytes32))
    function registerJurisdictionComplianceContract(address contractAddress, bytes4 selector) external onlyOwner {
        require(contractAddress != address(0), "Invalid address");
        require(jurisdictionAwareComplianceContracts[contractAddress] == 0x0, "Already registered");

        jurisdictionAwareComplianceContracts[contractAddress] = selector;
        jurisdictionAwareContractList.push(contractAddress);

        emit JurisdictionAwareComplianceContractRegistered(contractAddress, selector);
    }

    /// @notice Removes a compliance contract from either registry
    /// @param contractAddress The address of the contract to remove
    function removeComplianceContract(address contractAddress) external onlyOwner {
        bool removed = false;

        // Remove from general contracts if present
        if (generalComplianceContracts[contractAddress] != 0x0) {
            delete generalComplianceContracts[contractAddress];
            for (uint i = 0; i < generalComplianceContractList.length; i++) {
                if (generalComplianceContractList[i] == contractAddress) {
                    generalComplianceContractList[i] = generalComplianceContractList[generalComplianceContractList.length - 1];
                    generalComplianceContractList.pop();
                    removed = true;
                    break;
                }
            }
        }

        // Remove from jurisdiction-aware contracts if present
        if (jurisdictionAwareComplianceContracts[contractAddress] != 0x0) {
            delete jurisdictionAwareComplianceContracts[contractAddress];
            for (uint i = 0; i < jurisdictionAwareContractList.length; i++) {
                if (jurisdictionAwareContractList[i] == contractAddress) {
                    jurisdictionAwareContractList[i] = jurisdictionAwareContractList[jurisdictionAwareContractList.length - 1];
                    jurisdictionAwareContractList.pop();
                    removed = true;
                    break;
                }
            }
        }

        if (removed) {
            emit ComplianceContractRemoved(contractAddress);
        }
    }

    // ========== COMPLIANCE CHECK FUNCTIONS ==========

    /// @notice Checks if a user is compliant across all general compliance contracts
    /// @param user The address of the user to check
    /// @return True if compliant with any general contract, false otherwise
    function isCompliant(address user) external view returns (bool) {
        for (uint i = 0; i < generalComplianceContractList.length; i++) {
            address target = generalComplianceContractList[i];
            bytes4 selector = generalComplianceContracts[target];

            (bool success, bytes memory result) = target.staticcall(
                abi.encodeWithSelector(selector, user)
            );

            if (success && result.length == 32 && abi.decode(result, (bool))) {
                return true;
            }
        }
        return false;
    }

    /// @notice Checks if a user is compliant for a specific jurisdiction
    /// @param user The address of the user
    /// @param jurisdiction The jurisdiction identifier (e.g., country code)
    /// @return True if compliant with any jurisdiction-aware contract, false otherwise
    function isCompliant(address user, bytes32 jurisdiction) external view returns (bool) {
        for (uint i = 0; i < jurisdictionAwareContractList.length; i++) {
            address target = jurisdictionAwareContractList[i];
            bytes4 selector = jurisdictionAwareComplianceContracts[target];

            (bool success, bytes memory result) = target.staticcall(
                abi.encodeWithSelector(selector, user, jurisdiction)
            );

            if (success && result.length == 32 && abi.decode(result, (bool))) {
                return true;
            }
        }
        return false;
    }

    // ========== VIEW FUNCTIONS ==========

    /// @notice Returns the number of general compliance contracts
    function getGeneralComplianceContractCount() external view returns (uint) {
        return generalComplianceContractList.length;
    }

    /// @notice Returns the number of jurisdiction-aware compliance contracts
    function getJurisdictionAwareContractCount() external view returns (uint) {
        return jurisdictionAwareContractList.length;
    }
}
```

## Backwards Compatibility

There are no backwards compatibility concerns.

## Security Considerations

TBD

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
