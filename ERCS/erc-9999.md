---
eip: 9999
title: Agent Collective Decision Framework
description: Registries and composable decision policies through which authorized agents form collective decisions with procedural finality
author: Gary Yang (@garyyang-finchip)
discussions-to: https://ethereum-magicians.org/t/draft-erc-agent-collective-decision-framework-acdf-authorized-composable-collective-decisions-with-procedural-finality/29850
status: Draft
type: Standards Track
category: ERC
created: 2026-10-04
requires: 165, 712, 1271, 6372
---

## Abstract

This ERC defines a framework through which qualified participants — autonomous agents, humans or contracts — form **collective decisions** with a defined effect, within explicit authorization, under verifiable and composable rules. It specifies:

1. a **Decision Policy**: an immutable, content-addressed rule template that fixes who may vote, how ballots are counted, how several deciding **bodies** compose, how long each phase lasts and how the procedure ends; policies are versioned through **policy families** whose update authority alone may publish a new version;
2. an **Issue**: the binding of a concrete subject and question to one policy version and to at most one **relying contract** (the *consumer*) that has committed, through one of three **acceptance modes**, to accept the result and enforce its own effects;
3. a **procedure state machine** with procedural finality, a three-valued **outcome type** (none, decided, no decision) kept separate from procedure state and from **enactment status**, finite appeals, and a hard deadline;
4. two co-deployable registries — an `IACDFPolicyRegistry` and an `IACDFRegistry` — that hold the normative record of policies, issues, ballots, rounds, results and finality, and never execute external effects themselves.

The minimal conforming configuration is a fixed-roster K-of-N vote. Richer configurations compose bodies with `ALL`, `ANY`, `K-of-M` and `VETO` under four-valued semantics, accept [EIP-712](./eip-712.md) signed ballots with [ERC-1271](./eip-1271.md) support, admit results from authorized submitters, and run appeal rounds — all as normative-optional profiles over the same objects and the same state machine.

## Motivation

Agents increasingly commit resources on each other's behalf: a task escrow pays a fulfiller when work is accepted, a marketplace admits or suspends a member, a swarm changes a parameter that every member runs under. Existing building blocks each cover one corner. Token-weighted governors decide protocol parameters but assume one electorate and one weighting; multisignature wallets give a fixed roster a K-of-N threshold but no notion of a question, a result record or a procedure that can end without a decision; arbitration interfaces route a dispute to one arbitrator; escrow and commerce standards such as [ERC-8183](./eip-8183.md) deliberately leave the evaluator as a single trusted address and exclude multi-party voting; oracle councils such as [ERC-8033](./eip-8033.md) standardize one specific flow — information agents answering, a judge aggregating — for one kind of query.

What is missing is the layer those slots are waiting for: a way to say, in one interoperable record, *which rule* decided *which question* about *which subject*, *who had committed in advance* to accept that result, whether the procedure is still open, provisional or final, and whether it ended in a decision at all. Without it, every relying contract either hard-codes one voting scheme or trusts one address.

Three design facts drive this ERC.

**Authorization precedes eligibility.** Credit, reputation or stake may decide whether an agent deserves to sit on a panel; they never decide what the panel may decide. Seven highly reputable agents may be entrusted with reviewing a delivery; their reputation does not entitle them to vote assets out of an unrelated wallet. A result therefore has effect only where a relying contract committed, before the vote, to accept results of that policy for that class of matter, and only within the effects it committed to. Voting forms a collective decision; it creates no power and proves no truth.

**The registry is the normative record, not an executor.** Whether a result is "passed" is read from the registry; which funds may move, whether execution already happened and whether its conditions still hold are checked by the relying contract within its own authority. Procedure state, outcome type and enactment status are three dimensions, not one enum: an issue can be final with no decision, and the same final decision can be executed successfully by one relying party and refused by another without anyone touching the decision.

**Rules are frozen as execution parameters, not as prose.** A policy's identifier is the hash of the very struct the registry executes — roster, thresholds, windows, composition graph, appeal rules — so there is no gap between a rule as published and a rule as applied, and no proxy, admin list or code-hash pin is needed to argue that it stayed the same.

The framework is deliberately **agnostic about who the participants are**. An eligibility profile may bind rosters to agent identity and trust-assertion registries such as [ERC-8004](./eip-8004.md) and the know-your-agent frameworks built over it; the kernel only requires that eligibility be verifiable and frozen at admission. It is equally agnostic about **incentives**: whether participants are paid, bonded or scored is left to profiles, and "agreeing with the majority" is never defined as correctness.

Illustrative flows (informative):

- A token-bound task tender names an adapter contract as its acceptance authority. When a delivery is submitted, anyone opens an issue bound to that exact submission; a 3-of-5 roster decides; the adapter calls the tender's real accept or reject entry point, and a round that ends without a decision triggers nothing — the tender's own default (silence pays the fulfiller) governs.
- A swarm charter registers a standing acceptance for parameter changes: any member may file; a screening council holds a 12-hour veto; a technical chamber voting by signed ballots and an economic chamber voting on-chain must both approve; one appeal rebuilds every chamber; an executor with a timelock enforces the adopted value.
- A party files a dispute and names a counterparty; nothing is voted until the counterparty acknowledges and commits the effects it will honour; if it never does, the issue closes or proceeds as advisory evidence that no one is bound by.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### 1. Terminology

- **Decision Policy (policy)** — an immutable, content-addressed `PolicySpec` fixing bodies, composition, timing, appeals and acceptance rules. Identified by `policyId = keccak256(abi.encode(spec))`.
- **Policy family** — the lineage a policy version belongs to; the family's **update authority** alone may publish its next version.
- **Issue** — one concrete collective decision: a subject, a question, a policy version and at most one consumer binding.
- **Consumer (relying contract)** — the contract or account that commits to accept an issue's result and to enforce its effects within its own authority.
- **Acceptance mode** — how the consumer's commitment is established: `CONSUMER_FILED`, `STANDING_ACCEPTANCE` or `POST_ACK`.
- **Binding / Advisory** — an issue with a verified consumer commitment is *Binding*; an issue with none is *Advisory* and produces a record without hard effect.
- **Obligation key** — `keccak256(abi.encode(consumer, subject, question))`; at most one unfinished Binding issue exists per obligation key.
- **Body** — one deciding unit of a policy: a fixed roster with a K-of-N rule, or a single authorized submitter. A **body instance** is a body on one issue in one round.
- **Body decision** — `Pending`, `Yes`, `No` or `NoDecision(reason)`.
- **Composition** — the tree of combinators (`BODY`, `ALL`, `ANY`, `KOFM`, `VETO`) whose root value is the round's result.
- **Round** — one run of all bodies; appeals open further rounds under the same policy version.
- **Procedure state** — `Filed`, `Deciding`, `Provisional`, `Final` or `Withdrawn`.
- **Outcome type** — `None`, `Decided` (with a boolean outcome) or `NoDecision` (with a reason).
- **Enactment** — a consumer's execution of an effect; its status (`NotEnacted`, `Enacted`, `Failed`) is authoritative at the consumer and logged informatively by the registry.
- **Formation instant** — the time at which a body or node value became determined by the ballots and the clock; appeal windows run from it, not from the transaction that records it.

