# SDC Solidity implementation

## Description

The reference SDC implementation can be unit tested with Hardhat to understand the trade process logic.

### Compile and run tests with Hardhat

We provide the essential steps to compile the contracts and run the provided unit tests.

### Provided Contracts and Tests

#### Interfaces

- `contracts/ISDC.sol` - Interface contract (aggregation of `ISDCTrade`, `ISDCSettlement`, `IAsyncTransferCallback`)
- `contracts/ISDCTrade.sol` - Interface related to trade incept/confirm/terminate
- `contracts/ISDCSettlement.sol` - Interface related to settlement initiate/perform/after
- `contracts/IAsyncTransferCallback.sol` - Interface related to transfer.

- `contracts/IAsyncTransfer.sol` - Interface (extending the ERC-20) for settlement tokens used in `SDCPledgedBalance`.

#### Implementations

- `contracts/SDCSingleTrade.sol` - SDC abstract contract for an OTC Derivative (single trade case only)
- `contracts/SDCSingleTradePledgedBalance.sol` - SDC full implementation for an OTC Derivative (single trade case only)
- `contracts/ERC20Settlement.sol` - Mintable settlement token contract implementing `IERC20Settlement` for unit tests

#### Tests

- `test/SDCTests.js` - Unit tests for the life-cycle of the sdc implementation

### Compile and run tests with Hardhat

Install dependencies:
```shell
npm i
```

Compile:
```shell
npx hardhat compile
```

Run all tests:
```shell
npx hardhat test
```

### Configuration files

- `package.js` - Javascript package definition.
- `hardhat.config.js` - Hardhat config.

### Used javascript-based testing libraries for solidity

- `ethereum-waffle`: Waffle is a Solidity testing library. It allows you to write tests for your contracts with JavaScript.
- `chai`: Chai is an assertion library and provides functions like expect.
- `ethers`: This is a popular Ethereum client library. It allows you to interface with blockchains that implement the Ethereum API.
- `solidity-coverage`: This library gives you coverage reports on unit tests with the help of Istanbul.

## Version history / release notes

### 0.8.0

- Re-introduced the method `afterSettlement` that can be used to check pre-conditions of the next settlement cycle, e.g., triggered by a time-oracle.
- Added the event `SettlementAwaitingInitiation` which should be issued when the trade goes active and when `afterSettlement` veryfied that the trade is ready for the next settlement.
