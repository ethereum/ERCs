# ERC-8512 Reference Implementation & Test Vectors

Reference Solidity contracts, zero-dependency Node.js off-chain library, deterministic test vectors, tests, and offline walkthrough for **ERC-8512: GPU Collateral Evidence**.

## How to Run

From `assets/erc-8512/`:

```bash
# 0. Once: fetch forge-std (not vendored here)
forge install foundry-rs/forge-std --no-git

# 1. Solidity unit tests and vectors.json parity checks (Foundry)
forge test

# 2. Off-chain library, crypto self-checks, and test-vector suite (Node 20+)
node --test test.mjs

# 3. Offline narrated walkthrough (no RPC required)
node demo.mjs
```

To regenerate `vectors.json` deterministically:

```bash
node gen-vectors.mjs
```

## Files

- `contracts/IGPUCollateralEvidence.sol` — Exact Solidity interface defined in ERC-8512.
- `contracts/GPUCollateralEvidence.sol` — Minimal, ownerless, non-upgradeable registry implementing the pledge index (O(1) swap-and-pop removal) and period report assertions.
- `contracts/ERC8512Lib.sol` — Pure Solidity helpers for `deviceKey`, statement leaf/Merkle root, and EIP-712 domain separator / digest.
- `test/GPUCollateralEvidence.t.sol` — Foundry test suite covering every revert condition, double-pledge visibility, period replacement, overflow-safe `uint256` rule 3 arithmetic, and `vectors.json` parity with `evidence.mjs` (including `ecrecover`).
- `foundry.toml` — Foundry configuration (with read permission for `./vectors.json`).
- `evidence.mjs` — Zero-dependency Node 20+ module implementing Keccak-256, secp256k1 RFC 6979 low-`s` signing and recovery, duplicate-rejecting JSON parsing, RFC 8785 canonical JSON, EIP-712 digests, Merkle roots, statement validation, envelope verification, deterministic aggregation, and `reportProblem`.
- `gen-vectors.mjs` — Deterministic generator for `vectors.json`.
- `vectors.json` — Test vectors (3 device keys, 6 signed statements, 1 valid report with aggregates and Merkle root, empty root, and 4 invalid cases).
- `test.mjs` — Node built-in test suite checking crypto primitives, `evidence.mjs`, and `vectors.json`.
- `demo.mjs` — Offline narrated walkthrough showing double-pledge visibility, honest report verification, and catching an inflated report.

## Trust Model

The on-chain registry records filings and servicer assertions and makes conflicts (such as double pledges) visible; it checks only basic period and arithmetic consistency and does not verify signatures, hardware attestation, or statement contents. The off-chain verification script (`evidence.mjs`) is what turns those on-chain assertions into checked evidence by fetching the committed statement envelopes, verifying every signature, recomputing the Merkle root and selected-statement aggregates, confirming every statement names an actively pledged device and the matching period/collateral, and enforcing all statement schema and method rules.

Signatures of contract observers need an ERC-1271 call against the state after the report block. `evidence.mjs` works offline and does not make that call: pass such observers in `contractObservers` and their envelopes are reported as unverified.
