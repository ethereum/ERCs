---
title: Agent Off-Chain Conditional Settlement Extension Interface
description: Standard typed data formats and extension interfaces for agent-native off-chain conditional settlement over existing off-chain channel frameworks.
author: Xianrui Qin (@xrqin)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-03-10
requires: 165, 712, 1271
---

## Abstract

This ERC defines a minimal interoperability layer for agent-native off-chain conditional settlement.
It standardizes:

- [EIP-712](./eip-712.md) typed data for proof-bound conditional obligations and related settlement intents.
- A minimal on-chain conditional settlement extension interface for settlement, refund, and lock-status queries.
- Optional extensions for capability discovery, private claim relay, and local rebalancing coordination.

This ERC is designed to compose with existing off-chain channel frameworks rather than replace them.
It does **not** standardize channel lifecycle primitives, custody or exit primitives, routing algorithms, rebalancing algorithms, application-layer job or commerce state machines, specific zero-knowledge circuits, privacy pools, liquidity management strategies, or hub business logic.

## Motivation

Recent agent-related ERCs mainly focus on identity, accounts, permissions, or payment signaling.
They do not define a common settlement layer for high-frequency machine-to-machine interactions.

This gap matters because autonomous agents have a very different interaction profile than human users:

- They are online continuously.
- They can sign and verify state updates automatically.
- They perform recurring micropayments, streaming payments, and conditional execution.
- They benefit from sub-second, near-zero-marginal-cost settlement.

Historically, state channels have been difficult to adopt for human users because humans do not want to manage liveness, disputes, and frequent signatures.
Agents, however, are natural channel participants.

This ERC aims to standardize the settlement-facing interface of such systems without forcing a single implementation architecture.
It is designed so that different wallets, hubs, relays, private execution backends, and adjudicators can interoperate around a shared settlement envelope.

### Scope

This proposal intentionally standardizes the **settlement interface**, not the full payment channel stack.

The following are in scope:

- Proof-bound conditional obligation message formats.
- Proof reference formats.
- Relay claim request formats.
- Minimal conditional settlement extension interfaces.

The following are out of scope:

- Channel lifecycle primitives such as challenge, checkpoint, conclude, close, or dispute.
- Custody and exit primitives such as deposit, transfer, reclaim, or exit format.
- Specific payment-topology choices such as HTLCs or virtual channels.
- Specific rebalancing algorithms or coordination policies.
- Application-layer job or commerce protocols.
- Specific private execution backends or privacy-preserving routing constructions.
- Solvency proofs, margin vaults, or operator collateral models.

This boundary keeps the ERC narrow enough to be implementable while still being useful.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Roles

- `Agent`: an autonomous signer participating in off-chain settlement.
- `Hub`: a coordinating counterparty or routing service that may aggregate or forward settlement.
- `Relay`: an optional third party that submits a claim or settlement transaction on behalf of an agent.
- `Host Framework`: an existing off-chain channel or settlement framework that defines lifecycle and custody primitives.
- `Adjudicator`: an on-chain contract that exposes conditional settlement extension hooks and may be composed with a host-framework adjudicator.
- `Verifier`: an optional external verifier or proof system endpoint referenced by settlement proofs.

Contracts implementing the core interface or any extension defined in this ERC SHOULD implement [ERC-165](./eip-165.md) and return `true` for the relevant interface identifiers.

### Design Goals

An implementation conforming to this ERC SHOULD support:

- Near-zero-gas happy-path settlement through off-chain signatures.
- Conditional settlement triggered by proofs, attestations, or timeouts.
- Strong replay protection across channels, chains, and intents.
- Compatibility with both EOAs and contract accounts.
- Composability with existing channel frameworks.
- Composability with [ERC-4337](./eip-4337.md) wallets, private relays, and application-specific backends.

### Non-Goals

This ERC MUST NOT be interpreted as standardizing:

- The canonical lifecycle primitives for channels or sessions.
- The canonical custody, transfer, or exit format.
- The canonical routing path format.
- The canonical rebalancing algorithm.
- The canonical proof system.
- The canonical privacy backend.
- The economic policy of hubs.

### Composition With Existing Channel Frameworks

This ERC is intended to compose with an existing host framework, not replace it.

If a host framework already defines canonical lifecycle primitives, such as `challenge`, `checkpoint`, `conclude`, `close`, or `dispute`, implementations SHOULD reuse those primitives rather than expose conflicting wrappers as part of ERC compliance.

