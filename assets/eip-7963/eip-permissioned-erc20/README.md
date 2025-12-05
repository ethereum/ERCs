# Oracle-Permissioned ERC-20 Transfers with ZK-Verified Payment Instructions

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This repository provides a reference implementation for EIP-XXXX, a standard for permissioned ERC-20 tokens.

The core idea is an ERC-20 token (`PermissionedERC20.sol`) where standard transfers (`A` to `B`) require validation from an on-chain `TransferOracle.sol`. This oracle verifies off-chain authorizations, attested by RISC Zero ZK proofs, before permitting transfers.

This implementation uses:
*   **Hardhat:** For development, testing, and deployment.
*   **Solidity:** For smart contracts (using OpenZeppelin contracts as base).
*   **RISC Zero:** For the zero-knowledge proof system and verification.
*   **Rust:** For the ZK guest program that validates payment instruction messages.
*   **TypeScript:** For tests and scripts.

## Key Components

1.  **`contracts/PermissionedERC20.sol`**: The ERC-20 token overriding `_update` to check with the oracle.
2.  **`contracts/TransferOracle.sol`**: Manages transfer approvals based on RISC Zero ZK proofs.
3.  **`contracts/verifier/RiscZeroVerifier.sol`**: The RISC Zero verifier contract.
4.  **`zk/methods/guest/src/main.rs`**: The RISC Zero guest program that validates payment instruction messages.
5.  **`zk/methods/guest/src/lib.rs`**: Core verification logic for payment instruction format.
6.  **`zk/host/src/main.rs`**: CLI tool for generating RISC Zero proofs.
7.  **`test/`**: Hardhat tests written in TypeScript.
8.  **`scripts/`**: Deployment and interaction scripts using Hardhat.

## Prerequisites

*   [Node.js](https://nodejs.org/) (v18+ recommended)
*   [npm](https://www.npmjs.com/) or [yarn](https://yarnpkg.com/)
*   [Rust](https://rustup.rs/) (for RISC Zero development)
*   [RISC Zero toolchain](https://dev.risczero.com/api/zkvm/install) (`rzup` installer)

## Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/YOUR_USERNAME/eip-permissioned-erc20.git # Replace with your actual repository URL
    cd eip-permissioned-erc20
    ```
2.  Install Node.js dependencies:
    ```bash
    npm install
    ```
3.  Install RISC Zero toolchain:
    ```bash
    curl -L https://risczero.com/install | bash
    rzup install
    ```

## Usage

### Build Everything

```bash
npm run build
```

This will:
- Compile Solidity contracts
- Build the RISC Zero workspace (guest program + host CLI)

### Build Components Separately

```bash
# Compile Solidity contracts only
npm run build:contracts

# Build RISC Zero workspace only  
npm run build:zk
```

### Run Tests

```bash
# Run all tests (smart contracts + ZK proofs)
npm test

# Run only smart contract tests
npm run test:contracts

# Run only ZK proof tests
npm run test:zk
```

**Current Test Status:**
- **Smart Contract Tests**: 80 passing, 3 pending
- **ZK Proof Tests**: 34 passing (unit tests), 11 integration tests

### Generate RISC Zero Proofs

```bash
# Generate a proof using the CLI tool
cd zk
cargo run --bin host -- --input sample_input.json --output proof_output.json

# Or use the npm script
npm run prove:risc0 -- --input sample_input.json --output proof_output.json
```

### Code Formatting & Linting

*   Format all code (Solidity & TypeScript):
    ```bash
    npm run format
    ```
*   Check formatting and lint Solidity:
    ```bash
    npm run lint
    ```

### Run Local Hardhat Node

```bash
npx hardhat node
```

### Deploy to Local Node

(Ensure a local node is running first)

```bash
npm run deploy:local
# or
npx hardhat run scripts/deploy.ts --network localhost
```

## RISC Zero Integration

This project has been migrated from Circom to RISC Zero for improved performance and developer experience. The RISC Zero guest program validates payment instruction messages with the following features:

- **Merkle Proof Verification**: Ensures all fields belong to the same committed message
- **Hash Validation**: Verifies debtor, creditor, currency, and amount integrity  
- **Range Checking**: Validates amounts are within specified bounds
- **Expiry Validation**: Checks execution date consistency
- **Privacy Preservation**: Only reveals necessary public outputs

### Key Benefits of RISC Zero Migration

- **Better Performance**: Faster proof generation compared to Circom
- **Easier Development**: Write verification logic in Rust instead of circuit constraints
- **No Trusted Setup**: RISC Zero uses transparent setup (no ceremony required)
- **Better Tooling**: Integrated debugging and testing capabilities
- **Flexible Logic**: Easy to modify verification rules without circuit redesign

## Documentation

*   **Test Plan:** `tests/UnitTests.md`
*   **EIP Walkthrough:** `docs/EIP-walkthrough.md`
*   **RISC Zero Details:** `zk/README.md`
*   **Migration Guide:** `circuits/README.md` (documents the Circom → RISC Zero migration)

## Development Workflow

1. **Modify verification logic**: Edit `zk/methods/guest/src/lib.rs`
2. **Test guest program**: Run `cd zk && cargo test`
3. **Generate proofs**: Use `cargo run --bin host` or npm scripts
4. **Test contracts**: Run `npm test` for full integration tests
5. **Deploy**: Use `npm run deploy:local` for local testing

## License

This reference implementation is part of ERC-7963 and is released under CC0 (public domain).
