---
eip: xxxx
title: Signature Verification for Pre-delegated Accounts
description: Enables ERC-1271 signature verification for accounts that intend to delegate via EIP-7702 before the delegation occurs onchain
author: Jake Moxey (@jxom)
discussions-to: https://ethereum-magicians.org/t/new-erc-signature-verification-for-pre-delegated-accounts/25201
status: Draft
type: Standards Track
category: ERC
created: 2025-08-21
requires: 1271, 7702
---

# Signature Verification for Pre-delegated Accounts

## Abstract

This ERC defines a signature verification procedure that enables signature validation for accounts that intend to delegate via [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) before onchain delegation occurs. The standard introduces a detectable signature wrapper containing an [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) authorization and initialization data, allowing verifiers to simulate the delegation and validate signatures through [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) in a single atomic operation.

## Motivation

[EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) enables EOAs to set code in their account, but signatures are often generated before onchain delegation occurs. Current verification methods cannot validate these pre-delegation signatures against the intended delegate logic.

This proposal addresses this limitation by:

- Standardizing a signature format that embeds delegation intent
- Defining a verification procedure that simulates delegation atomically
- Maintaining compatibility with existing [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) infrastructure, including Create2-based predeployed verification ([ERC-6492](https://eips.ethereum.org/EIPS/eip-6492))

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Signer Side (e.g. Wallets)

This ERC proposes that wallets can wrap signatures into a predelegate verification-compatible format that is constructed as follows:

```solidity
wrapped_signature =
  signature
  || MAGIC
  || abi.encode(init_data, authorization)

MAGIC = 0xd313d313d313d313d313d313d313d313d313d313d313d313d313d313d313d313
authorization = abi.encode(chain_id, address, nonce, y_parity, r, s)
```

Where:

- `signature`: The signature to be verified by the delegate's `isValidSignature` method
- `MAGIC`: Detection marker
- `authorization`: Signed EIP-7702 authorization
- `init_data`: Initialization data to be executed before validation

### Requirements

- Signers SHOULD NOT wrap signatures if the account has already been delegated.

### Verifier Side (e.g. Apps, Libraries)

The verification procedure is performed by consumers of the account (e.g. applications, services, libraries, etc.).

Given inputs `(account: address, digest: bytes32, wrapped_signature: bytes)`, verifiers MUST implement the following procedure (pseudocode):

### Step 1: Detection and parsing

1. Search for `MAGIC` within `wrapped_signature`
2. If `MAGIC` is not found:
    1. MUST perform standard ERC-1271 verification: `account.isValidSignature(digest, signature)` 
        1. If success, return the result
        2. If failure, attempt `ecrecover` verification.
        3. (or if ERC-6492 `MAGIC` is found instead, attempt 6492 verification)
3. If `MAGIC` is found:
    1. Split `wrappedSignature` at the `MAGIC` boundary:
        - `signature = wrapped_signature[0:magicIndex]`
        - `tail = wrapped_signature[magicIndex+32:]`
    2. Decode the `tail`:
        - `(initData, authorization) = abi.decode(tail, (bytes, bytes))`
        - `(chain_id, delegation, nonce, y_parity, r, s) = abi.decode(authorization, (uint256, address, uint64, uint8, bytes32, bytes32))`
    3. Continue to [Step 2](#step-2-check-if-already-delegated).

### Step 2: Check if already delegated

Check if the account is already delegated to the target `delegation`, and if so, perform standard [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) verification.

- If `account.code == bytes.concat(hex"ef0100", delegation)`:
    1. Perform ERC-1271 verification: `account.isValidSignature(digest, signature)` 
        1. If success, return the result. 
        2. If failure, attempt `ecrecover` verification. 
- Otherwise, continue to [Step 3](#step-3-simulate-delegation-and-validate).

### Step 3: Simulate delegation and validate

If the account is not delegated yet, we will simulate the delegation and validate the signature with a multicall mechanism.

1. Construct a multicall (via `eth_call` or alike) with:
    - `authorizationList` containing `[[chain_id, delegation, nonce, y_parity, r, s]]`
    - Two calls to be executed atomically
    a. Call 1: `(data: init_data, to: account)` (initialization)
    b. Call 2: `(data: abi.encodeWithSignature("isValidSignature(bytes32,bytes)", digest, signature), to: account)` (ERC-1271 signature validation)
2. MUST return result of the second call, or `0xffffffff` if the multicall failed.

### Requirements

- Verifiers MUST follow the verification procedure as specified
- Verifiers MAY use a (pre)deployed multicall contract (for Step 3), a deployless multicall mechanism (for Step 3), or a deployless contract to batch both steps (for Step 2 + Step 3)

## Rationale

### Atomic Simulation Context

The design executes initialization and validation atomically (via multicall) to ensure state changes from initialization are visible during validation. This mirrors the actual execution flow when a 7702 delegation transaction includes both authorization and subsequent calls.

## Backwards Compatibility

This ERC introduces a new signature format that is backward compatible with existing ERC-1271 infrastructure. Signatures without the `MAGIC` marker are processed using standard ERC-1271 verification, ensuring existing signatures remain valid.

This standard does not require compatibility with ERC-6492 or other signature wrapping standards, as it addresses the specific requirements of EIP-7702 delegation.

## Test Cases

TBD

## Security Considerations

TBD

## Copyright

Copyright and related rights waived via [CC0](https://www.notion.so/LICENSE.md).