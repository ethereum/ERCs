# Scenario 1 — Multi-Hop Dependency Tracking

## Problem Statement

In autonomous agent pipelines, jobs are frequently chained: Agent A produces output consumed by Agent B, whose output feeds Agent C, and so on. When a failure surfaces at the end of the pipeline (say, Agent D), the affected party needs **root-cause traceability** — a way to identify that the actual fault originated at Agent A, three hops upstream.

Without structured traceability, the claim filed in the assurance layer (ERC-8210 / AAP) contains only local context. Reviewers cannot determine whether the harm was caused by the immediate agent or by a propagated upstream failure.

## Actors

| Actor | Role |
|-------|------|
| **Pipeline Operator** | Deploys and orchestrates the A → B → C → D job chain |
| **Claimant** | End-user who suffers harm from the pipeline's final output |
| **Reviewer** | AAP reviewer who must trace the root cause before ruling |
| **ChainedJobs contract** | On-chain registry of job dependencies |
| **AAP contract** | Assurance protocol that receives the claim with an `upstream` reference |

## Flow (step by step)

1. The Pipeline Operator creates four jobs in `ChainedJobsMock`:
   - Job 1 (label `"DataIngest"`) — root, no upstream.
   - Job 2 (label `"Transform"`) — upstream = Job 1.
   - Job 3 (label `"Validate"`) — upstream = Job 2.
   - Job 4 (label `"Publish"`) — upstream = Job 3.

2. Jobs 1 and 2 complete successfully. Job 3 runs but produces a flawed validation. Job 4 publishes the flawed result.

3. The Claimant discovers the harm and files a claim in AAP. The `upstream` field of the claim is set to the `upstreamHash(jobId=4)` from ChainedJobs — this encodes the full dependency pointer.

4. The Reviewer calls `traceToRoot(4)` on ChainedJobs, obtaining the chain `[4, 3, 2, 1]`. Inspecting each job's status, the reviewer sees that Job 3 is marked `Failed`.

5. The Reviewer approves the claim, citing Job 3 as the root cause.

## What This Demonstrates

- The `upstream` field in the AAP `Claim` struct is sufficient to link a claim to an external dependency graph without ERC-8210 needing to understand the graph's structure.
- Root-cause analysis can be performed on-chain by walking the `traceToRoot` chain.
- The pattern is generic: any system that produces a deterministic `bytes32` identifier for a causal chain can plug into AAP's `upstream` field.

## Architectural Layers

| Layer | Role in this scenario |
|-------|----------------------|
| **Layer 1 (Structure / ERC-8183)** | Defines the job roles and state machine that the pipeline operates under |
| **Layer 2 (Behavior)** | Could have caught the flawed validation at Job 3 via a risk hook, but did not |
| **Layer 3 (Recovery / ERC-8210)** | Provides post-hoc redress — the claim is filed and the upstream field enables root-cause tracing |

This scenario is primarily a **Layer 3** demonstration, showing how the recovery layer composes with an external dependency graph to enable traceability across multi-hop pipelines.

## References

- The `upstream` field in the verification schema was discussed in the ERC-8183 Ethereum Magicians thread as a mechanism for cross-spec traceability.
- The 3-layer architecture (Structure / Behavior / Recovery) was articulated by [@wangbin9953](https://github.com/wangbin9953) (ERC-8210 author) in post #107 of the ERC-8183 Ethereum Magicians thread.
