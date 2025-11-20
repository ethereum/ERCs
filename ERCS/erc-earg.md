---
eip: 8xxx
title: Encrypted Arguments and Calls via Decryption Oracle
description: A Protocol for Encrypted Function Call and Encrypted Function Argument Execution
author: Christian Fries (@cfries), Peter Kohl-Landgraf (@pekola)
status: Draft
type: Standards Track
category: ERC
created: 2025-11-19
requires: 7573
---

## Simple Summary

This ERC standardizes how smart contracts can request a **function execution with encrypted arguments**,
optionally with an **encrypted call descriptor**,  using a stateless decryption oracle.

It separates

1. a reusable, verifiable container for **encrypted arguments**, and
2. a **call descriptor** (who may trigger, what to call, and which arguments are bound),

and defines how an off-chain oracle decrypts and executes such calls.

## Abstract

This ERC defines a data format and contract interface for executing smart contract calls where:

1. The **arguments** are encrypted and reusable (`EncryptedArguments`), and
2. The **call descriptor** (target contract, selector, access-control list, validity) is either
    - encrypted (`EncryptedFunctionCall`), or
    - transparent (`FunctionCall`).

The encrypted arguments and the call descriptor are bound together via a **hash commitment** (`argsHash`).
An off-chain decryption oracle listens to standardized events, decrypts payloads, verifies the hash commitment,
and calls back into the on-chain oracle to perform the requested call.

The ERC is compatible with existing decryption-oracle designs such as ERC-7573 and can be implemented
as an extension of such oracles.

The contract receiving the decrypted arguments can pass these on to other contracts, which can, if necessary,
validate the arguments against the previously stored  **hash commitment** (`argsHash`). 

## Motivation

Privacy- and conditionality-preserving protocols often need to:

- Keep **arguments** confidential until some condition is met.
- Optionally keep the **target address and function** itself confidential.
- Allow **reusable encrypted argument blobs** that can be passed between contracts and stored on-chain.
- Allow the **receiver** of a call to verify that the decrypted arguments used in the call are exactly those that were committed to earlier.

Existing work like ERC-7573 focuses on a specific decryption-oracle use-case with fixed callbacks (e.g. DvP).
This ERC generalizes that pattern to a **generic function execution** mechanism, designed around:

- a clear separation of **argument encryption** and **call encryption**, and
- an explicit hash commitment enabling verification of the arguments by the receiving contract.

### Exemplary Use-Cases

#### Order Book Build Process avoiding Front Running

A possible use-case is the construction of an auction / order book preventing front-running, where
the propsals can be made duing a predefined phase.
Here participants submit their proposals as an encrypted arguments, which are stored inside a smart
contract. Once the order phase is closed, the smart contract calls the decryption oracle given itself
as a callback to receive the decrypted arguments in a call that will build the order book.

## Specification

### 1. Encrypted arguments

Encrypted arguments are independent of any particular call descriptor and can be reused.

```solidity
struct EncryptedArguments {
    /// Commitment to the plaintext argument tuple.
    /// Convention: argsHash = keccak256(abi.encode(arguments_without_argsHash))
    bytes32 argsHash;

    /// Identifier of the public key used for encryption (e.g. keccak256 of key material).
    bytes32 publicKeyId;

    /// Ciphertext of abi.encode(arguments_without_argsHash), encrypted under publicKeyId.
    bytes ciphertext;
}
```

#### Normative requirements (EncryptedArguments)

For producers of `EncryptedArguments`:

- The producer **MUST** compute:
    - `argsHash = keccak256(abi.encode(arguments_without_argsHash))`
      using the exact argument ordering and ABI encoding that will later
      be used when forming the call data.
- The producer **MUST** set `argsHash` to the value computed above.
- The producer **MUST** set `ciphertext` to the encryption of exactly
  `abi.encode(arguments_without_argsHash)` under the key identified by `publicKeyId`.

The decryption oracle can provide a convienient commmand line too or endpont
to generate the encrypted argument.

This ERC does not standardize the encryption algorithm or key management; those are implementation-specific (similar to ERC-7573).
Implementations **SHOULD** document how `publicKeyId` is derived from the underlying key material.