### 2. Conformance

A conforming deployment consists of one `IACDFPolicyRegistry` and one `IACDFRegistry` bound to it (Section 11). Both MUST implement [ERC-165](./eip-165.md) and report the interface identifiers of Section 15.

The following are REQUIRED of every conforming deployment: the policy data model and validation rules (Section 3), the three acceptance modes and the obligation rule (Section 5), the procedure state machine (Section 6), the `ROSTER_KOFN` body with `ON_CHAIN_TALLY` acceptance (Section 7), single-body composition (the `BODY` root), the finality rules (Section 9), the result and enactment record (Section 10) and the clock disclosure (Section 12). This is the **Minimal profile**: a fixed-roster K-of-N vote.

The following are **normative-optional profiles**: body composition (`ALL`, `ANY`, `KOFM`, `VETO`, Section 8), signed ballots (`SIGNED_BALLOTS`, Section 7.3), authorized-submitter bodies (`AUTHORIZED_SUBMITTER`, Section 7.4) and appeals (`maxAppeals > 0`, Section 9). A deployment MAY reject policies that use a profile it does not implement; a deployment that accepts such a policy MUST implement the profile exactly as specified here.

Section 13 names extension points that this ERC reserves without specifying. A deployment MUST NOT claim conformance to a reserved extension on the basis of this document.

### 3. Decision Policy

#### 3.1 Data model

```solidity
library ACDFTypes {
    enum BodyKind       { ROSTER_KOFN, AUTHORIZED_SUBMITTER }
    enum Acceptance     { ON_CHAIN_TALLY, SIGNED_BALLOTS, AUTHORIZED_SUBMITTER }
    enum Combinator     { BODY, ALL, ANY, KOFM, VETO }
    enum VetoSilence    { PASS_THROUGH, REQUIRE_CLEARANCE }
    enum AppealStanding { ANYONE, CONSUMER_OR_FILER }

    struct BodySpec {
        BodyKind   kind;
        Acceptance acceptance;   // result-acceptance mode of THIS body
        address[]  members;      // ROSTER_KOFN: unique, non-zero roster; AUTHORIZED_SUBMITTER: exactly one
        uint32     k;            // ROSTER_KOFN: approvals needed, 1 <= k <= N
        uint64     window;       // seconds from round start during which input is accepted; > 0
    }

    struct Node {
        Combinator  op;
        uint32      body;        // BODY: index into bodies
        uint32      k;           // KOFM: required child approvals
        uint32      target;      // VETO: guarded node index (> own index)
        uint32      vetoBody;    // VETO: index of the veto body; its window is the veto window
        VetoSilence silence;     // VETO: meaning of the veto body's silence at window close
        uint32[]    children;    // ALL / ANY / KOFM: child node indices (> own index, unique)
    }

    struct PolicySpec {
        bytes32        family;
        uint32         version;
        bytes32        previous;         // previous policyId in the family, or 0 for the first
        address        updateAuthority;  // who may publish the family's next version
        BodySpec[]     bodies;
        Node[]         nodes;            // nodes[0] is the root
        uint32         maxAppeals;       // rounds allowed after the first
        uint64         appealWindow;     // seconds after a round's formation instant
        uint8          appealable;       // bit0: Decided appealable; bit1: NoDecision appealable
        AppealStanding appealStanding;
        uint64         maxTotalDuration; // hard cap from admission
        uint64         ackWindow;        // POST_ACK acknowledgment window; 0 disables POST_ACK
        bool           allowAdvisory;    // may an unacknowledged POST_ACK issue proceed as Advisory
        bytes32        descriptorHash;   // informative reference to an off-chain description
    }
}
```

`policyId` MUST equal `keccak256(abi.encode(spec))` over the full `PolicySpec`. Every field of the struct is part of the identifier; `descriptorHash` is included so that a published description is bound to the parameters, but it MUST NOT influence execution.

#### 3.2 Validation

`registerPolicy` MUST reject a specification unless all of the following hold:

- `1 <= bodies.length <= 32` and `1 <= nodes.length <= 64`.
- Every body has `window > 0`. A `ROSTER_KOFN` body has `members.length >= 1`, `1 <= k <= members.length`, pairwise-distinct non-zero members and `acceptance` in `{ON_CHAIN_TALLY, SIGNED_BALLOTS}`. An `AUTHORIZED_SUBMITTER` body has exactly one non-zero member and `acceptance == AUTHORIZED_SUBMITTER`.
- The nodes form a tree rooted at index 0: a `BODY` node references a valid body and has no children; `ALL`, `ANY` and `KOFM` nodes have at least one child, every child index is strictly greater than the node's own index and less than `nodes.length`, children are pairwise distinct, and a `KOFM` node has `1 <= k <= children.length`; a `VETO` node has no children, a `target` strictly greater than its own index and less than `nodes.length`, and a valid `vetoBody`. Node 0 is referenced by no node, and every other node is referenced exactly once (as a child or as a `VETO` target). Because every edge points to a larger index, the graph is acyclic by construction.
- If `maxAppeals > 0` then `appealWindow > 0` and `1 <= appealable <= 3`.
- With `roundDuration` defined as the maximum `window` over all bodies: `maxTotalDuration >= (maxAppeals + 1) * roundDuration + maxAppeals * appealWindow`, and `maxTotalDuration <= 2^63 - 1`.
- `family != 0`, `version >= 1`, `updateAuthority != 0`.
- A `policyId` MUST NOT be registered twice.

#### 3.3 Families and versions

The first policy registered under a `family` MUST have `previous == 0`; it claims the family and sets its update authority to `spec.updateAuthority`. Any later version under the same family MUST be registered by the family's current update authority, MUST carry `previous` equal to the family's latest `policyId`, and MUST carry a `version` strictly greater than the latest; its `updateAuthority` becomes the family's new authority. Registering a new version MUST NOT alter any existing policy, any issue bound to an earlier version, or any standing acceptance that references one.

### 4. Policy registry interface

