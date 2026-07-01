---
eip: XXXX
title: Notary-Backed Confidential Token
description: A confidential token interface using private state commitments, with state transitions pre-validated by a notary or notary group.
author: Andrew Richardson (@awrichar) <andrew.richardson@kaleido.io>, Peter Broadhurst (@peterbroadhurst) <peter.broadhurst@kaleido.io>, Jim Zhang (@jimthematrix) <jim.zhang@kaleido.io>
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2026-06-26
---

## Abstract

This standard defines a confidential token interface in which private token state transitions are validated under the authority of a designated notary address. The notary address may represent a single authority, a group, or a smart contract submission gate with programmable validation logic. The notary pre-validates and authorizes transitions off-chain, including by verifying ownership, amounts, conservation of value, and transfer policy.

The contract records submitted transitions, each of which consumes zero or more opaque input identifiers and produces zero or more opaque output commitments. The contract prevents reuse of consumed inputs and forms the authoritative sequence of transitions without exposing private token state. Parties with the relevant private data can verify the corresponding private transaction history.

By separating private validation from public transition recording, this interface supports gas-efficient confidential token transfers, provides a standard integration point for token-aware systems and settlement protocols, and allows implementations to define their own validation logic, commitment schemes, and enforcement models.

## Motivation

Many token systems already depend on a trusted validation role, such as an issuer, custodian, regulated transfer agent, or privacy-preserving execution environment. For these systems, confidentiality means keeping ownership, amounts, and policy-sensitive transaction details off-chain and visible only to selected parties, while relying on the public ledger for global ordering, double-spend protection, and an immutable, auditable history.

This standard defines a minimal interface for confidential tokens built around this trusted validation model. Private validation can remain implementation-specific, allowing a notary or notary group to enforce appropriate conditions with mechanisms suited to the deployment, including programmable validation logic and public or private EVM environments. The token contract exposes a public transition surface by recording opaque input identifiers and output commitments and enforcing consumed-input uniqueness. This separation supports gas-efficient confidential transfers and gives token-aware systems and settlement protocols a consistent integration point without exposing private ownership, amounts, authorization data, or policy data through the token interface.

While existing confidential token designs commonly use cryptographic mechanisms to reduce or remove trust in off-chain parties, this model is geared toward systems where trusted validation is achievable, acceptable, or already required.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

A **UTXO** (unspent transaction output) is a discrete state created by a transaction and consumable by a later transaction. In value-bearing systems, a UTXO represents some amount of value held subject to an owner or spending condition.

A **private UTXO** is a UTXO whose amount, owner, spending condition, and other attributes are maintained off-chain and are not exposed through the token interface.

An **output commitment** is an opaque `bytes32` value that serves as a representation of a private UTXO. Output commitments are derived from private UTXO data and allow parties with that data to verify the corresponding on-chain representation.

An **input identifier** is an opaque `bytes32` value representing a private UTXO being consumed. Implementations define how input identifiers are constructed and how consumed inputs are tracked.

A **nullifier** is a type of input identifier used to record the consumption of a private UTXO without revealing the corresponding output commitment or linking the spend to that commitment. Nullifiers are derived from private UTXO data so that consuming a particular UTXO requires recording the corresponding nullifier.

### Overview

This standard defines a confidential token interface based on private UTXOs. State transitions consume existing private UTXOs and create new private UTXOs to record movement of value. The token interface exposes these transitions as opaque input identifiers and output commitments.

Transitions are authorized by a designated notary address, which may represent a single party, a group, a smart contract submission gate, or another implementation-specific validation process. The notary validates private UTXO data off-chain, including ownership, amounts, authorization, conservation of value, and any applicable transfer policy.

The token contract records the authoritative sequence of submitted transitions and prevents reuse of consumed private UTXOs. When paired with available private data, this sequence allows involved parties to verify the corresponding private transaction history.

### State Model

Implementations MUST define how output commitments are constructed. Output commitments SHOULD be collision-resistant derivations from private UTXO data, including the owner, amount, and a secret salt or nonce. Implementations SHOULD domain-separate commitments by token contract, chain identifier, and commitment scheme version. A party that receives private UTXO data MUST be able to verify that the corresponding output commitment was produced from that data. This standard assumes that private UTXO data is distributed to recipients, but does not define the mechanism for such distribution.

Implementations MUST define how input identifiers are constructed and how consumed inputs are tracked. Input identifiers SHOULD be nullifiers unless the implementation intentionally uses another consumed-input tracking model. Implementations MUST reject any transition that attempts to reuse an input identifier. Implementations MUST ensure that a private UTXO cannot be consumed more than once without reusing the same input identifier.

### State Transitions

A state transition MUST be authorized by the current notary address. Implementations MAY require `msg.sender` to be the notary address, or MAY allow another operator to submit the transition if notary authorization is validated according to implementation-specific rules.

