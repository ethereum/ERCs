---
eip: <pending>
title: AI Agent Workflow Execution Interface
description: Standard interfaces for dispatching on-chain AI agent tasks with a composable, provable workflow execution model
author: JimmyShi22 (@JimmyShi22) <jimmyshixiang22@gmail.com>
discussions-to: https://ethereum-magicians.org/t/draft-erc-ai-agent-execution/28785
status: Draft
type: Standards Track
category: ERC
created: 2026-06-15
requires: 165
---

## Abstract

Every dApp that wants to invoke an AI agent today defines its own task format, and every agent must implement a separate adapter per dApp. This ERC addresses that N×M fragmentation by defining three minimal standard interfaces for on-chain AI agent task dispatch: `AgentTask` (task definition), `IAgentCaller` (dispatch with a `CallAgent` event), and `IAgentHandler` (result and proof callbacks).

A key addition beyond simple request–response is a composable workflow model. Each task carries an `agentWorkflowHash` — a cryptographic commitment to a workflow definition that specifies the execution stages (executor selection, input preparation, multi-agent orchestration, output consensus). The `IAgentHandler` callbacks `onAgentStep` and `onAgentProve` map directly onto these workflow stages, enabling a continuum from the simplest single-agent call to distributed multi-round consensus protocols, without changing the base interface.

## Motivation

The on-chain AI agent ecosystem has made real progress across several layers: agent identity (ERC-8004), inference proof verification (ERC-8274), proof anchoring (ERC-8263), agentic commerce (ERC-8183). But there is one foundational primitive still missing — a standard for *how* a smart contract invokes an AI agent and receives its output.

Today, every dApp that wants to call an AI agent defines its own task format, and every agent must implement a separate adapter per dApp:

```
dApp A defines its own task format  →  agent X adapts
dApp B defines a different format   →  agent X adapts again
dApp C defines yet another format   →  agent X adapts again
...
agent Y must do the same for A, B, C  →  N×M integration complexity
```

This is the same fragmentation ERC-8274 solved at the verification layer. The task layer has the same problem one level up.

The on-chain AI agent stack maps naturally to six base-layer primitives, analogous to blockchain's foundational properties:

| Primitive   | Blockchain Analogue                    | ERC                        |
|-------------|----------------------------------------|----------------------------|
| Identity    | Address                                | ERC-8004                   |
| **Execution** | Smart Contract (definition + invocation) | **This ERC**             |
| Verify      | Consensus                              | ERC-8274                   |
| Anchor      | On-chain State                         | ERC-8263                   |
| Settlement  | Value Transfer                         | ERC-8275                   |
| Prove       | Logs / Audit Trail                     | ERC-8281 + ERC-8299        |

There are also two layers built on top of this base:

```
  ┌── Ecosystem Layer ──────────────────────────────────────────────────┐
  │                                                                      │
  │  ┌───────────────┐   ┌───────────────┐   ┌───────────────────────┐  │
  │  │   ERC-8183    │   │   ERC-8273    │   │       ERC-8257        │  │
  │  │ Labor Market  │   │Authorization  │   │    Skill Registry     │  │
  │  └───────────────┘   └───────────────┘   └───────────────────────┘  │
  │                                                                      │
  └───────────────────────────────┬──────────────────────────────────────┘
                                  │ all depend on
  ┌── Base Layer ─────────────────▼──────────────────────────────────────┐
  │                                                                       │
  │  Identity → Execution → Verify → Anchor → Settlement →   Prove       │
  │  ERC-8004   [This ERC]   ERC-8274  ERC-8263  ERC-8275   8281+8299    │
  │                                                                       │
  └───────────────────────────────────────────────────────────────────────┘
```

Execution is the last missing brick in the base layer. Without it, every ecosystem ERC is forced to define its own task format rather than composing on a shared primitive — ERC-8183 uses a free-form `description` string, ERC-8001 uses opaque `executionData` bytes, ERC-8004 delegates entirely to off-chain A2A/MCP.


## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

---

### AgentTask — Task Definition

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AgentTask {
    bytes32 taskId;             // Unique task identifier; caller-supplied
    bytes32 agentWorkflowHash;  // keccak256 of the workflow definition (CID or inline JSON)
    bytes   agentWorkflow;      // Workflow definition plaintext; OPTIONAL (hash is authoritative)
    address handler;            // Contract implementing IAgentHandler
    uint256 deadline;           // Task expiry as Unix timestamp
}
```

**`agentWorkflowHash`** is the cryptographic commitment to the complete workflow definition for this task. It MUST be computed as `keccak256` of the canonical workflow document (see [Agent Workflow Definition](#agent-workflow-definition)). It is written into the `CallAgent` event and is immutable for the lifetime of the task. All subsequent `onAgentStep` and `onAgentProve` calls MUST be consistent with the workflow committed here.

**`taskId`** is caller-supplied. The caller is responsible for uniqueness within its context.

---

### IAgentCaller — Task Dispatch

```solidity
interface IAgentCaller {

