---
eip: 0
title: Flash Loan Proxy
description: A proxy for coordinating execution sessions using transiently cached programs and calldata, with configurable reentrant invocation dispatch
author: Helkomine (@Helkomine)
discussions-to: placeholder
status: Draft
type: Standards Track
category: ERC
created: 2026-11-5
---

## Abstract

This standard defines a proxy that coordinates execution sessions by temporarily caching a program and its associated calldata in transient storage. The proxy forwards the cached program to a fixed implementation through `DELEGATECALL` and uses a handler flag to control whether subsequent reentrant invocations are dispatched.

The program remains unchanged throughout an execution session, while the cached calldata is replaced on each accepted invocation. This enables a single implementation to coordinate callback-driven execution using different programs and calldata without deploying a new contract for each execution.

## Motivation

Many advanced execution strategies require dynamically changing execution logic, particularly when interacting with external contracts that invoke callbacks during execution.

Traditionally, dynamically changing the execution logic of a contract may require deploying a new contract containing the desired runtime code. This introduces deployment costs, including contract creation and code-deposit costs.

Flash Loan Proxy separates the execution program from the implementation responsible for interpreting it. Instead of deploying a new contract for each program, callers provide the program as calldata. The proxy temporarily caches the program and forwards it to an implementation that interprets and executes it.

This design provides several benefits:

- **Dynamic execution programs:** Different programs can be supplied for different execution sessions without deploying a new contract.
- **Callback coordination:** The proxy can dispatch reentrant invocations to the same implementation while preserving the program associated with the current session.
- **Reduced deployment overhead:** Programs are supplied as transaction data rather than deployed as contract code.
- **Flexible execution environments:** The implementation can interpret native EVM bytecode, EOF-related representations, or other program formats supported by its execution engine.
- **Larger programs:** The program size is not subject to the [EIP-170](./eip-170.md) deployed-contract code-size limit merely because it is supplied as calldata. It remains subject to transaction and block resource limits.

The proxy does not define a programming language, virtual machine, or execution semantics. These are determined by the implementation.

## Specification

### Overview

A Flash Loan Proxy MUST have a configured implementation address. The implementation is responsible for interpreting the program forwarded by the proxy and executing the corresponding logic.

The proxy MUST maintain the following transient storage values:

| Slot | Purpose |
|---|---|
| `HANDLER_SLOT` | Controls whether reentrant invocations are dispatched. |
| `DEPTH_SLOT` | Tracks the current invocation depth within an execution session. |
| `BYTECODE_SLOT` | Stores the program supplied at the beginning of the session. |
| `CALLDATA_SLOT` | Stores the calldata associated with the current accepted invocation. |

The slot identifiers MUST be fixed and consistently derived or otherwise defined by the implementation. ERC-7201-style identifiers MAY be used.

### Initial Invocation

When the proxy is invoked while `DEPTH_SLOT` is zero, it MUST begin a new execution session regardless of the current value of `HANDLER_SLOT`.

The initial calldata MUST be ABI-decoded as a tuple containing two dynamic byte arrays:

- `bytecode`: the program to be interpreted by the implementation.
- `data`: the initial calldata associated with the program.

The proxy MUST cache both values in transient storage under `BYTECODE_SLOT` and `CALLDATA_SLOT`, respectively.

The proxy MUST then set `DEPTH_SLOT` to one and invoke the configured implementation through `DELEGATECALL`, forwarding `bytecode` as the call data of that invocation.

The implementation MUST interpret the forwarded program and MAY read the cached calldata from `CALLDATA_SLOT`.

### Subsequent Invocations

When the proxy is invoked while `DEPTH_SLOT` is greater than zero, it MUST inspect `HANDLER_SLOT`.

If `HANDLER_SLOT` is zero, the proxy MUST skip the invocation and return successfully with empty returndata. The proxy MUST NOT modify the invocation depth or cached values in this case. If the invocation transfers ETH, the ETH transfer MUST still be accepted by the payable fallback, and the transferred ETH remains in the proxy's balance. The proxy does not automatically refund or forward the value.

If `HANDLER_SLOT` is nonzero, the proxy MUST:

1. Increment `DEPTH_SLOT`.
2. Replace the cached value at `CALLDATA_SLOT` with the complete `msg.data` of the current invocation.
3. Invoke the configured implementation through `DELEGATECALL`, forwarding the program stored in `BYTECODE_SLOT`.

The program stored in `BYTECODE_SLOT` MUST remain unchanged throughout the execution session, except for modifications caused by a violation of the implementation's storage-access requirements.

The proxy MUST NOT decode or interpret the calldata of subsequent invocations. Its interpretation is entirely delegated to the implementation.

### Handler Control

`HANDLER_SLOT` is a flag controlled by the implementation.

A value of zero indicates that reentrant invocations MUST be skipped. Any nonzero value indicates that reentrant invocations MUST be dispatched.

The implementation MAY change this value at any point during execution to enable or disable subsequent callback dispatch.

The proxy MUST NOT clear the handler flag before each reentrant invocation. It MUST clear the flag when the outermost invocation completes successfully.

The handler flag does not authenticate the caller. The implementation MUST perform any required caller authentication and callback validation.

If an invocation reverts, changes to transient storage MUST follow EVM revert semantics.

### Invocation Completion

Each accepted invocation MUST decrement `DEPTH_SLOT` exactly once after the implementation invocation has completed.

When the outermost invocation completes successfully, the proxy MUST clear `HANDLER_SLOT`, `BYTECODE_SLOT`, and `CALLDATA_SLOT`, and restore `DEPTH_SLOT` to zero.

The proxy MUST preserve the implementation's execution result:

