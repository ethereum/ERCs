---
title: AA-Compatible Solver
description: <Description is one full (short) sentence>
author: Helkomine (@Helkomine)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
---

## Abstract

This standard defines a stateless Solver contract interface and execution flow for coordinating Intent execution with existing smart wallets.

A Solver does not extend the capabilities of an account. Instead, it orchestrates the execution and authorization capabilities that the account already provides. Integrating a Solver therefore does not require existing wallets to understand or directly implement a new `UserIntent` structure, nor does it require wallets or other contracts to be upgraded, replaced, pre-registered, or explicitly trusted by the Solver.

A smart wallet is Solver-compatible when its existing execution and authorization capabilities satisfy the requirements defined for a Sender by this standard. The set of Intents that can be supported is consequently determined by the capabilities exposed by the account, rather than requiring the account to be modified for each new Intent standard.

## Motivation

Intent-based execution commonly separates the party that specifies a desired outcome from the party that determines and submits the execution required to achieve that outcome. This separation allows a Resolver to construct a Solution for a User without requiring the User to specify the complete execution path in advance.

Existing smart wallets, however, generally expose their own execution and authorization interfaces. Requiring each wallet to adopt a common Intent-specific interface would introduce additional integration requirements and would limit the ability of existing wallets to participate in new Intent protocols without modification.

This standard addresses this problem by separating the Solver's coordination logic from the wallet's existing execution and authorization logic. The Solver does not need to understand the semantics of an Intent or replace the authorization mechanism of a Sender. Instead, it provides a common execution flow in which:

1. an Executor can obtain context required for execution;
2. a Sender can validate an execution envelope using its existing authorization and execution mechanism;
3. the Sender can explicitly acknowledge the exact execution envelope through a Solver callback; and
4. the Solver can execute the corresponding Intent through the committed Executor.

The `UserEnvelopeTx` structure preserves the transaction envelope understood by an existing Sender while allowing the Solver to extract the execution envelope `executor || intent` from it. This allows existing wallet execution paths to be reused without requiring the wallet to understand the higher-level `UserIntent` abstraction.

The standard also separates the Solver's coordination role from the semantics of individual Intents. An Executor is responsible for interpreting and executing its Intent, while the Solver only coordinates Context, Validation, and Execution. This allows different Intent protocols and execution mechanisms to use the same Solver flow without requiring the Solver to implement Intent-specific logic.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

- **Solver**: A contract implementing this standard. A Solver does not require persistent execution state between transactions. Its execution state for a `resolve()` call MAY be held in transient storage. A Solver is publicly deployable, and protocols MAY independently choose whether to trust or use a particular Solver deployment.
- **Semi Tx**: An envelope transaction whose execution by the Sender is intentionally incomplete unless it is executed through the Solver flow and successfully performs the required Solver callback.
- **User (Requester)**: The party that specifies an Intent requiring resolution.
- **Resolver**: The party that constructs and submits a Solution for a User's Intent.
- **Intent**: The User's desired execution or outcome to be resolved.
- **Solution**: The execution proposal constructed by a Resolver to resolve one or more Intents.
- **Sender**: The User's smart wallet or other account responsible for validating the Intent and acknowledging the execution envelope during the Validation phase.
- **Delegator**: A contract that executes on behalf of a User and MAY act as a Sender in the Solver flow.
- **Executor**: The address that identifies the execution logic responsible for interpreting and executing an Intent. The Executor therefore represents the execution scope to which the Intent is committed.
- **Initiator**: The address that initiates a `resolve()` call on the Solver.
- **Envelope Tx**: The transaction envelope submitted to a Sender or Delegator during the Validation phase. The Solver extracts an execution envelope from a specified contiguous slice of the `envelopeTx` and interprets that execution envelope as `executor || intent`.
- **Context**: Data collected before or during execution and retained by the Solver for use by an Executor.
- `||`: The byte concatenation operator.

### Execution Flow

#### Offchain

The Resolver SHOULD simulate the proposed Solution against the relevant state before submitting it to the Solver.

The Resolver then submits a transaction to the Solver containing the `UserEnvelopeTx` objects required to execute the Solution.

#### Onchain

The Solver MUST process each `UserEnvelopeTx` in the batch through the following three phases:

1. Context
2. Validation
3. Execution

The Solver MUST execute the complete batch atomically. Any failure during the Context, Validation, or Execution phase MUST revert the entire `resolve()` call.

#### Context Phase

During the Context phase, the Solver collects the context required by the Executors and stores the resulting data for subsequent execution.

The Solver SHOULD use transient storage, as defined by [EIP-1153], when supported by the network, to avoid persistent state and reduce the cost of storing data that is only required during the current transaction.

Each Executor MUST be invoked using `STATICCALL` during the Context phase. Consequently, the Executor and the entire downstream static-call tree MUST NOT perform state-changing operations during this phase.

The Context phase MUST complete before the Solver enters the Validation phase.

#### Validation Phase

During the Validation phase, the Solver invokes each Sender specified by the corresponding `UserEnvelopeTx` in batch order.

