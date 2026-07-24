# Financial Lease Standard — Reference Implementation

Reference implementation of the Financial Lease Standard (see the ERC
draft in `ERCS/`). Includes the core contract, a conversion oracle
interface, a mock index oracle, and a Foundry test suite (8 tests,
including fuzz coverage of the rounding invariants).

## Setup

forge install OpenZeppelin/openzeppelin-contracts
forge test


Built against OpenZeppelin Contracts v5.x.
