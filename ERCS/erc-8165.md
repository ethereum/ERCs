---
eip: 8165
title: Agentic Onchain Operations
description: Standardized end-to-end workflow for agent-issued intents, permissionless fulfillment, atomic settlement, and verifiable receipts
author: Qin Wang (@qinwang-git), Ruiqiang Li (@richard-620), Saber Yu (@OniReimu), Shiping Chen <shiping.chen@data61.csiro.au>
discussions-to: https://ethereum-magicians.org/t/erc-8165-agentic-on-chain-operation-interface/27773
status: Draft
type: Standards Track
category: ERC
created: 2026-02-18
requires: 165, 712, 1271
---

# Abstract

This ERC standardizes the canonical workflow interface for agentic on-chain operations. It defines a signed intent envelope expressing core safety bounds (maximum input, minimum output, validity windows, and replay protection), a permissionless settlement surface enabling competitive solver fulfillment, and structured settlement receipts providing verifiable workflow closure.

The standard separates intent authorship from solving and execution, enabling autonomous agents, solvers, and users to coordinate around outcome-based objectives. Core safety bounds are enforceable on-chain by every compliant hub. Additional policies MAY be enforceable via optional constraint modules. Every outcome is recorded via machine-readable receipts suitable for post-execution verification and structured record-keeping.

This ERC provides a common vocabulary and interface for agentic on-chain operations: a standardized lifecycle and receipts that make agents interoperable across runtimes and ecosystems.

# Motivation

Ethereum transactions encode execution instructions rather than desired outcomes. Emerging agent systems require a mechanism to express goals without prescribing execution paths.

Many systems define "orders" or "intents," but these systems vary in lifecycle semantics, signature domains, and receipt formats. The ecosystem lacks a standard lifecycle and uniform settlement receipts that make agents interoperable across runtimes. Without a shared workflow interface, each agent-solver pair must negotiate bespoke formats, verification procedures, and completion signals — fragmenting the ecosystem and limiting composability.

While [ERC-8004](./eip-8004.md) standardizes trustless agent identities and reputation, it does not define how agents express actionable objectives or how such objectives are executed and verified on-chain.

This proposal introduces:

- A canonical intent envelope with core safety bounds enforceable on-chain by every compliant hub
- Optional constraint modules for additional policies, with a standard enforcement hook
- A permissionless fulfillment interface supporting on-chain and off-chain intent distribution
- Atomic settlement guarantees with structured receipt events
- A standardized workflow lifecycle from authorship through verification

The goal is to enable autonomous agents, solvers, and builders to coordinate around outcome-based execution while preserving user safety, composability, and auditability. This ERC defines the minimal workflow closure primitive — core safety bounds enforceable on-chain, structured receipts, and optional constraint modules — needed for agents to treat on-chain actions as composable, verifiable skills.

## Non-goals

This ERC does not standardize:

- **Execution routing**: solver strategies, DEX selection, bridging logic, or multi-call sequencing remain implementation-specific.
- **Agent cognition or learning**: while receipts are designed to be suitable for agent memory and skill systems, this ERC does not prescribe how agents process or store outcomes.
- **Cross-chain messaging**: settlement occurs on a single chain; cross-chain coordination is out of scope.
- **Token economics**: fee structures beyond the declared `feeBps` parameter are not standardized.
- **Delegation and permissioning**: authorization between a principal and an authoring agent is a wallet-policy concern and is out of scope for this ERC.

# Agentic Workflow Model

This section defines the canonical workflow that this ERC standardizes: the actors, lifecycle states, and execution loop that together form an interoperable agent execution loop.

## Workflow Actors

| Role | Description |
|------|-------------|
| **Principal (Maker)** | The accountable owner of funds and constraints. Signs the intent envelope. |
| **Authoring Agent** | Constructs intents on behalf of the Principal. May be the Principal themselves or a delegated agent. Identified by `agentIdentity` in the intent. |
| **Solver** | Searches for an execution plan that satisfies the intent's constraints. Computes `executionData`. |
| **Executor (Fulfiller)** | Submits the on-chain transaction that performs settlement. May be the same entity as the Solver. |
| **IntentHub** | The settlement contract that enforces constraints, executes atomic settlement, and emits receipt events. |

## Workflow States

Intents progress through the following lifecycle states. These are normative semantics; implementations MAY represent them differently internally but MUST exhibit equivalent behavior.

