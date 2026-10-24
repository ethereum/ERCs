# Reference implementation — Token-Bound Executable Skills

Everything needed to check an independent implementation byte-for-byte is
vendored in this directory.

## Contents

- `contracts/` — ISkillToken, IOnchainSkillDocument, and a reference SkillToken implementation
- `test/` — Foundry suite: 12/12 passing, one assertion per MUST clause of the specification
- `schemas/` — manifest and confidentiality descriptor JSON Schemas
- `vectors/` — six frozen test vectors (public / confidential / license-encrypted /
  custom primary path / companion-only update / key rotation) plus path negative tests;
  each object file is named by its SHA-256 digest, every `skillroot.cbor` hashes to the
  stated `packageHash`, and the version chains link `update-v2-companion-only → public-v1`
  and `key-rotation-v2 → confidential-v1`, so the deterministic encoding is fully
  reproducible from this directory alone

Interface IDs (compiler-verified): ISkillToken = 0x734553a6, IOnchainSkillDocument = 0x7050dd2c

KEY.demo files are NON-CRYPTOGRAPHIC TEST keys; the x-test-sha256-xor-stream-v1
profile is a test profile and must never be used in production.

Released under CC0.