If a host framework already defines canonical custody primitives, such as deposit, transfer, reclaim, or exit handling, implementations SHOULD reuse those primitives as well.

Accordingly, this ERC standardizes the conditional settlement envelope and extension hooks, while leaving lifecycle and custody to the host framework.

### Relationship to Application Protocols

This ERC is not intended to standardize a job, order, marketplace, subscription, or evaluator-driven commerce state machine.

Application-layer protocols such as [ERC-8183](./eip-8183.md) MAY define business objects, provider/evaluator roles, funding flows, submission flows, and terminal outcomes.

This ERC instead standardizes the lower-layer settlement envelope for proof-bound conditional obligations that may need to be represented and resolved within or alongside an off-chain channel or settlement framework.

An application protocol MAY compose with this ERC, but conformance to this ERC does not require any particular application object model.

### EIP-712 Domain

All off-chain messages standardized by this ERC MUST be signed over an [EIP-712](./eip-712.md) domain.

The domain MUST include at least:

- `name`
- `version`
- `chainId`
- `verifyingContract`

Implementations SHOULD use:

- `name = "AgentOffchainConditionalSettlement"`
- `version = "1"`

If a signer is a contract account, signatures MUST be verified via [ERC-1271](./eip-1271.md).

### Canonical Identifiers

#### Channel Identifier

This ERC does not require a single channel construction model, but interoperable implementations SHOULD derive `channelId` from stable settlement context rather than local database identifiers.

A RECOMMENDED derivation is:

```solidity
channelId = keccak256(abi.encode(
    block.chainid,
    address(adjudicator),
    participantSetHash,
    channelSalt
));
```

Where:

- `participantSetHash` commits to the authorized settlement participants.
- `channelSalt` distinguishes multiple settlement relationships between the same participants.

If an implementation is layered over an existing host framework that already defines a canonical `channelId`, it SHOULD reuse that identifier verbatim.

#### Request Identifier

For relay requests and capacity certificates, implementations SHOULD derive request identifiers from the full typed-data payload rather than sequential local counters alone.

### Core Typed Data

#### Condition Type Identifiers

Condition types are identified by `bytes32 conditionType`.
Implementations MAY support additional condition types, but the following identifiers are RECOMMENDED:

- `keccak256("HTLC")`
- `keccak256("ORACLE_ATTESTATION")`
- `keccak256("ZK_PROOF")`
- `keccak256("MULTISIG")`
- `keccak256("TIMELOCK")`
- `keccak256("COMPOSITE")`

#### Proof Type Identifiers

Proof types are identified by `bytes32 proofType` in `SettlementProofRef` and `ClaimRelayRequest`.
They indicate the verification pathway that MUST be used to validate the settlement evidence, not the internal format or length of the proof itself.

Implementations MAY support additional proof types, but the following identifiers are RECOMMENDED:

- `keccak256("RECEIPT_ROOT")` — settlement is proven by a Merkle inclusion proof against a receipt or state root.
- `keccak256("ZK_PROOF")` — settlement is proven by a zero-knowledge proof verified by the `verifier` contract. The proof system (Groth16, PLONK, STARK, etc.) is determined by the verifier, not by this identifier.
- `keccak256("ORACLE_ATTESTATION")` — settlement is proven by a signed attestation from an oracle identified by the `verifier` address.
- `keccak256("RELAY_CLAIM")` — settlement is claimed by an authorized relay on behalf of the claimant, subject to the relay authorization rules defined in this ERC.
- `keccak256("MULTISIG_ATTESTATION")` — settlement is proven by a threshold or multi-signature attestation from a known signer set.
- `keccak256("TEE_ATTESTATION")` — settlement is proven by a remote attestation from a trusted execution environment.

All canonical identifiers are derived via `keccak256` over a human-readable label.
Third-party extensions SHOULD follow the same convention, using a namespaced label such as `keccak256("VENDOR.CUSTOM_TYPE")` to avoid collisions.

Implementations MUST NOT interpret `proofType` as constraining the length, encoding, or circuit-level details of the proof bytes themselves. Those details are determined by the `verifier` contract or endpoint referenced in `SettlementProofRef`.

#### ConditionalLock

`ConditionalLock` is the canonical off-chain settlement envelope.
The name is a convenience label; it should be understood as a proof-bound conditional obligation envelope, not as a requirement that every host framework expose a standalone native lock primitive.

