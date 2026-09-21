# ERC-8187 Token Puller — Reference Implementation

Reference implementation for Token Puller, a standardized interface for permissioned, on-demand token pulls with custom sourcing logic, permit support, and allowance delegation.

## Overview

A **Puller** contract acts as an intermediary that:

- Manages pull allowances granted by owners to spenders
- Executes custom sourcing logic to obtain tokens (e.g., withdrawing from a vault)
- Transfers the sourced tokens to a requested destination
- Supports EIP-712 signed permits and allowance delegation

## Project Structure

```
contracts/
├── interfaces/IPuller.sol         — Full ERC-8187 interface with natspec docs
├── base/BasePuller.sol            — Abstract base: approvals, EIP-712 permits, allowance delegation
└── pullers/ERC4626Puller.sol      — Sources tokens via ERC-4626 vault withdrawal
```

### IPuller

The interface defining all events (`PullApproval`, `TokensPulled`, `TransferPullAllowance`) and functions (`approvePull`, `pullFrom`, `pullAllowance`, `maxPullable`, `transferPullAllowance`, `permitPull`, `pullFromWithPermit`, `eip712Domain`, `nonces`)

See [IPuller.sol](./contracts/interfaces/IPuller.sol).

### BasePuller

Abstract base contract implementing:

- Allowance storage and consumption with infinite-allowance skip
- `transferPullAllowance` with special infinite-allowance transfer and renunciation (`toSpender == address(0)`)
- `permitPull` via EIP-712 (`ECDSA.recoverCalldata` for EOA signatures)
    - **TODO**: Support for ERC-6492 (universal signature validation) and ERC-1271 (smart contract wallets)
- `pullFromWithPermit` with front-run DoS protection (silent permit failure fallback)
- Abstract `_sourceTokens(address token, address owner, address to, uint256 amount)` and `maxPullable`

Uses OpenZeppelin's `EIP712` for domain separators, `ECDSA` for signature recovery, and `SafeERC20` for token transfers.

See [BasePuller.sol](./contracts/base/BasePuller.sol).

### ERC4626Puller

Concrete puller paired with a single ERC-4626 vault. Its `_sourceTokens` calls `vault.withdraw(amount, to, owner)` — the vault's own ERC-20 allowance mechanism consumes the owner's share approval, burns shares, and sends the underlying asset directly to the destination.

See [ERC4626Puller.sol](./contracts/pullers/ERC4626Puller.sol).