```
Draft ──► Signed ──► Published ──► Executable ──► Fulfilled
                                       │
                                       ├──► Cancelled
                                       │
                                       └──► Expired
```

| State | Description |
|-------|-------------|
| **Draft** | Intent constructed off-chain; not yet signed. |
| **Signed** | Principal has produced a valid EIP-712 signature over the intent. |
| **Published** | Intent is distributed — either submitted on-chain (Profile A) or relayed off-chain (Profile B). |
| **Executable** | Within the validity window (`validAfter` ≤ now ≤ `validUntil`) and nonce not consumed. |
| **Fulfilled** | Atomic settlement has been executed; receipt emitted. Terminal state. |
| **Cancelled** | Principal has explicitly invalidated the intent. Terminal state. |
| **Expired** | `validUntil` has passed without fulfillment. Terminal state. |

## Canonical Execution Loop

The system defined by this ERC supports the following six-step workflow. The intent envelope enables steps 1–4 (off-chain); on-chain components MUST enable steps 5–6.

1. **Author**: An agent or user constructs an Intent envelope specifying outcome constraints and safety bounds.
2. **Sign**: The Principal signs the intent using EIP-712 structured data. Signature verification MUST support [EIP-1271](./eip-1271.md) where the maker is a contract wallet, in addition to EOA (ECDSA) signatures.
3. **Distribute**: The signed intent is published — either submitted on-chain via `submitIntent` (Profile A) or relayed off-chain to solver networks (Profile B).
4. **Solve**: One or more solvers compute an execution plan (`executionData`) that satisfies the intent's constraints.
5. **Execute**: A fulfiller calls the IntentHub's `fulfill` function, triggering atomic settlement.
6. **Verify & Record**: The IntentHub emits structured receipt events. Agents and monitoring systems can verify completion and store structured results for post-execution analysis, attribution, and record-keeping.

# Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

## Definitions

- **Maker**: Entity issuing an intent (the Principal).
- **Fulfiller**: Entity executing an intent (the Executor).
- **Intent**: Signed constraint envelope describing acceptable execution outcomes.
- **IntentHub**: Contract implementing settlement logic and emitting receipts.
- **Settlement Receipt**: Structured event data emitted upon fulfillment, providing verifiable workflow closure.
- **Registered Constraint Module**: A constraint module is considered registered iff `IConstraintRegistry.resolve(constraintsHash)` returns `module != address(0)` for a given `constraintsHash`. If `constraintsHash == bytes32(0)`, no module is registered and the hub MUST skip module validation.

## Applicability

This ERC standardizes a minimal safety envelope covering the common asset-moving core: maximum input, minimum output, validity windows, and replay protection. The core envelope standardizes bounded asset transfer outcomes; any multi-step objective is expressed as a bounded envelope plus constraint modules and `executionData`. This core applies to swaps, rebalancing, lending operations, bridge-and-execute sequences, and any operation expressible as bounded asset transfers. Native asset transfers (e.g., ETH) are out of scope; MAY be supported via wrapped tokens or hub-specific extensions.

Arbitrary non-universal objectives — such as governance voting, NFT acquisition criteria, or custom DeFi strategies — MUST be expressed via discoverable constraint modules referenced by `constraintsHash`. The core envelope remains intentionally minimal to maximize interoperability across agent runtimes and solver implementations.

## Intent Structure

Intents MUST be signed using [EIP-712](./eip-712.md) structured data. Implementations MUST include `chainId` and `verifyingContract` in the EIP-712 domain separator.

```
Intent {
    address maker;
    address inputToken;
    uint256 inputAmountMax;
    address outputToken;
    uint256 outputAmountMin;
    address receiver;
    uint48  validAfter;
    uint48  validUntil;
    uint256 nonce;
    bytes32 constraintsHash;
    uint256 feeBps;
    bytes32 salt;
    address agentIdentity;
}
```

### Field Semantics