A call to `transfer` or `mint` MUST revert unless the transition is authorized by the current notary address.

Calling `transfer`:

- MUST revert if any input identifier has already been consumed;
- MUST mark each input identifier as consumed;
- MUST record the output commitments; and
- MUST emit a `Transfer` event.

The emitted event MUST set `operator` to `msg.sender`.

Calling `mint`:

- MUST record the output commitments; and
- MUST emit a `Transfer` event.

The emitted event MUST set `operator` to `msg.sender`.

No separate burn function is defined. A burn is represented as a transfer whose private accounting destroys some or all of the consumed value. A burn MAY have an empty outputs array, or MAY create output commitments representing unburned remainder value.

The token contract is not required to verify ownership, amounts, authorization, conservation of value, transfer policy, or output commitment construction on-chain. These properties are pre-validated off-chain through the notary unless an implementation adds additional on-chain enforcement.

The `proof` parameter is opaque implementation-specific evidence associated with the transition. Implementations MAY use `proof` to carry participant authorization, notary authorization, root-transition evidence, or other validation data.

The `data` parameter is an opaque application-specific extension field, consistent with the general extensibility pattern described in [ERC-5750](./eip-5750.md).

Implementations MAY validate, store, emit, forward, or otherwise use `proof` and `data` according to their own rules.

### Events

The `Transfer` event MUST be emitted on every successful call to `transfer` or `mint`.

```solidity
event Transfer(
    bytes32 txId,
    address indexed operator,
    bytes32[] inputs,
    bytes32[] outputs,
    bytes proof,
    bytes data
);
```

- `txId`: A caller-provided transaction identifier.
- `operator`: The address that submitted the transition.
- `inputs`: The opaque input identifiers consumed by the transition. Empty for mints.
- `outputs`: The opaque output commitments produced by the transition.
- `proof`: Implementation-specific evidence associated with the transition.
- `data`: Application-specific metadata associated with the transition.

### Interface

