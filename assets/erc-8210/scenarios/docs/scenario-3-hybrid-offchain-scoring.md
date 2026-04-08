# Scenario 3 — Hybrid Off-chain Scoring + On-chain Assurance

## Problem Statement

Some evaluations cannot be performed entirely on-chain. Complex behavioral assessments — such as an Agent Health Score (AHS) that analyzes interaction patterns, response quality, and compliance metrics — require off-chain computation. However, the **result** of that computation must be consumable by on-chain contracts for both task completion (ERC-8183) and assurance claims (ERC-8210).

The challenge is encapsulating off-chain scoring as an on-chain "assessor rule" so that the same CID (content identifier for the reasoning) can be used as evidence in both `complete()`/`reject()` flows (ERC-8183) and `fileClaim()` flows (ERC-8210).

## Actors

| Actor | Role |
|-------|------|
| **Off-chain Scorer** | Oracle-like service that computes an Agent Health Score and posts it on-chain |
| **Suspect Agent** | Agent whose behavior is being evaluated |
| **Task Manager** | Entity that uses the score to decide on task completion/rejection |
| **Claimant** | Party harmed by the suspect agent, who files a claim using the score as evidence |
| **AAP Resolver** | Resolves the claim using the posted score |
| **OffchainScorer contract** | On-chain record of scores posted by the oracle |
| **AAP contract** | Assurance protocol where the claim is filed |

## Flow (step by step)

1. The Off-chain Scorer computes an Agent Health Score for the Suspect Agent. The result includes:
   - `verdict`: DENY (the agent's behavior is non-compliant)
   - `confidence`: 87 (out of 100)
   - `reasoningCID`: a `bytes32` hash pointing to the full reasoning stored off-chain (e.g., on IPFS)

2. The Off-chain Scorer posts the score on-chain via `postScore()`, which emits `ScorePosted(subject, verdict, confidence, reasoningCID)`.

3. The Task Manager reads the score and, seeing a DENY verdict with high confidence, rejects the suspect agent's task output (in an ERC-8183 context, this would be a `reject()` call).

4. The Claimant — a party harmed by the suspect agent's non-compliant behavior — files a claim in AAP via `fileClaim(assuranceId, requestedAmount, evidence)`. The opaque `evidence` payload encodes the same `reasoningCID` used in step 3, together with a marker for the score type and the scorer address:

   ```solidity
   bytes memory evidence = abi.encode(
       "OffchainScore",
       address(scorer),
       suspectAgent,
       REASONING_CID
   );
   ```

5. The AAP Resolver verifies the claim by:
   - Re-reading the score from the OffchainScorer contract using `scorer.score(suspectAgent)`
   - Confirming the verdict is DENY and confidence exceeds a threshold
   - Confirming the on-chain `reasoningCID` matches the one encoded in the evidence payload
   - Calling `resolveClaim(claimId, true, approvedAmount, reason)`

6. The Claimant (or anyone) calls `payout(claimId)` to settle the approved claim.

## What This Demonstrates

- Off-chain scoring can be encapsulated as an on-chain "assessor rule" that both the task layer (ERC-8183) and the assurance layer (ERC-8210) can consume.
- The same `reasoningCID` serves as evidence in both task rejection and claim filing, ensuring consistency and avoiding redundant evaluation.
- The confidence score provides a quantitative basis for claim review, enabling threshold-based automation in the future.
- The composition pattern lives entirely in the `evidence` payload, not in the AAP interface — the spec stays minimal and any off-chain scoring system (AHS, reputation models, ML classifiers) can plug in by encoding its result the same way.

## Architectural Layers

| Layer | Role in this scenario |
|-------|----------------------|
| **Layer 1 (Structure / ERC-8183)** | Uses the score to reject the task — the structural layer acts on the evaluation |
| **Layer 2 (Behavior)** | The off-chain scorer IS the behavioral layer — it detects non-compliance through pattern analysis |
| **Layer 3 (Recovery / ERC-8210)** | AAP uses the same evidence (reasoningCID) to compensate the harmed party |

This scenario demonstrates **full 3-layer composition**: the off-chain scorer bridges Layer 2 (behavior detection) into both Layer 1 (task rejection) and Layer 3 (recovery), with the `reasoningCID` as the shared evidence artifact.

## References

- The AHS (Agent Health Score) concept is inspired by contributions from **pablocactus** to the ERC-8183 Ethereum Magicians thread, where off-chain scoring was discussed as an assessor rule pattern.
- **RNWY is a separate project** with related but distinct multidimensional scoring (soulbound identity, explicit sybil signal weights, live ERC-8183 hook integration). It will be referenced separately in the AAP v2 IRiskHook section once their methodology document is published. The two efforts overlap conceptually but are independent.
- The 3-layer architecture was articulated by [@wangbin9953](https://github.com/wangbin9953) (ERC-8210 author) in post #107 of the ERC-8183 Ethereum Magicians thread.
