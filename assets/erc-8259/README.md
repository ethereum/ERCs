# Verification-expiry and inactive-agent checks

Run from this directory with Foundry:

```sh
forge test
```

No external Solidity dependencies are required. The package uses Solidity 0.8.24;
Forge 1.7.1 runs 13 passing tests, including two fuzz tests with 256 cases each.

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

`InactiveAgentChecks` extends those checks for the inactive-agent rules added in
[PR 2142](https://github.com/ethereum/ERCs/pull/2142). It covers deactivation before,
at and after verification expiry, an unverified agent with maximum reputation, and
different reputation/tier values. All three views must return zero/false for an
inactive agent, even if an active tier-0 agent would retain a base reputation score.
An unrelated active control must remain unaffected.

To run these additional checks against an implementation, inherit
`InactiveAgentChecks` and override both `deployRegistry()` and
`deactivateForTest(address)` using that implementation's authorized lifecycle path.
The standard interface does not define a deactivation method; this hook belongs
only to the test adapter. Existing `TrustScoreExpiryChecks` adapters remain usable.
The history-retention assertion applies only to the fixture, and the suite makes
no assumption about reactivation or whether deactivation clears stored fields.

`ExpiryRegistryFixture` is a minimal test double, **not a complete ERC-8259
implementation**. It implements only the methods used here and uses an illustrative
bounded additive score. The tests do not mandate that formula or validate every
registration, threat-reporting, authorization, event or scoring requirement. Passing
the fixture suite is not evidence of conformance by a deployed registry.

The original expiry cases replace the inline T8 sketch that left the time advance
commented out and compared scores across a reputation change. This asset update
changes no normative requirements or interface signatures. All files are CC0-1.0.