    /// @notice Emitted when an agent task is dispatched.
    /// @param taskId            Unique task identifier
    /// @param requester         Address that called callAgent()
    /// @param agentWorkflowHash Commitment to the workflow definition
    /// @param agentWorkflow     Workflow plaintext; may be empty
    /// @param inputHash         keccak256 of the caller-supplied input
    /// @param input             Input plaintext; may be empty
    /// @param handler           IAgentHandler contract address
    /// @param deadline          Task expiry timestamp
    event CallAgent(
        bytes32 indexed taskId,
        address indexed requester,
        bytes32         agentWorkflowHash,
        bytes           agentWorkflow,
        bytes32         inputHash,
        bytes           input,
        address         handler,
        uint256         deadline
    );

    /// @notice Dispatch an agent task.
    /// @param task      The task definition
    /// @param inputHash keccak256 of the input
    /// @param input     Input plaintext; MAY be empty bytes
    /// @return taskId   The dispatched task identifier
    function callAgent(
        AgentTask calldata task,
        bytes32           inputHash,
        bytes    calldata input
    ) external returns (bytes32 taskId);
}

---

### IAgentHandler — Workflow Callbacks

```solidity
interface IAgentHandler {

    /// @notice Called by an agent to advance the workflow by one step.
    ///         Replaces both "pre-reply" and "reply" callbacks; stage + isFinal carry
    ///         the distinction. MAY be called multiple times for the same task.
    ///
    /// @param taskId      Task identifier
    /// @param inputHash   MUST match CallAgent.inputHash for this task
    /// @param outputHash  keccak256 of this step's output; MAY be zero if no output yet
    /// @param output      Step output plaintext; MAY be empty
    /// @param agentId     ERC-8004 agent identity (uint256)
    /// @param agent       msg.sender — the calling agent address
    /// @param stage       Workflow stage index (0-based); see Workflow Stage Semantics
    /// @param isFinal     true = this is the task's final result
    /// @param data        Stage-specific extensible payload
    function onAgentStep(
        bytes32        taskId,
        bytes32        inputHash,
        bytes32        outputHash,
        bytes calldata output,
        uint256        agentId,
        address        agent,
        uint8          stage,
        bool           isFinal,
        bytes calldata data
    ) external;

    /// @notice Called to submit a cryptographic proof for a specific workflow stage.
    ///         MAY be called for any stage, including intermediate stages.
    ///         MAY be called by a third party, not only by the agent.
    ///
    /// @param taskId      Task identifier
    /// @param inputHash   MUST match CallAgent.inputHash for this task
    /// @param outputHash  MUST match the outputHash from onAgentStep(stage=N)
    /// @param proof       Raw proof bytes; encoding is verifier-specific
    /// @param verifier    IAgentVerifiable address (ERC-8274) used to verify this proof
    /// @param stage       The workflow stage this proof attests to
    function onAgentProve(
        bytes32        taskId,
        bytes32        inputHash,
        bytes32        outputHash,
        bytes calldata proof,
        address        verifier,
        uint8          stage
    ) external;
}
```

**Minimum path.** A conforming handler need only process `onAgentStep(stage=0, isFinal=true)` for the simplest single-agent, post-hoc scenario. All other stages and `onAgentProve` are OPTIONAL.

---

### Agent Workflow Definition

`agentWorkflowHash` commits to a workflow definition document. The document SHOULD be stored on a content-addressed system (e.g. IPFS) so that anyone can retrieve and verify the full definition from the hash alone.

The exact format of the workflow document is not specified in this version of the ERC and is left as an open question for community input. Standardizing the workflow document format across the ecosystem — including alignment with existing workflow description languages — warrants dedicated discussion.

What the workflow document MUST express, regardless of format:

- **Behavioral instructions**: what the agent is configured to do (the role previously played by `systemPrompt`). Opaque to this ERC; semantics are agent-implementation-specific.
- **Model or agent type**: which model or agent class should handle this task. Kept off-chain to avoid on-chain registry governance overhead.
- **Stage definitions**: which workflow stages are active for this task, in what order, and with what parameters. Stages cover four semantic categories: executor selection (stage 0), input preparation (stage 1), multi-agent orchestration (stage 1+), and output consensus (stage 2+).

The workflow document SHOULD be stored on a content-addressed system (e.g. IPFS) so that the full definition is retrievable and verifiable from `agentWorkflowHash` alone.

