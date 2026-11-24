# Policy-Enforced Agent Accounts: reference implementation

All files are CC0-1.0.

| File | What it is |
|---|---|
| `IPolicyEnforcedAccount.sol` | The interface (ERC-165 id `0xf594edcd`) |
| `PolicyEnforcedRegistry.sol` | The reference registry: no owner, no upgrade path, holds no funds. Deployed on Robinhood Chain mainnet (4663) at `0x4d37D0aD95593b2C65A0c2A98D5676D51DF3FDAB` with verified source, through the deterministic deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` and salt `keccak256("policy-enforced-accounts registry v3")` |
| `PolicyDecisionReceipt.sol` | Pure helpers to verify a decision receipt on chain (EIP-712 domain version "2") |
| `PolicyEnforcedRegistry.t.sol`, `PolicyVectors.t.sol` | Foundry tests: interface, events, ERC-165, no cross-account writes, the time rules and the stop hold (each review point has a test that shows the earlier draft's behavior and the fix), fuzzing, and the test vectors |
| `v1/` | The first draft's registry, interface and receipt helpers, deployed at `0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92` (interface `0xcc16d336`). Kept for the comparison tests and for verifying receipts issued under it |
| `v2/` | The previous registry and interface, deployed at `0xCa3bAE26d29a3A2cED7B87Fa996ca4C44367448d` (interface `0x7e0f19f9`), where a publisher could lift a stop the account engaged. Kept for the comparison tests; its receipts use the same format |
| `vectors.json` | Test vectors. The receipt key is test-only and public; never fund it |
| `client/src/*.ts` | A TypeScript reader and receipt verifier (viem), published as the npm package `policy-enforced-accounts` (0.3.0) |
| `client/independent-read.mjs` | Reads an account's signers, delay, policy and pending state, fetches and checks the policy document, and verifies a receipt, using only the chain |

To run the Solidity tests, put the `.sol` files under `src/peaa/` (and `v1/`, `v2/` under `src/peaa/v1/`, `src/peaa/v2/`) and the tests under `test/` in a Foundry project with `forge-std`, then point `PolicyVectors.t.sol` at `vectors.json`.
