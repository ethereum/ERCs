# Verification-expiry checks

Run from this directory with Foundry:

```sh
forge test
```

No external Solidity dependencies are required. The package uses Solidity 0.8.24;
Forge 1.7.1 runs seven passing tests, including 256 fuzz cases.

`TrustScoreExpiryChecks` covers T5/T8 using actual time advancement. It compares an
expired agent against an unverified control with the **same reputation score**, both
before and after reputation updates. A comparison against the expired agent's old
score would mix two variables. A strict decrease is also not required by T8: bounded
scoring formulas can saturate, and a tier's configured contribution can be zero.

The suite checks validity at the exact expiry timestamp and invalidity one second
later, reputation updates before and after expiry, explicit verification renewal,
and multiple reputation/tier values. Only the fixture-specific test requires the raw
stored tier to remain nonzero; the reusable checks use the effective tier.

To use another registry, inherit `TrustScoreExpiryChecks` and override
`deployRegistry()`. Configure zero fees and authorize the test contract to update
reputation and verification. The copied interface matches the proposal. Run these
tests on the local Foundry chain (31337); the two registration DIDs use that chain ID.

`ExpiryRegistryFixture` is a minimal test double, **not a complete ERC-8259
implementation**. It implements only the methods used here and uses an illustrative
bounded additive score. The tests do not mandate that formula or validate every
registration, threat-reporting, authorization, event or scoring requirement. Passing
the fixture suite is not evidence of conformance by a deployed registry.

These executable cases replace the inline T8 sketch that left the time advance
commented out and compared scores across a reputation change. No normative behavior
or interface is changed. All files are CC0-1.0.
