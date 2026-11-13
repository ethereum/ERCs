---
eip: 7777
title: SuperFuse — Atomic Liquidity Booster
author: Ali Boulkemh (@BoulkemhA)
discussions-to: https://twitter.com/BoulkemhA
status: Draft
type: Standards Track
category: ERC
created: 2025-10-11
requires: ERC-20
---

## Simple Summary
A new DeFi standard that allows atomic fusion of multiple liquidity operations — swapping, vault movement, and liquidity provision — in one secure transaction.

---

## Abstract
**EIP-7777: SuperFuse** introduces a unified smart-contract interface that lets protocols and users execute complex DeFi flows atomically.  
It reduces gas costs and eliminates multi-transaction complexity while maintaining compatibility with ERC-20 and standard DEX routers.

---

## Motivation
Most DeFi protocols require users to manually execute multiple steps:
1. Withdraw tokens from a vault  
2. Swap tokens on a DEX  
3. Add liquidity or re-deposit into a vault  

This approach is inefficient and expensive.  
SuperFuse standardizes the process into one atomic transaction, improving composability, efficiency, and UX.

---

## Specification

### Interface
```solidity
function superFuse(
    address vault,
    address router,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minOut,
    address[] calldata path,
    bool fromVault,
    bool toVault,
    uint256 deadline
) external nonReentrant;
```

### Behavior
1. If `fromVault` is true, withdraws from the vault.  
2. Executes token swap via the specified router using the provided path.  
3. Optionally deposits output into the vault if `toVault` is true.  
4. Emits structured events for transparency.

### Events
```solidity
event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
event VaultInteraction(address indexed vault, address indexed user, bool fromVault, bool toVault);
```

---

## Rationale
By merging vault, swap, and liquidity operations into one atomic action,  
SuperFuse simplifies DeFi interactions and allows developers to compose complex flows safely and cheaply.  
This pattern also enables on-chain strategies, smart wallets, and DeFi aggregators to become more gas-efficient.

---

## Reference Implementation
BNB Smart Chain Testnet deployment example:

| Component | Address |
|------------|----------|
| Router | `0x9ac64cc6e4415144c455bd8e4837fea55603e5c3` |
| Vault | `0x0000000000000000000000000000000000000000` |
| TokenA | `0xYourTokenAAddress` |
| TokenB | `0xYourTokenBAddress` |
| SuperFuse | `0xYourSuperFuseAddress` |

---

## Security Considerations
- Implements ReentrancyGuard protection.  
- Relies only on verified DEX router contracts.  
- Deadline parameter prevents delayed execution.  
- Requires token approval for ERC-20 transfers.

---

## Backward Compatibility
Fully compatible with existing ERC-20 tokens and Uniswap-style routers.

---

## Copyright
Copyright and related rights waived via  
[CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/).
