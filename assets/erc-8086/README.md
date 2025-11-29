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

## How to Test This Implementation

Due to the ZK-SNARK requirements, there are two ways to verify this implementation:

### Option 1: Use the Live Testnet Deployment (Recommended)

A fully functional deployment is available on **Base Sepolia** testnet:

**🔗 Test Application**: [testnative.zkprotocol.xyz](https://testnative.zkprotocol.xyz/)

**Deployed Contracts** (verified on Basescan):

| Contract | Address | Link |
|----------|---------|------|
| PrivacyTokenFactory | `0x04df6DbAe3BAe8bC91ef3b285d0666d36dda24af` | [View Code](https://sepolia.basescan.org/address/0x04df6DbAe3BAe8bC91ef3b285d0666d36dda24af#code) |
| PrivacyToken (Implementation) | `0xa025070b46a38d5793F491097A6aae1A6109000c` | [View Code](https://sepolia.basescan.org/address/0xa025070b46a38d5793F491097A6aae1A6109000c#code) |
| MintVerifier | `0x1C9260008DA7a12dF2DE2E562dC72b877f4B9a4b` | [View Code](https://sepolia.basescan.org/address/0x1C9260008DA7a12dF2DE2E562dC72b877f4B9a4b#code) |
| MintRolloverVerifier | `0x9423767D08eF34CEC1F1aD384e2884dd24c68f5B` | [View Code](https://sepolia.basescan.org/address/0x9423767D08eF34CEC1F1aD384e2884dd24c68f5B#code) |
| ActiveTransferVerifier | `0x14834a1b1E67977e4ec9a33fc84e58851E21c4Aa` | [View Code](https://sepolia.basescan.org/address/0x14834a1b1E67977e4ec9a33fc84e58851E21c4Aa#code) |
| FinalizedTransferVerifier | `0x1b7c464ed02af392a44CE7881081d1fb1D15b970` | [View Code](https://sepolia.basescan.org/address/0x1b7c464ed02af392a44CE7881081d1fb1D15b970#code) |
| RolloverTransferVerifier | `0x4dd4D44f99Afb3AE4F4e8C03BAdA2Ff84E75f9Cb` | [View Code](https://sepolia.basescan.org/address/0x4dd4D44f99Afb3AE4F4e8C03BAdA2Ff84E75f9Cb#code) |

**Network**: Base Sepolia (Chain ID: 84532)

**Testing Instructions**:
1. Visit [testnative.zkprotocol.xyz](https://testnative.zkprotocol.xyz/)
2. Connect a wallet to Base Sepolia testnet
3. Get test ETH from [Base Sepolia faucet](https://www.alchemy.com/faucets/base-sepolia)
4. Mint privacy tokens
5. Perform privacy transfers
6. Verify transactions on [Base Sepolia explorer](https://sepolia.basescan.org/)

### Option 2: Review Contract Code On-Chain

All contracts are verified on Basescan. You can:
- Read the full source code directly on Basescan
- Verify the bytecode matches the source
- Review all constructor parameters
- Check deployment history
- Inspect transaction history

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