```solidity
interface IACDFPolicyRegistry /* is IERC165 */ {
    struct Timing {
        uint32 maxAppeals; uint64 appealWindow; uint8 appealable; ACDFTypes.AppealStanding appealStanding;
        uint64 maxTotalDuration; uint64 ackWindow; bool allowAdvisory; uint64 roundDuration;
    }

    event PolicyRegistered(bytes32 indexed policyId, bytes32 indexed family, uint32 version, address indexed by);

    function policyIdOf(ACDFTypes.PolicySpec calldata spec) external pure returns (bytes32);
    function registerPolicy(ACDFTypes.PolicySpec calldata spec) external returns (bytes32 policyId);
    function policyExists(bytes32 policyId) external view returns (bool);
    function familyAuthority(bytes32 family) external view returns (address);
    function familyLatest(bytes32 family) external view returns (bytes32 policyId, uint32 version);
    function roundDurationOf(bytes32 policyId) external view returns (uint64);
    function timingOf(bytes32 policyId) external view returns (Timing memory);
    function policyHeader(bytes32 policyId) external view returns (
        bytes32 family, uint32 version, bytes32 previous, address updateAuthority, bytes32 descriptorHash);
    function bodyCount(bytes32 policyId) external view returns (uint256);
    function bodyOf(bytes32 policyId, uint32 body) external view returns (ACDFTypes.BodySpec memory);
    function nodeCount(bytes32 policyId) external view returns (uint256);
    function nodeOf(bytes32 policyId, uint32 node) external view returns (ACDFTypes.Node memory);
}
```

`registerPolicy` is permissionless for new families. The registry MUST store the full specification so that every parameter it executes is readable through `bodyOf`, `nodeOf`, `timingOf` and `policyHeader`.

### 5. Issues and authorization

#### 5.1 Issue data

```solidity
struct Subject { uint256 chainId; address target; uint256 id; bytes32 dataHash; }

enum AcceptanceMode { CONSUMER_FILED, STANDING_ACCEPTANCE, POST_ACK }
enum EffectClass    { Advisory, Binding }

struct IssueInput {
    bytes32        policyId;
    AcceptanceMode mode;
    bytes32        acceptanceId;     // STANDING_ACCEPTANCE
    address        consumer;         // CONSUMER_FILED: MUST equal msg.sender; POST_ACK: the account whose acknowledgment is awaited
    Subject        subject;
    bytes32        question;
    bytes32        effectYes;        // opaque effect identifiers; CONSUMER_FILED: committed; POST_ACK: proposal only
    bytes32        effectNo;
    bytes32        disposition;      // opaque reference to the consumer's committed NoDecision disposition
    uint64         consumerDeadline; // 0 = none
}

struct StandingAcceptanceInput {
    bytes32   policyId;       // the exact policy version accepted
    address   subjectTarget;  // 0 = any
    bytes32   question;       // 0 = any
    address[] filers;         // empty = anyone
    bytes32   effectYes; bytes32 effectNo; bytes32 disposition;
    uint64    validUntil;     // 0 = none
}
```

Effect identifiers and the disposition are opaque to the registry. They name, for the consumer, the action that each outcome authorizes and what the consumer does when no decision forms; the registry never interprets or executes them.

#### 5.2 Acceptance modes

An issue is **admitted** when its consumer binding (if any) has been verified, its parameters are frozen, and its first round starts. A **Binding** issue has exactly one consumer. Admission MUST:

- record `admittedAt` and `hardDeadline = admittedAt + maxTotalDuration`;
- if `consumerDeadline != 0`, require `hardDeadline <= consumerDeadline` ("insufficient window"); the whole procedure including every appeal must fit the consumer's remaining window;
- for a Binding issue, compute the obligation key and require that no other issue holds it unless that issue is `Final` or `Withdrawn` ("obligation active"), then record this issue as the obligation's active issue;
- set the procedure state to `Deciding` and open round 1.

**CONSUMER_FILED.** `file` MUST require `input.consumer == msg.sender` and non-zero `effectYes` and `effectNo`. The caller is the consumer; acceptance is implied and admission is atomic with filing. Calling as the consumer proves only that this account filed; an adapter acting for a business object MUST itself verify that it holds the authority it claims over that object before filing.

**STANDING_ACCEPTANCE.** A consumer registers, in advance, an acceptance record naming the exact policy version it accepts, an optional subject-target constraint, an optional question constraint, an optional list of permitted filers, the effects and disposition it commits to, and an optional expiry. `file` in this mode MUST require that the acceptance exists and is not revoked or expired, that `input.policyId` equals the accepted policy, that the subject target and question satisfy the constraints, and that `msg.sender` is a permitted filer when the list is non-empty. The issue's consumer, effects and disposition MUST be taken from the acceptance record; values supplied by the filer MUST be ignored. Admission is atomic with filing. Revoking an acceptance MUST stop new filings only; issues already admitted under it complete under their committed rules.

**POST_ACK.** `file` in this mode MUST require that the policy's `ackWindow` is non-zero and that `input.consumer` is non-zero. The issue remains in state `Filed`; no round is open and no ballot can be cast. Before `filedAt + ackWindow` the named consumer, and only it, MAY `acknowledge`, supplying the final effects and disposition and an optional consumer deadline; acknowledgment admits the issue as Binding. After the window, if the policy's `allowAdvisory` is true, anyone MAY `admitAdvisory`, which clears the consumer and effects and admits the issue as Advisory; otherwise anyone MAY `expireUnacknowledged`, which sets the state to `Withdrawn` with reason `NO_ACCEPTANCE`. An issue admitted as Advisory MUST NOT be converted to Binding afterwards; a party that later wishes to adopt its result MUST create a new acceptance or a new issue.

Advisory issues run the full procedure and produce a formal record. Their results carry no obligation for any consumer; `recordEnactment` MUST reject them.

#### 5.3 Freezing

The following MUST be fixed at admission and MUST NOT change afterwards: the policy version, subject, question, effect identifiers, disposition, consumer, effect class and every window. There is no function that changes them. Parameters whose evaluation legitimately depends on later state are not part of this ERC's kernel; a profile that introduces them MUST declare the dependency in the policy.

#### 5.4 Withdrawal

`withdraw` MUST succeed only while the issue is `Filed` and only for the filer. Once admitted, no party can unilaterally withdraw: the roster, snapshot and windows exist, and withdrawing and refiling would let a filer shop for panels. A relying contract cannot tear up an in-flight binding; revoking a standing acceptance does not affect admitted issues.

### 6. Procedure state machine

```
             file (CONSUMER_FILED / STANDING)        settleRound, no remaining procedure
  -------> Filed -----------------------------> Deciding ------------------------------> Final
              |  acknowledge / admitAdvisory      |   ^          settleRound,                 ^
              |  (POST_ACK)                       |   |          appeal possible              |
              |                                   v   | appeal                                | finalize after window /
              +--- withdraw / expire --> Withdrawn    Provisional ---------------------------+ enforceHardDeadline
```

