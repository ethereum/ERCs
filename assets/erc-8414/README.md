# Reference implementation — Token-Bound Task Tenders

Canonical repository (full toolchain, worked examples, quick start, and reproduction
instructions): https://github.com/garyyang-finchip/task-token-standard

Live on Sepolia: `TaskToken` at `0xA62059A498E40C4Ae4aF926E2B00C1Ff122bDdb7` — the worked
examples in the canonical repository were executed end to end against it; every hash is
checkable on-chain.

## Contents

- `contracts/` — `ITaskToken`, `ITaskTender`, `ITaskVerifier`, `IOnchainTaskDocument`;
  a self-contained `TaskToken` deploying one locked `TaskVault` per token (native and
  ERC-20 settlement); `verifiers/HashlockVerifier.sol` — stock verifier for permissionless
  machine settlement; `judgment/JuryPanel.sol` — K-of-N reference judging authority with a
  voting window and timeout default
- `tools/task-pack/` — zero-dependency packer/verifier for the deterministic DAG-CBOR
  TaskRoot encoding, byte-compatible with the Token-Bound Executable Skills toolchain
- `schemas/` — task manifest + fulfillment descriptor JSON Schemas (the confidentiality
  schema is shared with the companion supply-side standard)
- `vectors/` — frozen test vectors (public / companion-only update with constant `tdHash`
  / confidential) plus path negative tests; reproducible byte-for-byte by independent
  implementations. `KEY.demo` files are NON-CRYPTOGRAPHIC TEST keys;
  `x-test-sha256-xor-stream-v1` is a TEST profile — never use it in production.

Interface IDs (compiler-verified, solc 0.8.24):
`ITaskToken = 0xcdaeb26d` · `ITaskTender = 0xc319d532` · `ITaskVerifier = 0x9977db15` · `IOnchainTaskDocument = 0xeb078d05`

Reference quality, unaudited — audit before mainnet use with real value.
Released under CC0.
