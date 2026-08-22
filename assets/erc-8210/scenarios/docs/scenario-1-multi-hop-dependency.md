# Scenario 1 — Multi-Hop Dependency Tracking

## Problem Statement

In autonomous agent pipelines, jobs are frequently chained: Agent A produces output consumed by Agent B, whose output feeds Agent C, and so on. When a failure surfaces at the end of the pipeline (say, Agent D), the affected party needs **root-cause traceability** — a way to identify that the actual fault originated at Agent A, three hops upstream.

Without structured traceability, the claim filed in the assurance layer (ERC-8210 / AAP) contains only local context. Resolvers cannot determine whether the harm was caused by the immediate agent or by a propagated upstream failure.

## Actors

| Actor | Role |
|-------|------|
| **Pipeline Operator** | Deploys and orchestrates the A → B → C → D job chain |
| **Assured Agent** | Posts collateral and commits a JobAssurance covering the leaf job |
| **Beneficiary (Claimant)** | Party harmed by the pipeline's final output |
| **AAP Resolver** | Resolves the claim after tracing the upstream chain |
| **ChainedJobs contract** | On-chain registry of job dependencies |
| **AAP contract** | Assurance protocol that receives the claim with an upstream-encoded evidence payload |

## Flow (step by step)

1. The Pipeline Operator creates four jobs in `ChainedJobsMock`:
   - Job 1 (label `"DataIngest"`) — root, no upstream.
   - Job 2 (label `"Transform"`) — upstream = Job 1.
   - Job 3 (label `"Validate"`) — upstream = Job 2.
   - Job 4 (label `"Publish"`) — upstream = Job 3.

2. Jobs 1 and 2 complete successfully. Job 3 runs but produces a flawed validation. Job 4 publishes the flawed result.

3. The Assured Agent calls `depositAssurance()` and `commitToJob()` on AAP, binding a JobAssurance to Job 4 (the leaf job) with `coverageType = JobFailure`. The AAP spec stays 1:1 Job-scoped — the multi-hop dependency is composition metadata, not part of the JobAssurance.

4. The Beneficiary obtains an upstream reference via `pipeline.upstreamHash(jobD)` and files a claim through `fileClaim(assuranceId, requestedAmount, evidence)`. The opaque `evidence` payload encodes the upstream pointer and a failure tag:

   ```solidity
   bytes memory evidence = abi.encode(
       "pipeline_failure",
       jobD,
       upstreamRef
   );
   ```

5. The AAP Resolver inspects the evidence, then calls `traceToRoot(jobD)` on ChainedJobs to walk the upstream chain `[jobD, jobC, jobB, jobA]`. Inspecting each job's status, the Resolver identifies Job C (Validate) as the failed root cause.

6. The Resolver calls `resolveClaim(claimId, true, approvedAmount, reason)`, citing Job C as the root cause in the reason payload. Anyone (typically the beneficiary) calls `payout(claimId)` to settle.

## What This Demonstrates

- The upstream reference travels through AAP's opaque `evidence` payload, linking a 1:1 Job-scoped JobAssurance to an external dependency graph **without ERC-8210 needing to model graphs at the protocol level**.
- Root-cause analysis can be performed on-chain by walking `traceToRoot` from the leaf back to the failing ancestor.
- The pattern is generic: any system that produces a deterministic `bytes32` reference into a causal chain can plug into AAP's evidence payload the same way.

## Architectural Layers

| Layer | Role in this scenario |
|-------|----------------------|
| **Layer 1 (Structure / ERC-8183)** | Defines the job roles and state machine that the pipeline operates under |
| **Layer 2 (Behavior)** | Could have caught the flawed validation at Job 3 via a risk hook, but did not |
| **Layer 3 (Recovery / ERC-8210)** | Provides post-hoc redress — the claim is filed and the upstream reference enables root-cause tracing |

This scenario is primarily a **Layer 3** demonstration, showing how the recovery layer composes with an external dependency graph to enable traceability across multi-hop pipelines.

## References

- The upstream reference pattern in the verification schema was discussed in the ERC-8183 Ethereum Magicians thread as a mechanism for cross-spec traceability.
- The 3-layer architecture (Structure / Behavior / Recovery) was articulated by [@wangbin9953](https://github.com/wangbin9953) (ERC-8210 author) in post #107 of the ERC-8183 Ethereum Magicians thread.
