---
title: AA-Compatible Solver
description: A standard for AA-compatible Solver contracts that orchestrate existing account execution and authorization capabilities to support Intent-based execution without modifying existing smart wallets
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

The Solver SHOULD use transient storage, as defined by [EIP-1153](./eip-1153.md), when supported by the network, to avoid persistent state and reduce the cost of storing data that is only required during the current transaction.

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

```solidity
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

```solidity
struct UserEnvelopeTx {
    address sender;
    uint256 sliceInfo;
    bytes envelopeTx;
}
```

The `offset` and `length` values encoded in `sliceInfo` are `uint128` values and MUST satisfy:

```solidity
offset + length <= envelopeTx.length
```

The extracted slice MUST contain at least 20 bytes.

The Solver MUST interpret the first 20 bytes of the extracted slice as `executor` and the remaining bytes as `intent`. Thus, the extracted execution envelope is:

`executor || intent`

where `executor` is exactly 20 bytes.

The following is a reference implementation illustrating how a `UserEnvelopeTx` can be decoded into the conceptual `UserIntent` representation:

```solidity
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

#### Interface

A contract conforming to this standard MUST implement the following interface:

```solidity
interface ICompatibleSolver {
    enum Phase {
        INACTIVE,
        CONTEXT,
        VALIDATION,
        EXECUTION
    }

    struct UserEnvelopeTx {
        address sender;
        uint256 sliceInfo;
        bytes envelopeTx;
    }

    function resolve(
        UserEnvelopeTx[] calldata userEnvelopeTxs
    ) external;

    function senderCallback(
        bytes calldata intentInfo
    ) external;

    function context() external view returns (
        Phase phase,
        uint256 currentIndex,
        address initiator,
        bytes32[] memory executionHash,
        UserEnvelopeTx[] memory userEnvelopeTxs,
        bytes[] memory executorPreContext,
        bytes[] memory executorPostContext
    );
}
```

#### Behavior

A CompatibleSolver MUST only process a batch when `resolve()` is invoked. A Resolver SHOULD construct and order the `UserEnvelopeTx` batch according to the proposed Solution before invoking `resolve()`.

The `resolve()` function MUST execute the Context, Validation, and Execution phases described below. The complete batch MUST be processed atomically. Any failure during the Context, Validation, or Execution phase MUST revert the entire `resolve()` call and therefore revert all effects produced during the batch.

#### Context Phase

During the Context phase, the Solver MUST invoke each Executor using `STATICCALL`.

Consequently, the Executor and the entire downstream static-call tree MUST NOT perform state-changing operations during the Context phase.

The Solver itself is not subject to this restriction and MAY use state-changing operations to record or cache Context, including transient storage where supported by the execution environment.

The Context phase MUST complete before the Solver proceeds to the Validation phase.

#### Validation Phase

During the Validation phase, the Solver MUST invoke each Sender in batch order using the corresponding `envelopeTx`.

The Solver MUST revert if a Sender invocation reverts or if the execution envelope extracted from the `UserEnvelopeTx` is invalid.

During its invocation, the Sender MAY prepare the execution environment required by the Intent and MUST validate the execution envelope by invoking `senderCallback()` on the Solver as specified below.

The Sender MAY interleave the callback with other validation and environment-preparation operations. This standard does not impose an ordering between the callback and such operations.

#### Execution Phase

During the Execution phase, the Solver MUST invoke each Executor in batch order using the `intent` extracted from the corresponding execution envelope.

For each Executor invocation, the Solver MUST record the returned `executorPostContext`, except that the Solver MAY omit the post-context of the final Executor because no subsequent batch item can observe it.

The execution envelope used by the Executor MUST be the same execution envelope that was acknowledged by the Sender during the Validation phase.

A CompatibleSolver implementation MUST ensure that state belonging to a previous `resolve()` execution cannot be observed by a subsequent `resolve()` execution.

#### Envelope Transaction

This standard does not require existing wallets to be upgraded or replaced. Instead, it is designed to reuse the data encoding and execution mechanisms already supported by the Sender. Integrating a Solver therefore primarily requires constructing the transaction data used by the existing Sender such that it also satisfies the requirements of this standard.

A conforming `envelopeTx` MUST satisfy all of the following requirements:

1. It MUST be validly authorized and executable by the Sender.
2. It MUST be a Semi Tx.
3. It MUST contain a contiguous byte sequence from which the Solver can extract an execution envelope in the form `executor || intent`.
4. During its execution by the Sender, it MUST invoke `senderCallback()` on the Solver with `executor || intent` as the argument.