The workflow state machine — which stages are required, which transitions are valid, and which invariants must hold — is managed by the `AgentVerifier` (ERC-8274). This ERC does not define state storage or transition logic.

---

---

## Rationale

### Workflow Stage Model

A simple request–response model is sufficient for the most basic agent invocations, but real-world deployments quickly encounter problems that a single callback cannot express. The workflow model exists to address four distinct classes of problem that arise as agent systems scale.

**Stage 0 — Executor selection.** In open agent networks, multiple agents compete to handle a task. Without a standard selection stage, every protocol reinvents its own assignment mechanism. The workflow model supports competitive bidding (price-based), VRF-based random selection, reputation-weighted assignment (ERC-8004), and stake-to-claim with timeout rotation — all as composable stage types that the caller commits to upfront and the handler enforces.

**Stage 1 — Input preparation.** The input a caller commits to on-chain (`inputHash`) and the input a model actually processes may differ due to sanitization, template injection, or RAG context assembly. Without a formal preparation stage, this gap is invisible to verifiers. Stage 1 provides a standard slot for WYRIWE (ERC-8299) input provenance attestation, OCP (ERC-8281) temporal anchoring, pre-action verdict gating (the verifier approves the input before inference begins), and TEE channel establishment. These mechanisms cannot be retrofitted after inference; they must be committed before it.

