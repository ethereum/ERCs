# ERC-8186: Identity Account — Reference Implementation

Minimal, self-contained reference implementation of the Identity Account standard.

## Contracts

| File | Description |
|------|-------------|
| `IAccountFactory.sol` | Factory interface |
| `IIdentityAccount.sol` | Account interface (`execute` only) |
| `IReclaimableIdentityAccount.sol` | Optional reclaim extension interface |
| `AccountFactory.sol` | Factory with EIP-1167 clones |
| `IdentityAccount.sol` | Account with owner `execute` + `IReclaimableIdentityAccount` + `receive` |

## Notes

- This implementation uses EIP-1167 minimal proxies for simplicity. Production deployments may use BeaconProxy for upgradeability (as in the [full implementation](https://github.com/carlbarrdahl/ethereum-entity-registry)).
- The `execute` function allows the registered owner to make any call through the account. Token withdrawals, protocol interactions, and any other on-chain action are all performed via `execute`.
- No external dependencies — all interaction is done via low-level calls.
- The factory can be embedded into the registry contract or deployed standalone.
- Anyone can call `deployAccount`, including the owner after claiming their identifier.

## Fund Reclaim (Optional Extension)

The reference implementation includes optional fund reclaim through `IReclaimableIdentityAccount` — not as part of the base `IIdentityAccount` interface. Platforms can configure reclaim via `setReclaim` on the concrete `IdentityAccount` contract:

1. Platform deploys accounts via the factory, then calls `account.setReclaim(reclaimTo, deadline)`.
2. Anyone funds the accounts with plain ETH/ERC-20 transfers.
3. If the entity claims ownership in the registry, the owner controls all funds via `execute`. The reclaim path is blocked.
4. If the identity remains unclaimed after the deadline, `reclaimTo` calls `execute` to recover funds.

Platforms that want atomic deploy + reclaim setup can build a thin wrapper contract around the factory. Ecosystems that want one canonical deposit address per identifier should also coordinate on a canonical factory deployment per chain.