The Sender SHOULD propagate a revert from `senderCallback()` to its enclosing execution frame.

For security reasons, an `envelopeTx` SHOULD contain only one distinct execution-envelope slice when a slice is used as the execution envelope. An `envelopeTx` containing multiple identical execution-envelope slices SHOULD be considered by a separate standard.

The Sender receives the `envelopeTx` from the Solver during the Validation phase. During this invocation, the Sender MAY prepare the execution environment required by the Intent. For example, it MAY transfer tokens required for a subsequent swap to an address involved in the execution.

This standard does not require the Sender to invoke `senderCallback()` before or after its other validation and preparation operations. The Sender MAY interleave the callback with any number of validation or environment-preparation operations.

#### Callback and Execution-Envelope Validation

During the Validation phase, the Sender MUST invoke `senderCallback()` on the Solver.
The `senderCallback()` function MUST revert unless all of the following conditions are satisfied:

1. The Solver is currently processing a batch.
2. `msg.sender` is the Sender currently being invoked by the Solver during the Validation phase.
3. The `intentInfo` argument exactly matches the `executor || intent` execution envelope extracted from the `UserEnvelopeTx` currently being validated.
4. The callback has not already been successfully accepted for the current Sender invocation.

The Solver MUST associate the callback with the Sender that it is currently invoking. An implementation MAY establish this association by recording the expected Sender before invoking the Sender and comparing `msg.sender` against the recorded address when the callback is received.

The exact equality of `intentInfo` with the execution envelope is sufficient for the Solver to establish that the Sender has acknowledged the specific execution envelope that the Solver is authorized to execute.

This callback does not replace the Sender's own authorization mechanism. The Sender remains responsible for validating the `envelopeTx` according to its existing authorization and execution mechanism.

The Solver MUST ensure that at most one valid callback is accepted for each Sender invocation associated with each `UserEnvelopeTx`. Reentrant callback attempts that are reverted MUST NOT count as successful callbacks.

#### Context Retrieval

The standard provides access to Solver execution context through the `context()` function.

The `context()` function MUST return a tuple containing the following information:

| Type | Name | Description |
| --- | --- | --- |
| `Phase` | `phase` | The current phase of the Solver execution |
| `uint256` | `currentIndex` | The index of the `UserEnvelopeTx` currently being processed |
| `address` | `initiator` | The address that initiated the current `resolve()` call |
| `bytes32[]` | `executionHash` | The execution-envelope commitments for the batch. Each element is `keccak256(executor \|\| intent)` |
| `UserEnvelopeTx[]` | `UserEnvelopeTxs` | The complete `UserEnvelopeTx` batch supplied to the Solver for the current `resolve()` call |
| `bytes[]` | `executorPreContext` | Context collected from Executor invocations during the Context phase |
| `bytes[]` | `executorPostContext` | Context produced by Executor invocations during the Execution phase |

`currentIndex` is meaningful only while the Solver is processing a batch.

Each element of `executionHash` MUST be defined as:

`keccak256(executor || intent)`

The Solver MAY use these commitments to verify that the `intentInfo` supplied by a Sender through `senderCallback()` corresponds exactly to the execution envelope associated with the current `UserEnvelopeTx`.

The `executionHash` is a commitment used to verify the execution envelope acknowledged by the Sender. It does not replace or define the Sender's authorization mechanism.

The `Phase` values are defined as follows:

| Value | Phase | Description |
| --- | --- | --- |
| 0 | `INACTIVE` | The Solver is not currently processing a batch |
| 1 | `CONTEXT` | Executors are invoked to collect pre-execution context |
| 2 | `VALIDATION` | Senders are invoked to validate and acknowledge execution envelopes |
| 3 | `EXECUTION` | Executors are invoked to execute Intents |

Because the Context and Execution phases invoke the same Executor with the same `executor || intent` execution envelope, the Solver MUST expose sufficient execution context for an Executor to distinguish the current phase and select the corresponding execution path.

The `phase` field returned by `context()` provides this phase distinction.

The `initiator` MUST remain unchanged throughout the execution of `resolve()` and MUST equal the address that invoked `resolve()`.

The `initiator` identifies the caller of the current Solver execution and MUST NOT be changed by nested calls made during the execution of `resolve()`.

### Extensions

#### Blob

Some Intent designs may carry `UserEnvelopeTx` objects that are used only as supplemental execution data rather than representing an actual Sender. This standard can support such use cases indirectly by using a `UserEnvelopeTx` with an empty `intent`.

In this case, the `Sender` and `Executor` serve only technical roles for introducing the blob data into the Solver flow and do not necessarily represent entities that participate in the actual Intent execution.