### 2. Call descriptor

A **call descriptor** defines:

- which address is allowed to request execution,
- which contract and function will be called, and
- which arguments (via their hash) are bound to this call.

```solidity
struct FunctionCall {
    /// Addresses allowed to request this execution.
    /// If empty, any requester is allowed.
    address[] eligibleCaller;

    /// Contract that will be called by the oracle.
    address targetContract;

    /// 4-byte function selector for the targetContract.
    bytes4 selector;

    /// Hash of the argument tuple that this call commits to.
    /// MUST equal EncryptedArguments.argsHash.
    bytes32 argsHash;

    /// Optional expiry (block number). 0 means "no explicit expiry".
    uint256 validUntilBlock;
}
```

#### Transparent vs. encrypted call descriptors

A call descriptor can be:

- **Transparent**: `FunctionCall` is passed in clear on-chain.
- **Encrypted**: `FunctionCall` is wrapped into:

```solidity
struct EncryptedFunctionCall {
    /// Identifier of the public key used for encryption.
    bytes32 publicKeyId;

    /// Ciphertext of abi.encode(FunctionCall), encrypted under publicKeyId.
    bytes ciphertext;
}
```

#### Normative requirements (FunctionCall and EncryptedFunctionCall)

- `FunctionCall.argsHash` **MUST** equal the `argsHash` field in the associated `EncryptedArguments` object with which it is meant to be used.
- When using `EncryptedFunctionCall`, the ciphertext **MUST** be the encryption of exactly `abi.encode(FunctionCall)` under the key identified by `publicKeyId`.

### 3. Oracle interface

The oracle exposes a **request/fulfill** pattern. Requests are cheap and do not require on-chain decryption; fulfillment is called by an off-chain operator after decryption.

```solidity
interface IEncryptedExecutionOracle {
    /// Raised when a request with encrypted call + encrypted args is registered.
    event EncryptedExecutionRequested(
        uint256 indexed requestId,
        address indexed requester,
        bytes32 callPublicKeyId,
        bytes   callCiphertext,
        bytes32 argsPublicKeyId,
        bytes   argsCiphertext,
        bytes32 argsHash
    );

    /// Raised when a request with transparent call + encrypted args is registered.
    event TransparentExecutionRequested(
        uint256 indexed requestId,
        address indexed requester,
        address[] eligibleCaller,
        address targetContract,
        bytes4  selector,
        bytes32 argsHash,
        uint256 validUntilBlock,
        bytes32 argsPublicKeyId,
        bytes   argsCiphertext
    );

    /// Raised when an execution attempt has been fulfilled by the oracle operator.
    event ExecutionFulfilled(
        uint256 indexed requestId,
        bool    success,
        bytes   returnData
    );

    /// Request execution with encrypted call + encrypted args.
    ///
    /// MUST:
    /// - register a unique requestId,
    /// - store (requestId â requester, argsHash, any auxiliary metadata),
    /// - emit EncryptedExecutionRequested.
    function requestEncryptedExecution(
        EncryptedFunctionCall calldata encCall,
        EncryptedArguments   calldata encArgs
    ) external returns (uint256 requestId);

    /// Request execution with transparent call + encrypted args.
    ///
    /// MUST:
    /// - require call.argsHash == encArgs.argsHash,
    /// - register a unique requestId and store call data + requester,
    /// - emit TransparentExecutionRequested.
    function requestTransparentExecution(
        FunctionCall         calldata call,
        EncryptedArguments   calldata encArgs
    ) external returns (uint256 requestId);

    /// Fulfill an encrypted-call request (called by oracle operator).
    ///
    /// MUST:
    /// - verify that requestId exists and was created with
    ///   requestEncryptedExecution,
    /// - verify call.argsHash equals the stored argsHash,
    /// - verify call.validUntilBlock is zero or >= current block.number,
    /// - verify that the original requester is contained in call.eligibleCaller
    ///   (unless the eligibleCaller array is empty),
    /// - verify that keccak256(argsPlain) equals call.argsHash,
    /// - perform low-level call:
    ///     call.targetContract.call(abi.encodePacked(call.selector, argsPlain))
    /// - emit ExecutionFulfilled(requestId, success, returnData),
    /// - clean up stored state for this requestId.
    function fulfillEncryptedExecution(
        uint256       requestId,
        FunctionCall  calldata call,
        bytes         calldata argsPlain
    ) external;

    /// Fulfill a transparent-call request (called by oracle operator).
    ///
    /// MUST:
    /// - verify that requestId exists and was created with
    ///   requestTransparentExecution,
    /// - load stored FunctionCall from state,
    /// - verify storedCall.validUntilBlock is zero or >= current block.number,
    /// - verify that keccak256(argsPlain) equals storedCall.argsHash,
    /// - verify that the original requester is contained in storedCall.eligibleCaller
    ///   (unless the eligibleCaller array is empty),
    /// - perform low-level call:
    ///     storedCall.targetContract.call(abi.encodePacked(storedCall.selector, argsPlain))
    /// - emit ExecutionFulfilled(requestId, success, returnData),
    /// - clean up stored state for this requestId.
    function fulfillTransparentExecution(
        uint256       requestId,
        bytes         calldata argsPlain
    ) external;
}
```