- `maker`: The Principal's address. MUST match the signer (or be authorized via EIP-1271).
- `inputToken` / `outputToken`: ERC-20 token addresses for the input spent and output received.
- `inputAmountMax`: Maximum input the maker is willing to spend (gross, before fees).
- `outputAmountMin`: Minimum output the receiver must obtain (net, after fee deduction). MUST be enforced during settlement. See Fee Accounting below.
- `receiver`: Address that receives the output tokens.
- `validAfter` / `validUntil`: Unix timestamps defining the validity window. `validUntil` MUST be greater than `validAfter`.
- `nonce`: Replay protection. MUST prevent replay per maker. `nonce` MAY be sequential or arbitrary; hubs MUST treat it as an opaque value and enforce uniqueness only.
- `constraintsHash`: The `keccak256` hash of the canonical encoding of additional constraint rules. RECOMMENDED encoding is a v1 canonical encoding defined as `abi.encode(bytes4 constraintsType, bytes constraintsData)`, where `constraintsType` is a 4-byte identifier that references a published constraint spec. `constraintsType` identifiers SHOULD be derived from a namespaced hash — e.g., `bytes4(keccak256("com.example.ConstraintName:v1"))` — to minimize collision risk. Collision resistance is best-effort due to 4-byte truncation; registries SHOULD reject registrations where a `constraintsType` value is already in use for a different spec. Implementations MAY alternatively store a registry-resolvable pointer. See Constraint Discoverability in Optional Modules. Opaque, undiscoverable hashes reduce interoperability.
- `feeBps`: Fee in basis points relative to the gross output. MUST NOT exceed 10,000. Declared as `uint256` for ABI slot uniformity; values above 10,000 MUST be rejected. See Fee Accounting below.
- `salt`: Additional entropy for intent uniqueness.
- `agentIdentity`: The identity of the **authoring agent** that constructed the intent. This is distinct from the fulfiller/executor, which is recorded in the settlement receipt.

### Fee Accounting

To avoid ambiguity between gross and net amounts, the following definitions apply:

- **`outputAmountGross`**: The total output produced by the execution, before fee deduction.
- **`feeAmount`**: Computed as `floor(outputAmountGross * feeBps / 10_000)`. Integer floor division MUST be used.
- **`outputAmountNet`**: The amount delivered to the receiver, equal to `outputAmountGross - feeAmount`. This MUST be ≥ `outputAmountMin`.

`feeBps` MUST NOT exceed 10,000. A value of 10,000 is technically valid but results in `outputAmountNet = 0`; such an intent MUST fail unless `outputAmountMin == 0`. Makers SHOULD set `outputAmountMin > 0` to guard against this.

The following invariants MUST hold for every settled intent:

```
feeAmount     = floor(outputAmountGross * feeBps / 10_000)
outputAmountNet = outputAmountGross - feeAmount
outputAmountNet ≥ outputAmountMin
```

All receipt fields (`outputAmountGross`, `outputAmountNet`, `feeAmount`) and the `IntentFulfilled` event MUST use these definitions consistently. Amounts MUST be derived from observed balance deltas rather than trusting token return values, to correctly handle fee-on-transfer and rebasing tokens. Concretely: `inputAmountUsed = makerInputBalanceBefore − makerInputBalanceAfter`; `outputAmountGross = receiverOutputBalanceAfter − receiverOutputBalanceBefore`. If the hub acts as an intermediary (e.g., via `transferFrom`, `permit`, or a pull-based pattern), hub balance deltas SHOULD be used when the hub is the accounting boundary. Input transfer MAY use any approved pull mechanism; this ERC does not mandate `transferFrom` exclusively.

`outputAmountGross` is derivable as `outputAmountNet + feeAmount` and is therefore not explicitly included in the `IntentFulfilled` event to save gas.

A nonce MAY be reused on a different hub, since replay protection is scoped to `(hub.domainSeparator, maker, nonce)`. Cross-hub replay of a signed intent is not possible unless the maker signs an intent for each hub independently.

### Requirements

- Expired or fulfilled intents MUST be rejected.
- Signature verification MUST support [EIP-1271](./eip-1271.md) where the maker is a contract, in addition to standard EOA (ECDSA) verification.

## Profiles

This ERC defines two submission profiles to accommodate different distribution models. Implementations MUST support at least one profile.

### Profile A — Registered Intent (On-chain)

In Profile A, the intent and signature are submitted on-chain before fulfillment.

- `submitIntent(intent, signature)` stores the intent and signature, returning an `intentId`.
- `fulfill(intentId, executionData)` references the stored intent.

Profile A is RECOMMENDED because it enables deterministic signature verification without requiring the fulfiller to carry the full intent calldata in every `fulfill` transaction. This reduces gas costs for fulfillers and simplifies verification logic.

### Profile B — Unregistered Intent (Off-chain)

In Profile B, the intent is relayed off-chain (e.g., via solver networks or intent pools).

- `fulfill(intent, signature, executionData)` receives the full intent and signature inline.
- The IntentHub computes `intentId` deterministically from the intent.

