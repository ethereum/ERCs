# ERC-8085: Dual-Mode Fungible Tokens - Reference Implementation

## ⚠️ Implementation Status

This directory contains the **smart contract implementation** of ERC-8085.

**Note**: Complete end-to-end testing of this standard requires ZK-SNARK circuit artifacts (proving keys, witness generators) which are **not included** in this repository due to size constraints.

### What's Included

- ✅ Core Solidity contracts
- ✅ Interface definitions (IDualModeToken, IZRC20)
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
erc-8085/
├── README.md                          # This file
├── contracts/
│   ├── interfaces/
│   │   ├── IDualModeToken.sol        # Core interface (ERC-8085)
│   │   └── IZRC20.sol                # Privacy interface (ERC-8086)
│   └── reference/
│       ├── PrivacyToken.sol          # ERC-8086 base layer (abstract)
│       ├── DualModeToken.sol         # ERC-8085 implementation
│       └── DualModeTokenFactory.sol  # Factory for token deployment
└── deployments/
    ├── base-sepolia.json             
```

## How to Test This Implementation

Due to the ZK-SNARK requirements, there are two ways to verify this implementation:

### Option 1: Use the Live Testnet Deployment (Recommended)

A fully functional deployment is available on **Base Sepolia** testnet:

**🔗 Test Application**: [testdmt.zkprotocol.xyz](https://testdmt.zkprotocol.xyz/)

**Deployed Contracts** (Latest - December 2025):

| Contract | Address | Link |
|----------|---------|------|
| DualModeTokenFactory | `0x64EeF485F82918bBf61dd5349300F5a84f907140` | [View Code](https://sepolia.basescan.org/address/0x64EeF485F82918bBf61dd5349300F5a84f907140#code) |
| DualModeToken (Implementation) | `0xd8714b3E2B490585c22d5a7a030f3946e46940c4` | [View Code](https://sepolia.basescan.org/address/0xd8714b3E2B490585c22d5a7a030f3946e46940c4#code) |
| MintVerifier | `0x0C9F3208b44d26B7e5D0ab145d49b050F5C7fFa5` | [View Code](https://sepolia.basescan.org/address/0x0C9F3208b44d26B7e5D0ab145d49b050F5C7fFa5#code) |
| MintRolloverVerifier | `0x8F1C5De7b7193B0Ce1E9886E5f1c58aE3A5491dF` | [View Code](https://sepolia.basescan.org/address/0x8F1C5De7b7193B0Ce1E9886E5f1c58aE3A5491dF#code) |
| ActiveTransferVerifier | `0x791cd059fA2b4B2d4015408eF6624BBD2F80d50E` | [View Code](https://sepolia.basescan.org/address/0x791cd059fA2b4B2d4015408eF6624BBD2F80d50E#code) |
| FinalizedTransferVerifier | `0x96Bb15bE0a79C1f17dFed17b9D57c3DE1C5eA205` | [View Code](https://sepolia.basescan.org/address/0x96Bb15bE0a79C1f17dFed17b9D57c3DE1C5eA205#code) |
| RolloverTransferVerifier | `0xEB85CA2d80da109fe9348a9B17F2E683BEaa4a07` | [View Code](https://sepolia.basescan.org/address/0xEB85CA2d80da109fe9348a9B17F2E683BEaa4a07#code) |

**Network**: Base Sepolia (Chain ID: 84532)

**Testing Instructions**:
1. Visit [testdmt.zkprotocol.xyz](https://testdmt.zkprotocol.xyz/)
2. Connect a wallet to Base Sepolia testnet
3. Get test ETH from [Base Sepolia faucet](https://www.alchemy.com/faucets/base-sepolia)
4. Mint public tokens (ERC-20)
5. Convert to privacy mode: `toPrivacy()`
6. Perform privacy transfers
7. Convert back to public: `toPublic()`
8. Verify transactions on [Base Sepolia explorer](https://sepolia.basescan.org/)

### Option 2: Review Contract Code On-Chain

All contracts are verified on Basescan. You can:
- Read the full source code directly on Basescan
- Verify the bytecode matches the source
- Review all constructor parameters
- Check deployment history
- Inspect transaction history

## Implementation Notes

### Architecture

ERC-8085 uses a layered design (updated December 2025):
```
DualModeToken.sol (ERC-8085)
  ├─ Public Mode: ERC-20 (OpenZeppelin)
  ├─ Mode Conversion: toPrivacy() / toPublic()
  └─ Extends: PrivacyToken.sol (ERC-8086 base layer)
       └─ Privacy Mode: IZRC20 compatible
```

- **PrivacyToken.sol**: Abstract base contract implementing ERC-8086
- **DualModeToken.sol**: Extends PrivacyToken with ERC-8085 mode conversion

### Key Design Decisions

1. **Unified Supply**: `totalSupply() = ERC20.totalSupply() + privacyTotalSupply`
2. **Direct Privacy Mint Disabled**: Tokens must enter via public mode first
3. **BURN_ADDRESS Enforcement**: Ensures privacy-to-public conversion security
4. **Supply Invariant**: Total supply remains constant during mode conversions

### Dual-Layer Merkle Tree (Privacy Mode)

- **Active subtree**: 16 levels (65,536 notes)
- **Finalized tree**: 20 levels (1,048,576 subtrees)
- **Total capacity**: 68.7 billion notes

### Mode Conversion Flow

**Public → Privacy** (`toPrivacy`):
```solidity
1. User holds 100 ERC-20 tokens
2. Calls toPrivacy(100, proof, encryptedNote)
3. Contract burns 100 ERC-20 tokens
4. Contract creates privacy commitment (ZK proof verified)
5. Result: -100 public, +100 privacy, totalSupply unchanged
```

**Privacy → Public** (`toPublic`):
```solidity
1. User holds 100 in privacy mode
2. Calls toPublic(recipient, proof, encryptedNotes)
3. Contract verifies first output → BURN_ADDRESS
4. Contract mints 100 ERC-20 tokens to recipient
5. Result: -100 privacy, +100 public, totalSupply unchanged
```

### Security Features

- ✅ BURN_ADDRESS enforcement (prevents double-spending across modes)
- ✅ Supply invariant maintenance
- ✅ Nullifier uniqueness enforcement
- ✅ Merkle tree integrity (append-only)
- ✅ ZK-SNARK proof verification (Groth16)
- ✅ Reentrancy protection
- ✅ Mode isolation (public/privacy balances cryptographically separated)

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

### BURN_ADDRESS Constants

Used in `toPublic()` verification:
```solidity
BURN_ADDRESS_X = 3782696719816812986959462081646797447108674627635188387134949121808249992769
BURN_ADDRESS_Y = 10281180275793753078781257082583594598751421619807573114845203265637415315067
```

This is an unspendable point, ensuring converted values cannot be double-spent.

## Use Cases

| Scenario | Public Mode | Privacy Mode |
|----------|-------------|--------------|
| **DAO Governance** | Treasury management, grant distributions | Anonymous voting, private delegation |
| **DeFi Trading** | DEX liquidity, staking | Long-term holdings, OTC transfers |
| **Business Tokens** | Investor reporting, compliance | Employee compensation, strategic reserves |

## License

CC0-1.0
