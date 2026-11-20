# Scenario 4 — Stateless Solvency-Aware Claim Assessment

## Problem Statement

When an evaluator is slashed, the `EvaluatorSlashed` event tells downstream consumers *what happened* (slash amount, reason, jobId), but not *what the evaluator's remaining capacity is*. Consumers like AHM (Agent Health Score), ThoughtProof's verification, or any AAP resolver that wants to assess future deterrent need a separate RPC call to query the evaluator's post-slash balance — or they need to maintain local state tracking all stake movements.

Neither approach works well for stateless indexers: extra RPC calls add latency and cost, and local state tracking introduces complexity and failure modes.

## Solution

Emit `EvaluatorStakeUpdated(evaluator, oldBalance, newBalance)` in the **same transaction** as `EvaluatorSlashed`. A stateless consumer reading the tx logs sees both events together and can assess:

1. **Misconduct details** — from `EvaluatorSlashed`: who was slashed, for which job, how much, and why.
2. **Post-slash solvency** — from `EvaluatorStakeUpdated`: what the evaluator's balance was before and after the slash, without any additional query.

The delta (`oldBalance - newBalance`) matches the slash `amount`, and the `newBalance` directly indicates remaining capacity. A zero `newBalance` signals total wipeout — the evaluator has no future deterrent.

## Actors

| Actor | Role |
|-------|------|
| **Dishonest Evaluator** | Evaluator being slashed; has staked into the registry |
| **Registry Operator** | Triggers the slash |
| **Assured Agent** | Posts collateral and commits a JobAssurance covering the disputed Job |
| **Harmed Beneficiary** | Files a claim with enriched evidence referencing both events |
| **AAP Resolver** | Verifies the claim using both the slash record AND the solvency snapshot |
| **EvaluatorRegistryWithStake** | Registry that tracks stake balances and emits both events in slash transactions |
| **AAP contract** | Assurance protocol where the claim is filed |

## Flow (step by step)

1. The Dishonest Evaluator calls `depositStake()` on the registry, which emits `EvaluatorStakeUpdated(evaluator, 0, 2000e18)`.

2. The Assured Agent calls `depositAssurance()` and `commitToJob()` on AAP, binding a JobAssurance to the disputed job with `coverageType = EvaluatorDispute`.

3. The Registry Operator calls `slashEvaluator()`. In a single transaction, the registry emits:
   - `EvaluatorSlashed(evaluator, jobId, 800e18, "front_running")`
   - `EvaluatorStakeUpdated(evaluator, 2000e18, 1200e18)`

4. The Harmed Beneficiary builds an enriched evidence payload encoding references to **both** events:

   ```solidity
   bytes memory evidence = abi.encode(
       "SolvencyAwareSlash",
       address(registry),
       jobId,
       slashHash,
       evaluator,
       stakeHash
   );
   ```

   Then files the claim via `fileClaim(assuranceId, requestedAmount, evidence)`.

5. The AAP Resolver verifies both hashes:
   - Re-derives `slashHash` from the registry — confirms the slash is authentic
   - Re-derives `stakeHash` from the registry — confirms the solvency snapshot
   - Reads `stakeBalances(evaluator)` — sees 1200e18 remaining (60% of original)
   - Calls `resolveClaim(claimId, true, approvedAmount, reason)` with the solvency context encoded in the reason

6. Anyone calls `payout(claimId)` to settle.

## What This Demonstrates

- **Stateless solvency assessment**: Two events in the same tx give a complete picture — misconduct details plus remaining capacity — without RPC calls or local state.
- **Evidence-first composability**: The enriched evidence payload carries references to both events through AAP's opaque `bytes evidence` parameter, extending the pattern from Scenario 2.
- **Consumer-agnostic design**: `EvaluatorStakeUpdated` fires on any stake movement (deposit, withdraw, slash), serving AHM scoring, ThoughtProof verification, and protocol-level risk assessment equally.
- **Edge case handling**: The test includes a full-wipeout scenario where post-slash balance is zero — a stateless indexer seeing `EvaluatorStakeUpdated(evaluator, X, 0)` knows the evaluator has zero future deterrent.

## Architectural Layers

| Layer | Role in this scenario |
|-------|----------------------|
| **Layer 1 (Structure / ERC-8183)** | Defines evaluator roles and the job lifecycle |
| **Layer 2 (Behavior)** | The slash event signals misconduct; the stake-update event signals solvency state |
| **Layer 3 (Recovery / ERC-8210)** | AAP claim is filed with enriched evidence referencing both events |

This scenario extends Scenario 2 (slash → claim) by adding **solvency context** to the evidence payload, demonstrating how `EvaluatorStakeUpdated` enriches the Layer 2 → Layer 3 composition without modifying the AAP interface.

## References

- The `EvaluatorStakeUpdated(address indexed evaluator, uint256 oldBalance, uint256 newBalance)` event was designed collaboratively in the ERC-8183 Ethereum Magicians thread. The `oldBalance/newBalance` dual-field refinement was contributed by [@ThoughtProof](https://github.com/ThoughtProof) for stateless-indexer compatibility.
- The event is deployed in [@Demsys](https://github.com/Demsys)'s [agent-settlement-protocol](https://github.com/Demsys/agent-settlement-protocol) on Base Sepolia at `EvaluatorRegistry` `0xe5517C488a470D5eeB5Aa812bb87c09fc5c14D21`.
- The `EvaluatorSlashed` 4-field canonical signature was agreed with @Demsys in the same thread.
- The 3-layer architecture was articulated by [@wangbin9953](https://github.com/wangbin9953) (ERC-8210 author) in post #107 of the ERC-8183 Ethereum Magicians thread.
