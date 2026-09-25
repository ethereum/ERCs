# Assets for Portable Spend Grants

- `vectors/v1.json` — golden hashes, rendering, and an EOA signature
- `clear-signing/spend-grant.json` — non-normative ERC-7730 display descriptor for the reference registry deployment
- `src/` — compact Solidity reference (CC0): SpendGrantExecutor.sol, SpendGrantHash.sol, SpendGrantRegistry.sol, SpendGrantTypes.sol
- `test/` — Foundry tests for the reference (HashHarness.sol, Inheritance.t.sol, MockERC20.sol, SpendGrantHash.t.sol, SpendGrantInvariant.t.sol, SpendGrantRegistry.t.sol, SpendGrantRing.t.sol). They import `../src/` and read vectors at `assets/erc-0/vectors/v1.json` when run from a Foundry project that has this directory at that path.

The full reference repository, with the TypeScript package, Halmos properties, deploy script, and Arc testnet deployment record, is https://github.com/tankcdr/erc-spend-grants.