Profile B is common in competitive solver markets where intents are distributed off-chain to maximize solver participation. Implementations MAY support Profile B.

**Cancellation**: Cancellation via `cancelIntent` is defined only for intents submitted on-chain (Profile A). For Profile B, intents have no on-chain registration to cancel. Off-chain cancellation is accomplished by the maker consuming the `(maker, nonce)` pair — either by fulfilling a different intent or by submitting and cancelling a Profile A intent with the same nonce. A hub MAY offer a `cancelBySig(Intent, signature)` extension for off-chain-originated cancellations, but this is NON-STANDARD and not required for compliance.

**Profile B-only hubs**: Implementations supporting only Profile B MUST still emit `IntentFulfilled` receipts and MUST still enforce `(maker, nonce)` uniqueness. They MAY be otherwise stateless (no on-chain intent storage required), apart from nonce tracking.

## Intent ID Computation

This ERC uses two distinct hash values that align with [EIP-712](./eip-712.md) terminology:

- **`intentStructHash`**: The EIP-712 struct hash of the Intent, independent of the domain:

```
intentStructHash = keccak256(abi.encode(
    INTENT_TYPEHASH,
    intent.maker, intent.inputToken, intent.inputAmountMax,
    intent.outputToken, intent.outputAmountMin, intent.receiver,
    intent.validAfter, intent.validUntil, intent.nonce,
    intent.constraintsHash, intent.feeBps, intent.salt, intent.agentIdentity
))
```

The canonical EIP-712 type string is:

```
INTENT_TYPEHASH = keccak256(
    "Intent(address maker,address inputToken,uint256 inputAmountMax,"
    "address outputToken,uint256 outputAmountMin,address receiver,"
    "uint48 validAfter,uint48 validUntil,uint256 nonce,"
    "bytes32 constraintsHash,uint256 feeBps,bytes32 salt,address agentIdentity)"
)
```

The field order in the type string MUST match the `abi.encode` encoding order above.

- **`intentDigest`**: The EIP-712 typed-data digest, which binds the struct to a specific domain (chain + hub):

```
intentDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, intentStructHash))
```

**`intentId` MUST equal `intentStructHash`.** Using the struct hash makes `intentId` portable across domains (useful for Profile B off-chain relay), while replay protection is enforced separately by domain-bound signature verification on `intentDigest`. `intentId` is an indexing and correlation primitive — authorization is enforced by verifying `intentDigest`, not `intentId`.

### Domain Binding

The EIP-712 domain separator MUST include `verifyingContract`. It is RECOMMENDED that `verifyingContract` be set to the target IntentHub address. This prevents cross-hub replay attacks at the cost of making intents non-portable across hub deployments.

**Rationale**: Binding intents to a specific hub via `intentDigest` prioritizes safety over portability. An intent signed for Hub A cannot be replayed on Hub B even if `intentId` (the struct hash) is the same. If portability across hubs is required, makers MUST sign separate intents per hub OR employ an adapter that introduces a unique domain separator to prevent replay. Implementations targeting multi-hub ecosystems MAY define adapter mechanisms, but cross-hub portability introduces replay risks that MUST be explicitly mitigated.

## IntentHub Interface

Contracts compliant with this ERC MUST implement `IIntentHub`. Implementations MAY additionally implement `IIntentHubOffchain` (Profile B) and/or `IIntentHubReceipts`.

