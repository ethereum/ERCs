---
title: AA-Compatible Solver
description: A standard for AA-compatible Solver contracts that orchestrate existing account execution and authorization capabilities to support Intent-based execution without modifying existing smart wallets
author: Helkomine (@Helkomine)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2026-09-22
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

For the purposes of this section, **Entry Point** refers to any trusted contract that serves as an execution entry point for a smart wallet. It does not necessarily refer to the [ERC-4337]((./eip-4337.md)) EntryPoint contract.

A Delegator as described in this standard MUST NOT be confused with an [EIP-7702](./eip-7702.md) delegation contract that supplies code for an EOA.

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

### Why Use a Slice of `UserEnvelopeTx`

Slicing `UserEnvelopeTx` is intended to represent a minimal capability that can be supported by a broad range of existing wallets.

For example, a typical smart wallet may expose an `execute*` function that accepts one or more `bytes[]` arguments. Such byte arrays can contain a contiguous byte sequence from which a Solver can extract the execution envelope.

This provides the basis for the slicing approach used by this standard: the Solver does not require the wallet to understand the `UserIntent` structure. Instead, it extracts the `executor || intent` sequence from an existing wallet transaction envelope while preserving the wallet's existing execution and authorization mechanism.

### Why Must the Sender Perform a Callback

From the Sender's perspective, an `envelopeTx` can be viewed as a sequence of calls that the Sender is authorized to execute and for which it expects valid responses from the called contracts.

An implicit property of such execution is that the Sender generally calls only contracts that it considers authorized or trusted. For example, a Sender may execute a call to an ERC-20 contract to transfer a balance as part of an authorized operation.

The Solver therefore needs a mechanism by which the Sender can explicitly acknowledge that the execution envelope currently being processed is authorized by the Sender, without requiring the Sender to abandon or otherwise restructure its existing execution flow.

A callback provides such an acknowledgement while preserving compatibility with existing wallet execution mechanisms. The callback is performed as part of the Sender's existing execution flow rather than requiring a separate authorization transaction or a new authorization interface.

### Atomic Execution of a Batch of `UserEnvelopeTx`

This standard is intended to support existing wallets that satisfy the requirements described above. The Validation phase may therefore include operations that prepare the execution environment for the subsequent Execution phase.

Such preparation may be difficult to introduce through a separate authorization call, particularly for existing wallets whose execution interfaces cannot be extended. It is therefore important that preparation performed during Validation can be reverted if the corresponding execution does not complete successfully.

Otherwise, a failure in the Execution phase after successful Validation could leave persistent effects produced during Validation. This could result in an irreversible loss or other unintended state change for the User.

For this reason, the execution of a batch of `UserEnvelopeTx` is atomic. A failure in any Context, Validation, or Execution operation reverts the entire `resolve()` call and all state changes produced within that call.

Revert propagation provides an atomic failure signal that cannot be accidentally ignored while preserving the EVM's rollback semantics.

### Caching `UserEnvelopeTx`

The Solver caches the original `UserEnvelopeTx` batch so that Executors and related contracts can access the complete transaction envelopes without explicitly copying and forwarding the batch through each execution call.

This introduces an accounting trade-off compared with loading the original calldata into memory and passing only the required data directly to an Executor. Caching incurs the cost of writing and reading data from transient storage, whereas direct access can make use of calldata-to-memory copies.

When an Executor accesses the same data frequently, repeated transient-storage reads may cost more than loading the required data into memory once and reading it from memory. Conversely, caching may be preferable when the data is accessed infrequently but a uniform context-access interface is desirable across different Executors and related contracts.

The caching mechanism also preserves the original raw envelope. This allows Executors to remain compatible with existing wallet calldata formats without requiring the Solver to reinterpret or reconstruct wallet-specific transaction encodings.

Implementations MAY expose additional getter functions for querying individual pieces of execution context. Such getters can avoid the cost of returning and ABI-decoding the complete `UserEnvelopeTx` batch through `context()` when a caller requires only a subset of the available context.

