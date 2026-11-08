---
eip: 9999
title: Agent Meditation Mechanism
description: Attributable, versioned self-maintenance records of an AI agent across runtime, memory and skills, tasks and roles, and cognition
author: Gary Yang (@garyyang-finchip)
discussions-to: https://ethereum-magicians.org/t/placeholder
status: Draft
type: Standards Track
category: ERC
created: 2026-11-09
requires: 165, 6372
---

## Abstract

This ERC defines a minimal on-chain registry through which an AI agent records its own self-maintenance: the checking, cleaning, repair, updating and iteration of its own state. The state of an agent is described in four fixed layers: runtime (layer 0); memory and skills (layer 1); tasks and roles (layer 2); cognition (layer 3). For every enrolled subject the registry keeps a versioned maintenance policy, an optional floor of minimum requirements set by a controller, one commitment per layer, the root of every registered state version, and per-layer completion checkpoints from which maintenance status is derived. Each maintenance cycle is registered as one record that the registry checks for linkage to the state the cycle was computed against, for the policy version that governs it, for the consistency of its declared scope, completions and outcome, and for time ordering. An optional activity signal (a pulse) is kept apart from maintenance timeliness. The mechanism is first-person: only the subject, or an operator the subject authorizes, writes records about the subject; everyone else reads them.

## Motivation

An agent keeps its identity while its code, dependencies, memories, skills, task plans and ways of judging keep changing. Agent runtimes increasingly perform this change in the background: self-checks, dependency walks, memory consolidation, re-planning and reflection. Those processes run off-chain and their results stay local. Nothing connects the successive states of one agent into a history that another party can recognize, and nothing lets a counterparty ask simple questions before relying on an agent:

- Which state is currently registered, and since when?
- Which layers were checked recently, and which of them changed?
- Under which rules, in effect at the time, was a change adopted, and who authorized the submission?
- Did a cycle adopt an update, confirm that nothing needed to change, or fail, and in which layers?
- When an agent claims to have improved, what was evaluated and what does the claim cover?

This ERC standardizes the shared semantics and the query surface for those questions. It does not standardize how an agent maintains itself. What goes on chain is what other parties need and what a neutral, time-ordered ledger is good at: the attributable registration of a subject, of versioned rules, of state commitments before and after each cycle, of per-layer completion times, and of results. The content of the state stays off chain and is committed to, not published.

The on-chain part is deliberately bounded. A registry can verify who submitted a record, that the record links to the state the cycle was computed against, that layers outside the declared scope did not change, that a completion is not registered with a time earlier than the previous one, and that the declared outcome agrees with the declared per-layer completions. A registry cannot verify that the off-chain routine ran, that a self-check passed, or that a change is an improvement. Those claims are attributable and time-ordered, and they are supported only as far as the evidence referenced by a record supports them.

The mechanism is intentionally not social. Enrollment, policy, records and status involve one subject and the parties it has authorized. Other systems reading the records (identity registries, assertion registries, safety frameworks, dispute processes, task mechanisms) is a consequence of composability, not a requirement of this specification.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals, as shown here.

### Definitions

- **Subject**: the address whose self-maintenance is recorded. Records are attributed to the subject regardless of which authorized account submitted them.
- **Controller**: an optional address named by the subject, holding a fixed set of rights over the subject's requirements.
- **Operator**: an address the subject authorizes to submit records or policy on its behalf.
- **Layer**: one of four fixed parts of the subject's state, indexed 0 to 3. Layer bitmasks use bit `1 << layer`.
- **Layer state document**: the off-chain document describing the stable state of one layer.
- **Layer commitment**: the `bytes32` commitment to a layer state document, computed as specified below.
- **State root**: the `bytes32` value derived from the four layer commitments.
- **State version**: a per-subject counter that advances whenever at least one layer commitment changes.
- **Policy**: the subject's versioned declaration of which layers it maintains, which of them carry a timeliness requirement and at which interval, which triggers it accepts, whether an activity signal is tracked, and how much it discloses.
- **Floor**: the controller's versioned declaration of minimum requirements that the policy cannot relax.
- **Cycle**: one off-chain run of maintenance covering one or more layers.
- **Cycle record**: the on-chain registration of one cycle.
- **Pulse**: an activity signal without maintenance content.
- **Clock**: the timepoint source of a deployment, as defined by [ERC-6372](./eip-6372.md).

### Layers

| Index | Name | What the layer describes |
| --- | --- | --- |
| 0 | Runtime | Code and configuration, dependencies, adapters to external interfaces (such as APIs and tool protocols), authorization configuration, self-check suite |
| 1 | Memory and skills | Memory organization and digest, skill inventory with versions and package hashes, the harness configuration that manages them |
| 2 | Tasks and roles | Current roles, short- and mid-term plans, tasks taken on with their version bindings to skills and services, services offered |
| 3 | Cognition | Self-model (capabilities, limits, resources, applicability), assumptions with their evidential status, judgment strategies, reflection methods, the policy the subject maintains itself under |