An implementation MAY use one or two addresses for these roles. When two addresses are used, one address serves as `NO_OP_SENDER` and the other as `NO_OP_EXECUTOR`. The two roles MAY also be implemented by the same contract if that contract can satisfy both roles.

The Solver itself MAY be used for both roles:

```text
NO_OP_SENDER   = Solver
NO_OP_EXECUTOR = Solver
```

In this configuration, during the Validation phase the Solver can perform a self-call to `senderCallback()`:

```text
Solver -> Solver
```

instead of the following flow:

```text
Solver -> NO_OP_SENDER -> Solver
```

This requires only a minor implementation change to the Solver: the Solver MUST provide a no-op `fallback()` or equivalent execution path so that the self-call does not revert.

This does not change the execution flow or semantics defined by this standard. The `UserEnvelopeTx` is still processed through the same Context, Validation, and Execution phases.

For example, when the Solver is used as both `NO_OP_SENDER` and `NO_OP_EXECUTOR`, a `UserEnvelopeTx` carrying blob data MAY be constructed as follows:

```solidity
address immutable NO_OP_SENDER = address(this);
address immutable NO_OP_EXECUTOR = address(this);

uint256 sliceInfo = (36 << 128) | 20; // offset = 36, length = 20
bytes memory blob = anyBlob;

/*
    Calldata layout:

    0x00 -> 0x03: function selector
    0x04 -> 0x23: ABI offset
    0x24 -> 0x43: ABI length/data area containing NO_OP_EXECUTOR
    0x44 -> ... : blob
*/

bytes memory envelopeTx = bytes.concat(
    abi.encodeCall(
        ICompatibleSolver.senderCallback,
        (abi.encodePacked(NO_OP_EXECUTOR))
    ),
    blob
);

UserEnvelopeTx memory userBlob = UserEnvelopeTx({
    sender: NO_OP_SENDER,
    sliceInfo: sliceInfo,
    envelopeTx: envelopeTx
});
```

This approach may introduce additional execution overhead compared with passing blob data directly. Its benefit is that blob data can reuse the same `UserEnvelopeTx` processing flow without requiring a separate execution path in the Solver.

#### Delegator

A wallet may not be able to directly coordinate its execution with a Solver. Examples include EOAs without executable code and smart wallets that exclusively accept execution through a trusted Entry Point without providing an alternative entry point.

In such cases, a Delegator MAY be used to execute on behalf of the User and act as the Sender within the Solver flow.

This standard only describes the role and high-level interaction of a Delegator. It does not require Delegators to implement a particular interface. The concrete Delegator design SHOULD be defined by an Intent protocol or a separate standard.

For the purposes of this section, **Entry Point** refers to any trusted contract that serves as an execution entry point for a smart wallet. It does not necessarily refer to the ERC-4337 EntryPoint contract.

A Delegator as described in this standard MUST NOT be confused with an EIP-7702 delegation contract that supplies code for an EOA.

##### Restricted Wallets with a Trusted Entry Point Path

Some wallets have restricted access and only trust a particular Entry Point, while the Entry Point itself does not restrict which contracts may invoke it. In such a configuration, a Delegator MAY establish an execution path through the trusted Entry Point:

```text
Solver -> Delegator -> Entry Point -> Wallet -> Delegator -> Solver
```

The Wallet MUST be capable of invoking the Delegator as part of this execution path.

The Delegator SHOULD verify that the execution path between the Delegator and the Solver callback contains only the expected Entry Point and Wallet, as applicable to the implementation, and does not introduce an untrusted contract into the path.

The Delegator SHOULD cross-check the expected Entry Point and the Wallet that performs the callback. This design may require the Delegator to trust the Entry Point as part of its security model. This standard does not prescribe how such trust should be established or managed.

##### Restricted Wallets without a Trusted Entry Point Path

Some wallets cannot be reached through a Delegator via their trusted Entry Point. This includes EOAs without executable code and smart wallets that restrict access to a trusted Entry Point using conditions such as:

```solidity
msg.sender == tx.origin
```

A Delegator MAY instead collect and validate the wallet's authorization, such as a signature, and perform the execution on behalf of the wallet. Depending on the implementation, execution MAY occur directly on the Delegator or through an Executor.

This approach may provide the wallet with less access to auxiliary execution capabilities. For example, operations such as an ERC-20 `approve()` may require a separate execution path or may not be available through the Delegator.

Nevertheless, such a Delegator provides a mechanism for integrating wallets that cannot otherwise expose a compatible execution path to the Solver. The concrete authorization, delegation, and execution mechanism is outside the scope of this standard.

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
