# ERC-8376 Reference Weight Profiles v0.1

The reference profile for each pattern, published as the Score Computation section of
ERC-8376 requires. Weights sum to 100 in each. A deployment MAY tune them and MUST
publish the profile it used; a signal absent from a profile carries no weight for that
pattern and is excluded from its mean.

| Pattern | Weights |
| --- | --- |
| `PATTERN_HARD_RUG` | liquidityRemoved 30, lpLockedShare 20, proceedsWithdrawnShare 15, lpLockRemaining 10, deployerSellRatio 10, privilegedPowers 10, priorUpheldClaims 5 |
| `PATTERN_SOFT_RUG` | deployerSellRatio 35, deployerSupplyShare 20, proceedsWithdrawnShare 20, lpLockedShare 10, privilegedPowers 10, priorUpheldClaims 5 |
| `PATTERN_INSIDER_ALLOCATION` | insiderAllocationShare 45, deployerSupplyShare 20, sniperConcentration 20, priorUpheldClaims 15 |
| `PATTERN_SNIPER_COORDINATION` | sniperConcentration 50, insiderAllocationShare 25, deployerSupplyShare 15, priorUpheldClaims 10 |
| `PATTERN_HONEYPOT` | privilegedPowers 70, deployerSupplyShare 15, priorUpheldClaims 15 |
| `PATTERN_MINT_DILUTION` | supplyInflation 50, privilegedPowers 30, deployerSupplyShare 10, priorUpheldClaims 10 |
| `PATTERN_RETAINED_CONTROL` | privilegedPowers 70, lpLockedShare 15, priorUpheldClaims 15 |
| `PATTERN_WASH_LAUNCH` | washTradeRatio 50, sniperConcentration 25, insiderAllocationShare 15, priorUpheldClaims 10 |
| `PATTERN_UNLOCK_EXIT` | lpLockRemaining 30, deployerSellRatio 30, liquidityRemoved 25, priorUpheldClaims 15 |
| `PATTERN_SERIAL_DEPLOYER` | priorUpheldClaims 60, deployerSupplyShare 15, privilegedPowers 15, insiderAllocationShare 10 |
| `PATTERN_IMPERSONATION` | symbolCollision 40, nameSimilarity 30, metadataReuse 20, priorUpheldClaims 10 |

## Activation Exceptions

Where a profile weights `privilegedPowers`, the bits that activate it are masked to the
powers the pattern is about.

Exceptions: `PATTERN_HARD_RUG` masks DANGEROUS; `PATTERN_SOFT_RUG` masks DANGEROUS; `PATTERN_HONEYPOT` masks PAUSE, BLACKLIST, FEE, LIMITS, EXEMPT; `PATTERN_MINT_DILUTION` masks MINT; `PATTERN_RETAINED_CONTROL` masks MINT, PAUSE, BLACKLIST, FEE, UPGRADE, SEIZE, LIMITS, EXEMPT; `PATTERN_SERIAL_DEPLOYER` masks DANGEROUS; `PATTERN_SERIAL_DEPLOYER` activates `priorUpheldClaims` at 3. `DANGEROUS` denotes mint, upgrade and seize.
