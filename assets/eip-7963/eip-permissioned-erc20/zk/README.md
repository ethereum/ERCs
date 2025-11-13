# RISC Zero Implementation for EIP Permissioned ERC-20

This directory contains the RISC Zero implementation for validating payment instruction payment instruction messages in the EIP Permissioned ERC-20 project.

## Overview

This RISC Zero workspace replaces the previous Circom-based proving system with a more efficient and developer-friendly Rust implementation. The guest program validates payment instruction messages and generates zero-knowledge proofs that can be verified on-chain by the TransferOracle contract.

## Key Features

- **ISO 20022 Validation**: Validates payment instruction payment instruction format
- **Merkle Proof Verification**: Ensures all fields belong to the same committed message
- **Privacy Preservation**: Only reveals necessary public outputs while keeping sensitive data private
- **No Trusted Setup**: Uses RISC Zero's transparent proving system
- **Efficient Verification**: Optimized for on-chain verification costs

## Directory Structure

```text
zk/
├── Cargo.toml                     # Workspace configuration
├── host/                          # Host program (proof generation CLI)
│   ├── Cargo.toml
│   └── src/
│       └── main.rs               # CLI tool for generating proofs
├── methods/                       # Guest program and build configuration
│   ├── Cargo.toml
│   ├── build.rs                  # Build script for guest program
│   ├── guest/                    # Guest program source
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── main.rs          # Guest program entry point
│   │   │   └── lib.rs           # Core verification logic
│   └── src/
│       └── lib.rs               # Method exports and constants
└── test-utils/                   # Testing utilities and integration tests
    ├── Cargo.toml
    ├── src/
    │   ├── lib.rs                # Library exports and configuration
    │   ├── payment_instruction_generator.rs  # Test data generation
    │   ├── test_helpers.rs       # Testing utilities
    │   ├── crypto_utils.rs       # Cryptographic utilities
    │   ├── merkle_tree.rs        # Merkle tree implementation
    │   ├── proof_validator.rs    # Proof validation helpers
    │   ├── guest_logic.rs        # Guest program logic tests
    │   ├── mock_data.rs          # Mock data generators
    │   └── integration.rs        # Integration test framework
    ├── tests/                    # Comprehensive test suite
    │   ├── phase2_core_tests.rs  # Core functionality tests
    │   └── phase3_integration_tests.rs # Integration tests
    └── examples/                 # CLI examples and demos
        ├── payment_instruction_demo.rs       # Basic proof generation demo
        ├── phase2_cli.rs         # Core testing CLI
        └── phase3_cli.rs         # Integration testing CLI
```

## Quick Start

### Prerequisites

