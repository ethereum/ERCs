# ERC-8086: Privacy Token - Reference Implementation

## ⚠️ Implementation Status

This directory contains the **smart contract implementation** of ERC-8086.

**Note**: Complete end-to-end testing of this standard requires ZK-SNARK circuit artifacts (proving keys, witness generators) which are **not included** in this repository due to size constraints .

### What's Included

- ✅ Core Solidity contracts (production-ready)
- ✅ Interface definitions (IZRC20)
- ✅ Verifier contracts (Groth16)
- ✅ Factory pattern for token deployment
- ✅ Testnet deployment information

### What's NOT Included

- ❌ ZK circuit source code (.circom files)
- ❌ Compiled circuit artifacts (.zkey, .wasm files)
- ❌ Client-side proof generation SDK
- ❌ Unit test suite (requires circuit artifacts)

## Directory Structure

```
erc-8086/
├── README.md                          # This file
├── contracts/
│   ├── interfaces/
│   │   ├── IZRC20.sol                # Core interface (ERC-8086)
│   │   └── IVerifier.sol             # Verifier interfaces
│   └── reference/
│       ├── PrivacyToken.sol          # Reference implementation
│       └── PrivacyTokenFactory.sol   # Factory for token deployment
└── deployments/
    └── base-sepolia.json              # Deployment addresses & config
```

## Implementation Notes

### Architecture

- **Dual-layer Merkle tree**: 16-level active subtree + 20-level finalized tree
- **Total capacity**: 68.7 billion notes (65,536 × 1,048,576)
- **Proof types**:
  - Type 0: Active transfer (both inputs from active subtree)
  - Type 1: Finalized transfer (inputs from finalized tree)
  - Type 2: Rollover transfer (triggers subtree finalization)
- **Gas optimization**: Custom errors, packed storage, ReentrancyGuard

### Key Features

- **Privacy-preserving**: Amounts and recipients hidden via commitments
- **Nullifier-based**: Prevents double-spending
- **Scalable**: Dual-tree architecture supports decades of transactions
- **Flexible**: Supports multiple proof strategies via `proofType` parameter

### Security Features

- ✅ Nullifier uniqueness enforcement
- ✅ Merkle tree integrity (append-only)
- ✅ ZK-SNARK proof verification (Groth16)
- ✅ Reentrancy protection
- ✅ Double-spending prevention
- ✅ Commitment existence checks

## Technical Details

### Cryptographic Parameters

From `deployments/base-sepolia.json`:
- Subtree levels: 16
- Root tree levels: 20
- Subtree capacity: 65,536 notes
- Empty subtree root: `0x2a7c7c9b6ce5880b9f6f228d72bf6a575a526f29c66ecceef8b753d38bba7323`
- Empty finalized root: `0x224ccc25981822d4c5b6fc199fbc74828488741c7151a6159ecfaab7c2a8bac9`

### Compiler Configuration

- Solidity version: 0.8.20
- Optimizer: Enabled (200 runs)
- Via IR: true

## License

CC0-1.0