```solidity
struct ConditionalLock {
    bytes32 channelId;
    address initiator;
    address responder;
    bytes32 assetId;
    uint256 amount;
    uint256 fee;
    uint256 expiry;
    bytes32 conditionType;
    bytes32 conditionCommitment;
    bytes32 applicationCommitment;
    bytes32 escrowCommitment;
    uint256 channelNonce;
}
```

Field requirements:

- `channelId` MUST uniquely identify the off-chain settlement relationship.
- `amount` MUST represent the principal to be settled.
- `fee` MUST represent the fee owed to the settlement counterparty, if any.
- `expiry` MUST define the timeout after which refund becomes valid if settlement has not completed.
- `conditionCommitment` MUST commit to the condition-specific witness or attestation requirements.
- `applicationCommitment` MAY commit to application-specific execution details such as call parameters, constraints, or intent hashes.
- `escrowCommitment` MAY commit to a claim secret, escrow key, or claim destination abstraction.
- `channelNonce` MUST prevent stale-state replay within the channel and MAY correspond to the host framework's turn number, version counter, or equivalent monotonic lifecycle counter.

The `lockId` for a `ConditionalLock` MUST be derived as:

```solidity
lockId = keccak256(abi.encode(
    channelId,
    initiator,
    responder,
    assetId,
    amount,
    fee,
    expiry,
    conditionType,
    conditionCommitment,
    applicationCommitment,
    escrowCommitment,
    channelNonce
));
```

#### SettlementProofRef

`SettlementProofRef` references whatever evidence is used to settle the lock.

```solidity
struct SettlementProofRef {
    bytes32 channelId;
    bytes32 lockId;
    bytes32 proofType;
    bytes32 settlementRoot;
    bytes32 proofDigest;
    address verifier;
    bytes32 auxDataHash;
}
```

Field requirements:

- `channelId` MUST match the channel or settlement context of the referenced lock.
- `lockId` MUST reference a previously agreed `ConditionalLock`.
- `proofType` MUST identify the proof or attestation family.
- `settlementRoot` MAY represent a receipt root, attestation root, Merkle root, or other settlement anchor.
- `proofDigest` MUST commit to the opaque proof bytes or attestation payload.
- `verifier` MUST identify the verification contract or verification endpoint when on-chain verification is required.
- `auxDataHash` MAY commit to additional public inputs or settlement metadata.

This ERC does not standardize the contents of the proof itself.

#### ClaimRelayRequest

`ClaimRelayRequest` is used when a relay submits a claim on behalf of an agent.

```solidity
struct ClaimRelayRequest {
    bytes32 channelId;
    bytes32 lockId;
    bytes32 escrowCommitment;
    bytes32 outputCommitmentHash;
    uint256 maxRelayFee;
    uint256 deadline;
    bytes32 proofType;
    bytes32 proofDigest;
    uint256 nonce;
}
```

Field requirements:

- `channelId` MUST match the channel or settlement context of the related conditional lock.
- `lockId` MUST reference the related conditional lock.
- `escrowCommitment` MUST match the commitment expected by the settlement flow.
- `outputCommitmentHash` MUST commit to the desired output state or minted notes.
- `maxRelayFee` MUST cap the maximum relay fee the requester is willing to pay.
- `deadline` MUST define after which the request becomes invalid.
- `nonce` MUST prevent relay replay.

### Signing And Activation Rules

#### Conditional Lock Activation

A `ConditionalLock` MUST NOT be considered active solely because one party signed it.

Instead, an implementation MUST define an activation rule and apply it consistently.
For bilateral channel-style systems, the RECOMMENDED rule is:

- the initiator signs the lock proposal, and
- the counterparty or hub co-signs the same lock payload before the lock becomes active.

If an implementation supports multi-party channels or delegated signers, it MUST define:

- which signers are required,
- how their signatures are ordered or aggregated,
- whether the signer set is fixed or capability-dependent.

#### Proof Reference Binding

An implementation MUST ensure that a `SettlementProofRef` is bound to exactly one `lockId`.
It MUST NOT be possible to reuse one proof reference to settle multiple incompatible locks.

#### Relay Request Authorization

An implementation that supports `ClaimRelayRequest` MUST verify that the relay request was explicitly authorized by the claimant or the claimant's authorized contract account.

This authorization MAY be:

- an [EIP-712](./eip-712.md) signature over `ClaimRelayRequest`,
- an [ERC-1271](./eip-1271.md) contract signature check,
- an implementation-specific proof tied to `escrowCommitment`.

