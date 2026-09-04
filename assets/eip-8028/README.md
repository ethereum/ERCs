# ERC-8028 Reference Implementation

This directory contains a reference implementation for ERC-8028. The following files are organized to help implementers understand the specification.

## Core Contracts

### Data Anchoring Token (DAT)
- [`src/dat/DataAnchoringToken.sol`](src/dat/DataAnchoringToken.sol) - Main implementation
- [`src/dat/DataAnchoringTokenProxy.sol`](src/dat/DataAnchoringTokenProxy.sol) - Proxy contract

### Data Registry
- [`src/dataRegistry/DataRegistry.sol`](src/dataRegistry/DataRegistry.sol) - Main implementation
- [`src/dataRegistry/DataRegistryProxy.sol`](src/dataRegistry/DataRegistryProxy.sol) - Proxy contract
- [`src/dataRegistry/interfaces/IDataRegistry.sol`](src/dataRegistry/interfaces/IDataRegistry.sol) - Interface
- [`src/dataRegistry/interfaces/DataRegistryStorageV1.sol`](src/dataRegistry/interfaces/DataRegistryStorageV1.sol) - Storage layout

### Verified Computing
- [`src/verifiedComputing/VerifiedComputing.sol`](src/verifiedComputing/VerifiedComputing.sol) - Main implementation
- [`src/verifiedComputing/VerifiedComputingProxy.sol`](src/verifiedComputing/VerifiedComputingProxy.sol) - Proxy contract
- [`src/verifiedComputing/interfaces/IVerifiedComputing.sol`](src/verifiedComputing/interfaces/IVerifiedComputing.sol) - Interface
- [`src/verifiedComputing/interfaces/VerifiedComputingStorageV1.sol`](src/verifiedComputing/interfaces/VerifiedComputingStorageV1.sol) - Storage layout

### AI Process
- [`src/process/AIProcess.sol`](src/process/AIProcess.sol) - Main implementation
- [`src/process/AIProcessProxy.sol`](src/process/AIProcessProxy.sol) - Proxy contract
- [`src/process/interfaces/IAIProcess.sol`](src/process/interfaces/IAIProcess.sol) - Interface
- [`src/process/interfaces/AIProcessStorageV1.sol`](src/process/interfaces/AIProcessStorageV1.sol) - Storage layout

### Settlement
- [`src/settlement/Settlement.sol`](src/settlement/Settlement.sol) - Main implementation
- [`src/settlement/SettlementProxy.sol`](src/settlement/SettlementProxy.sol) - Proxy contract
- [`src/settlement/interfaces/ISettlement.sol`](src/settlement/interfaces/ISettlement.sol) - Interface
- [`src/settlement/interfaces/SettlementStorageV1.sol`](src/settlement/interfaces/SettlementStorageV1.sol) - Storage layout

### IDAO
- [`src/idao/IDAO.sol`](src/idao/IDAO.sol) - Main implementation
- [`src/idao/IDAOProxy.sol`](src/idao/IDAOProxy.sol) - Proxy contract
- [`src/idao/interfaces/IIDAO.sol`](src/idao/interfaces/IIDAO.sol) - Interface
- [`src/idao/interfaces/IDAOStorageV1.sol`](src/idao/interfaces/IDAOStorageV1.sol) - Storage layout

## Tests

- [`test/Workflow.t.sol`](test/Workflow.t.sol) - Test suite demonstrating the workflow

## Configuration

- [`foundry.toml`](foundry.toml) - Foundry configuration
- [`remappings.txt`](remappings.txt) - Import remappings