Layer indices and semantics are fixed by this specification. Layers 1 and 2 may both mention the same skill: layer 1 describes whether the skill is held, complete, current and worth keeping; layer 2 describes which tasks use it and in which version. The order of the layers expresses increasing abstraction. It does not prescribe an order of execution: a cycle MAY cover any non-empty subset of layers, and a policy MAY declare dependencies between layers off chain.

Timed observations (balances, endpoint reachability, resource usage) are not part of a layer state document. They belong to the cycle record document.

### Commitment format

Let `JCS(d)` denote the UTF-8 serialization of a JSON document `d` under the JSON Canonicalization Scheme ([RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)).

Every layer state document MUST contain a string member `schema` identifying its schema and an integer member `layer` equal to its layer index. The schema identifiers of this version are `amm.layer.runtime/1`, `amm.layer.memory-skills/1`, `amm.layer.tasks-roles/1` and `amm.layer.cognition/1`; their JSON Schemas are part of the reference assets.

```text
TAG_LAYER_COMMITMENT = keccak256("AgentMeditationMechanism/LayerCommitment/v1")
TAG_STATE_ROOT       = keccak256("AgentMeditationMechanism/StateRoot/v1")

schemaHash  = keccak256(bytes(schema))
contentHash = keccak256(JCS(document))
commitment  = keccak256(abi.encode(TAG_LAYER_COMMITMENT, uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt))
root        = keccak256(abi.encode(TAG_STATE_ROOT, bytes32 c0, bytes32 c1, bytes32 c2, bytes32 c3))
```

`salt` MAY be zero. A non-zero salt SHOULD be used when the document content could be guessed from public information, and MUST be disclosed together with the document whenever the document is disclosed. The commitment to an off-chain policy document or cycle record document is `keccak256(JCS(document))`.

### Clock

A registry MUST implement ERC-6372. All timepoints in this specification are `uint48` values in the clock domain of the registry. A registry conforming to this version MUST use `CLOCK_MODE()` equal to `mode=timestamp`; intervals are therefore seconds. A deployment MUST NOT change its clock mode.

Two kinds of time appear in records. **Reported** timepoints (`reportedStartedAt`, `reportedEndedAt`) are supplied by the submitter and describe when the off-chain cycle ran. **Recorded** timepoints are read from the clock when the registry accepts a transaction. The registry checks the ordering of reported timepoints against each other, against the clock and against previously registered completions; it does not and cannot verify that a cycle ran at the reported time.

### Roles and authorization

**Enrollment.** A subject enrolls itself by calling `enroll` with four baseline layer commitments, an initial policy, and an optional controller with a set of controller rights. `msg.sender` is the subject. A subject MUST NOT enroll twice. Enrollment registers state version 1 with the baseline root, policy version 1 effective from the recorded enrollment time, and an activity signal at that time. The baseline is a registration of state, not a completion of any layer.

