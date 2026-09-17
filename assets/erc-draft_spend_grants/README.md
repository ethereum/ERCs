# Assets for Portable Spend Grants

- `vectors/v1.json` — golden hashes, rendering, and an EOA signature
- `src/` — compact Solidity reference (CC0)
- `test/` — Foundry tests for the reference. They import `../src/` and read vectors at `assets/erc-draft_spend_grants/vectors/v1.json` when run from a Foundry project that has this directory at that path.