### Required: IIntentHub

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IIntentHub is IERC165 {

    /// @notice Emitted when an intent is submitted on-chain (Profile A).
    event IntentSubmitted(bytes32 indexed intentId, address indexed maker);

    /// @notice Emitted when a maker cancels an intent.
    event IntentCancelled(bytes32 indexed intentId);

    /// @notice Emitted upon successful fulfillment with structured receipt data.
    /// @dev maker is the accountable principal (signer of the intent); receiver is the payout address. They MAY differ.
    /// @dev fulfiller is indexed for workflow attribution. receiver is not indexed because it can
    ///      be filtered off-chain from non-indexed fields; prioritising maker and fulfiller
    ///      maximises ergonomics for wallet and solver analytics.
    /// @dev feeRecipient defaults to msg.sender if not specified via constraint module semantics.
    /// @dev executorAgent MAY be address(0) if the executor is unknown or undeclared.
    event IntentFulfilled(
        bytes32 indexed intentId,
        address indexed maker,
        address indexed fulfiller,
        address receiver,
        address inputToken,
        uint256 inputAmountUsed,
        address outputToken,
        uint256 outputAmountNet,
        uint256 feeAmount,
        address feeRecipient,
        address executorAgent
    );

    /// @notice Submit an intent and signature on-chain.
    function submitIntent(
        Intent calldata intent,
        bytes calldata signature
    ) external returns (bytes32 intentId);

    /// @notice Cancel a previously submitted intent. Only callable by the maker.
    /// @dev MUST mark (maker, nonce) as used, preventing any future fulfillment
    ///      of any intent sharing that (maker, nonce) pair, regardless of other fields.
    function cancelIntent(bytes32 intentId) external;

    /// @notice Fulfill a registered intent by intentId.
    function fulfill(
        bytes32 intentId,
        bytes calldata executionData
    ) external returns (uint256 outputAmountNet);

    /// @notice Returns the EIP-712 domain separator currently used for intentDigest verification.
    /// @dev MUST reflect the domain separator in active use. If the hub's chainId or domain
    ///      parameters change (e.g., after an upgrade), this MUST return the updated value.
    ///      Hubs that cannot guarantee domain stability MUST NOT allow domain changes after
    ///      deployment without invalidating all outstanding intents.
    function domainSeparator() external view returns (bytes32);
}
```

### Optional: IIntentHubOffchain (Profile B)

Implementations supporting Profile B MUST implement this interface.

```solidity
interface IIntentHubOffchain is IERC165 {

    /// @notice Fulfill an unregistered intent by providing intent + signature inline.
    function fulfill(
        Intent calldata intent,
        bytes calldata signature,
        bytes calldata executionData
    ) external returns (uint256 outputAmountNet);
}
```

### Optional: IIntentHubReceipts

Implementations supporting on-chain receipt queries MUST implement this interface.

```solidity
interface IIntentHubReceipts is IERC165 {