### 4. Target contract verification

A target contract that wants to verify the arguments can follow this convention:

1. The **plaintext arguments** are encoded as:

   ```solidity
   abi.encode(arguments_without_argsHash)
   ```

2. The oracle forms the call data as:

   ```solidity
   abi.encodeWithSelector(
       selector,
       argsHash,             // first parameter
       /* decoded arguments_without_argsHash */
   );
   ```

3. Inside the target function, the contract recomputes the hash and verifies it:

   ```solidity
   function doSomething(
       bytes32 argsHash,
       uint256 amount,
       address beneficiary
   ) external {
       bytes32 computed = keccak256(abi.encode(amount, beneficiary));
       require(computed == argsHash, "Encrypted args mismatch");

       // Safe to use amount and beneficiary here
   }
   ```

The exact parameter list is application-specific; this ERC only standardizes the hashing convention and the binding via `argsHash`.

### 5. Security considerations

This section is non-normative.

#### Oracle trust

The on-chain contract cannot verify correctness of decryption; it can only check that `keccak256(argsPlain) == argsHash`. Parties must trust the oracle operator (or design an incentive/penalty mechanism) to decrypt correctly and call `fulfill*` faithfully.

#### Replay

Implementations SHOULD mitigate replay by:

- using `validUntilBlock` in `FunctionCall`, and/or
- including nonces or sequence numbers in higher-level protocols.

#### Access control

- `eligibleCaller` binds the original requester to the execution:
    - the oracle MUST check whether the original requester is contained in `eligibleCaller`, unless `eligibleCaller.length == 0`.
- Implementations MAY extend this with roles, multi-signatures, or other access-control schemes.

#### Fees

Fee mechanisms are out of scope. Implementations MAY charge fees in ETH or ERCâ20 tokens as part of their specific deployment.

## Rationale

- The **two-stage design** (arguments vs. call) allows encrypted arguments to be reusable and independent of any particular call descriptor.
- The explicit **hash commitment** (`argsHash`) binds arguments to the call descriptor while still allowing the arguments to be stored and passed separately.
- The **request/fulfill pattern** reflects that decryption is off-chain. Requests are cheap; fulfill is initiated when decryption is ready.
- The use of `abi.encodePacked(selector, argsPlain)` makes the oracle generic and able to support arbitrary function signatures without on-chain decoding.

## Backwards Compatibility

This ERC is designed to coexist with ERCâ7573 decryption oracles. An existing ERCâ7573 implementation can be extended to implement `IEncryptedExecutionOracle` without breaking existing interfaces.

## Reference Implementation

A non-normative reference implementation (Solidity) and a matching Java/off-chain implementation are provided separately. They illustrate:

- storage of pending requests,
- event emission for both encrypted and transparent call descriptors,
- validation of hash bindings, and
- low-level call execution.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).




