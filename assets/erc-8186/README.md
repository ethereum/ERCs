# ERC-8186: Identity Account — Reference Implementation

Minimal, self-contained reference implementation of the Identity Account standard.

## Contracts

| File | Description |
|------|-------------|
| `IAccountFactory.sol` | Factory interface |
| `IIdentityAccount.sol` | Account interface (`execute` + `id` / `registry` introspection) |
| `IReclaimableIdentityAccount.sol` | Optional factory-bound reclaim extension interface |
| `AccountFactory.sol` | Factory with EIP-1167 clones; reclaim policy fixed in the constructor |
| `IdentityAccount.sol` | Account with owner `execute` + factory-bound reclaim + `receive` + ERC-721/ERC-1155 receiver hooks + ERC-165 |

## Notes

- This implementation uses EIP-1167 minimal proxies for simplicity. Production deployments may use BeaconProxy for upgradeability.
- The `execute` function allows the registered owner to make any call through the account. Token withdrawals, protocol interactions, and any other on-chain action are all performed via `execute`.
- No external dependencies — all interaction is done via low-level calls.
- The factory can be embedded into the registry contract or deployed standalone.
- Anyone can call `deployAccount`, including the owner after claiming their identifier. `deployAccount` is idempotent: if the account is already deployed, it returns the existing address instead of reverting.
- Reclaim is factory-bound: the factory constructor fixes `reclaimTo` and `reclaimDelay` for every account it deploys, no matter who calls `deployAccount`. While an identifier is unclaimed and past its deadline, `reclaimTo` may `execute` — e.g. a platform redirecting never-claimed funds to a public goods pool. Pass `reclaimTo = address(0)` to disable reclaim entirely.
- Per-account reclaim configuration was deliberately rejected: a permissionless setter would let anyone name themselves reclaimer of an unclaimed account. Senders who need to recover their *own* deposit should use a depositor-side escrow that releases each deposit on claim (deferred to a future ERC).