    /// @notice Query the settlement receipt for a fulfilled intent.
    function getReceipt(
        bytes32 intentId
    ) external view returns (SettlementReceipt memory);
}
```

### Settlement Receipt Structure

```solidity
struct SettlementReceipt {
    address fulfiller;
    address receiver;
    address inputToken;
    uint256 inputAmountUsed;
    address outputToken;
    uint256 outputAmountGross;  // total output before fees
    uint256 outputAmountNet;    // delivered to receiver = outputAmountGross - feeAmount
    uint256 feeAmount;          // floor(outputAmountGross * feeBps / 10_000)
    address feeRecipient;
    address executorAgent;
    uint256 settledAt;          // block.timestamp of settlement
    bytes32 executionHash;      // OPTIONAL: keccak256(executionData), for correlation only
}
```

`executionHash` is OPTIONAL. When provided, it MUST be computed as `keccak256(executionData)`. It is intended solely for traceability and correlation — it does NOT provide privacy guarantees, as `executionData` is typically visible in calldata.

`executorAgent` is an OPTIONAL attribution field. It is self-declared by the fulfiller and carries no on-chain authentication guarantee unless validated by an external registry (e.g., [ERC-8004](./eip-8004.md)). `executorAgent` MAY be `address(0)` if the executor is unknown or undeclared; implementations MAY default it to `agentIdentity` from the intent when no override is provided. Consumers SHOULD NOT rely on `executorAgent` for access control or trust decisions without independent verification.

`feeRecipient`: A constraint module MAY specify `feeRecipient` via its constraint semantics. If not overridden, `feeRecipient` MUST default to `msg.sender` (the fulfiller). There is no `feeRecipient` field in the core intent envelope.

### ERC-165 Interface Detection

Compliant implementations MUST implement [ERC-165](./eip-165.md) interface detection.

- `supportsInterface(bytes4 interfaceId)` MUST return `true` for `0x01ffc9a7` (IERC165).
- `supportsInterface(bytes4 interfaceId)` MUST return `true` for the interface id of `IIntentHub`.
- Implementations supporting Profile B MUST return `true` for the interface id of `IIntentHubOffchain`; claiming Profile B support without this signal is non-compliant.
- Implementations supporting receipt queries MUST return `true` for the interface id of `IIntentHubReceipts`.
- Implementations SHOULD compute interface ids using `type(IIntentHub).interfaceId`, `type(IIntentHubOffchain).interfaceId`, and `type(IIntentHubReceipts).interfaceId` respectively.
- Interface ids MUST remain stable across upgrades; introducing breaking changes to these interfaces requires a new ERC.

## Settlement Rules

During `fulfill` execution, implementations MUST:

1. Verify signature correctness by validating the signer over `intentDigest` (computed using this IntentHub's EIP-712 `domainSeparator`), supporting both ECDSA and [EIP-1271](./eip-1271.md). For both profiles, this verification MUST use the hub's `domainSeparator` even though `intentId` is `intentStructHash`. If `isValidSignature` reverts, the hub MUST treat the signature as invalid and revert.
2. Verify time window validity (`validAfter` ≤ `block.timestamp` ≤ `validUntil`).
3. Ensure nonce has not been used. Implementations MUST enforce uniqueness per `(maker, nonce)` globally within the hub, regardless of which profile is used. Tracking `fulfilled[intentId]` is OPTIONAL (useful for quick receipt lookups) but MUST NOT substitute for `(maker, nonce)` uniqueness enforcement — two intents sharing the same `(maker, nonce)` but differing only in `salt` or `constraintsHash` would each have distinct `intentId`s, so `fulfilled[intentId]` alone is insufficient.
4. Ensure intent is neither cancelled nor already fulfilled. If `constraintsHash == bytes32(0)`, constraint module validation MUST be skipped (see Constraint Discoverability in Optional Modules).
5. Ensure the total input transferred from the maker does not exceed `inputAmountMax`.
6. Ensure receiver obtains at least `outputAmountMin` as `outputAmountNet` (see Fee Accounting).
7. Execute settlement atomically (all-or-nothing within a single transaction).
8. Transfer `feeAmount` to the fee recipient. If not specified by a constraint module, `feeRecipient` MUST default to `msg.sender` (the fulfiller).
9. Emit the `IntentFulfilled` event with all receipt fields.

If any condition fails, the transaction MUST revert.

## Execution Semantics

Execution paths are intentionally NOT standardized.

`executionData` MAY encode arbitrary routing logic including:

- DEX aggregation
- Bridging
- Lending operations
- Multi-call execution

Additional operations MAY be executed atomically within settlement, but implementations MUST preserve settlement safety guarantees.

## Optional Modules

**Signature-Based Authorization**

Implementations MAY support signature-based token authorization mechanisms (e.g., permit-style approvals) to reduce interaction overhead prior to fulfillment.

**Commit–Reveal Mode**

Implementations MAY support a commit–reveal mechanism:

```
commitIntent(bytes32 commitHash)
revealIntent(Intent intent, bytes signature, bytes32 salt)
```

This mode MAY mitigate information leakage and front-running risks in competitive solver environments.

**Bond Requirement**

Implementations MAY require fulfillers to stake collateral or provide bonded guarantees to reduce spam, malicious execution, or settlement griefing.

**Incremental Fulfillment**

Implementations MAY allow incremental (partial) fulfillment across multiple transactions. If supported, implementations MUST define:

- Whether `nonce` is consumed at the first partial fill or upon full completion.
- Whether `outputAmountMin` is enforced per partial fill or cumulatively across all fills.
- How receipt events represent partial vs. complete settlement.

Incremental fulfillment adds significant complexity and is NOT part of the core specification. Implementations supporting it SHOULD document their partial-fill semantics explicitly.

**Constraint Discoverability and Enforcement**

Core compliance enforces the core settlement properties declared in Settlement Rules (signature, time, nonce, cancellation/fulfillment status, input max, output min, fee). `constraintsHash` is NOT enforced by the hub unless the hub supports a constraint module mechanism.

Implementations SHOULD support a discoverable mechanism for solvers to resolve `constraintsHash` to interpretable constraint rules. The RECOMMENDED encoding is `abi.encode(bytes4 constraintsType, bytes constraintsData)` where `constraintsType` identifies a published spec.

Implementations MAY support on-chain enforcement via an optional constraint module interface. If supported, the hub MUST follow this order for every `fulfill` with a registered constraint module:

1. Verify signature, time, and nonce status (steps 1–3 of Settlement Rules).
2. Resolve the module via `IConstraintRegistry.resolve(constraintsHash)`.
3. Call `module.validate(intent, executionData)` — MUST occur before any `transferFrom(maker, …)` or external call that could move maker funds.
4. Mark `(maker, nonce)` as used (e.g., `nonceUsed[maker][nonce] = true`). Implementations MAY additionally record `fulfilled[intentId] = true` for receipt lookup convenience. Both MUST be set before any external calls in step 5.
5. Execute transfers and external calls.

The hub MUST revert if `validate` reverts. The hub MUST obtain `constraintsData` from the registry; the intent does not carry `constraintsData` inline. If `constraintsHash == bytes32(0)`, the hub MUST skip steps 2–3. Equivalently, if `resolve(constraintsHash)` returns `module == address(0)`, the hub MUST treat this as "no constraint module" and skip validation.

The hub SHOULD be aware that `validate()` MAY make external calls and could be re-entrant. Implementations SHOULD either restrict accepted modules to a trusted allowlist (e.g., governance-controlled registry, immutable allowlist, or deploy-time configuration), or apply standard reentrancy protections (e.g., checks-effects-interactions pattern) around the validate call. Hubs SHOULD also guard against gas-grief attacks from unbounded `validate()` execution — e.g., by calling the module via `staticcall` with an explicit gas limit, or by requiring modules to declare a bounded gas usage.

```solidity
interface IConstraintModule {
    /// @notice Validate that executionData satisfies the intent's additional constraints.
    /// @dev MUST revert with a descriptive reason if constraints are not satisfied.
    /// @dev MUST be a view function — MUST NOT mutate state.
    /// @dev Modules SHOULD avoid relying on secrets embedded in executionData;
    ///      commit–reveal is recommended when secrecy matters.
    function validate(
        Intent calldata intent,
        bytes calldata executionData
    ) external view;
}