### Recommended Commitment Composition

This ERC intentionally leaves commitment internals flexible, but interoperable implementations SHOULD use stable hash composition rules.

#### applicationCommitment

For execution-oriented systems, a RECOMMENDED derivation is:

```solidity
applicationCommitment = keccak256(abi.encode(
    applicationId,
    parametersHash,
    constraintsHash,
    executionDeadline,
    salt
));
```

#### escrowCommitment

A RECOMMENDED derivation is:

```solidity
escrowCommitment = keccak256(abi.encode(
    claimSecretHash,
    outputDescriptorHash,
    salt
));
```

These are recommendations only and do not constrain implementations that use alternative commitment schemes.

### Core On-Chain Interface

Implementations MAY use any internal storage model, but a conforming contract MUST expose the following minimal conditional settlement extension interface.

```solidity
interface IAgentConditionalSettlementExtension {
    enum LockStatus {
        None,
        Locked,
        Settled,
        Refunded
    }

    event ConditionalLockSettled(
        bytes32 indexed channelId,
        bytes32 indexed lockId,
        bytes32 indexed proofType,
        bytes32 proofDigest
    );

    event ConditionalLockRefunded(
        bytes32 indexed channelId,
        bytes32 indexed lockId
    );

    function settleConditional(
        bytes32 channelId,
        ConditionalLock calldata lock,
        SettlementProofRef calldata proofRef,
        bytes calldata proof
    ) external;

    function refundConditional(
        bytes32 channelId,
        bytes32 lockId
    ) external;

    function lockStatus(
        bytes32 channelId,
        bytes32 lockId
    ) external view returns (LockStatus);

    function supportsConditionType(
        bytes32 conditionType
    ) external view returns (bool);

    function domainSeparator() external view returns (bytes32);
}
```

#### Required Semantics

A compliant implementation MUST satisfy the following:

- `settleConditional` MUST settle a lock only if:
  - the lock is valid,
  - `channelId`, `lock.channelId`, and `proofRef.channelId` are identical,
  - `proofRef.lockId` equals the derived `lockId` of `lock`,
  - the proof or attestation is valid under local implementation rules, and
  - the lock has not already been settled or refunded.
- `refundConditional` MUST refund a lock when its expiry has passed and valid settlement has not completed.
- `lockStatus` MUST expose whether a lock is unsettled, settled, or refunded.

This ERC does not require `ConditionalLock` objects to be individually registered on-chain during the happy path.
Implementations MAY settle them only when invoked during the host framework's lifecycle resolution path.

#### Host Framework Boundaries

This ERC does not standardize `challenge`, `checkpoint`, `conclude`, `close`, `dispute`, `deposit`, `transfer`, `reclaim`, or exit format.

If implemented alongside a similar framework, those host-framework methods remain authoritative for lifecycle and custody.

A contract MAY offer convenience wrappers around the host framework, but such wrappers are not part of ERC compliance.

### Optional Extension A: Capability Discovery

An implementation that supports capability discovery SHOULD expose:

```solidity
interface IAgentCapabilityDiscovery {
    event CapabilityURIUpdated(string uri);

    function capabilityURI() external view returns (string memory);
    function defaultExpiry() external view returns (uint256);
    function maxPendingLocks() external view returns (uint256);
}
```

The `capabilityURI` document SHOULD describe:

- supported condition types,
- supported proof types,
- whether private claim relay is supported,
- whether virtual channels are supported,
- whether local rebalancing coordination is supported,
- fee model hints,
- recommended timeout policy.

A RECOMMENDED JSON shape is:

```json
{
  "name": "Example Agent Settlement Hub",
  "version": "1",
  "conditionTypes": [
    "HTLC",
    "ORACLE_ATTESTATION",
    "ZK_PROOF",
    "TIMELOCK"
  ],
  "proofTypes": [
    "RECEIPT_ROOT",
    "ZK_PROOF",
    "ORACLE_ATTESTATION",
    "RELAY_CLAIM"
  ],
  "supportsPrivateClaimRelay": true,
  "supportsVirtualChannels": true,
  "supportsLocalRebalancingCoordination": true,
  "defaultExpiryBlocks": 100,
  "maxPendingLocks": 64,
  "feeModel": {
    "baseFee": "1",
    "proportionalPPM": "300"
  }
}
```

