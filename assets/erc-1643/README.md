# ERC-1643 Reference Implementation (ERC-20 + ERC-721)

Reference implementation of the ERC-1643 document management standard attached to both ERC-20 and ERC-721 token modules.

## Security Notice

This repository is a reference implementation and **has not been audited**. Do not use in production without an independent security review.

## Overview

This implementation provides:

- `IERC1643` interface per `erc-1643.md`
- Reusable `ERC1643` module with OpenZeppelin `Ownable` access control
- `ERC20DocumentToken` example attaching ERC-1643 to ERC-20
- `ERC721DocumentToken` example attaching ERC-1643 to ERC-721

`setDocument` and `removeDocument` are owner-restricted. Enumeration is maintained with O(1) removal (swap-and-pop + index mapping).

## Contracts

- `src/erc-1643/IERC1643.sol`
- `src/erc-1643/ERC1643.sol`
- `src/ERC20DocumentToken.sol`
- `src/ERC721DocumentToken.sol`

## ERC-1643 Behavior Implemented

- `getDocument(bytes32)` returns `(uri, documentHash, lastModified)` and returns empty values for missing docs
- `setDocument(bytes32,string,bytes32)` creates or updates entries and emits `DocumentUpdated`
- `removeDocument(bytes32)` removes entries, reverts if missing, and emits `DocumentRemoved`
- `getAllDocuments()` returns active document names only

## Build and Test

```bash
forge build
forge test
```

## Tooling Versions

- Foundry config (`foundry.toml`):
  - `solc = "0.8.34"`
  - `evm_version = "prague"`
- OpenZeppelin Contracts: `v5.6.1` (`lib/openzeppelin-contracts`)

## Static Analysis

- This project can be analyzed with **Aderyn** (smart contract static analyzer): [https://github.com/Cyfrin/aderyn](https://github.com/Cyfrin/aderyn)
- If you generate an Aderyn report for this repository, store or reference it in the `doc/` folder (for example `doc/aderyn-report.md`).

## Deployment Security Warning

- The deployment script reads `PRIVATE_KEY` from an environment variable for convenience.
- Storing raw private keys in environment variables is **not secure** for production usage.
- Prefer safer signer flows (hardware wallets, keystores, multisig/deployment relayers, or dedicated secret managers).

## Notes

- Document identifiers are `bytes32`; callers should use deterministic naming conventions.
- Document content is expected to be off-chain and integrity-checked via `documentHash`.