interface IConstraintRegistry {
    /// @notice Publish a constraints preimage for discoverability.
    /// @dev Anyone MAY call this; the registry stores (constraintsType, constraintsData,
    ///      module) keyed by keccak256(abi.encode(constraintsType, constraintsData)).
    /// @dev Registry entries SHOULD be immutable once published for a given constraintsHash.
    ///      Mutable registries MUST clearly document the upgrade/swap policy and associated
    ///      replay/DoS implications; makers MUST be aware that a module swap after signing
    ///      could alter constraint semantics without a new signature. Registries SHOULD reject
    ///      registrations where `module == address(0)`.
    function publishConstraints(
        bytes4 constraintsType,
        bytes calldata constraintsData,
        address module
    ) external returns (bytes32 constraintsHash);

    /// @notice Resolve a constraintsHash to its module, raw data, and type identifier.
    function resolve(bytes32 constraintsHash)
        external view
        returns (address module, bytes memory data, bytes4 typeId);
}
```

Constraint modules and registries are OPTIONAL and not required for base compliance. Implementations providing a registry SHOULD advertise support via ERC-165 interface detection or an initialization event.

**ERC-8004 Compatibility**

If `agentIdentity` is provided, implementations MAY query [ERC-8004](./eip-8004.md) registries for reputation or validation status. This ERC does not require ERC-8004 but is designed to interoperate with it.

# Rationale

- Separating intent definition from execution enables competitive fulfillment markets while maintaining safety guarantees.

- The six-step workflow (Author → Sign → Distribute → Solve → Execute → Verify & Record) provides a complete lifecycle that agents can implement uniformly, regardless of the solver infrastructure or execution environment.

- Structured settlement receipts close the workflow loop: agents can verify outcomes, attribute execution to specific fulfillers, and store structured results without parsing transaction traces.

- Two submission profiles (A and B) accommodate both on-chain-first architectures and off-chain solver markets without mandating a single distribution model.

- This ERC complements [EIP-7521](./eip-7521.md) by standardizing on-chain intent settlement semantics and atomic execution guarantees, while EIP-7521 focuses on generalized intent expression formats.

- The design avoids introducing new transaction types, allowing deployment without protocol upgrades.

- ERC-165 is used for capability discovery (Profile B, receipt queries) rather than static assumptions about function existence, enabling safe and composable hub detection across heterogeneous deployments and avoids brittle selector probing patterns.

- Execution routing remains intentionally unspecified to preserve composability, extensibility, and innovation across different solver and agent implementations.

# Interoperability & Adoption

This ERC is designed as a shared interface layer between agent runtimes, solver networks, and settlement infrastructure.

**Wallets and agents** need only know how to construct and sign the intent envelope (EIP-712) and how to read structured receipt events to verify completion.

**Solvers** compete permissionlessly. They need only produce valid `executionData` that satisfies an intent's constraints. No integration with other solvers is required.

**IntentHub** provides a uniform settlement surface. By implementing this interface, any hub becomes accessible to any compliant agent or solver.

## Workflow Examples

### Example 1: Agent rebalances portfolio across DEXs

1. **Author**: An agent detects portfolio drift and constructs an intent to swap 1,000 USDC for at least 0.5 ETH.
2. **Sign**: The user's smart contract wallet signs via EIP-1271.
3. **Distribute**: Intent is submitted on-chain (Profile A).
4. **Solve**: Multiple solvers compute routes across Uniswap, Curve, and Balancer.
5. **Execute**: The winning solver calls `fulfill` with optimal routing in `executionData`.
6. **Verify & Record**: The agent reads the `IntentFulfilled` event, confirms 0.52 ETH received, and records the outcome.

### Example 2: Agent executes bridge + swap + repay atomically

1. **Author**: An agent constructs an intent to bridge USDC from L2 to mainnet, swap to DAI, and repay an Aave loan — expressed as a single intent with constraints.
2. **Sign**: EOA signature via EIP-712.
3. **Distribute**: Intent relayed off-chain to specialized cross-protocol solvers (Profile B).
4. **Solve**: A solver constructs a multi-call execution plan encoding bridge, swap, and repay steps.
5. **Execute**: The solver calls `fulfill(intent, signature, executionData)` on the IntentHub.
6. **Verify & Record**: Receipt confirms input spent and loan repayment, closing the workflow.

# Backwards Compatibility

This ERC introduces no consensus changes and remains fully compatible with existing Ethereum transactions and smart contracts.

This ERC defines a new interface. Existing intent hub implementations are not expected to be compatible without modification. Implementations targeting backwards compatibility with pre-existing systems MAY implement adapter contracts that translate between legacy interfaces and this standard.

Implementations MAY support legacy event formats for transitional purposes but MUST emit the `IntentFulfilled` event with all receipt fields specified in this standard when claiming compliance.

# Security Considerations

Security analysis is organized by workflow phase to map threats to their point of origin and corresponding mitigations.

## Authoring and Signing

- **Delegation abuse**: A malicious authoring agent may construct intents that do not reflect the Principal's goals. The `agentIdentity` field provides attribution, enabling post-hoc audit and accountability. Implementations MAY integrate with [ERC-8004](./eip-8004.md) reputation systems for pre-execution agent validation.
- **Signature safety**: [EIP-712](./eip-712.md) structured data signing ensures the maker can inspect intent parameters before signing. Domain binding (`chainId` + `verifyingContract`) prevents cross-chain and cross-hub replay. [EIP-1271](./eip-1271.md) support enables contract wallets to enforce additional authorization policies.

## Distribution

- **Front-running**: Publicly distributed intents may be observed and exploited by MEV searchers. Implementations MAY support commit–reveal mechanisms to mitigate information leakage.
- **Time bounds**: `validAfter` and `validUntil` limit the exposure window for distributed intents.

## Solving

- **Misleading execution plans**: A solver may construct `executionData` that technically satisfies constraints but extracts value (e.g., via sandwich attacks within the execution). The `outputAmountMin` enforcement provides a hard floor, and the `inputAmountMax` provides a hard ceiling, but solvers may still extract surplus between these bounds.
- **Constraint enforcement**: `constraintsHash` enables additional policy checks beyond the core bounds. Implementations SHOULD make constraint semantics discoverable to solvers.

## Execution

- **Malicious fulfiller**: A fulfiller may attempt griefing (reverting after partial execution) or fund extraction. Atomic settlement ensures all-or-nothing execution. Bond requirements (optional) MAY further disincentivize malicious behavior.
- **Nonce tracking**: MUST be enforced per maker to prevent replay attacks. Implementations MUST ensure that a nonce cannot be reused even across Profiles A and B.
- **Fee extraction**: `feeBps` MUST be enforced to not exceed the declared value. Implementations SHOULD ensure that fee logic cannot be manipulated to drain maker funds beyond declared parameters.

## Verification

- **Receipt integrity**: `IntentFulfilled` events MUST accurately reflect the settlement outcome. Receipt fields (`inputAmountUsed`, `outputAmountNet`, `feeAmount`) MUST correspond to actual token transfers executed during settlement and follow the Fee Accounting definitions.
- **Deterministic Intent ID**: The `intentId` computation MUST be deterministic to enable off-chain verification and prevent ambiguity in receipt correlation.
- **executionHash correlation**: When provided, `executionHash` is for traceability only and does NOT provide privacy guarantees. Agents and monitoring systems SHOULD NOT rely on `executionHash` for confidentiality.

# Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