### Optional Extension B: Private Claim Relay

An implementation that supports private claim relays SHOULD expose:

```solidity
interface IAgentPrivateClaimRelay {
    event ClaimRelayed(
        bytes32 indexed lockId,
        address indexed relayer,
        bytes32 indexed requestHash
    );

    function relayClaim(
        ClaimRelayRequest calldata request,
        bytes calldata proof,
        bytes calldata authorization
    ) external returns (bytes32 claimId);
}
```

Requirements:

- `authorization` MUST prove that the relay request was authorized by the claimant.
- The relay implementation MUST respect `deadline`, `maxRelayFee`, and `nonce`.
- The relay extension MAY be implemented by the adjudicator, a vault, or a dedicated relay contract.

### Optional Extension C: Local Rebalancing Coordination

This extension standardizes a certificate format for local capacity shifts.
It does **not** standardize the scheduling algorithm or rebalancing policy.

```solidity
struct CapTransferCert {
    bytes32 transferId;
    bytes32 srcChannelId;
    bytes32 dstChannelId;
    uint256 delta;
    uint256 srcNonceCapNew;
    uint256 dstNonceCapNew;
    uint256 expiry;
    bytes32 metadataHash;
}
```

Requirements:

- `CapTransferCert` MUST NOT change the canonical settlement meaning of the underlying `payState`.
- If a local rebalancing coordination action conflicts with the host framework lifecycle resolution, the latest valid settlement state MUST take precedence.
- This extension MUST be treated as a liveness and throughput optimization, not as a canonical settlement state transition.

An implementation that supports this extension SHOULD expose:

```solidity
interface IAgentLocalRebalancingCoordination {
    event CapTransferCompleted(
        bytes32 indexed transferId,
        bytes32 indexed srcChannelId,
        bytes32 indexed dstChannelId,
        uint256 delta
    );

    function supportsLocalRebalancingCoordination() external view returns (bool);
}
```

### Message Hashing

Implementations SHOULD publish exact [EIP-712](./eip-712.md) type strings for all supported message families.

Recommended primary types:

```text
ConditionalLock(
  bytes32 channelId,
  address initiator,
  address responder,
  bytes32 assetId,
  uint256 amount,
  uint256 fee,
  uint256 expiry,
  bytes32 conditionType,
  bytes32 conditionCommitment,
  bytes32 applicationCommitment,
  bytes32 escrowCommitment,
  uint256 channelNonce
)

SettlementProofRef(
  bytes32 channelId,
  bytes32 lockId,
  bytes32 proofType,
  bytes32 settlementRoot,
  bytes32 proofDigest,
  address verifier,
  bytes32 auxDataHash
)

ClaimRelayRequest(
  bytes32 channelId,
  bytes32 lockId,
  bytes32 escrowCommitment,
  bytes32 outputCommitmentHash,
  uint256 maxRelayFee,
  uint256 deadline,
  bytes32 proofType,
  bytes32 proofDigest,
  uint256 nonce
)
```

## Rationale

### Why standardize the settlement layer instead of the full channel stack?

The full channel stack is still an active design space.
Different systems may choose HTLCs, virtual channels, programmable conditional locks, pairwise rebalancing, local rebalancing coordination, privacy-preserving hubs, or different dispute proofs.

Trying to standardize all of that in a single ERC would be too broad and would likely freeze experimentation too early.

By contrast, standardizing the settlement-facing envelope is immediately useful:

- wallets can produce a common lock format,
- hubs can advertise common capabilities,
- relays can serve many backends,
- adjudicators or companion extensions can expose a common integration surface.

### Why leave lifecycle and custody to the host framework?

Existing channel frameworks already define lifecycle and custody primitives.
Redefining those same primitives in this ERC would create unnecessary overlap, confuse implementers about which surface is authoritative, and make composability worse rather than better.

This ERC therefore standardizes the conditional settlement extension surface while explicitly delegating lifecycle and custody to the host framework.

### Why not just use an application protocol such as ERC-8183?

Application protocols may standardize jobs, providers, evaluators, submissions, and terminal job outcomes.
This ERC does not attempt to replace those protocols.

Instead, it defines the lower-layer settlement envelope used when a proof-bound conditional obligation must be represented, proven, settled, refunded, or relayed inside or alongside an off-chain channel framework.

An [ERC-8183](./eip-8183.md)-like application MAY compose with this ERC, but this ERC does not require any job abstraction, evaluator role, or application-specific state machine.

