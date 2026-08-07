# Reference implementation

Accompanies the ERC "Token Launch Abuse Detection and Remediation".

Self-contained: no external dependencies, no submodules.

```
forge build
forge test
```

178 tests and four fuzzed invariants. Every interface in the ERC matches these
sources signature for signature.

## What it does

A launch venue takes buyer funds into escrow instead of forwarding them to the
deployer. Proceeds vest on a schedule. If a detector reports abuse and a claim is
upheld, the escrow refunds buyers pro rata from what it still holds, drawing any
shortfall from a bond the deployer posted before launching.

```
venue ──registerLaunch──▶ escrow ──list──▶ directory
  │                         ▲                  │
  └──recordPurchase─────────┘                  │ launchesOf(token)
                                               ▼
detector ──observe──▶ signal vector ──submitReport──▶ registry
                                                        │
                                          activeScore   │
                                                        ▼
claimant ──openClaim──▶ remediation ──freeze / open──▶ escrow
                              │                                 │
                        adjudicate                        claim
                                                                ▼
                                                             buyers
```

## Components

| Path | Purpose |
| --- | --- |
| `LaunchAbuseTypes.sol` | Pattern identifiers, privileged-power bits, `SignalVector`, `AbuseReport` |
| `ScoreEvaluator.sol` | Weighted-mean scoring, with a reference profile for all ten patterns |
| `SignalProbe.sol` | Derives the chain-readable signals from bytecode and balances |
| `LaunchDetector.sol` | Assembles a signal vector; canonical evidence leaf and root |
| `LaunchDirectory.sol` | Per-chain resolution from a token or deployer to its launches |
| `LaunchAbuseRegistry.sol` | Bonded report publication, submitter-key rotation, `activeScore` |
| `LaunchEscrow.sol` | Vesting release, lapsing freeze, pro-rata  by pull |
| `LaunchRemediation.sol` | Bonds, claims, contest, settle, adjudication,  execution |
| `LaunchGuard.sol` | Advisory pre-purchase check, called by `STATICCALL` |
| `CommitteeAdjudicator.sol` | n-of-m adjudication with published reasoning, in place of a single key |
| `Containment.sol` | The containment ladder as a pure function |
| `SaleVenue.sol` | Minimal fixed-price venue; a bonding curve differs only in pricing |

Interfaces sit alongside each implementation as `I*.sol`.

## Deployment

The escrow and the remediation contract reference each other, so the link closes
once and cannot be repointed.

The directory is deployed once per chain through the deterministic proxy, not
with `new`, so it lands on the same address everywhere:

```
cast send 0x4e59b44847b379578588920cA78FbF26c0B4956C   $(cast concat-hex 0x0000000000000000000000000000000000000000000000000000000000000000     $(jq -r .bytecode.object out/LaunchDirectory.sol/LaunchDirectory.json))
```

The rest is per-deployment:

```solidity
remediation = new LaunchRemediation(adjudicator, feeRecipient, bondBps, minBond, highValue);
registry    = new LaunchAbuseRegistry(address(remediation));
escrow      = new LaunchEscrow(address(remediation), directory);
remediation.initialize(escrow, registry);
// adjudicator is the committee address, computed before deploying remediation
detector    = new LaunchDetector(directory);
guard       = new LaunchGuard(registry);
```

`LaunchDirectory` is deployed with `CREATE2` through the deterministic proxy at
`0x4e59b44847b379578588920cA78FbF26c0B4956C` with salt `0x00`, so it occupies the
same address on every EVM chain. Recompute the address after any change:

```
cast keccak $(jq -r .bytecode.object out/LaunchDirectory.sol/LaunchDirectory.json)
```

## Scoring

Each signal is normalized into `[0, 10000]` against its activation threshold,
then combined as a weighted mean and scaled to `0-100`, rounding half up.

- **Conduct, not outcome.** No input carries price, market capitalization or
  buyer loss. Scoring outcome would mark honest failure as fraud.
