# ERC-8376 Sellability Extension Schema v0.1

The reference extension schema for `PATTERN_HONEYPOT`, published at a stable URI as
the Extension Signals section of ERC-8376 requires.

`PATTERN_HONEYPOT` cannot be scored from the base vector, and unlike impersonation this was established by measurement rather than by argument. A launch on Base holding 5.8 ETH of paired liquidity, with more than fifty purchases out of its pool, scored **zero** on the pattern. Its twelve signals read `privilegedPowers` 0, `liquidityRemoved` 0 and `lpLockedShare` 0, because the token exposes none of the eight functions the bit table names and its pool is intact. Fourteen of fourteen externally owned accounts holding it could not transfer any amount of it to that pool.

Every signal in the base vector describes the token, the pool's balance, or an action by the deployer. Whether a holder can leave is none of those three, and it is the defining property of this pattern.

Schema `keccak256("erc.launch.schema.sellability")`, version 1:

| Field | Type | Units | Definition | Polarity | Threshold |
| --- | --- | --- | --- | --- | --- |
| `blockedHolderShare` | `uint16` | bps | Share of sampled holders for whom a transfer of a non-zero amount of the token to its pool does not succeed | Adverse | 5000 |
| `proceedsRetainedShare` | `uint16` | bps | Share of the value a sale should return, computed from the pool's own reserves, that is withheld from an ordinary seller | Adverse | 1000 |

Weights: `blockedHolderShare` 45, `proceedsRetainedShare` 35, `privilegedPowers` 10, `priorUpheldClaims` 10.

## Sampling

`blockedHolderShare` is a sample and MUST be reported as the unavailability sentinel where fewer than three holders could be sampled. One blocked holder is what a blacklist looks like, and a blacklist is a different claim from a trap: the first denies a person and the second denies everyone. A detector reporting a trap from a single refusal is reporting the wrong pattern, and the reference implementation of this scan did exactly that before the floor was imposed.

Sampled holders MUST be externally owned accounts holding a non-zero balance. The recipient of a transfer out of a pool is frequently the router or aggregator that routed the swap rather than the person who bought, and such contracts hold dust balances of thousands of tokens. Sampling one reports a property of the aggregator: in testing, three launches were reported as traps on the strength of a single 27KB contract whose transfers reverted for its own reasons.

The sample size MUST be reported in `evidenceURI`, so that a reader can tell a share of fourteen from a share of three.

## Establishing it without a transaction

Both fields are established by simulated call against current state, which costs nothing, needs no approval and touches no chain. `eth_call` accepts an arbitrary `from`, so the transfer a holder would actually make can be attempted as that holder. A direct transfer to the pool requires no allowance, which is why it is the operation specified here rather than a router swap.

A detector MUST distinguish a refusal caused by the token from one caused by the attempt. An insufficient balance is the caller's error, and the commonest way a naive probe reports a honeypot that is not one. Where the token reverts with a recognised balance error the holder MUST NOT be counted as blocked.

A detector SHOULD distinguish an operation that reverts from one that succeeds and returns a fraction of the expected value. Unopened trading and uninitialised curves revert in volume at legitimate venues, so reverts carry noise; a successful call returning a fraction is a measurement. The second field exists for that case and MAY require state overrides or a deployed probe to establish, which is why it is specified separately rather than folded into the first.

## Why the restriction need not be in the token

`proceedsRetainedShare` is deliberately not defined over token bytecode. A token observed on Base held no privileged roles, attached no transfer policy and paused nothing, while the single pool trading it ran a hook returning approximately 0.1 per cent of the value of a round trip to ordinary callers and approximately one thousand times that proportion to the deployer for the identical sell. `privilegedPowers` sets no bit for a restriction held in a pool, and no reading of the token's code can find one.

A deployment MUST NOT treat a clean reading of this schema as evidence that a position can be exited. It establishes that sampled holders could sell at the time of sampling, through the venue sampled, which is a narrower claim than it appears and a far stronger one than the base vector can make.
