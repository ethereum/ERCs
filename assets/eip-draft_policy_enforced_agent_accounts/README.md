# Policy-Enforced Agent Accounts: reference implementation

All files are CC0-1.0.

| File | What it is |
|---|---|
| `IPolicyEnforcedAccount.sol` | The interface (ERC-165 id `0xcc16d336`) |
| `PolicyEnforcedRegistry.sol` | The reference registry: no owner, no upgrade path, holds no funds. Deployed on Robinhood Chain mainnet (4663) at `0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92` with verified source, through the deterministic deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` and salt `keccak256("policy-enforced-accounts registry v1")` |
| `PolicyDecisionReceipt.sol` | Pure helpers to verify a decision receipt on chain |
| `PolicyEnforcedRegistry.t.sol`, `PolicyVectors.t.sol` | Foundry tests (interface, events, ERC-165, no cross-account writes, fuzzing, test vectors) |
| `vectors.json` | Test vectors. The receipt key is test-only and public; never fund it |
| `client/src/*.ts` | A TypeScript reader and receipt verifier (viem), published as the npm package `policy-enforced-accounts` |
| `client/independent-read.mjs` | Reads an account's signers, policy and pending state, fetches and checks the policy document, and verifies a receipt, using only the chain |

To run the Solidity tests, put the `.sol` files under `src/peaa/` and the tests under `test/` in a Foundry project with `forge-std`, then point `PolicyVectors.t.sol` at `vectors.json`.