**Stage 1+ — Multi-agent orchestration.** Many useful agent tasks require coordination across multiple agents: a classifier routes to a specialist, a summarizer feeds a critic, a planner delegates to executors. Without a workflow stage for orchestration, these patterns collapse into ad-hoc off-chain logic with no on-chain record of coordination. Stage 1+ provides a standard slot for sequential chains (A→B→C with each step's `outputHash` feeding the next as `inputHash`), parallel fanout with aggregation, conditional routing based on intermediate results, and inter-agent message passing — all with an auditable on-chain trace.

**Stage 2+ — Output consensus.** Distributed inference networks, where multiple nodes independently execute the same task and must agree on an output, cannot be expressed as a single `onAgentStep` call. Stage 2+ provides standard slots for commit-reveal protocols (each node commits a hash, then reveals; protects against last-mover advantage), BFT-style multi-round voting (analogous to Tendermint pre-vote / pre-commit rounds), and optimistic finalization with a challenge window. These patterns are directly applicable to the distributed inference model described in ERC-8275.

**The minimum path remains simple.** None of these stages are mandatory. A caller that needs none of this complexity calls `callAgent()` and receives a single `onAgentStep(stage=0, isFinal=true)`. The workflow machinery is available without being imposed.

### Input Verification and WYRIWE Integration

The `inputHash` recorded in `CallAgent` is a *declared* commitment — it reflects what the caller intended to send to the model. However, the input a model actually processes may differ due to sanitization transforms, template injection, or RAG context assembly applied by the inference gateway. Without closing this gap, a verifier operating on `inputHash` is verifying a claim about an input the model may never have seen.

WYRIWE (ERC-8299) addresses this by introducing a provable chain of custody between the declared input and the attested input:

```
declared inputHash  (CallAgent event, on-chain commitment)
        ↓
sanitization transform  (applied by inference gateway, specified by CID)
        ↓
attested inputHash  (WYRIWE attestation, proven by gateway signature / ZK / TEE)
```

When a workflow includes a WYRIWE stage (stage=1), the agent submits the WYRIWE attestation via `onAgentStep(stage=1, data=<attestation>)` before inference begins. Verifiers consuming `onAgentProve` MUST key on the attested `inputHash` from the WYRIWE attestation, not the declared `inputHash` from `CallAgent`.

The `agentWorkflowHash` pre-commits the authorized sanitization pipeline CID. Because this commitment is on-chain and immutable, the gateway cannot substitute an unauthorized transform after seeing the input. The WYRIWE attestation then proves the gateway actually applied the committed pipeline — closing the loop between caller authorization and execution reality.

**No-transform invariant.** When no sanitization transform is applied, the attested `inputHash` MUST equal the declared `inputHash`. This equality is a conformance condition enforced by the verifier, not a derived assumption — an implementation that skips WYRIWE attestation on the grounds that "nothing changed" provides no proof that nothing changed.

### Stage State Management

This ERC defines the callback interface for workflow stages but does not specify how stage state is tracked — which stages have been completed, which transitions are valid, and what invariants must hold before a stage can advance. Different agent implementations may handle this in fundamentally different ways: some may enforce strict sequencing on-chain, others may treat stage ordering as advisory and validate only the final result, and others still may delegate state tracking entirely to off-chain infrastructure.

The recommended approach is to manage stage state inside the `AgentVerifier` implementation (ERC-8274). `IAgentVerifier` is explicitly designed to be stateful — it wraps application-level context about which agents are authorized, which tasks are in progress, and what verification policy applies. This makes it the natural home for workflow state: the `AgentVerifier` can track which `onAgentStep` calls have been received per task, enforce that stage=1 (input preparation) completes before inference proceeds in a pre-action workflow, and validate that consensus rounds reach the required threshold before `isFinal=true` is accepted.

Keeping state management in `AgentVerifier` rather than in this ERC preserves the dispatch interface's neutrality — the same `onAgentStep` and `onAgentProve` callbacks work regardless of verification policy — and allows different verification regimes (optimistic, ZK, TEE, multisig, BFT) to enforce their own stage semantics without requiring changes to the base interfaces.

### Pre-action Verification versus Post-hoc Attestation

Two fundamentally different verification shapes exist for agent output, and each has valid use cases.

**Post-hoc attestation** is the simpler path: the agent executes inference, submits a result via `onAgentStep(isFinal=true)`, and a proof is submitted afterward via `onAgentProve`. The verifier attests that the output was correctly produced — but the handler has already received the result before verification completes. This is appropriate for most use cases: the proof provides an auditable record, and any fraud is detectable after the fact.

**Pre-action gating** inverts this: the verifier issues a verdict on the *input* before inference begins, and only a passing verdict allows execution to proceed. This is necessary when the consequences of acting on an unauthorized or malformed input are irreversible — for example, a task that authorizes an on-chain token transfer or triggers an external action. In these cases, post-hoc detection is insufficient because the action has already occurred.

The design tension is real. Pre-action gating requires more contract interactions (a verdict round-trip before inference), separates the verdict from the inference step, and adds latency. It is also a better fit for distributed inference models (ERC-8275) where multiple nodes independently commit to verdicts before any of them executes — verdict reuse across multiple inference candidates becomes possible. Post-hoc attestation requires fewer interactions, composes more naturally with existing agent frameworks, and keeps the execution path simple.

This ERC does not mandate either shape. Both are expressible through the same interface: post-hoc uses `onAgentStep(stage=0, isFinal=true)` followed by `onAgentProve`; pre-action uses `onAgentStep(stage=1, isFinal=false)` to submit the verdict commitment before inference, then `onAgentStep(isFinal=true)` for the result. The choice belongs to the workflow definition and the `AgentVerifier` policy, not to the dispatch interface.

---

## Backwards Compatibility

This ERC introduces new interfaces with no conflicts with existing ERCs. ERC-8274, ERC-8275, ERC-8004, and ERC-8299 integrate with this ERC as optional dependencies; none require modification.

The minimum conforming path — `callAgent()` → `onAgentStep(stage=0, isFinal=true)` — is equivalent in behavior to the simplest existing patterns and requires no additional infrastructure.

---

## Security Considerations

**`inputHash` integrity depends on handler verification.** The caller computes `inputHash = keccak256(input)` off-chain and passes it alongside the optional `input` plaintext. Because the ERC cannot mandate behavior of off-chain agents, the on-chain `IAgentHandler` implementation SHOULD verify `keccak256(input) == inputHash` on receipt if plaintext is provided. Any mismatch is also detectable by replaying the `CallAgent` event. Callers that include plaintext `input` in the event accept that it is publicly visible in the mempool before the task executes; sensitive inputs SHOULD be withheld from the event and delivered to the agent through an off-chain channel.

**`agentWorkflowHash` pre-commits the execution protocol.** Because the full workflow definition — including the WYRIWE sanitization pipeline CID — is committed at dispatch time, an agent cannot substitute an unauthorized transform after seeing the user input. Any deviation between the committed workflow and the executed steps is detectable by the `AgentVerifier`.

**Callers SHOULD use content-addressed workflow documents.** Storing the workflow document at a mutable URL allows the document to change after `agentWorkflowHash` is committed. Callers SHOULD use IPFS CIDs or equivalent content-addressed references so the document is retrievable and verifiable by anyone.

**Handlers SHOULD guard against task replay.** `taskId` is caller-supplied and is not deduplicated by this ERC. A handler that processes the same `taskId` twice may produce duplicate effects. Handlers SHOULD track which `taskId` values have been processed and reject duplicate `onAgentStep` or `onAgentProve` calls for the same task.

**Deadline expiry is the only built-in revocation mechanism.** This ERC does not define revocation semantics for the model or pipeline referenced by the workflow definition. If the workflow's target model or inference provider becomes unavailable or unsafe after a task is dispatched, the task expires naturally at `deadline`. Callers SHOULD set short deadlines for high-risk tasks.

---

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