### Why EIP-712?

[EIP-712](./eip-712.md) provides explicit domain separation, human- and machine-readable structured messages, compatibility with EOAs and smart accounts, and a familiar signing model for wallets and agents.

### Why define canonical condition type and proof type identifiers?

Without a shared set of type identifiers, different implementations would invent incompatible labels for the same verification pathway. A hub receiving a `ConditionalLock` would be unable to determine whether it can verify the condition without implementation-specific out-of-band negotiation.

Canonical identifiers solve this by giving the ecosystem a common vocabulary. At the same time, this ERC uses an open registry convention — `keccak256` over a human-readable label — rather than a fixed enumeration. This means:

- the initial set covers the most common verification pathways today,
- new proof systems or attestation families can be added by any party by following the `keccak256("NAMESPACE.TYPE")` convention,
- no governance process or ERC amendment is required to introduce a new type,
- implementations can use `supportsConditionType` and capability discovery to negotiate support dynamically.

### Why keep proof systems opaque?

The proof system used for conditional settlement is expected to evolve quickly.
Some implementations may use Merkle inclusion proofs, zk-SNARKs, oracle attestations, threshold signatures, or trusted execution attestations.

The ERC therefore standardizes the reference envelope, not the proof internals.

### Why is local rebalancing coordination only an extension?

Local rebalancing coordination is useful for agent-heavy hubs because it reduces coordination fan-out.
However, it is still a rebalancing strategy choice.
Other systems may prefer pairwise, local, global-merge, or future strategies.
The extension standardizes the certificate shape without forcing a specific algorithm.

## Backwards Compatibility

This ERC is designed to be compatible with:

- [ERC-4337](./eip-4337.md) smart accounts and session-key systems,
- [ERC-1271](./eip-1271.md) contract-based signers,
- existing state channel frameworks that already provide lifecycle and custody primitives,
- existing payment channel implementations that already support close/dispute or challenge/conclude style resolution,
- private execution backends such as shielded pools or relay-based execution systems.

It does not require breaking changes to those systems.
It adds a common conditional settlement extension interface above them.

## Test Cases

Future versions of this draft will include:

- [EIP-712](./eip-712.md) hashing test vectors,
- signature verification examples for EOAs and [ERC-1271](./eip-1271.md) accounts,
- conditional refund edge cases,
- proof reference examples for multiple proof families,
- local rebalancing coordination certificate examples.

## Reference Implementation

TBD

## Security Considerations

### Stale State And Replay

Implementations MUST protect against:

- replay across channels,
- replay across chains,
- replay across relays,
- replay of expired locks,
- replay of old lifecycle states.

This is why `channelId`, `chainId`, `channelNonce`, and request nonces are required.

### Canonical Settlement State

If an implementation also uses local operational states such as routing budgets or capacity budgets, those states MUST NOT override the canonical settlement state used by the host framework lifecycle.

In particular:

- `payState` MUST remain canonical for settlement,
- operational states such as `capState` MUST be treated as advisory or liveness-oriented,
- conflicts MUST resolve in favor of the latest valid canonical settlement state.

### Proof Verifier Trust

This ERC does not prove that a referenced proof verifier is trustworthy.
Implementations MUST define:

- who chooses the verifier,
- how the verifier is upgraded,
- how the settlement root or proof anchor is authenticated.

### Timeout Griefing

Conditional locks can be abused to consume liquidity or pending-lock slots.
Implementations SHOULD define:

- maximum pending locks per channel,
- minimum lock values,
- relay fee policy,
- expiry windows,
- reputation or rate limits for abusive participants.

### Private Claim Relay

Relays improve privacy but introduce additional trust and operational assumptions.
Implementations SHOULD document:

- whether relays learn claimant metadata,
- whether relay requests are encrypted,
- what replay protections are used,
- whether relays can censor or delay claims.

### Adapter And Execution Safety

If a system uses adapters or execution routers behind this settlement standard, those adapters remain out of scope for the ERC but are security-critical in practice.
Implementations SHOULD use strict whitelists, typed parameter validation, exact approvals, allowance reset, reentrancy protection, and output constraint checks.

### Privacy Considerations

This ERC can be used in both private and non-private systems.
By itself it does **not** guarantee hub blindness, amount privacy, unlinkability, claim anonymity, or side-channel resistance.

Those properties depend on optional routing, cryptographic, and relay layers built on top of this interface.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
