# ERC-8318 Reference Implementation

A minimal Foundry package implementing the core interface of ERC-8318 (Tokenized fund lifecycle metadata).

The Specification section of ERC-8318 is normative. Where this code and the specification differ, the specification takes precedence. This code is not audited and is not intended for production use.

## Files

| File | Contents |
| --- | --- |
| `contracts/IFundMetadata.sol` | Enums, structs, the core interface `IFundMetadata` with its required events, and the optional extensions `IFundMetadataAUM`, `IFundMetadataLockup`, `IFundMetadataYield`, `IFundMetadataMultiClass` and `IFundMetadataProofOfReserves`, exactly as specified. |
| `contracts/FundMetadataExample.sol` | Implementation of `IFundMetadata` and ERC-165. It does not implement the optional extensions. |
| `test/FundMetadataExample.t.sol` | Foundry tests. |
| `foundry.toml` | Compiler (solc 0.8.24) and remapping configuration. |

## Normative and non-normative parts

The read functions, events, indexed-field layout and ERC-165 identifiers in `IFundMetadata.sol` are normative.

All write functions in `FundMetadataExample.sol` are **non-normative**. This includes `setNav`, `setLifecycleState`, `declareDistribution`, `markDistributionPaid`, `cancelDistribution`, the parameter setters and the role names. They show one admin-driven model; implementations may use different names, signatures and access control.

## Behaviour illustrated

- **ERC-165:** `supportsInterface` returns `true` for ERC-165 (`0x01ffc9a7`) and `IFundMetadata` (`0x9539c458`). It returns `false` for `0xffffffff` and for the unimplemented extensions. The tests assert all six identifiers in the specification's table and recompute the core identifier as the XOR of its selectors.
- **NAV:**
  - Each published NAV is stored with its decimals and effective timestamp.
  - `navAsOf(t)` returns the latest NAV effective at or before `t`, found by binary search. It reverts if no such NAV exists.
  - `navStale()` returns `true` before the first NAV, and afterwards only when the NAV's age is strictly greater than `navStalenessThreshold()`.
  - A stale NAV is still returned by `navPerShare()`.
  - Re-publishing an identical NAV emits nothing.
  - Before the first NAV, `navPerShare()` returns `(0, 0)` and `navUpdatedAt()` returns `0`. This distinguishes "unset" from a published NAV of zero.
- **Lifecycle:**
  - Illegal and no-op transitions revert.
  - `Closed` is terminal.
  - `Paused` records the prior state and exits only to that state or to a legal successor of it.
- **Distributions:**
  - IDs start at 1, and `distributionById` reverts for unknown IDs.
  - A `Declared` distribution is reported with status `ExDate` once its ex-date has passed.
  - Cancellation and payment remove the ID from `pendingDistributionIds()`. Payment also updates `lastDistributionId()`.
- **Payment confirmation:** `markDistributionPaid` does not move funds. It records that settlement has occurred and emits `DistributionPaid`. The caller, holding `DISTRIBUTION_AGENT_ROLE`, is trusted to call it only after settlement has actually taken place. A production implementation should bind this to verified settlement.

## Build and test

Run these commands from this directory. Requires Foundry.

```bash
forge install --no-git OpenZeppelin/openzeppelin-contracts@v5.6.1 foundry-rs/forge-std@v1.16.1
forge build
forge test -vv
```

## License

All files in this directory are released under CC0-1.0.