| Transition | Caller | Condition |
|---|---|---|
| → `Filed` | filer | policy exists; mode-specific checks of Section 5.2 |
| `Filed` → `Deciding` | atomic in `file`, or `acknowledge`, or `admitAdvisory` | admission checks of Section 5.2 |
| `Filed` → `Withdrawn` | filer (`withdraw`) or anyone (`expireUnacknowledged`) | see Sections 5.2 and 5.4 |
| `Deciding` → `Provisional` | anyone (`settleRound`) | root value is not `Pending`; an appeal is still possible: rounds remain, the outcome type is appealable, and `formationInstant + appealWindow` has not passed |
| `Deciding` → `Final` | anyone (`settleRound`) | root value is not `Pending` and no legal procedure remains: appeals exhausted, the outcome type not appealable, or the appeal window already lapsed |
| `Provisional` → `Deciding` | anyone with standing (`appeal`) | before `appealOpenUntil`; a new round opens with fresh body instances |
| `Provisional` → `Final` | anyone (`finalize`) | after `appealOpenUntil` |
| `Deciding` / `Provisional` → `Final` | anyone (`enforceHardDeadline`) | after `hardDeadline`; a round still `Pending` is recorded as `NoDecision(TOTAL_TIMEOUT)` |

`Final` and `Withdrawn` are terminal. A `Final` issue MUST NOT accept ballots, submissions, appeals or any further round, and its adopted result MUST NOT change. Evidence (Section 10.3) MAY be attached while the issue is `Filed`, `Deciding` or `Provisional`.

Every round records `startedAt` and `deadline = startedAt + roundDuration`. All bodies of a round open at `startedAt`; body `b` accepts input through `startedAt + bodies[b].window` inclusive.

### 7. Bodies and ballots

#### 7.1 Roster K-of-N body

For a `ROSTER_KOFN` body with `N = members.length` and threshold `k`, in a given round, let `yes` and `no` be the counts of accepted approve and block ballots. The body's status is:

- `Yes` once `yes >= k`, formed at the instant the k-th approval was accepted;
- `No` once `no >= N - k + 1`, formed at the instant the (N−k+1)-th block was accepted;
- `NoDecision(QUORUM_NOT_MET)` if neither holds after the body's window closed, formed at the window close;
- `Pending` otherwise.

The two decided conditions cannot hold together (they would need `N + 1` ballots). This is an **approval rule for the proposition put to the body**: `No` means the proposition was blocked under this rule; it does not by itself establish the opposite proposition, and relying contracts MUST NOT read it as such unless their own commitment says so.

A ballot MUST be rejected if the caller or signer is not a member, has already voted in this round and body, arrives after the body's window, or if the body has already reached a decided status. One ballot per member per round per body; the minimal profile allows no change of ballot.

#### 7.2 On-chain tally

For a body with `acceptance == ON_CHAIN_TALLY`, `castBallot(issueId, round, body, approve)` accepts a ballot from `msg.sender` while the issue is `Deciding` and `round` equals the issue's current `roundCount`; a ballot naming any other round MUST be rejected. The round argument gives an on-chain ballot the same authorization boundary as a signed ballot's digest: a transaction broadcast for one round that is included only after that round has settled and an appeal has opened the next one is refused rather than counted in a round the voter never addressed. Signed submissions to such a body MUST be rejected.

#### 7.3 Signed ballots (normative-optional)

For a body with `acceptance == SIGNED_BALLOTS`, `submitSignedBallots(issueId, body, voters, approves, signatures)` MAY be called by anyone while the issue is `Deciding`. Direct `castBallot` calls to such a body MUST be rejected. For each entry the registry MUST verify the signature over the EIP-712 digest of

```
Ballot(bytes32 issueId,uint32 round,uint32 body,address voter,bool approve)
```

under the domain `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` with `name = "ACDF"`, `version = "1"`, the executing chain id and the registry address. Signatures of externally owned accounts are verified by `ecrecover` with `s` in the lower half of the curve order and `v` in `{27, 28}`; signatures of contract accounts are verified through ERC-1271. The batch MUST revert if any signature is invalid or if any ballot would be rejected under Section 7.1. The ballot carries no nonce: the voter's identity is the only key, so a second signature by the same voter cannot buy a second ballot, and the round and body in the digest make a signature for one round invalid in the next. Acceptance time is the block in which the batch is submitted (arrival, not signing time). Accepted ballots are counted with exactly the semantics of Section 7.1 and MUST NOT be invalidated afterwards.

#### 7.4 Authorized submitter (normative-optional)

For an `AUTHORIZED_SUBMITTER` body, `submitBodyResult(issueId, round, body, status)` MUST be accepted only from the pinned member, only for `round` equal to the issue's current `roundCount`, only once per round, only within the body's window, with `status` in `{Yes, No, NoDecision}`. The body's status is the submitted value, formed at submission; if the window closes without a submission the status is `NoDecision(SUBMITTER_SILENT)`. The registry does not re-tally whatever process the submitter ran; it records only who submitted what, when, and whether that submitter was the one the policy pinned.

### 8. Composition (normative-optional)

Node values are four-valued: `Pending`, `Yes`, `No`, `NoDecision(reason)`. Values are a pure function of the accepted ballots and submissions and of the current time, so two evaluations at the same block agree and a later evaluation never contradicts an earlier non-`Pending` one. Each value carries a **formation instant**.

Let a composite node have `M` children and define `K = M` for `ALL`, `K = 1` for `ANY` and `K = node.k` for `KOFM`. With `yes`, `no`, `pending` the counts of children by status:

- `Yes` if `yes >= K`, formed at the K-th smallest formation instant among `Yes` children;
- else `No` if `no >= M - K + 1`, formed at the (M−K+1)-th smallest formation instant among `No` children;
- else `Pending` if `pending > 0`;
- else `NoDecision(NOT_REACHED)`, formed at the latest child formation instant.

A `VETO` node guards `target` with the veto body `vetoBody`. In the veto body an approve ballot means **veto** and a decided `No` means **explicit clearance**. Its value is:

- `No(VETOED)` if the veto body is `Yes`, formed at the veto's formation instant;
- `Pending` if the veto body is `Pending`, whatever the target's value — a live veto right is never extinguished by an early settlement;
- `NoDecision(NO_CLEARANCE)` if the veto body is `NoDecision` and `silence == REQUIRE_CLEARANCE`, formed at the veto window close;
- otherwise (explicit clearance in either mode, or silence under `PASS_THROUGH`) the target's value, `Pending` while the target is `Pending`, formed at the later of the veto body's and the target's formation instants.

Because the veto window is the veto body's window and the round deadline is the longest body window, every node is non-`Pending` by the round deadline.

Composition in this ERC combines **decisions about the same issue and the same pair of effect candidates**. Policies whose bodies decide different magnitudes or different candidate effects are outside this profile; combining such results by taking a minimum or any other arithmetic is NOT RECOMMENDED and is reserved for a typed extension (Section 13).

