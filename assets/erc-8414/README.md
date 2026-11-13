# Reference implementation — Token-Bound Task Tenders (ERC-8414)

This directory is the complete, self-contained reference implementation for ERC-8414.
Everything needed to reproduce the test vectors is vendored here.

A reference deployment of `TaskToken` exists on Sepolia at
`0xA62059A498E40C4Ae4aF926E2B00C1Ff122bDdb7`; every hash in the vectors below is
checkable against it on-chain.

## Contents

- `contracts/` — `ITaskToken`, `ITaskTender`, `ITaskVerifier`, `IOnchainTaskDocument`;
  a self-contained `TaskToken` deploying one locked `TaskVault` per token (native and
  ERC-20 settlement); `verifiers/HashlockVerifier.sol` — stock verifier for permissionless
  machine settlement; `judgment/JuryPanel.sol` — K-of-N reference judging authority with a
  voting window and timeout default
- `tools/task-pack/` — zero-dependency Python packer / verifier (`pack.py`, `tom.py`,
  `verify.py`) for the deterministic DAG-CBOR TaskRoot encoding, byte-compatible with the
  Token-Bound Executable Skills toolchain
- `schemas/` — JSON Schemas for the task manifest, the fulfillment descriptor, and the
  confidentiality descriptor
- `test/` — Foundry suite (`TaskToken.t.sol`, `TaskTokenCoverage.t.sol`)
- `vectors/` — frozen test vectors (`public-v1`, `update-v2-companion-only` with constant
  `tdHash`, `confidential-v1`) plus `path-negative-tests.json`; reproducible byte-for-byte
  by independent implementations. `KEY.demo` files are NON-CRYPTOGRAPHIC TEST keys;
  `x-test-sha256-xor-stream-v1` is a TEST profile — never use it in production.

Interface IDs (compiler-verified, solc 0.8.24):
`ITaskToken = 0xcdaeb26d` · `ITaskTender = 0xc319d532` · `ITaskVerifier = 0x9977db15` · `IOnchainTaskDocument = 0xeb078d05`

Reference quality, unaudited — audit before mainnet use with real value.
Released under CC0.