- If the implementation succeeds, the proxy MUST return its returndata unchanged.
- If the implementation reverts, the proxy MUST revert with the implementation's revert data unchanged.

A skipped reentrant invocation MUST return successfully with empty returndata.

### Calldata Lifetime

`CALLDATA_SLOT` represents the calldata of the most recent accepted invocation. It MUST be overwritten whenever a reentrant invocation is accepted.

Consequently, an implementation that needs to retain calldata from an earlier invocation MUST copy it to another location before performing an external call that may reenter the proxy.

The proxy does not maintain a stack of previous calldata values and does not restore an earlier value after a nested invocation returns.

### Implementation Requirements

The implementation MUST be capable of interpreting the program forwarded by the proxy.

The implementation MUST treat the following slots as read-only:

- `DEPTH_SLOT`
- `BYTECODE_SLOT`
- `CALLDATA_SLOT`

The implementation MAY read and write `HANDLER_SLOT` to control callback dispatch.

The implementation MUST ensure that its execution environment cannot unintentionally modify the protected transient storage slots. If the implementation exposes arbitrary storage-access instructions to the interpreted program, it MUST enforce the required access restrictions itself.

The implementation MUST NOT assume that the calldata forwarded to it is the same as the calldata cached at `CALLDATA_SLOT`. The former contains the program; the latter contains the input data associated with the current invocation.

## Rationale

### Separation of Program and Calldata

The program is supplied once and remains constant throughout an execution session. Calldata is supplied separately and can change across reentrant invocations.

This separation allows the implementation to reuse the same program for multiple callback stages while using the latest invocation data to determine the appropriate execution path.

### Transient Storage

Transient storage provides transaction-scoped caching without incurring the persistent state costs associated with ordinary storage.

Because the cache is shared by all invocations of the proxy within the same transaction, the implementation can access the current program and calldata without requiring the proxy to deploy or update runtime code.

### Handler Flag

Not every invocation of the proxy should necessarily trigger program execution.

For example, a contract may receive ETH through a transfer that forwards only the 2,300 gas stipend. Executing the full proxy dispatch path may exceed the available gas.

The handler flag allows the implementation to disable callback dispatch when execution is not expected or cannot be safely performed. When disabled, reentrant invocations are skipped with empty returndata.

The initial invocation is not subject to this flag because it is responsible for starting the execution session.

## Backwards Compatibility

This proposal introduces a new execution mechanism and does not modify or conflict with existing Ethereum protocol rules or standards. No backwards compatibility issues are identified.

## Test Cases

## Implementation Notes

### EVM Interpreter Example

One possible implementation is an on-chain EVM interpreter, such as `https://github.com/Analog-Labs/evm-interpreter`.

In this architecture, callers provide an EVM program that the interpreter executes. The program is commonly generated by compiling high-level Solidity code into EVM bytecode.

When using Solidity-generated bytecode, the program should generally place its execution logic in the `fallback` function and perform calldata-based dispatch explicitly.

Unlike a conventional Solidity contract, the proxy does not distinguish between initialization code and runtime code. It accepts a single bytecode sequence and forwards the same sequence to the implementation throughout the execution session.

Consequently, when Solidity-generated initialization code is supplied, the interpreter executes the constructor path. When the corresponding runtime bytecode is supplied, the interpreter executes the runtime path, including the fallback logic.

Both approaches can be used in this architecture, but placing execution logic in `fallback` is generally recommended because it provides clearer Solidity-level semantics for a program that receives changing calldata across multiple invocations.

The implementation must also expose a way for the interpreted program to access the cached calldata and control `HANDLER_SLOT`. For example, the program may inspect the first four bytes of the cached calldata to select a callback-specific execution branch, following a dispatch pattern similar to Solidity's function selector dispatch.

### Transaction Example

`https://dashboard.tenderly.co/tx/0x310decf1423d37da5868f8354b2bd5c36b92411650118f3c6b7fc91a5cbb1553?trace=0.8`

## Reference Implementation

See `https://github.com/Helkomine/ERCs/tree/flash-loan-proxy/assets/erc-0`.

## Security Considerations

### Calldata Replacement

The proxy maintains only one active calldata cache. A reentrant invocation replaces the previous value. Implementations MUST preserve any earlier calldata that remains necessary after an external call.

### Transient Storage Access

The proxy relies on specific transient storage slots for its execution state. An implementation that permits arbitrary `TSTORE` operations may allow interpreted programs to overwrite these slots.

Implementations MUST prevent untrusted programs from modifying protected proxy slots. This restriction is the responsibility of the implementation and cannot be guaranteed solely by the proxy.

### Callback Authentication

The handler flag only determines whether a reentrant invocation is dispatched. It does not establish that the caller is authorized.

Implementations MUST validate callback callers and any other relevant execution conditions.

### Gas Availability

Every accepted invocation incurs proxy overhead for transient storage access, calldata caching, and implementation dispatch.

As a result, callback execution that would succeed when called directly may fail when routed through the proxy under a restricted gas allowance. Implementations and integrating contracts SHOULD account for this overhead and forward sufficient gas when callback dispatch is required.

### Program Interpretation and Analysis

The proxy does not constrain the semantics of the supplied program. Implementations that interpret general-purpose bytecode may expose execution paths that are difficult to analyze or may permit unexpected memory, storage, control-flow, or external-call behavior.

Implementations SHOULD provide a constrained and auditable execution environment where appropriate.

### Code Size

Programs supplied as calldata are not deployed runtime code and therefore are not directly subject to the [EIP-170](./eip-170.md) deployed-code-size limit. However, execution remains constrained by calldata availability, transaction gas limits, block gas limits, and the resource limits imposed by the implementation.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
