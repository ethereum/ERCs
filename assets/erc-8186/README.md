# ERC-8186: Identity Account — Reference Implementation

Minimal, self-contained reference implementation of the Identity Account standard.

## Contracts

| File | Description |
|------|-------------|
| `IAccountFactory.sol` | Factory interface |
| `IIdentityAccount.sol` | Account interface |
| `AccountFactory.sol` | Minimal factory using EIP-1167 clones |
| `IdentityAccount.sol` | Minimal account with `execute` + `receive` |

## Notes

- This implementation uses EIP-1167 minimal proxies for simplicity. Production deployments may use BeaconProxy for upgradeability (as in the [full implementation](https://github.com/carlbarrdahl/ethereum-canonical-registry)).
- The `execute` function allows the registered owner to make any call through the account. Token withdrawals, protocol interactions, and any other on-chain action are all performed via `execute`.
- No external dependencies — all interaction is done via low-level calls.
- The factory can be embedded into the registry contract or deployed standalone.