- **Protective inversion.** `lpLockedShare` and `lpLockRemaining` contribute as
  their absence; full protection contributes zero.
- **Unavailability.** A signal at its type maximum leaves both the numerator and
  the denominator, so a detector cannot assert an innocence it never checked.
- **Per-pattern masks.** `privilegedPowers` is categorical. A honeypot profile
  scores pause, blacklist and fee; a rug profile scores mint, upgrade and seize.

All ten patterns carry a reference profile whose weights sum to 100:

| Pattern | Leading signals |
| --- | --- |
| `hard-rug` | liquidity removed, lock absent, proceeds withdrawn |
| `soft-rug` | deployer sell ratio, retained supply, proceeds withdrawn |
| `insider-allocation` | insider share, retained supply, sniper concentration |
| `sniper-coordination` | sniper concentration, insider share |
| `honeypot` | pause, blacklist, fee and limit powers |
| `mint-dilution` | supply inflation, mint power |
| `retained-control` | any privileged power, lock absent |
| `wash-launch` | wash trade ratio, sniper concentration |
| `unlock-exit` | lock remaining, deployer sell ratio, liquidity removed |
| `serial-deployer` | prior upheld claims, retained supply |

## Detector

`LaunchDetector.observe()` derives seven of the twelve signals from chain state,
including reading `proceedsWithdrawnShare` from the escrow the directory names
rather than from the party under examination. The remaining signals come from an
off-chain service and are carried through, marked unavailable where the service
could not establish them.

Evidence commits to chain-anchored leaves:

```
leaf = keccak256(abi.encode(0x00, chainId, blockNumber, txHash, logIndex, fieldId, value))
root = ordered pairwise fold, 0x01 domain on internal nodes
```

The domain tags keep leaves and internal nodes disjoint, so a node cannot be
presented as a leaf. An odd leaf is promoted rather than duplicated.

## Gas

Opening a  pool is constant in the number of buyers, which is what makes
the pull model necessary rather than merely tidy. Measured with 2,000 recorded
buyers on a single launch:

| Operation | Gas |
| --- | --- |
| `open` with 2,000 buyers | ~70,800 |
| `claim`, per buyer | 45,000 to 96,000 |

A push distribution over the same 2,000 buyers would exceed the block gas limit
by a wide margin, and would fail entirely if any single recipient reverted.

## Safety properties under test

| Property | Where |
| --- | --- |
| A launch never pays out more than it took in | invariant, 128k calls |
| The escrow stays solvent across all launches | invariant, 128k calls |
| Accounted tokens never exceed the balance held | invariant, 128k calls |
| Released proceeds never exceed proceeds paid in | invariant, 128k calls |
|  is unreachable without an upheld claim | `Remediation.t.sol` |
| The reentrancy lock blocks a re-entering payee | `GuardAndProbe.t.sol` |
| The pro-rata denominator is frozen once the pool opens | `SecurityRegression.t.sol` |
| A launch identifier cannot be squatted | `DirectorySquat.t.sol` |
| A hostile claimant cannot block resolution | `HostileClaimant.t.sol` |
| A compromised submitter key can be rotated out | `Submitter.t.sol` |
| Every pattern scores, and a clean launch scores None | `Profiles.t.sol` |
| The containment ladder is correct in all twelve cells | `Containment.t.sol` |
| No single member can adjudicate alone | `CommitteeAdjudicator.t.sol` |

## Static analysis

All source files return zero findings from Slither-based verification.
`timestamp` and `low-level-calls` are suppressed with the reason inline. The
contracts are time-based by nature: vesting, freeze deadlines and  windows
are measured in days, against a validator skew bounded at seconds.

`call` is required twice over. `transfer` forwards only 2300 gas, which stopped
being enough for many recipients once EIP-1884 raised the cost of a storage read,
so a contract recipient doing any bookkeeping on receive would fail. And a
high-level ERC-20 call reverts while decoding the absent return value of a token
that returns nothing, which would exclude USDT and others like it from ever being
a settlement asset.