**Controller rights** are a bitmask: `RIGHT_FLOOR = 1` (may set the floor), `RIGHT_DEMAND = 2` (may demand completion of layers by a deadline), `RIGHT_REVOKE_OPERATORS = 4` (may revoke the subject's operators). Rights are fixed when the controller is appointed. A controller MAY transfer its position to another address with a subset of its rights, MAY shrink its own rights, and MAY renounce; the subject MUST NOT change or remove an existing controller. When no controller is set, the subject MAY appoint one with any rights. A controller MUST NOT be the subject itself. A controller cannot submit cycle records or pulses, and cannot grant operators.

**Operators** are granted by the subject with a permission bitmask: `PERM_REPORT = 1` (may submit cycle records and pulses), `PERM_PULSE = 2` (may submit pulses), `PERM_POLICY = 4` (may set policy). Operators are revoked by the subject, or by a controller holding `RIGHT_REVOKE_OPERATORS`. Submissions by operators are attributed to the subject; events carry the submitter separately.

### Policy and floor

```solidity
struct Policy {
    bytes32 policyHash;      // commitment to the off-chain policy document, may be zero
    string policyURI;        // optional locator
    uint8 supportedLayers;   // layers the subject maintains
    uint8 requiredLayers;    // subset of supportedLayers that carry a timeliness requirement
    uint8 allowedTriggers;   // bitmask over trigger codes, bit (1 << trigger)
    uint8 disclosure;        // 0 commitment only, 1 summary, 2 full
    uint48 dueWindow;        // warning window before a deadline
    uint48 pulseInterval;    // 0 = activity signal not tracked
    uint48[4] maxInterval;   // per layer, in clock units
}

struct Floor {
    uint8 requiredLayers;
    uint48 pulseInterval;
    uint48[4] maxInterval;
}
```

A policy is valid only if `supportedLayers` is non-empty and within `0x0F`, `requiredLayers` is a subset of `supportedLayers`, `allowedTriggers` is non-empty and within `0x0F`, `disclosure` is at most 2, and every required layer has a non-zero `maxInterval`. A floor is valid only if `requiredLayers` is within `0x0F` and every required layer has a non-zero `maxInterval`.

Policies are versioned per subject. `setPolicy` (subject, or operator with `PERM_POLICY`) appends a new version and records its effective-from timepoint. Policy versions are never modified or deleted. Setting a policy MUST NOT change any layer checkpoint. The floor is set by a controller holding `RIGHT_FLOOR`; each call increments the floor version and replaces the floor.

**Effective requirements** combine the current policy and the floor: `supportedLayers` is the policy's; `requiredLayers` is the union of both; for each layer, the effective `maxInterval` is the smallest non-zero interval among the policy's (if the policy requires the layer) and the floor's (if the floor requires the layer); the effective `pulseInterval` is the smallest non-zero of the two; `dueWindow` is the policy's. The policy can therefore tighten requirements and add requirements, and cannot relax what the floor requires.

### Layer checkpoints and state versions

For each subject and layer the registry keeps:

```solidity
struct LayerCheckpoint {
    bytes32 commitment;              // current registered state commitment
    uint48 lastCompletedAt;          // reported completion time of the last completed routine, 0 = never
    uint48 lastCompletedRecordedAt;  // clock value when that completion was recorded
    uint32 completedUnderPolicy;     // policy version governing that completion
    uint64 lastChangedVersion;       // state version at which the commitment last changed
}
```

The subject's head record keeps the current state version, the current root, the number of records (cycle records and pulses), the last activity signal, the planning hint and the controller relation. The registry MUST keep the root of every state version (`rootAt`). The state version advances only when at least one layer commitment changes; a cycle that changes nothing does not advance it. Pulses never advance it.

### Cycle records

```solidity
struct CycleReport {
    uint64 baseVersion;            // state version the cycle was computed against
    bytes32 preRoot;               // state root the cycle was computed against
    bytes32[4] postCommitments;    // layer commitments after the cycle, all four layers
    uint8 layerMask;               // layers in scope
    uint8 completedLayers;         // layers whose routine was completed, subset of layerMask
    uint16 opsMask;                // bit (layer * 4 + op); op: 0 clean, 1 repair, 2 update, 3 iterate
    uint8 outcome;                 // 0 COMPLETED, 1 PARTIAL, 2 ABORTED, 3 FAILED
    uint8 trigger;                 // 0 SCHEDULED, 1 EVENT, 2 COMMANDED, 3 SELF
    uint32 policyVersion;          // policy version in effect when the cycle started
    uint48 reportedStartedAt;
    uint48 reportedEndedAt;        // completion time of every completed layer
    uint48 nextPlannedAt;          // planning hint, 0 = none
    uint64 restoresVersion;        // non-zero when the post state restores an earlier state version
    bytes32 recordHash;            // commitment to the off-chain cycle record document, may be zero
    string recordURI;              // optional locator
}
```

`report(subject, r)` is callable by the subject or an operator with `PERM_REPORT`. The registry MUST reject the record unless all of the following hold:

1. **Scope.** `layerMask` is non-empty and within `0x0F`; `completedLayers` is a subset of `layerMask`; every nibble of `opsMask` belonging to a layer outside `layerMask` is zero.
2. **Outcome consistency.** `COMPLETED` requires `completedLayers == layerMask`; `PARTIAL` requires `completedLayers` to be non-empty and different from `layerMask`; `ABORTED` requires `completedLayers != layerMask`; `FAILED` requires `completedLayers == 0`.
3. **Governing policy.** `policyVersion` exists for the subject; its effective-from timepoint is at or before `reportedStartedAt`; and, if a later version exists, `reportedStartedAt` is before that later version's effective-from timepoint. `layerMask` is a subset of the governing policy's `supportedLayers`, and the governing policy allows `trigger`.
4. **Linkage.** `baseVersion` equals the subject's current state version and `preRoot` equals the current root.
5. **Unscoped layers unchanged.** For every layer outside `layerMask`, `postCommitments[layer]` equals the current commitment.
6. **Time ordering.** `reportedStartedAt <= reportedEndedAt <= clock()`; and for every layer in `completedLayers`, `reportedEndedAt` is strictly greater than that layer's `lastCompletedAt`.
7. **Restore claim.** If `restoresVersion` is non-zero, it is smaller than the current state version and `rootAt(restoresVersion)` equals the root of `postCommitments`.

On acceptance the registry: sets the commitment of every layer whose post commitment differs from its current commitment and, if any differs, increments the state version and stores the new root; for every layer in `completedLayers`, sets `lastCompletedAt = reportedEndedAt`, `lastCompletedRecordedAt = clock()` and `completedUnderPolicy = policyVersion`, and clears any outstanding demand for that layer whose `demandedAt` is at or before `reportedEndedAt`; increments the record count; sets the last activity signal to `clock()` and the planning hint to `nextPlannedAt`; and emits `CycleRecorded` with the derived `changedLayers` plus one `LayerCommitmentChanged` per changed layer.

A layer in scope but not in `completedLayers` MAY still change its commitment: a cycle that modified a layer and then failed registers what actually happened. A layer in `completedLayers` with an unchanged commitment registers that the routine ran and found nothing to change. A record with `opsMask == 0` is valid. The whole-cycle outcome and the per-layer results are distinct facts and are both recorded.

Rollback is a cycle like any other: the post state equals an earlier registered state, the record carries `restoresVersion`, and the state version advances. History is never rewritten.

### Pulse

`pulse(subject, nextPlannedAt)` is callable by the subject or an operator with `PERM_PULSE` or `PERM_REPORT`. It increments the record count, sets the last activity signal to `clock()` and stores the planning hint. It MUST NOT change any layer checkpoint, the state version, the root, or any deadline. A pulse is the degenerate cycle record with empty scope; every accepted cycle record is also an activity signal.

### Demand

`demand(subject, layerMask, dueBy)` is callable by a controller holding `RIGHT_DEMAND`, with `dueBy` in the future. For each layer in `layerMask` it stores `(demandedAt = clock(), dueBy)`, replacing any earlier demand for that layer. An outstanding demand lowers the layer's deadline to `dueBy` in status derivation. It is cleared by a completion of the layer whose `reportedEndedAt` is at or after `demandedAt`, or by `withdrawDemand`. A demand requests maintenance; it does not perform it and does not change any state.

### Status derivation

`layerStatus(subject, layer)` returns a status, the deadline it was judged against (0 if none) and whether the layer has never completed a routine since enrollment:

- `NOT_ENROLLED` if the subject is not enrolled.
- If the layer is not in the effective `requiredLayers`: `UNSCHEDULED` if it is in the policy's `supportedLayers`, otherwise `UNSUPPORTED`.
- Otherwise let `anchor` be the layer's `lastCompletedAt`, or the enrollment time if the layer never completed; let `deadline = anchor + maxInterval[layer]`, lowered to `dueBy` when a demand is outstanding; then `OVERDUE` if `clock() >= deadline`, `DUE` if `clock() + dueWindow >= deadline`, else `FRESH`.

`FRESH` is a statement about the timeliness of registered maintenance only. It is not a statement about health, readiness or capability.

`signalStatus(subject)` returns `NOT_ENROLLED`, `NOT_TRACKED` (effective `pulseInterval` is zero), `PRESENT`, or `SILENT` when `clock()` exceeds `lastSignalAt + pulseInterval`, together with `lastSignalAt` and, when silent, the timepoint at which the signal became silent. Activity and maintenance are independent: a subject can be silent and fresh, or present and overdue. Silence means that no signal was observed within the expected window; it does not by itself mean that the subject is gone or that maintenance failed.

### Interface

A registry MUST implement the following interface and MUST report support for it through [ERC-165](./eip-165.md). The ERC-165 identifier of `IAgentMeditation` is `0x9c81b550`. The full interface with structures, events and documentation comments is at [`IAgentMeditation.sol`](../assets/eip-9999/contracts/IAgentMeditation.sol).

```solidity
interface IAgentMeditation {
    enum Outcome { COMPLETED, PARTIAL, ABORTED, FAILED }
    enum MaintenanceStatus { NOT_ENROLLED, UNSUPPORTED, UNSCHEDULED, FRESH, DUE, OVERDUE }
    enum SignalStatus { NOT_ENROLLED, NOT_TRACKED, PRESENT, SILENT }

    function enroll(bytes32[4] calldata baseline, Policy calldata policy, address controller, uint8 controllerRights) external;
    function setOperator(address operator, uint8 permissions) external;
    function revokeOperator(address subject, address operator) external;
    function setController(address subject, address newController, uint8 rights) external;

    function setPolicy(address subject, Policy calldata policy) external;
    function setFloor(address subject, Floor calldata floor) external;
    function demand(address subject, uint8 layerMask, uint48 dueBy) external;
    function withdrawDemand(address subject, uint8 layerMask) external;

    function report(address subject, CycleReport calldata r) external returns (uint64 seq);
    function pulse(address subject, uint48 nextPlannedAt) external returns (uint64 seq);

    function headOf(address subject) external view returns (Head memory);
    function checkpointOf(address subject, uint8 layer) external view returns (LayerCheckpoint memory);
    function rootAt(address subject, uint64 stateVersion) external view returns (bytes32);
    function policyOf(address subject, uint32 version) external view returns (Policy memory);
    function policyEffectiveFrom(address subject, uint32 version) external view returns (uint48);
    function floorOf(address subject) external view returns (Floor memory);
    function demandOf(address subject, uint8 layer) external view returns (Demand memory);
    function operatorPermissions(address subject, address operator) external view returns (uint8);
    function requirementsOf(address subject) external view returns (Requirements memory);
    function layerStatus(address subject, uint8 layer) external view returns (MaintenanceStatus status, uint48 deadline, bool neverCompleted);
    function signalStatus(address subject) external view returns (SignalStatus status, uint48 lastSignalAt, uint48 silentSince);
    function computeRoot(bytes32[4] calldata commitments) external pure returns (bytes32);
    function computeLayerCommitment(uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt) external pure returns (bytes32);
}
```

The `Head`, `Demand` and `Requirements` structures are:

```solidity
struct Head {
    bool enrolled;
    address controller;
    uint8 controllerRights;
    uint32 policyVersion;
    uint32 floorVersion;
    uint64 stateVersion;
    uint64 recordCount;
    bytes32 root;
    uint48 enrolledAt;
    uint48 lastSignalAt;
    uint48 nextPlannedAt;
}

struct Demand {
    uint48 demandedAt;   // 0 = none
    uint48 dueBy;
}

struct Requirements {
    uint8 supportedLayers;
    uint8 requiredLayers;
    uint48 dueWindow;
    uint48 pulseInterval;
    uint48[4] maxInterval;
}
```

A registry MUST also implement `supportsInterface(bytes4)` of ERC-165 and `clock()` and `CLOCK_MODE()` of ERC-6372.

### Events

```solidity
event Enrolled(address indexed subject, address indexed controller, uint8 controllerRights, bytes32 root, uint48 enrolledAt);
event ControllerChanged(address indexed subject, address indexed previousController, address indexed newController, uint8 rights);
event OperatorSet(address indexed subject, address indexed operator, uint8 permissions, address indexed by);
event PolicyUpdated(address indexed subject, uint32 indexed version, bytes32 policyHash, uint48 effectiveFrom, address by);
event FloorUpdated(address indexed subject, uint32 indexed version, uint48 effectiveFrom, address by);
event Demanded(address indexed subject, uint8 layerMask, uint48 dueBy, address by);
event DemandWithdrawn(address indexed subject, uint8 layerMask, address by);
event CycleRecorded(address indexed subject, uint64 indexed seq, uint64 baseVersion, uint64 newVersion, CycleReport report, uint8 changedLayers, uint48 recordedAt, address submitter);
event LayerCommitmentChanged(address indexed subject, uint8 indexed layer, uint64 indexed version, bytes32 previousCommitment, bytes32 newCommitment);
event Pulsed(address indexed subject, uint64 indexed seq, uint48 recordedAt, uint48 nextPlannedAt, address submitter);
```

Full cycle records are available from `CycleRecorded` events; storage keeps the head, the four checkpoints, policy versions, the floor, demands and the root of every state version. A registry MAY store more.

### Off-chain documents

The policy document (`amm.policy/1`) and the cycle record document (`amm.cycle-record/1`) have JSON Schemas in the reference assets. A cycle record document SHOULD state, per layer in scope, the checks performed and their results, timed observations, the changes made with their operation kinds, the evaluation method and result, candidate changes that were formed but not adopted, and the adoption decision (`adopted`, `kept`, `candidate`, `failed`, `restored`). The on-chain `CycleReport` is derived from it. A subject's disclosure level governs what of these documents is served to whom; a level of 0 means that only commitments are published.

## Rationale

**First-person registration.** In registries of identity, assertions and reputation, third parties write about a subject. Self-maintenance is the one thing only the subject can do and only the subject can report. The kernel therefore lets only the subject and its operators write records, lets a controller set requirements and request maintenance without ever submitting a record, and treats everything written as the subject's own attributable claim. Delegated submission does not change attribution.

**Four fixed layers, four commitments.** With the layer count fixed, the registry stores four commitments directly and derives the root from them. That lets it check in-contract that layers outside a cycle's scope did not change, which a single opaque root cannot do, and keeps partial updates cheap. The layers are ordered by abstraction, but a cycle covers any subset, because a fault fix touches one layer while a thorough review touches all four, and because a reflection in layer 3 can send work back down to layer 0.

**Per-layer completion.** A whole-cycle outcome cannot say which layers completed. Keeping `completedLayers` apart from `layerMask`, and keeping both apart from the derived `changedLayers`, distinguishes four facts that are routinely conflated: a layer was checked; the check completed; the check found something; a change was adopted. Finding a fault is a complete check and is not a repair; completing a check and changing nothing is a legitimate result.

**Per-layer freshness.** Completing layer 0 today says nothing about layer 3. Status is therefore computed per layer from that layer's last completion, and a never-completed required layer counts from enrollment, so that enrollment alone never reads as recent maintenance.

**Reported and recorded time.** ERC-6372 fixes the clock interface; it does not make a self-reported execution time trustworthy. Records carry both. Timeliness follows the reported completion time, after ordering checks that prevent a completion from being registered earlier than the previous one or later than now, so that a cycle submitted late keeps its real age; activity follows the recorded time. Applications that need proof of execution time add a start commitment or an external observation on top.

**The policy in effect at the start governs.** A cycle is interpreted under the policy version that was in effect when it started. The subject cannot lower its own bar mid-cycle, a policy update never resets completion times, and a new interval never turns a past overdue state into an on-time one, because the anchor of every deadline is a completion, not a rule change.

**Floor and controller rights.** A subject can always do more than its policy says; what it cannot do is less than its controller requires. The floor is a separate object with its own authority, combined with the policy by minimum, so a layer-3 cycle that "revises the self-model" and then relaxes the subject's policy leaves the effective requirements untouched. Controller rights are fixed at appointment and can only shrink, so the relationship the subject accepted is the one that persists.

**Pulse is not maintenance.** A pulse answers "was there a signal recently", a question lifecycle and coordination protocols answer at second-level cadence with their own semantics. This specification keeps the activity signal because an agent in the middle of a long maintenance window will want to say so, but a pulse refreshes nothing: not a layer, not a deadline, not a count of completions. `nextPlannedAt` is a planning hint; whether it becomes a binding commitment is left to a later extension that would have to define its scope and its change rules.

**History in events, checkpoints in storage.** Contracts cannot read logs. The four checkpoints and the root of every version are the minimum storage that lets another contract answer status and verify a restore claim; everything else about a cycle is in the `CycleRecorded` event.

**What the kernel leaves out.** Verification of records by third parties, a start registration with cancellation and timeout rules, reminders by anyone, do-not-disturb announcements, batched records and accumulated maintenance debt are all useful and all excluded from this version. Each of them is an evaluation model or a workflow of its own; each can be added as an extension or a profile without changing the semantics above.

**Relation to existing work.** Autonomic computing framed self-configuration, self-healing, self-optimization and self-protection as properties of a system that monitors, analyzes, plans and executes over its own knowledge; the four operations of this specification (clean, repair, update, iterate) and the per-layer routine follow that framing. Recent work on continual learning alternates wake and sleep phases with memory consolidation, and agent runtimes ship background consolidation that promotes short-term entries into long-term memory on a schedule; those are implementations of layer 1 whose results stay local. Agent lifecycle protocols define heartbeats and readiness for work assignment; that is a different question from maintenance timeliness, which is why the two signals are kept apart here and why no heartbeat parameters are inherited. Reflection methods that improve later decisions from task feedback have been shown to help, and self-correction without external feedback has been shown to sometimes hurt; this specification therefore asks layer 3 to record candidates, evaluations and adoption decisions rather than to assert improvement.

## Backwards Compatibility

This ERC introduces a new registry and does not modify existing contracts. It depends normatively on ERC-165 and ERC-6372 only.

Adapters to other systems are informative. An agent registered in an [ERC-8004](./eip-8004.md) identity registry may mirror its head (state version, root, last completion times) into its metadata under a key of its choosing; the reputation registry of that ERC does not accept feedback from an agent's owner or operator, and nothing in this specification suggests otherwise: self-maintenance records are facts and evidence, not reputation. Address-anchored agent identity registries may read `signalStatus` and `layerStatus` as evidence for their own liveness and behavior facets. Assertion registries may issue assertions about verified records. Safety frameworks may treat a policy as an adopted specification and cycle records as compliance evidence. Dispute processes may cite records and demand disclosure of the committed documents. Task and swarm mechanisms may require a counterparty's layers to be `FRESH` before acting. None of these adapters changes the semantics of the records they read, and none of them is required to implement this ERC.

## Test Cases

The values below are computed with the reference tooling and checked by the reference test suite.

### Domain tags

```text
TAG_LAYER_COMMITMENT = 0xc76b0a7a69207b3cf002d75e6493bc9fe99e8d75b5096ead1276bc4339b69d85
TAG_STATE_ROOT       = 0xe2251470d039826c2565c6e003924bb890e07cd981b370528c245e47f1c3e7c6
```

### Canonicalization

| Input (JSON) | Canonical form | keccak256 |
| --- | --- | --- |
| `{"b":1,"a":[true,null,"x"],"c":{"z":1.5,"y":"é"}}` | `{"a":[true,null,"x"],"b":1,"c":{"y":"é","z":1.5}}` (non-ASCII characters stay literal UTF-8) | `0xa5bf818c53f5a4b41e090fb63de6621bd9efe8da3a89e87bc41e7fcd004f9031` |
| `{"€":1,"A":2,"a":3,"":4}` | `{"":4,"A":2,"a":3,"€":1}` (members sorted by UTF-16 code units) | `0x22816a6b64184a15ee2d60a54c0f519ec38dbf7310593294a545467c66c5ea77` |
| `{"n":1e21,"m":0.000001,"k":-0,"s":"line\nbreak\ttab\"quote\\"}` | `{"k":0,"m":0.000001,"n":1e+21,"s":"line\nbreak\ttab\"quote\\"}` | `0x8953829f4ccb00b31d6f6ea5b40793765a654514a2049b6e1fb99ab38be2f069` |

### Layer commitments of the worked example

Pre state (the four layer state documents under `examples/mcp-timeout-cycle/baseline/` in the reference assets):

| Layer | schemaHash | contentHash | salt | commitment |
| --- | --- | --- | --- | --- |
| 0 | `0x6a00023d50bfe315bf6650953a4bb81910aef335c63ee465d2f52937b860790b` | `0xa25eae406d69cd3802dbb588487f486e5b5e006b7ef521303ea24406979a4731` | `0x00…00` | `0x053bdcecda479dd30b5bfd7a02661df67b79e978fea6888245df8aa167d6d282` |
| 1 | `0x2862ecb7722af301f96bf7b7127d96568563c9c6cd281308f315e97b433d2055` | `0xf3640f14c472bf43b5e89ea5a0a7d1e3681f47c81a7cf1a0d3f41cc685ed1701` | `0x9b1e4c7a2d5f8b0c3e6a9d1f4b7e0a3c6f9b2e5d8a1c4f7b0e3a6d9c2f5b8e1a` | `0x3a8a0162793df87f7094634e37d9e5d3d8470bd43cc7fee5669f609d922ee9c3` |
| 2 | `0x739b5fc9aa474200ce364ed1db095acd99a4407eb27e258f294f3e65ffff40ad` | `0x1cefdfbcd841dc162bea189aa25d1e3e2a031d5805901a407db4003706cafdd5` | `0x00…00` | `0x3d3356ae1bc86136718f1ecd7f42d8a0570db2d21116c886cab291a789010585` |
| 3 | `0x086a5b8a0101b4013c63de2d7392ddb4ae22c61e33afd0eaef58387952c1f468` | `0xc6e5d3da30fc9d27be29773df620dbed9a359d6bba795d93bafcdb5963e9ede8` | `0x4d7a0c3f6b9e2d5a8c1f4b7e0a3d6c9f2b5e8a1d4c7f0b3e6a9d2c5f8b1e4a7d` | `0xbe9a1abba6f84ec051c3eb91bb19e2d3504d773da883b94aece5ee9e37c79e8e` |

Pre root: `0x090e63d66e6cdb08331fece350bd0320551287d53d6644d5af158b04d94d149f`.

Post state (documents under `examples/mcp-timeout-cycle/post/`; layer 3 is unchanged):

| Layer | contentHash | salt | commitment |
| --- | --- | --- | --- |
| 0 | `0xacd47bc6d2511898088ea3f2b561707ff0f23f434385f4fee7fd53991e50b881` | `0x00…00` | `0xb5a33b6d3732e664a08a19ed068432a6ab1085bf7013b3ffce1ff88ec7dd8519` |
| 1 | `0x205d5acb2bec31ae30aeaad85e5761ff592b1d50011138dc0d5cd2f38fcfb607` | `0xc3f6a9d2e5b8c1f4a7d0e3b6c9f2a5d8e1b4c7f0a3d6e9b2c5f8a1d4e7b0c3f6` | `0xd24fedfca7a64b7596414751a6d4a1ed7a89bf906bce4b453453a7b086d26641` |
| 2 | `0x8c008b3acd189eea792a1c56b70020fef36a2ed9bb75cfa07944bfdeac6115cd` | `0x00…00` | `0x8f03de4a144d8d453c84d2d4546fb0f01af23bd6f7ba31d18dac0c6dd1a942f0` |
| 3 | unchanged | unchanged | `0xbe9a1abba6f84ec051c3eb91bb19e2d3504d773da883b94aece5ee9e37c79e8e` |

Post root: `0x9918ebff7f3bc97ca08580033da3aa99b27871d8d57b2b8c9845221fa3dec3de`.

### Worked example cycle record

The example subject enrolls with the pre state and the policy whose document hash is `0x5dfdd440a0eced1f62839fa0281f21cadacfa0f527642ea586b5f5c1ce5e41d9` (all layers supported and required; intervals 86400, 604800, 2592000 and 7776000; due window 3600; pulse interval 21600; all triggers). An event-triggered cycle then runs from timepoint 1762653600 to 1762654500 and is registered as:

```text
baseVersion        1
preRoot            0x090e63d66e6cdb08331fece350bd0320551287d53d6644d5af158b04d94d149f
postCommitments    the four post commitments above
layerMask          0x0F
completedLayers    0x0F
opsMask            0x0456   (layer 0: repair, update; layer 1: clean, update; layer 2: update; layer 3: none)
outcome            0 (COMPLETED)
trigger            1 (EVENT)
policyVersion      1
reportedStartedAt  1762653600
reportedEndedAt    1762654500
nextPlannedAt      1762740000
restoresVersion    0
recordHash         0xdcbc7047b5bf0d600b98d7829fc37757bdac9406ec992128cc90e910e9645088
```

Expected effects: the state version becomes 2 with the post root; `changedLayers` is `0x07`; every layer's `lastCompletedAt` is 1762654500 and its `completedUnderPolicy` is 1; layer 3's `lastChangedVersion` stays 1 while layers 0 to 2 show 2; `rootAt(1)` is the pre root and `rootAt(2)` the post root. The cycle record document behind `recordHash` records that layer 3 formed a candidate strategy, evaluated it against 12 replayed cases and did not adopt it because the policy requires at least 20 cases.

### Behavioral cases

The reference test suite covers, among others, the following cases, each of which an implementation is expected to reproduce:

1. A pulse changes `lastSignalAt`, the record count and the planning hint, and changes no commitment, no completion time, no state version and no deadline; a subject that only pulses becomes `OVERDUE` at its deadline.
2. A cycle that completes layers 0 and 1 out of a four-layer scope with outcome `PARTIAL` moves only the deadlines of layers 0 and 1.
3. A layer that is required and has never completed is judged from the enrollment time; a policy update that lengthens its interval recomputes the deadline from the same anchor and does not reset it; only a completion moves the anchor.
4. A cycle that ended 20 hours ago and is submitted now registers its reported completion time; its deadline follows that time, not the submission time.
5. A record whose `baseVersion` or `preRoot` does not match the current state is rejected, so a cycle computed against an outdated state cannot overwrite a newer one.
6. A record that changes the commitment of a layer outside its scope is rejected.
7. A record that claims a policy version which was not in effect at `reportedStartedAt` is rejected, in both directions.
8. A record whose `reportedEndedAt` is not strictly later than a completed layer's registered completion is rejected; an identical record submitted twice is therefore rejected the second time.
9. After the controller sets a floor, the subject's policy cannot lower any effective requirement below it, cannot remove a layer the floor requires, and cannot change the controller or its rights; the subject cannot set the floor.
10. A demand lowers a layer's deadline to `dueBy`; a completion whose `reportedEndedAt` precedes `demandedAt` does not satisfy it, a completion at or after `demandedAt` clears it.
11. A rollback registers a new state version whose root equals an earlier `rootAt`; a `restoresVersion` claim that does not match history is rejected.
12. `signalStatus` and `layerStatus` are independent: a subject is silent and fresh at one time, present and overdue at another.
13. The ERC-165 identifier `0x9c81b550` is the exclusive-or of the selectors of the 23 functions of `IAgentMeditation`.

## Reference Implementation

The reference implementation, tooling, schemas, examples and vectors are in the assets of this ERC:

- [`IAgentMeditation.sol`](../assets/eip-9999/contracts/IAgentMeditation.sol) and [`AgentMeditationRegistry.sol`](../assets/eip-9999/contracts/AgentMeditationRegistry.sol): the interface and a registry implementation with a timestamp clock.
- [`schemas/`](../assets/eip-9999/schemas/layer-runtime.schema.json): JSON Schemas of the four layer state documents, the policy document and the cycle record document.
- [`examples/mcp-timeout-cycle/`](../assets/eip-9999/examples/mcp-timeout-cycle/cycle-record.json): the worked example (baseline and post state documents, policy, salts, cycle record).
- [`vectors/`](../assets/eip-9999/vectors/example-mcp-timeout.json): the vectors reproduced in the Test Cases section.

## Security Considerations

**Records are self-reported.** Every cycle record is a claim by the subject. The registry establishes who made the claim, when it was recorded, which state it referred to and which state it registered. It does not establish that a routine ran, that a check passed or that a change improved anything. Consumers that need more than attribution rely on the evidence a record references, on disclosure of the committed documents, on third-party verification, or on later behavior of the subject. A status of `FRESH` means that maintenance was registered on time; it is not a health, readiness or capability signal, and consumers that treat it as one take on the corresponding risk.

**Commitments without content.** A commitment binds the subject to a document it can be asked to disclose; it reveals nothing until then. Content that could be guessed from public information is protected only by a non-zero salt. Disclosure of a document that matches its commitment proves consistency with the registration, not the correctness of the process that produced it. Operators of a registry should expect subjects to publish commitments to documents they never intend to disclose, and consumers should price that in through disclosure levels and the policies they accept.

**Stale and late submissions.** Because timeliness follows the reported completion time, an old cycle submitted late does not look recent, and a completion can never be registered with a time earlier than the previous one. A subject can still delay submission to hide a failed cycle; the monotonic rule and the linkage rule only bound what the delayed record can claim.

**Policy manipulation.** A cycle is interpreted under the version in effect at its start, so the subject cannot relax its policy and then report under the relaxed rules, and policy updates never move completion anchors. What the subject can do is lower its own requirements for the future, which is visible in the policy history and bounded by the floor where a controller exists.

**Controller abuse.** A controller can raise requirements and demand completions, which can make a subject overdue by construction. It cannot submit records, cannot change state, cannot grant itself operator rights and cannot grow its rights after appointment. The subject chose the controller and its rights at appointment; where that choice is made for the subject by its deployer, the subject's status reflects the deployer's requirements, which is the intended meaning.

**Operator keys.** An operator with report permission can register arbitrary commitments as the subject's state and arbitrary completion times within the ordering rules. Compromise of an operator key is compromise of the subject's maintenance history from that point on. The subject and a controller with the corresponding right can revoke operators; the history before revocation stays attributable to the subject because the subject granted the key.

**Self-modification of the cognition layer.** A cycle may revise the subject's self-model, including the policy it maintains itself under. The registry bounds this in two ways: the policy at the start of the cycle governs its interpretation, and the controller's floor and rights are outside the subject's reach. Obligations the subject has adopted elsewhere (safety specifications, task commitments, swarm charters) are not visible to this registry, and a cycle cannot dissolve them by changing a layer commitment; whether such a change happened is only checkable by whoever can read the committed document or holds the obligation. A reference runner should therefore refuse to adopt a layer-3 change that would remove an obligation it knows about, and should record the refusal.

**Divergence between off-chain and on-chain state.** Adopting a new state locally and registering it on chain are not one atomic step. A runner that has adopted a change whose registration failed holds state the registry does not know; a runner whose registration succeeded but which then lost the change holds state the registry contradicts. Runners should keep a pending-synchronization marker, retry registration with the same base version, and, after a partially applied cycle, register what actually happened rather than assume the previous state was restored. Anyone reading `headOf` is reading registered state, not live state.

**Clock mode.** A timestamp clock is as reliable as block timestamps are. Deadlines at the granularity of hours and days are insensitive to the drift block producers can introduce; deployments that need finer timing should not use this mechanism for it.

**Cost and spam.** Every write touches only the writer's own records, so a subject can inflate its own history but cannot touch anyone else's. Frequent small writes are the expected workload and belong on execution layers where they are cheap.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
