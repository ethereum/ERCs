# Scenario 2 — EvaluatorSlashed → fileClaim

## Problem Statement

When an evaluator (an agent responsible for assessing other agents' work) is caught acting dishonestly, the EvaluatorRegistry slashes their stake. But the parties harmed by the evaluator's dishonest assessment — the agents who received unfair evaluations — still need a mechanism to recover damages.

The key insight is that the **slash event itself is sufficient evidence** for filing a claim in the assurance layer. There is no need for re-adjudication: if the evaluator was already slashed for misconduct on a specific `jobId`, the corresponding claim should be auto-approvable based on that on-chain proof.

## Actors

| Actor | Role |
|-------|------|
| **Registry Operator** | Governance address that triggers evaluator slashing |
| **Dishonest Evaluator** | The evaluator being slashed |
| **Harmed Agent (Claimant)** | Agent who received an unfair evaluation and files a claim |
| **AAP Reviewer** | Reviews the claim using the slash record as evidence |
| **EvaluatorRegistry** | Contract that records slashes and emits `EvaluatorSlashed` events |
| **AAP contract** | Assurance protocol where the claim is filed |

## Flow (step by step)

1. The Registry Operator calls `slashEvaluator()` on the EvaluatorRegistry, passing the dishonest evaluator's address, the `jobId` of the unfair evaluation, the slashed amount, and a reason hash.

2. The EvaluatorRegistry emits `EvaluatorSlashed(evaluator, jobId, slashedAmount, reason)` and stores the slash record on-chain.

3. The Harmed Agent calls `buildEvidenceHash(jobId)` on the EvaluatorRegistry to obtain a deterministic evidence hash derived from the slash record.

4. The Harmed Agent files a claim in AAP using:
   - `amount`: the damages suffered
   - `evidenceHash`: the hash from step 3
   - `upstream`: `keccak256(abi.encode("EvaluatorSlashed", jobId))` — a tagged reference to the slash event

5. The AAP Reviewer verifies the claim by:
   - Checking that a slash record exists for the referenced `jobId`
   - Confirming the evidence hash matches
   - Approving the claim without re-adjudication

6. The AAP contract transfers the approved amount to the claimant.

## What This Demonstrates

- An indexed `EvaluatorSlashed` event with `jobId` serves as **automatic proof** for assurance claims, eliminating the need for a separate dispute process.
- The `upstream` field in the AAP claim links back to the slash event, creating an auditable cross-contract trail.
- The pattern separates concerns: the EvaluatorRegistry handles punishment (slashing), while AAP handles recovery (compensation). Neither needs to understand the other's internal logic.

## Architectural Layers

| Layer | Role in this scenario |
|-------|----------------------|
| **Layer 1 (Structure / ERC-8183)** | Defines evaluator roles and the job lifecycle |
| **Layer 2 (Behavior)** | The EvaluatorRegistry acts as a behavioral check — it detects and punishes evaluator misconduct |
| **Layer 3 (Recovery / ERC-8210)** | AAP provides compensation to the harmed party, using the Layer 2 slash as evidence |

This scenario demonstrates **Layer 2 → Layer 3 composition**: the behavioral detection layer produces evidence that the recovery layer consumes directly, without duplication of effort.

## References

- The `EvaluatorSlashed` event signature and the "slash as proof" pattern were agreed upon with [@Demsys](https://github.com/Demsys) in the ERC-8183 Ethereum Magicians thread. Reference implementation: [agent-settlement-protocol](https://github.com/Demsys/agent-settlement-protocol).
- The 3-layer architecture was articulated by [@wangbin9953](https://github.com/wangbin9953) (ERC-8210 author) in post #107 of the ERC-8183 Ethereum Magicians thread.