The Sender MUST validate the execution envelope using its existing authorization and execution mechanism and MUST successfully invoke the Solver's callback with the exact execution envelope associated with the current batch item.

The Solver MUST reject the batch if a Sender invocation reverts or if the required callback is not successfully acknowledged.

#### Execution Phase

During the Execution phase, the Solver invokes each Executor in batch order with the Intent extracted from the corresponding execution envelope.

The Executor is responsible for interpreting and executing the Intent. The Solver does not define or enforce the semantics of individual Intents.

The execution phase MUST use the same execution envelope that was acknowledged during the Validation phase.

#### Intent Structure

Conceptually, a User submits a `UserIntent` when expressing an Intent. The structure consists of the following fields:

| Type | Name | Description |
| --- | --- | --- |
| `address` | `sender` | Address responsible for validating the Intent |
| `address` | `executor` | Address to which execution of the committed Intent is assigned after successful Sender validation |
| `bytes` | `intent` | Execution payload of the Intent |

The conceptual Solidity representation is:

```
struct UserIntent {
    address sender;
    address executor;
    bytes intent;
}
```

`UserIntent` is a conceptual representation and does not require existing wallets to understand or implement this structure.

Instead, the User submits a backwards-compatible `UserEnvelopeTx` structure that preserves the transaction envelope understood by the Sender:

| Type | Name | Description |
| --- | --- | --- |
| `address` | `sender` | Address responsible for validating the Intent |
| `uint256` | `sliceInfo` | Packed representation of `offset` and `length`. The high 128 bits contain `offset` and the low 128 bits contain `length` |
| `bytes` | `envelopeTx` | Transaction payload submitted to the Sender. It MUST preserve the execution and authorization format expected by the Sender |

The Solidity representation is:

```
struct UserEnvelopeTx {
    address sender;
    uint256 sliceInfo;
    bytes envelopeTx;
}
```

The `offset` and `length` values encoded in `sliceInfo` are `uint128` values and MUST satisfy:

`offset + length <= envelopeTx.length`

The extracted slice MUST contain at least 20 bytes.

The Solver MUST interpret the first 20 bytes of the extracted slice as `executor` and the remaining bytes as `intent`. Thus, the extracted execution envelope is:

`executor || intent`

where `executor` is exactly 20 bytes.

The following is a reference implementation illustrating how a `UserEnvelopeTx` can be decoded into the conceptual `UserIntent` representation:

```
function getUserIntent(
    UserEnvelopeTx calldata userEnvelopeTx
) internal pure returns (UserIntent memory userIntent) {
    (uint256 offset, uint256 length) =
        _getOffsetAndLength(userEnvelopeTx.sliceInfo);

    (address executor, bytes calldata intent) =
        _decodeIntentInfo(
            _sliceEnvelopeTx(
                offset,
                length,
                userEnvelopeTx.envelopeTx
            )
        );

    return UserIntent({
        sender: userEnvelopeTx.sender,
        executor: executor,
        intent: intent
    });
}

function _decodeIntentInfo(
    bytes calldata intentInfo
) internal pure returns (
    address executor,
    bytes calldata intent
) {
    return (
        address(bytes20(intentInfo[0:20])),
        intentInfo[20:]
    );
}

function _sliceEnvelopeTx(
    uint256 offset,
    uint256 length,
    bytes calldata envelopeTx
) internal pure returns (
    bytes calldata intentInfo
) {
    return envelopeTx[offset:offset + length];
}

function _getOffsetAndLength(
    uint256 sliceInfo
) internal pure returns (
    uint256 offset,
    uint256 length
) {
    return (
        sliceInfo >> 128,
        sliceInfo & type(uint128).max
    );
}
```

This decoding method is provided as a reference implementation only. Implementations MAY use a different mechanism provided that they satisfy the normative requirements of this standard.

The mapping from `UserEnvelopeTx` to `UserIntent` is intentionally non-invertible. A `UserIntent` does not contain sufficient information to reconstruct the original `UserEnvelopeTx`, because the latter may contain additional transaction data required by the Sender's existing execution and authorization mechanism.

## Rationale

<!--
  The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

TBD

## Backwards Compatibility

<!--

  This section is optional.

  All EIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The EIP must explain how the author proposes to deal with these incompatibilities. EIP submissions without a sufficient backwards compatibility treatise may be rejected outright.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

No backward compatibility issues found.

## Test Cases

<!--
  This section is optional for non-Core EIPs.

  The Test Cases section should include expected input/output pairs, but may include a succinct set of executable tests. It should not include project build files. No new requirements may be introduced here (meaning an implementation following only the Specification section should pass all tests here.)
  If the test suite is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed

  TODO: Remove this comment before submitting
-->

## Reference Implementation

<!--
  This section is optional.

  The Reference Implementation section should include a minimal implementation that assists in understanding or implementing this specification. It should not include project build files. The reference implementation is not a replacement for the Specification section, and the proposal should still be understandable without it.
  If the reference implementation is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed.

  TODO: Remove this comment before submitting
-->

## Security Considerations

<!--
  All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life cycle of the proposal. For example, include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
