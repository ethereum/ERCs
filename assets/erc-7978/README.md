# ERC-7978: Non-Fungible Account Tokens

Reference implementation of Non-Fungible Account Tokens (NFATs) - NFTs that control smart wallets.

## Overview

NFATs are ERC-721 tokens whose metadata embeds smart wallet addresses. Transferring the NFT transfers control of the wallet through an immutable validator module.

## Architecture

```
┌─────────────┐    mints     ┌──────────────┐
│ NFATFactory │ ────────────► │     NFAT     │
└─────────────┘              │   (ERC-721)  │
       │                     └──────────────┘
       │ deploys                     │ controls
       ▼                             ▼
┌─────────────┐              ┌──────────────┐
│   NBA       │ ◄─validates─ │ NFTBound     │
│ (ERC-7579)  │              │  Validator   │
└─────────────┘              └──────────────┘
```

## Components

### Core Contracts
- `NFATFactory.sol` - Abstract factory for minting NFATs and deploying wallets
- `NFTBoundValidator.sol` - Abstract validator checking NFT ownership
- `ECDSANFTBoundValidator.sol` - Concrete ECDSA implementation

### Interfaces
- `INFATFactory.sol` - Factory interface
- `INFTBoundValidator.sol` - Validator interface

## Implementation Pattern

### Abstract Factory
The `NFATFactory` provides the core NFAT logic while delegating wallet deployment to existing ERC-7579 factories:

```solidity
abstract contract NFATFactory is ERC721, INFATFactory {
    // Core NFAT logic: minting, metadata, transfers
    
    function _deployWallet(uint256 tokenId, bytes calldata data) 
        internal virtual returns (address);
        
    function _initializeValidator(address wallet, uint256 tokenId) 
        internal virtual;
}
```

### Concrete Examples
Concrete factories would integrate with specific wallet implementations:

- **KernelNFATFactory**: Uses Kernel v3 factory
- **BiconomyNFATFactory**: Uses Biconomy smart account factory  
- **SafeNFATFactory**: Uses Safe{Core} account factory
- **NexusNFATFactory**: Uses Nexus modular account factory

### Abstract Validator
The `NFTBoundValidator` handles NFT ownership validation while delegating signature verification:

```solidity
abstract contract NFTBoundValidator is INFTBoundValidator {
    // NFT ownership checking logic
    
    function _validateSignature(bytes32 hash, bytes calldata signature) 
        internal view virtual returns (address signer);
}
```

## Key Features

- ✅ **Wallet-Agnostic**: Works with any ERC-7579 implementation
- ✅ **Atomic Operations**: Mint NFT + deploy wallet in single transaction
- ✅ **Deterministic Addresses**: CREATE2-based wallet deployment
- ✅ **Module Reset**: Clean ownership transitions
- ✅ **Self-Transfer Protection**: Prevents wallet deadlock
- ✅ **Metadata Embedding**: No external registries required

## Usage Example

```solidity
// Deploy components
ECDSANFTBoundValidator validator = new ECDSANFTBoundValidator();
ConcreteNFATFactory factory = new ConcreteNFATFactory(
    "MyNFATs", 
    "NFAT", 
    address(validator),
    kernelFactory,
    kernelImplementation
);

// Mint NFAT + deploy wallet
(uint256 tokenId, address wallet) = factory.mint{value: 0.1 ether}("");

// Wallet address is deterministic
address computed = factory.getAccountAddress(tokenId);
assert(wallet == computed);

// Transfer NFT = transfer wallet control
factory.transferFrom(owner, newOwner, tokenId);
```

## Security Model

| Feature | Purpose |
|---------|---------|
| **Immutable Validator** | Prevents ownership bypass attacks |
| **Module Reset** | Prevents previous owner access via stale modules |
| **Self-Transfer Lock** | Prevents irreversible NFT → wallet deadlock |
| **Deterministic Deployment** | Enables pre-computation and validation |

## Integration Paths

1. **New Projects**: Deploy concrete factory + validator
2. **Existing NFTs**: Create NFAT wrapper referencing original token
3. **Wallet Providers**: Add NFAT factory to existing ERC-7579 deployment
4. **Marketplaces**: Standard NFT trading enables wallet ownership transfer

## License

CC0-1.0