### The Data Returned by `context()`

The `context()` function provides a generic interface through which any caller can access the complete execution context required by the standard without requiring authorization.

This is intended to provide a common context-access mechanism across different Executors and related contracts, while allowing implementations to expose more specialized getters where appropriate.

`currentIndex` explicitly identifies the `UserEnvelopeTx` currently being processed. This avoids requiring Executors or related contracts to infer the active execution from the contents of the batch and provides an explicit reference to the execution whose context is currently being observed.

`currentIndex` may also be useful for execution logic or auxiliary proofs whose validity depends on the currently active batch item.

### Why Use `STATICCALL` During the Context Phase

The Context phase is intended to provide Executors with a snapshot of the state preceding Validation and Execution. An Executor may use this information to establish assertions about the state in which an Intent is subsequently executed. For example, a wallet may use pre-context information to verify whether a balance delta satisfies a condition imposed by the Intent.

If an Executor were permitted to modify state during the Context phase, the context collection itself could change the state before Validation begins. In that case, the resulting pre-context would no longer represent the state against which the Intent was initially evaluated.

The Context phase therefore uses `STATICCALL` to prevent state-changing operations in the Executor call tree. This provides a simple EVM-level mechanism for limiting side effects and ensuring that context collection does not modify state before Validation.

### Why Does the Standard Not Support Additional Advanced Configurations

An important property of this standard is that it does not require a global trust relationship between Senders and Solvers. A Sender may choose whether to authorize a particular Solver for a given execution, after which the Solver session terminates when `resolve()` completes.

Consequently, the standard does not need to serve as a universal execution entry point incorporating every possible advanced feature or trust model. Keeping the core abstraction small allows implementations to be deployed without requiring substantial changes to established wallet infrastructure.

Additional functionality can instead be introduced through separate extensions or standards that build on compatible abstractions. This also reduces the need for existing wallets to migrate their established execution infrastructure when new functionality is introduced.

## Backward Compatibility

This standard is designed to be compatible with existing execution protocols and wallets deployed on those protocols.

Integrating a Solver does not require an existing wallet to understand or directly implement the `UserIntent` structure. Instead, the Solver uses `UserEnvelopeTx` to leverage the execution and authorization capabilities already exposed by the Sender.

The standard encourages extensions through proposals that share compatible goals or abstractions. Such extensions are not required to be fully compatible with the specific design or execution flow defined by this standard.

## Test Cases

Three example transactions were tested on the Sepolia test network using a Safe wallet. All three transactions executed successfully.

These tests were performed using an earlier version of the implementation under the name `UniversalSolver`. Equivalent tests using the current contract name are planned separately.

### Tx1 — Two-Party Token Swap

[Tenderly Transaction 1](https://dashboard.tenderly.co/tx/0x5a457e36d507e95f60b51435479e6be644137f3e8d412020890673bcee630071?action=)

### Tx2 — Three-Party Token Swap

[Tenderly Transaction 2](https://dashboard.tenderly.co/tx/0xd2ae06a5b203dac7724f0f454faa63e7d5f6a74cc0968829537daa289b8c57ea?action=)

### Tx3 — POL-to-ETH Swap Order

[Tenderly Transaction 3](https://dashboard.tenderly.co/tx/0x8777be765b1fe1f694c830d7a95fb52b4147ae17784c956d69bf3b254c9859f7?action=)

## Reference Implementation

A reference implementation is available at: `https://github.com/Helkomine/ERCs/tree/erc-draft/assets/erc-0`

## Security Considerations

### Error Simulation Notifications in User Interfaces

Because this standard requires `envelopeTx` to be a Semi Tx, execution of an `envelopeTx` outside the intended Solver execution flow may revert. Wallet interfaces and other transaction simulation infrastructure may therefore report the transaction as failed during simulation.

This behavior is a consequence of the Semi Tx design and does not necessarily indicate that the corresponding Solver execution will fail.

Handling such simulation results is primarily an infrastructure and user-interface concern. It does not require the on-chain execution flow defined by this standard to be modified.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
