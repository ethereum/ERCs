# Assets for Portable Spend Grants

- `vectors/v1.json` — golden hashes, rendering, and an EOA signature
- `vectors/authorization-v1.json` — golden digest and signature for the reference executor's SpendAuthorization
- `clear-signing/spend-grant.json` — non-normative ERC-7730 display descriptor for the reference registry deployment
- `src/` — compact Solidity reference (CC0): SpendGrantAuthorizationExecutor.sol, SpendGrantExecutor.sol, SpendGrantHash.sol, SpendGrantRedemptionEnforcer.sol, SpendGrantRedemptionExecutor.sol, SpendGrantRegistry.sol, SpendGrantSignature.sol, SpendGrantTypes.sol
- `test/` — Foundry tests for the reference (HashHarness.sol, Inheritance.t.sol, MockERC20.sol, SpendGrantAuthorization.t.sol, SpendGrantHash.t.sol, SpendGrantInvariant.t.sol, SpendGrantRedemption.t.sol, SpendGrantRegistry.t.sol, SpendGrantReplacement.t.sol, SpendGrantRing.t.sol, SpendGrantSemantics.t.sol, SpendGrantTokenBehavior.t.sol). They import `../src/` and read vectors at `assets/erc-8427/vectors/v1.json` when run from a Foundry project that has this directory at that path.

The full reference repository, with the TypeScript package, Halmos properties, deploy script, and Arc testnet deployment record, is https://github.com/tankcdr/erc-spend-grants.
