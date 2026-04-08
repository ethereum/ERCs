# Scenario 2 — EvaluatorSlashed → fileClaim

## Problem Statement

When an evaluator (an agent responsible for assessing other agents' work) is caught acting dishonestly, the EvaluatorRegistry slashes their stake. But the parties harmed by the evaluator's dishonest assessment — the agents who received unfair evaluations — still need a mechanism to recover damages.

The key insight is that the **slash event itself is sufficient evidence** for filing a claim in the assurance layer. There is no need for re-adjudication: if the evaluator was already slashed for misconduct on a specific `jobId`, the corresponding claim should be auto-approvable based on that on-chain proof.

## Actors

| Actor | Role |
|-------|------|
| **Registry Operator** | Governance address that triggers evaluator slashing |
| **Dishonest Evaluator** | The evaluator being slashed |
| **Assured Agent** | Posts collateral and commits a JobAssurance covering the disputed Job |
| **Harmed Beneficiary (Claimant)** | Party harmed by the unfair evaluation, who files the claim |
| **AAP Resolver** | Resolves the claim using the slash record as evidence |
| **EvaluatorRegistry** | Contract that records slashes and emits `EvaluatorSlashed` events |
| **AAP contract** | Assurance protocol where the claim is filed |

## Flow (step by step)

1. The Assured Agent calls `depositAssurance()` and then `commitToJob()` on AAP, creating a JobAssurance bound to the disputed `jobId` with `coverageType = EvaluatorDispute`.

2. The Registry Operator calls `slashEvaluator()` on the EvaluatorRegistry, passing the dishonest evaluator's address, the `jobId` of the unfair evaluation, the slashed amount, and a reason hash.

3. The EvaluatorRegistry emits `EvaluatorSlashed(evaluator, jobId, slashedAmount, reason)` and stores the slash record on-chain.

4. The Harmed Beneficiary calls `buildEvidenceHash(jobId)` on the EvaluatorRegistry to obtain a deterministic hash of the slash record, then files a claim via `fileClaim(assuranceId, requestedAmount, evidence)`. The opaque `evidence` payload encodes a tagged reference to the slash event:

   ```solidity
   bytes memory evidence = abi.encode(
       "EvaluatorSlashed",
       address(registry),
       jobId,
       slashHash
   );
   ```

5. The AAP Resolver verifies the claim by:
   - Re-deriving the slash hash from the registry via `buildEvidenceHash(jobId)`
   - Confirming the re-derived hash matches the one encoded in the evidence payload
   - Calling `resolveClaim(claimId, true, approvedAmount, reason)` — no re-adjudication of the underlying evaluation

6. Anyone (typically the beneficiary) calls `payout(claimId)` to settle the approved claim.

## What This Demonstrates

- An indexed `EvaluatorSlashed` event with `jobId` serves as **automatic proof** for assurance claims, eliminating the need for a separate dispute process.
- The slash record reference travels through AAP's opaque `evidence` payload, creating an auditable cross-contract trail without expanding the AAP interface.
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