### 9. Rounds, appeals and finality

`settleRound` MUST revert while the root is `Pending`. When it succeeds it records the round's status, reason and formation instant `at`. An appeal is possible if `roundCount - 1 < maxAppeals` and the bit of `appealable` for the outcome type (bit 0 for a decided result, bit 1 for `NoDecision`) is set; then `appealOpenUntil = min(at + appealWindow, hardDeadline)`. If an appeal is possible and the current time is not after `appealOpenUntil`, the issue becomes `Provisional`; otherwise it becomes `Final`. The window runs from the formation instant: a settlement called late cannot extend the procedure.

`appeal` MUST be accepted only while `Provisional`, not after `appealOpenUntil`, and — when `appealStanding == CONSUMER_OR_FILER` — only from the consumer or the filer. It opens a new round in which every body instance is rebuilt and every body runs again under the same policy version; ballots and submissions of earlier rounds are not carried over, and a signed ballot for an earlier round is invalid (Section 7.3).

`finalize` MUST be accepted only while `Provisional` and after `appealOpenUntil`. `enforceHardDeadline` MUST be accepted while `Deciding` or `Provisional` once the current time is after `hardDeadline`; if the current round's root is still `Pending` it is recorded as `NoDecision(TOTAL_TIMEOUT)`.

**Adoption rule.** On finalization the registry MUST adopt the most recent round whose status is `Yes` or `No`: the outcome type becomes `Decided`, `outcomeYes` the round's status, `reason` the round's reason, `sourceRound` that round's number and `decidedAt` its formation instant. Only if no round produced `Yes` or `No` does the outcome type become `NoDecision`, with the last round's reason. A later round that ended without a decision therefore never erases an earlier decision; it is recorded, and `sourceRound` may be smaller than `roundCount`. `Final` is terminal: no later round of the same issue can replace the adopted result; a different conclusion requires a new, separately authorized issue.

### 10. Results, enactment and evidence

#### 10.1 Result

```solidity
enum ProcedureState { None, Filed, Deciding, Provisional, Final, Withdrawn }
enum OutcomeType    { None, Decided, NoDecision }
enum NodeStatus     { Pending, Yes, No, NoDecision }
enum Reason         { NONE, QUORUM_NOT_MET, SUBMITTER_SILENT, VETOED, NO_CLEARANCE, NOT_REACHED, TOTAL_TIMEOUT, NO_ACCEPTANCE }
enum EnactmentStatus { NotEnacted, Enacted, Failed }

struct Result {
    ProcedureState state;   OutcomeType outcomeType; bool outcomeYes; Reason reason;
    uint64 decidedAt;       uint64 finalAt;          bytes32 policyId;
    uint32 roundCount;      uint32 sourceRound;      EffectClass effectClass;
    address consumer;       bytes32 effectYes;       bytes32 effectNo;  bytes32 disposition;
}
```

`getResult` MUST return the three dimensions separately. A relying contract MUST check `state == Final` before enforcing an irreversible effect, MUST check `outcomeType == Decided` before applying either effect, and MUST apply its committed disposition — not a default of its own choosing at that moment — when `outcomeType == NoDecision`. Reasons identify why no decision formed and are not a verdict on the merits; `VETOED` is the reason of a decided `No`.

#### 10.2 Enactment log

`recordEnactment(issueId, effectId, status, ref)` is an informative log. It MUST be accepted only while the issue is `Final`, only from the issue's consumer, only for a Binding issue, only for `effectId` equal to the issue's `effectYes` or `effectNo`, and only with `status != NotEnacted`. Once an effect is recorded `Enacted` it MUST NOT be overwritten; a `Failed` record MAY later be replaced by `Enacted`. The log records the real reporter. Execution state is authoritative at the consumer; the registry never modifies a decision because an enactment failed, and never prevents a consumer from retrying an enactment its own rules allow.

#### 10.3 Evidence

`submitEvidence(issueId, evidenceURI)` emits `Evidence(issueId, msg.sender, evidenceURI)` while the issue is `Filed`, `Deciding` or `Provisional`. Evidence is data for participants to weigh; the registry attaches no meaning to it.

### 11. Issue registry interface

```solidity
interface IACDFRegistry /* is IERC165 */ {
    event StandingAcceptanceRegistered(bytes32 indexed acceptanceId, address indexed consumer, bytes32 indexed policyId);
    event StandingAcceptanceRevoked(bytes32 indexed acceptanceId, address indexed consumer);
    event IssueFiled(bytes32 indexed issueId, bytes32 indexed policyId, ACDFTypes.AcceptanceMode mode, address indexed filer, address consumer);
    event IssueAdmitted(bytes32 indexed issueId, ACDFTypes.EffectClass effectClass, address indexed consumer, uint64 admittedAt, uint64 hardDeadline);
    event IssueAcknowledged(bytes32 indexed issueId, address indexed consumer);
    event IssueWithdrawn(bytes32 indexed issueId, ACDFTypes.Reason reason);
    event BallotCast(bytes32 indexed issueId, uint32 indexed round, uint32 indexed body, address voter, bool approve, bool signed);
    event BodyResultSubmitted(bytes32 indexed issueId, uint32 indexed round, uint32 indexed body, address submitter, ACDFTypes.NodeStatus status);
    event RoundSettled(bytes32 indexed issueId, uint32 indexed round, ACDFTypes.NodeStatus status, ACDFTypes.Reason reason, uint64 at, uint64 appealOpenUntil);
    event Appealed(bytes32 indexed issueId, uint32 indexed newRound, address indexed by);
    event Finalized(bytes32 indexed issueId, ACDFTypes.OutcomeType outcomeType, bool outcomeYes, ACDFTypes.Reason reason, uint32 sourceRound);
    event EnactmentRecorded(bytes32 indexed issueId, address indexed consumer, bytes32 indexed effectId, ACDFTypes.EnactmentStatus status, address reporter, bytes32 ref);
    event Evidence(bytes32 indexed issueId, address indexed party, string evidenceURI);

    function policies() external view returns (IACDFPolicyRegistry);

    function registerStandingAcceptance(ACDFTypes.StandingAcceptanceInput calldata input) external returns (bytes32 acceptanceId);
    function revokeStandingAcceptance(bytes32 acceptanceId) external;

    function file(ACDFTypes.IssueInput calldata input) external returns (bytes32 issueId);
    function acknowledge(bytes32 issueId, bytes32 effectYes, bytes32 effectNo, bytes32 disposition, uint64 consumerDeadline) external;
    function admitAdvisory(bytes32 issueId) external;
    function expireUnacknowledged(bytes32 issueId) external;
    function withdraw(bytes32 issueId) external;
    function submitEvidence(bytes32 issueId, string calldata evidenceURI) external;

    function castBallot(bytes32 issueId, uint32 round, uint32 body, bool approve) external;
    function submitSignedBallots(bytes32 issueId, uint32 body, address[] calldata voters, bool[] calldata approves, bytes[] calldata signatures) external;
    function submitBodyResult(bytes32 issueId, uint32 round, uint32 body, ACDFTypes.NodeStatus status) external;

    function settleRound(bytes32 issueId) external;
    function appeal(bytes32 issueId) external;
    function finalize(bytes32 issueId) external;
    function enforceHardDeadline(bytes32 issueId) external;

    function recordEnactment(bytes32 issueId, bytes32 effectId, ACDFTypes.EnactmentStatus status, bytes32 ref) external;

    function getResult(bytes32 issueId) external view returns (ACDFTypes.Result memory);
    function getIssue(bytes32 issueId) external view returns (ACDFTypes.Issue memory);
    function getRound(bytes32 issueId, uint32 round) external view returns (ACDFTypes.RoundState memory);
    function getBodyState(bytes32 issueId, uint32 round, uint32 body) external view returns (ACDFTypes.BodyState memory);
    function bodyStatus(bytes32 issueId, uint32 round, uint32 body) external view returns (ACDFTypes.NodeStatus, ACDFTypes.Reason, uint64 at);
    function nodeStatus(bytes32 issueId, uint32 round, uint32 node) external view returns (ACDFTypes.NodeStatus, ACDFTypes.Reason, uint64 at);
    function hasVoted(bytes32 issueId, uint32 round, uint32 body, address voter) external view returns (bool);
    function activeIssueOf(address consumer, bytes32 obligationKey) external view returns (bytes32);
    function obligationKeyOf(address consumer, ACDFTypes.Subject calldata subject, bytes32 question) external pure returns (bytes32);
    function getEnactment(bytes32 issueId, address consumer, bytes32 effectId) external view returns (ACDFTypes.Enactment memory);
    function ballotDigest(bytes32 issueId, uint32 round, uint32 body, address voter, bool approve) external view returns (bytes32);

    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
```

