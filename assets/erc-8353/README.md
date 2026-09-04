# ERC-8353 reference implementation

Non-normative. Foundry project, solc 0.8.20.

| Path | What |
|---|---|
| `src/IVerificationGate.sol` | The interface: four transitions, two views, four events |
| `src/VerificationGate.sol` | Minimal abstract base implementing every normative requirement; policy is exposed as virtual hooks |
| `examples/MarketGate.sol` | Adapter: staked-marketplace shape — mandatory stake, arbiter revocation burns it, verifier depth recursive over the gate's own settled claims |
| `examples/IdentityGate.sol` | Adapter: credential-registry shape — zero stake, depth read from an external source, issuer-revocable |
| `test/VerificationGate.t.sol` | 15 tests covering both shapes and every normative requirement |

The two adapters differ only in the policy hooks (`weightOf`,
`_requiredStake`, `_promotionThreshold`, `_canSettle`, `_canRevoke`,
`_onSettled`) — the same interface serves a staked marketplace and a
zero-stake credential registry.

Run:

```
forge install foundry-rs/forge-std
forge test -vv
```

Not audited. This is a reference for implementers, not production code.