- [Rust](https://rustup.rs/) (latest stable)
- [RISC Zero toolchain](https://dev.risczero.com/api/zkvm/install)

### Installation

```bash
# Install RISC Zero toolchain
curl -L https://risczero.com/install | bash
rzup install

# Build the workspace
cargo build --release
```

### Generate a Proof

```bash
# Generate proof with sample data
cargo run --bin host -- --input examples/sample_usd.json --output proof_output.json

# View the generated proof
cat proof_output.json
```

### Run Tests

```bash
# Run all tests (34 unit tests + integration tests)
cargo test

# Run only library unit tests
cargo test --package test-utils --lib

# Run specific test files
cargo test --test phase2_core_tests
cargo test --test phase3_integration_tests

# Run with output to see details
cargo test -- --nocapture

# Run CLI examples for interactive testing
cargo run --example payment_instruction_demo
cargo run --example phase2_cli
cargo run --example phase3_cli demo
```

**Current Test Status:**
- **Unit Tests**: 34 passing (0 failed, 0 ignored)
- **Integration Tests**: 11 functional tests (1 runs by default, 10 ignored for performance)
- **CLI Examples**: 3 working examples with various demo modes

## Guest Program Logic

The guest program (`methods/guest/src/lib.rs`) performs comprehensive validation of payment instruction messages:

### 1. Hash Verification
- Validates debtor (sender) data hash
- Validates creditor (recipient) data hash  
- Validates currency hash
- Uses Keccak256 for compatibility with Ethereum

### 2. Amount Validation
- Ensures transfer amount is within specified bounds
- Validates min_amount ≤ actual_amount ≤ max_amount
- Prevents amount manipulation attacks

### 3. Expiry Validation
- Checks execution date consistency
- Converts ISO date format to timestamp
- Ensures message hasn't expired

### 4. Merkle Proof Verification
Verifies 5 separate Merkle proofs to ensure all fields belong to the same committed message:
- **Debtor proof**: Proves sender data integrity
- **Creditor proof**: Proves recipient data integrity
- **Amount proof**: Proves amount data integrity
- **Currency proof**: Proves currency data integrity
- **Expiry proof**: Proves execution date integrity

### Input/Output Format

**Private Inputs (hidden in proof):**
```rust
pub struct PaymentInstructionInput {
    // Public commitments
    pub root: [u8; 32],
    pub debtor_hash: [u8; 32],
    pub creditor_hash: [u8; 32],
    pub min_amount_milli: u64,
    pub max_amount_milli: u64,
    pub currency_hash: [u8; 32],
    pub expiry: u64,
    
    // Private data
    pub debtor_data: String,          // Raw JSON
    pub creditor_data: String,        // Raw JSON
    pub amount_value: u64,            // Exact amount
    pub currency: String,             // Currency code
    pub execution_date: String,       // ISO date
    
    // Merkle proofs (5 separate proofs)
    pub debtor_proof_siblings: Vec<[u8; 32]>,
    pub debtor_proof_directions: Vec<u8>,
    // ... similar for creditor, amount, currency, expiry
}
```

**Public Outputs (committed to blockchain):**
```rust
pub struct PaymentInstructionOutput {
    pub root: [u8; 32],               // Message commitment
    pub debtor_hash: [u8; 32],        // Sender hash
    pub creditor_hash: [u8; 32],      // Recipient hash
    pub min_amount_milli: u64,        // Amount range min
    pub max_amount_milli: u64,        // Amount range max
    pub currency_hash: [u8; 32],      // Currency hash
    pub expiry: u64,                  // Expiry timestamp
}
```

## Host CLI Usage

The host program provides a command-line interface for generating proofs:

```bash
# Basic usage
cargo run --bin host -- --input <input.json> --output <output.json>

# Example with sample data
cargo run --bin host -- \
  --input examples/sample_usd.json \
  --output proof_usd.json

# View help
cargo run --bin host -- --help
```

### Input File Format

```json
{
  "root": "0x1234...",
  "debtor_hash": "0x5678...",
  "creditor_hash": "0x9abc...",
  "min_amount_milli": 50000,
  "max_amount_milli": 150000,
  "currency_hash": "0xdef0...",
  "expiry": 20241215,
  "debtor_data": "{\"name\":\"John Smith\",\"account\":\"12345\"}",
  "creditor_data": "{\"name\":\"Alice Johnson\",\"account\":\"67890\"}",
  "amount_value": 100000,
  "currency": "USD",
  "execution_date": "2024-12-15",
  "debtor_proof_siblings": ["0x..."],
  "debtor_proof_directions": [0, 1],
  // ... other Merkle proof data
}
```

### Output File Format

```json
{
  "proof": "0x...",           // RISC Zero proof bytes
  "journal_hash": "0x...",    // Hash of public outputs
  "seal_hash": "0x...",       // Hash of the proof
  "public_outputs": {         // The committed public data
    "root": "0x...",
    "debtor_hash": "0x...",
    "creditor_hash": "0x...",
    "min_amount_milli": 50000,
    "max_amount_milli": 150000,
    "currency_hash": "0x...",
    "expiry": 20241215
  }
}
```

## Integration Testing

The `test-utils` package provides comprehensive testing infrastructure:

### Test Categories

1. **Unit Tests**: Individual function validation (34 tests)
2. **Core Tests**: End-to-end guest program validation (phase2_core_tests.rs)
3. **Integration Tests**: Full proof generation and verification pipeline (phase3_integration_tests.rs)
4. **CLI Demos**: Interactive testing and demonstration tools

### Test Structure

```bash
# Phase 2: Core functionality tests
cargo test --test phase2_core_tests
# Tests: guest program validation, proof generation, data integrity

# Phase 3: Integration tests  
cargo test --test phase3_integration_tests
# Tests: E2E workflows, performance validation, stress testing

# Interactive CLI testing
cargo run --example phase3_cli e2e       # End-to-end test
cargo run --example phase3_cli batch 5   # Batch processing
cargo run --example phase3_cli stress    # Stress testing
cargo run --example phase3_cli demo      # Full demo
```

### Integration Test Features

The integration tests include:
- **E2E Pipeline Testing**: Complete proof generation and verification workflows
- **Performance Validation**: Timing and memory usage analysis
- **Batch Processing**: Multi-proof generation testing
- **Stress Testing**: High-load scenarios with 20+ concurrent proofs
- **ISO 20022 Compliance**: Format validation for USD, EUR, SGD currencies
- **Error Handling**: Invalid input scenarios and edge cases

## Performance Characteristics

### Proof Generation
- **Time**: ~5-30 seconds depending on complexity
- **Memory**: ~1-2GB RAM required
- **CPU**: Benefits from multiple cores

### On-Chain Verification
- **Gas Cost**: ~200-400k gas for verification
- **Verification Time**: ~1-2 seconds on-chain
- **Proof Size**: ~1-2KB proof data

## Development Workflow

1. **Modify Guest Logic**: Edit `methods/guest/src/lib.rs`
2. **Test Changes**: Run `cargo test`
3. **Generate Test Proofs**: Use `cargo run --bin host`
4. **Integration Testing**: Run full test suite
5. **Performance Validation**: Check gas costs and timing

## Migration from Circom

This RISC Zero implementation replaces the previous Circom-based system with significant improvements:

### Benefits
- **Faster Development**: Write logic in Rust instead of circuit constraints
- **Better Performance**: More efficient proof generation
- **No Trusted Setup**: Transparent cryptographic assumptions
- **Easier Debugging**: Standard Rust tooling works
- **Flexible Logic**: Easy to modify verification rules

### Migration Process
1. ✅ Converted Circom constraints to Rust functions
2. ✅ Implemented Merkle proof verification
3. ✅ Added comprehensive test suite
4. ✅ Updated smart contracts for RISC Zero format
5. ✅ Performance optimization and validation

## Security Considerations

- **Guest Program Correctness**: All validation logic must be implemented correctly
- **Merkle Tree Integrity**: Ensures fields belong to the same message
- **Hash Function Security**: Uses Keccak256 for Ethereum compatibility
- **Replay Protection**: Proof IDs prevent reuse of the same authorization
- **Input Validation**: Comprehensive bounds checking and format validation

## Troubleshooting

### Common Issues

1. **Build Failures**: Ensure RISC Zero toolchain is installed and up-to-date
2. **Proof Generation Errors**: Check input JSON format and field validation
3. **Test Failures**: Verify all dependencies are installed correctly
4. **Performance Issues**: Ensure sufficient RAM and CPU resources

### Debug Mode

```bash
# Run in development mode for faster iteration
RISC0_DEV_MODE=1 cargo run --bin host -- --input sample.json --output proof.json

# Enable detailed logging
RUST_LOG=debug cargo run --bin host -- --input sample.json --output proof.json
```

## Contributing

When modifying the guest program:

1. Ensure all tests pass: `cargo test`
2. Add tests for new functionality
3. Update documentation for API changes
4. Verify gas cost implications
5. Test with various input formats

## Resources

- [RISC Zero Documentation](https://dev.risczero.com/)
- [RISC Zero Examples](https://github.com/risc0/risc0/tree/main/examples)
- [Payment Instruction Specification](https://www.iso20022.org/)
- [ERC-7963 Specification](https://eips.ethereum.org/EIPS/eip-7963)