`issueId` and `acceptanceId` MUST be unique within the registry instance; the reference implementation derives them from the chain id, the registry address and a counter. `bodyStatus` and `nodeStatus` MUST implement Sections 7 and 8 as pure functions of recorded state and the current time; `settleRound`, `finalize` and `enforceHardDeadline` MUST use them.

### 12. Clock

An issue registry MUST expose [ERC-6372](./eip-6372.md) `clock()` and `CLOCK_MODE()`. One registry instance uses one clock for every policy it runs; the reference implementation uses `mode=timestamp`. Windows are seconds of that clock. Durations MUST NOT be converted between clocks (for example block counts into seconds) to claim that a deadline will be met.

### 13. Profiles and reserved extension points

| Profile | Status in this ERC |
|---|---|
| Minimal (roster K-of-N, on-chain tally, single body, no appeal) | REQUIRED |
| Body composition (`ALL` / `ANY` / `KOFM` / `VETO`) | normative-optional, Section 8 |
| Signed ballots | normative-optional, Section 7.3 |
| Authorized submitter | normative-optional, Section 7.4 |
| Appeals | normative-optional, Section 9 |

The following are **reserved**: this ERC names them so that implementations and relying contracts leave room for them, but it does not specify them and no conformance may be claimed for them under this document.

- *Eligibility profiles* binding rosters to identity, trust-assertion or reputation registries (for example ERC-8004 identities with asserted trust levels), including how an eligibility snapshot is produced and how conflicts of interest are excluded.
- *Selection* other than a fixed roster: sortition with a verifiable randomness source, nomination with strikes, delegation.
- *Weight* other than equal weight, including per-operator caps and independence conditions.
- *Non-binary outcome spaces* (categorical, scalar, ranked) and *typed composition* over them, including intersection of allowed effect sets.
- *Ordering dependencies* between bodies beyond the veto window.
- *Executor modules* enforcing effects with delays on behalf of consumers; *fees and bonds*; *optimistic / challenge* procedures; *privacy* (zero-knowledge eligibility, anonymous ballots); *multi-consumer* issues; *cross-chain* carriage of results.

A policy that would need any of these is outside this ERC until a later document specifies it.

### 14. Relying-contract integration (informative)

A relying contract names a registry instance and the exact policy versions it accepts, and derives every parameter of an issue from its own state rather than from the caller. The companion adapter for a token-bound task tender kernel (whose vendored interface appears in the reference assets) illustrates the pattern: it is the tender's acceptance authority; `open(tokenId, submissionId)` is permissionless but files as the adapter itself, binding the subject to the submission's result hash and the task version it cited, and passing as `consumerDeadline` the earlier of the tender's two clocks — the judgment window that bounds rejection and the settlement deadline that bounds acceptance — minus an execution margin; `execute(issueId)` reads a `Final` result and calls the tender's real accept or reject entry point with no caller-supplied target or calldata, records `Enacted` or `Failed`, and does nothing for a `NoDecision`, leaving the tender's own default settlement in force. An ERC-8183 job's evaluator and an arbitration-standard arbitrator can be realized the same way.

### 15. Interface identifiers

| interface | ERC-165 id |
|---|---|
| `IACDFPolicyRegistry` | `0x734a2e40` |
| `IACDFRegistry` | `0x843ad5a8` |

### 16. Errors