Implementations MUST expose the following interface.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERCXXXX {
    event Transfer(
        bytes32 txId,
        address indexed operator,
        bytes32[] inputs,
        bytes32[] outputs,
        bytes proof,
        bytes data
    );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function notary() external view returns (address);

    function transfer(
        bytes32 txId,
        bytes32[] calldata inputs,
        bytes32[] calldata outputs,
        bytes calldata proof,
        bytes calldata data
    ) external;

    function mint(
        bytes32 txId,
        bytes32[] calldata outputs,
        bytes calldata proof,
        bytes calldata data
    ) external;
}
```

The `name`, `symbol`, and `decimals` functions provide token metadata. The `decimals` value describes the decimal precision used for private token amounts and does not affect on-chain behavior.

The `notary` function returns the address whose authority is required to authorize state transitions.

### Optional Query Extensions

Implementations SHOULD expose query functions appropriate to their state model.

Implementations using nullifier-based input tracking SHOULD expose:

```solidity
interface IERCXXXXNullifierQuery is IERCXXXX {
    function isNullified(bytes32 nullifier) external view returns (bool);
}
```

Implementations that explicitly track unspent output commitments SHOULD expose:

```solidity
interface IERCXXXXStateQuery is IERCXXXX {
    function isUnspent(bytes32 output) external view returns (bool);
}
```

## Rationale

### Notary-Backed Validation

Many token ecosystems already depend on a trusted validation role. This standard makes that role explicit and uses it as a primary enabler for efficient, confidential token operations.

The notary address represents the authority for validating private state transitions. This validation can include ownership, amounts, participant authorization, conservation of value, transfer policy, and private data distribution. The token contract is responsible for recording submitted transitions and enforcing the public invariants defined by the implementation's state model, such as preventing reuse of consumed inputs. Additional invariants may be enforced on-chain by specific implementations.

Representing the notary as a single address keeps the token interface minimal while allowing different validation arrangements. The address may be an externally owned account, multisig, threshold signature address, smart contract, or other mechanism that represents a notary group or programmable policy process. A smart contract notary can gate submission using implementation-specific validation logic, including signature checks, quorum rules, compliance controls, and policy execution in public or private EVM environments, without changing the token interface.

In the simplest model, the notary address submits each transition directly and the contract checks `msg.sender`. Implementations may instead allow another operator to submit a transition when `proof` contains sufficient notary authorization, but such implementations must properly validate that authorization and account for replay, stale proofs, and sequencing risks.

### Private UTXO Model

A UTXO model fits confidential tokens because value can move by consuming and creating private states rather than updating visible account balances. UTXO metadata, including owners, amounts, and policy-relevant attributes, can remain off-chain while the token contract records only opaque input identifiers and output commitments.

Output commitments allow parties with private UTXO data to verify that their data corresponds to an on-chain representation. Input identifiers allow the contract to record consumption of private UTXOs without requiring the contract to know the private state being consumed. When paired with available private data, the on-chain sequence of submitted transitions can support verification, audit, and dispute resolution.

### Minimal On-Chain Execution

The required on-chain work is intentionally limited to notary authorization, consumed-input tracking, output recording, and event emission. This supports gas-efficient confidential transfers without requiring on-chain verification of private transaction contents.

The exact gas cost depends on the implementation's state model, the number of inputs and outputs, and the size of the `proof` and `data` fields. Implementations that choose to add stronger public verification can do so at additional gas cost.

### On-Chain Enforcement Spectrum

The interface is designed to allow varying levels of on-chain enforcement without changing the common transition shape.

Implementations may enforce uniqueness of `txId` values to reject duplicate logical transitions. They may explicitly track unspent output commitments instead of using nullifiers, enabling public `isUnspent` queries at the cost of revealing more transaction-graph information. They may maintain commitment roots, root histories, or full commitment trees to anchor or verify the private state set. They may also validate aspects of the `proof` parameter on-chain, including signatures, Merkle proofs, zero-knowledge proofs, or other implementation-specific evidence.

These options are not required for conformance. They allow deployments to choose the appropriate balance among gas cost, confidentiality, auditability, and trust minimization.

### Separation of Concerns

This standard defines the confidential token transition interface rather than a generalized programmability or settlement layer. As with account-based token standards such as [ERC-20](./eip-20.md), applications can compose token operations with separately developed contracts and protocols on top of the minimal interface defined here.

In particular, atomic settlement and cross-contract coordination require protocols that can operate over prepared or authorized private transitions rather than visible balances and allowances. Implementations that require interoperable atomic settlement can compose this interface with [ERC-8316](./eip-8316.md).

## Backwards Compatibility

No backwards compatibility issues are introduced. This standard defines a new token interface and does not alter the behavior of existing token standards or deployed contracts.

This interface is not backwards compatible with any account-based token interface such as ERC-20, because balances, allowances, transfer amounts, and supply are not exposed through the token contract.

## Security Considerations

### Notary Trust Model

The notary is trusted to validate private transaction correctness off-chain. This includes ownership, amounts, authorization, conservation of value, transfer policy, output commitment construction, and distribution of private UTXO data.

The token contract does not verify these properties unless an implementation adds additional on-chain enforcement. The contract only enforces the public invariants defined by the implementation's state model, such as rejecting reuse of consumed input identifiers.

A malicious, compromised, unavailable, or incorrectly implemented notary may censor transactions, submit invalid transitions, create incorrect output commitments, withhold private data, violate policy rules, inflate or destroy private supply, or otherwise disrupt token operation. Deployments should choose a notary structure appropriate for their trust model and should document which correctness and availability properties are enforced by the notary, by the token contract, or by external audit and recovery processes.

### Data Availability

Private UTXO data must be available to the parties that need to verify, hold, or spend the corresponding outputs. If this data is lost or withheld, affected parties may be unable to verify ownership, construct future transitions, or participate in audits.

Implementations should define how private UTXO data is distributed, encrypted, retained, and recovered. Deployments should consider distributing data through redundant or independently operated channels.

### Commitment Construction

Output commitments should be collision-resistant and domain-separated. A commitment scheme should bind the private UTXO data to the token contract, chain identifier, and commitment scheme version, and should include a secret salt or nonce.

Weak commitment construction may allow collisions, replay across domains, incorrect attribution of private data, or ambiguity during audit and dispute resolution.

### Nullifier Construction

Implementations using nullifiers must ensure that a private UTXO cannot be consumed more than once without reusing the same nullifier. Nullifiers should be constructed so that parties without the relevant private UTXO data cannot link the nullifier to the corresponding output commitment.

Weak nullifier construction may allow double-spending, front-running, or linkage between private outputs and later spends.

### On-Chain Enforcement Limits

Additional on-chain enforcement can reduce reliance on the notary for selected properties, but may increase gas cost or reveal additional metadata. For example, explicit UTXO tracking can make output status publicly queryable, but may expose more of the transaction graph. On-chain proof verification can reduce trust in off-chain validation, but increases complexity and verification cost.

Implementations should document which properties are enforced on-chain and which remain dependent on the notary or off-chain validation process.

If an implementation allows submission of authorized transactions by parties other than the notary address, the contract must validate notary authorization from the submitted data. Such implementations should consider whether their state model requires additional on-chain enforcement, such as root histories, explicit UTXO tracking, Merkle proof verification, or transaction identifier deduplication, to prevent stale, replayed, or incorrectly sequenced transitions.

### Privacy Limits

This standard hides ownership, amounts, and private policy data from the token interface, but it does not hide all metadata. Observers may still learn timing, transaction frequency, input and output counts, operator identity, event data sizes, and any information included in `proof` or `data`.

Implementations should avoid placing sensitive information in `proof` or `data` unless it is encrypted or intentionally disclosed.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
