# Reference implementation — Token-Bound Executable Skills

Canonical repository (full toolchain, quick start, and reproduction instructions):
https://github.com/garyyang-finchip/skill-token-standard (release v1.0.0)

Live on Sepolia: 0x12cc1a5319c6F08bFB50982e3814A376A59fE550 — Skill Token #1 is the
`public-v1` frozen vector; on-chain anchors match the vectors in this directory.

## Contents

- `contracts/` — ISkillToken, IOnchainSkillDocument, and a reference SkillToken implementation
- `test/` — Foundry suite: 12/12 passing, one assertion per MUST clause of the specification
- `tools/` — zero-dependency packer/verifier for the deterministic DAG-CBOR encoding
- `schemas/` — manifest and confidentiality descriptor JSON Schemas
- `vectors/` — six frozen test vectors (public / confidential / license-encrypted /
  custom primary path / companion-only update / key rotation) plus path negative tests;
  reproducible byte-for-byte by independent implementations

Interface IDs (compiler-verified): ISkillToken = 0x734553a6, IOnchainSkillDocument = 0x7050dd2c

Released under CC0.