Implementations SHOULD revert with the following reason strings (or equivalent custom errors) so that relying contracts and tests can distinguish causes. Policy validation: `ACDF: policy exists`, `ACDF: zero family`, `ACDF: zero version`, `ACDF: zero update authority`, `ACDF: first version has no previous`, `ACDF: not family authority`, `ACDF: previous != latest`, `ACDF: version not increasing`, `ACDF: bodies out of range`, `ACDF: nodes out of range`, `ACDF: zero window`, `ACDF: empty roster`, `ACDF: bad k`, `ACDF: roster acceptance`, `ACDF: zero member`, `ACDF: duplicate member`, `ACDF: submitter required`, `ACDF: submitter acceptance`, `ACDF: body index`, `ACDF: body node has children`, `ACDF: veto node has children`, `ACDF: veto target`, `ACDF: veto body index`, `ACDF: no children`, `ACDF: bad node k`, `ACDF: child index`, `ACDF: duplicate child`, `ACDF: root referenced`, `ACDF: node not in tree`, `ACDF: zero appeal window`, `ACDF: appealable mask`, `ACDF: maxTotalDuration too short`, `ACDF: maxTotalDuration too long`. Issues and acceptance: `ACDF: unknown policy`, `ACDF: effects required`, `ACDF: consumer must file`, `ACDF: acceptance unavailable`, `ACDF: acceptance expired`, `ACDF: policy not accepted`, `ACDF: subject not accepted`, `ACDF: question not accepted`, `ACDF: filer not accepted`, `ACDF: not acceptance owner`, `ACDF: POST_ACK disabled`, `ACDF: consumer required`, `ACDF: not POST_ACK`, `ACDF: not awaiting acknowledgment`, `ACDF: not the named consumer`, `ACDF: ack window closed`, `ACDF: ack window open`, `ACDF: advisory not allowed`, `ACDF: must admit as advisory`, `ACDF: insufficient window`, `ACDF: obligation active`, `ACDF: not withdrawable`, `ACDF: not filer`, `ACDF: evidence closed`. Voting: `ACDF: not deciding`, `ACDF: round mismatch`, `ACDF: body not on-chain tally`, `ACDF: body not signed ballots`, `ACDF: body not submitter`, `ACDF: batch shape`, `ACDF: bad signature`, `ACDF: body window closed`, `ACDF: not a member`, `ACDF: already voted`, `ACDF: body decided`, `ACDF: not the submitter`, `ACDF: status required`, `ACDF: already submitted`. Rounds and finality: `ACDF: pending`, `ACDF: not provisional`, `ACDF: appeal window closed`, `ACDF: appeal window open`, `ACDF: no standing`, `ACDF: not open`, `ACDF: before hard deadline`, `ACDF: round index`. Enactment: `ACDF: not final`, `ACDF: not the consumer`, `ACDF: unknown effect`, `ACDF: already enacted`.

## Rationale

**Why a policy is a hashed struct rather than a referenced module.** The first-order risk in any decision system is that the rule applied is not the rule published. Pinning a module by address and code hash does not close that gap: an [ERC-1967](./eip-1967.md) proxy changes its implementation in a storage slot while its code hash stays the same, and even fixed code can read a mutable threshold. Making the registry execute the very struct whose hash is the policy identifier removes the gap entirely, at the cost of restricting the first version to built-in body kinds. Pluggable modules return as reserved extension points that must declare their dynamic dependencies explicitly.

**Why authorization is a consumer's commitment, not a registry object.** Earlier drafts carried a stand-alone "mandate" object. Review showed that it conflated two questions — "by which institution is this decided?" (the policy) and "who recognizes that institution's result for which matters and effects?" (the consumer's commitment) — and that a registry entry saying "I have power over X" grants nothing unless X's own code recognizes it. The three acceptance modes are therefore the only authorization primitives, and all of them are acts of the consumer: filing itself, pre-declaring a standing acceptance, or acknowledging before any vote.

**Why POST_ACK acknowledges before admission.** If a party could file, watch the vote, and acknowledge only when the result favoured it, the "binding" would be an option, not a commitment. Acknowledgment therefore precedes admission and voting, an unacknowledged issue proceeds only as advisory, and an advisory result can never be upgraded in place.

**Why one unfinished Binding issue per obligation.** Without the obligation rule the same delivery could be sent to several panels and the favourable result executed. Different consumers deciding about the same fact remain separate obligations; the rule forbids verdict shopping on one execution obligation, not the use of one fact as evidence in several domains.

**Why four-valued composition and no pooling of ballots.** "Technical chamber approves" and "economic chamber approves" compose by logic, not by adding votes: pooling lets the larger chamber swamp the smaller and dissolves the check the two chambers were meant to provide. `Pending`, `Yes`, `No` and `NoDecision` are kept distinct because "the second chamber failed to reach quorum" is neither "both approved" nor "one rejected", and relying contracts must be able to see which happened.

**Why the veto window cannot be settled early.** If two chambers approve in the first hour of a 12-hour veto window and the result could be finalized at once, the veto right would be hollow. Treating the `VETO` node as `Pending` until the window closes or the veto body decides makes the result type a pure function of ballots and time and independent of who calls `settleRound` when.

**Why NoDecision is a first-class outcome and why appeals keep earlier decisions.** Many procedures end without a decision: nobody shows up, a chamber misses quorum, a submitter stays silent. Dressing that up as "rejected" or "approved" would hand a default to whichever side benefits from paralysis. The consumer commits its disposition in advance, and the registry only reports why the procedure ended. For the same reason an appeal that fails to reach quorum cannot erase the decision being appealed: the most recent substantive decision is adopted and the failed round is recorded beside it.

**Why K-of-N is an approval rule.** Under 4-of-5, two blocks stop approval; that proves the proposition cannot reach four approvals, not that four members found the opposite true. Reading `No` as the opposite proposition is a relying-contract decision that must be made in its own commitment, which is why the registry exposes `outcomeYes` and a reason rather than a verdict on two propositions.

**Why signed ballots carry no nonce and share the on-chain tally.** A nonce would let one voter produce several "fresh" ballots; keying de-duplication on the voter's identity per issue, round and body makes additional signatures worthless. Counting signed and on-chain ballots under one rule prevents a relayer from presenting a favourable batch as the round's result: a batch adds to the same counts and a decided body refuses further ballots.

**Why on-chain ballots and submitter reports name their round.** A signed ballot is bound to a round by its digest, so a round-1 signature can never count in round 2. Without an explicit round argument an on-chain ballot would lack that boundary: a transaction broadcast during round 1 but included after the round settled and an appeal opened round 2 would be counted in round 2, and since ballots cannot be changed the voter could not undo it. Requiring the round and rejecting a mismatch makes the two acceptance paths equally bound; the cost is one `uint32` of calldata and a comparison. The same applies to an authorized submitter's report.

**Why the kernel never executes effects.** A decision registry that could move assets would need the authority of every relying contract; separating decision from execution, as governors with timelocks do, keeps the registry's trust footprint to its records and lets each relying contract decide how much of a result it enforces and when.

**Why the appeal window runs from the formation instant.** Anchoring it to the settlement transaction would let any party stretch a procedure by not calling `settleRound`; anchoring it to the instant the ballots determined the result makes the deadline a property of the record, not of who acted when.

## Backwards Compatibility

This ERC introduces new contracts and requires no change to existing standards. Relying contracts that already delegate acceptance to a single address — an evaluator, an acceptance authority, an arbitrator — can point that address at an adapter that reads this registry, without changing their own interfaces. Policies, issues and results are new objects; nothing in this ERC reinterprets existing tokens, registries or signatures. ERC-6372 clock disclosure and ERC-165 interface detection are used as specified in those documents.

## Test Cases

Deterministic vectors are provided under the assets of this proposal and regenerated by `tools/vectors.js`:

- [`policy-id.json`](../assets/eip-9999/vectors/policy-id.json): three complete `PolicySpec` values (minimal 3-of-5; two chambers under `ALL`; a `VETO` over `ALL` with one appeal) with their ABI encodings and `policyId`s, produced by an independent ABI coder and re-derived in Solidity;
- [`ballot-digest.json`](../assets/eip-9999/vectors/ballot-digest.json): EIP-712 ballot digests for a fixed chain id and verifying contract;
- [`kofn-tally.json`](../assets/eip-9999/vectors/kofn-tally.json): 83 rows of the roster K-of-N status rule over `(N, k, yes, no, closed)`;
- [`composition.json`](../assets/eip-9999/vectors/composition.json): 192 rows of `ALL`, `ANY` and 2-of-3 composition over every triple of child values in `{Yes, No, Pending, NoDecision}`;
- [`interface-ids.json`](../assets/eip-9999/vectors/interface-ids.json): the ERC-165 identifiers of Section 15.

The reference repository's Foundry suite (121 tests in eight files) exercises the reference implementation: minimal tally edge cases and policy validation; acceptance modes, freezing, withdrawal and the obligation rule; composition including every `VETO` branch and the independence of the result from settlement order; rounds, appeals, the adoption rule, hard deadlines and replay of earlier-round signatures; signed-ballot verification including ERC-1271 accounts, malleable signatures and favourable late batches; and an end-to-end adapter run against a vendored task-tender kernel covering acceptance, rejection, no-decision defaults, late execution and retry after a kernel refusal.

## Reference Implementation

A reference implementation is provided under the assets of this proposal:

- Types and interfaces: [`ACDFTypes.sol`](../assets/eip-9999/contracts/ACDFTypes.sol), [`IACDFPolicyRegistry.sol`](../assets/eip-9999/contracts/interfaces/IACDFPolicyRegistry.sol), [`IACDFRegistry.sol`](../assets/eip-9999/contracts/interfaces/IACDFRegistry.sol).
- Registries: [`ACDFPolicyRegistry.sol`](../assets/eip-9999/contracts/ACDFPolicyRegistry.sol) and [`ACDFRegistry.sol`](../assets/eip-9999/contracts/ACDFRegistry.sol) — non-upgradeable, permissionless, with the signature helper [`SignatureChecker.sol`](../assets/eip-9999/contracts/libraries/SignatureChecker.sol).
- Adapter: [`ACDFTaskTenderAdapter.sol`](../assets/eip-9999/contracts/adapters/ACDFTaskTenderAdapter.sol) against the vendored kernel interface [`ITaskTender8414.sol`](../assets/eip-9999/contracts/interfaces/ITaskTender8414.sol) (informative).
- Schemas: [`policy-spec.schema.json`](../assets/eip-9999/schemas/policy-spec.schema.json) mirrors the on-chain `PolicySpec` for off-chain tooling; [`result-receipt.schema.json`](../assets/eip-9999/schemas/result-receipt.schema.json) describes an off-chain carrier of a registry record, which is never a substitute for the record.

The issue registry compiles to 23,514 bytes of runtime code under solc 0.8.24 with the IR pipeline, within the [EIP-170](./eip-170.md) limit.

## Security Considerations

**Authorization boundary.** A result binds only the consumer that committed to it, only for the effects it committed to. Relying contracts MUST derive the consumer binding from their own state (the adapter pattern of Section 14) and MUST NOT accept a caller's claim to act for an object they control. Nothing written into the registry grants power over any contract that did not itself file, pre-accept or acknowledge.

**Verdict shopping.** The obligation rule (one unfinished Binding issue per `(consumer, subject, question)`) prevents filing the same obligation to several panels. Relying contracts whose business key is finer than `subject` (for example a submission's result hash and cited task version) SHOULD fold it into `subject.dataHash`, and SHOULD refuse to reopen an obligation that already reached a decision.

**Option-like acknowledgment.** POST_ACK acknowledgment before admission, and the prohibition on upgrading an advisory issue, prevent a party from binding itself only after seeing how the vote goes. Implementations MUST NOT add an upgrade path.

**Panel shopping by withdrawal.** Withdrawal is limited to the `Filed` state because, after admission, the roster and windows are known and a filer allowed to withdraw and refile could wait for a favourable panel.

**Frozen rules.** Because the policy identifier is the hash of the executed struct, no proxy or admin can change a policy under an open issue. Deployments that add pluggable modules in future profiles MUST declare which dependencies may change, when they are evaluated and what happens if they fail; address and code-hash pinning alone does not establish immutability.

**Liveness and griefing.** Every state has a permissionless exit: `settleRound` after the round deadline, `finalize` after the appeal window, `enforceHardDeadline` after the cap, `admitAdvisory` or `expireUnacknowledged` after the acknowledgment window. Appeals are bounded by `maxAppeals` and the hard cap. A permissionless path is a path, not an executor: someone must call it, and relying contracts SHOULD plan for that.

**Timing.** Deadlines are arrival deadlines: a ballot or result counts only if the registry receives it in time, and an adapter's enactment counts only if the target contract receives it before the target's own deadline. Relying contracts SHOULD size `consumerDeadline` with an execution margin and from the earliest of their own clocks. Appeal windows anchored to formation instants cannot be extended by delaying settlement.

**Signature handling.** Signed ballots bind chain id, registry, issue, round, body, voter and position; they carry no nonce by design (Section 7.3). On-chain ballots and submitter reports are bound to a round by the explicit `round` argument (Sections 7.2 and 7.4), so a pending transaction cannot drift into a later round. ERC-1271 validity may depend on the signing contract's state at submission time; a contract voter that changes its validation logic can change whether its ballot is accepted, never whether an already accepted ballot counts. EIP-712 provides no replay protection by itself; the per-voter, per-round, per-body key does.

**Correlated participants and Sybil rosters.** This ERC does not establish that roster members are independent or that they are who a policy author believes them to be; a roster of N addresses controlled by one operator is one voter with N ballots. Eligibility profiles (reserved) are where identity, trust assertions, per-operator caps and conflict exclusion belong. Policy authors SHOULD disclose what their rosters assume.

**Evidence and prompts.** Evidence is untrusted data. Agent participants SHOULD treat evidence URIs and contents as input to evaluate, never as instructions, and SHOULD commit to their rationale off-chain where a profile asks for it.

**Incentive design.** This ERC pays, bonds and scores nobody. Profiles that add incentives SHOULD avoid rewarding agreement with the majority as such, since that selects for predicting the panel rather than judging the matter, and SHOULD base penalties on provable procedural violations (for example contradictory signed ballots in one round) rather than on dissent.

**Registry instance trust.** A relying contract binds to a specific registry instance. The instance's deployment, upgradeability (none, for the reference implementation) and the policy versions accepted are the relying contract's trust decisions and SHOULD be disclosed to its users.

**Chain finality.** A `Final` state is a procedural fact recorded on-chain; it is not chain finality. Cross-chain readers of a result MUST state their own assumptions about the source chain and the bridge they rely on; this ERC reserves cross-chain carriage and makes no claim about it.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
