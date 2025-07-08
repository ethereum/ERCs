---
eip: XXXX
title: Confidential Fungible Token Interface
description: An interface for confidential fungible tokens
author: Aryeh Greenberg (@arr00), Ernesto García (@ernestognw), Hadrien Croubois (@Amxx)
discussions-to: https://ethereum-magicians.org/t/new-erc-confidential-fungible-token-standard/24735
status: Draft
type: Standards Track
category: ERC
created: 2025-07-03
---

## Abstract

The following standard defines an implementation of a standard API for confidential fungible tokens via pointers. All amounts in this standard are represented by pointers, whose resolution is implementation specific. The interface defines functions to transfer tokens with pointers, as well as approve operators so the tokens can be transferred by a third-party.

## Motivation

A standard interface allows pointer based confidential tokens on Ethereum to be reused by other applications: from privacy-focused wallets to decentralized exchanges, while keeping transaction amounts private from public view.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Nomenclature

- All amounts in this ERC are pointer based amounts represented by `bytes32` pointers unless otherwise specified. The resolution and manipulation of these pointers is implementation specific.

### Token

### Methods

Compliant tokens MUST implement the following methods, unless otherwise specified:

#### `name()`

Returns the name of the token - e.g. `"MyConfidentialToken"`.

OPTIONAL - This method can be used to improve usability, but interfaces and other contracts MUST NOT expect these values to be present.

```solidity
function name() external view returns (string memory)
```

#### symbol

Returns the symbol of the token - e.g. `"MCT"`.

OPTIONAL - This method can be used to improve usability, but interfaces and other contracts MUST NOT expect these values to be present.

```solidity
function symbol() external view returns (string memory)
```

#### decimals

Returns the number of decimals the token uses (e.g. `6`) as a plaintext `uint8`.

```solidity
function decimals() external view returns (uint8)
```

#### `confidentialTotalSupply()`

Returns the total token supply.

```solidity
function totalSupply() external view returns (bytes32)
```

#### `confidentialBalanceOf()`

Returns the balance of `account`.

```solidity
function balanceOf(address account) external view returns (bytes32)
```

#### isOperator

Returns `true` if `spender` is currently authorized to transfer tokens on behalf of `holder`.

```solidity
function isOperator(address holder, address spender) external view returns (bool)
```

#### setOperator

Authorizes `operator` to transfer tokens on behalf of the caller until timestamp `until`--passed as a plaintext `uint48`. An operator may transfer any amount of tokens on behalf of a holder while approved.

MUST emit the `OperatorSet` event.

```solidity
function setOperator(address operator, uint48 until) external
```

#### confidentialTransfer(address,bytes32)

Transfers `amount` of tokens to address `to`. The function MAY revert if the caller's balance does not have enough tokens to spend.

Returns the actual amount that was transferred.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransfer(address to, bytes32 amount) external returns (bytes32)
```

#### confidentialTransfer(address, bytes32, bytes)

Transfers `amount` of tokens to address `to`. The function MAY revert if the caller's balance does not have enough tokens to spend.

The `data` parameter contains implementation-specific information such as cryptographic proofs.

Returns the actual amount that was transferred.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransfer(address to, bytes32 amount, bytes calldata data) external returns (bytes32)
```

#### confidentialTransferFrom(address, address, bytes32)

Transfers `amount` of tokens from address `from` to address `to`. The function MAY revert if the `from`'s account balance does not have enough tokens to spend.

Returns the actual amount that was transferred.

MUST revert if the caller is not an operator for `from`.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferFrom(address from, address to, bytes32 amount, bytes calldata data) external returns (bytes32)
```

#### confidentialTransferFrom(address, address, bytes32, bytes)

Transfers `amount` of tokens from address `from` to address `to`. The function MAY revert if the `from`'s account balance does not have enough tokens to spend.

The `data` parameter contains implementation-specific information such as cryptographic proofs.

Returns the actual amount that was transferred.

MUST revert if the caller is not an operator for `from`.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferFrom(address from, address to, bytes32 amount, bytes calldata data) external returns (bytes32)
```

#### confidentialTransferAndCall(address, address, bytes32, bytes)

Transfers `amount` of tokens to address `to`. The function MAY revert if the caller's balance does not have enough tokens to spend.

The `data` parameter contains implementation-specific information such as cryptographic proofs.

See [Callback Details](#callback-details) below for details on the callback flow.

Returns the actual amount that was transferred.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferAndCall(address to, bytes32 amount, bytes calldata callData) external returns (bytes32)
```

#### confidentialTransferAndCall(address, address, bytes32, bytes, bytes)

Transfers `amount` of tokens to address `to`. The function MAY revert if the caller's balance does not have enough tokens to spend.

The `data` parameter contains implementation-specific information such as cryptographic proofs.

See [Callback Details](#callback-details) below for details on the callback flow.

Returns the actual amount that was transferred.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferAndCall(address to, bytes32 amount, bytes calldata data, bytes calldata callData) external returns (bytes32)
```

#### confidentialTransferFromAndCall(address, address, bytes32, bytes)

Transfers `amount` of tokens from address `from` to address `to`. The function MAY revert if the `from`'s account balance does not have enough tokens to spend.

See [Callback Details](#callback-details) below for details on the callback flow.

Returns the actual amount that was transferred.

MUST revert if the caller is not an operator for `from`.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferFromAndCall(address from, address to, bytes32 amount, bytes calldata data) external returns (bytes32)
```

#### confidentialTransferFromAndCall(address, address, bytes32, bytes, bytes)

Transfers `amount` of tokens from address `from` to address `to`. The function MAY revert if the `from`'s account balance does not have enough tokens to spend.

The `data` parameter contains implementation-specific information such as cryptographic proofs.

See [Callback Details](#callback-details) below for details on the callback flow.

Returns the actual amount that was transferred.

MUST revert if the caller is not an operator for `from`.

MUST emit the `ConfidentialTransfer` event.

```solidity
function confidentialTransferFromAndCall(address from, address to, bytes32 amount, bytes calldata data, bytes calldata callData) external returns (bytes32)
```

### Events

#### ConfidentialTransfer

MUST trigger when confidential tokens are transferred, including zero value transfers.

A token contract which creates new tokens SHOULD trigger a ConfidentialTransfer event with the `from` address set to `0x0` when tokens are created.

```solidity
event ConfidentialTransfer(address indexed from, address indexed to, bytes32 indexed amount)
```

#### OperatorSet

MUST trigger on any successful call to `setOperator`.

```solidity
event OperatorSet(address indexed holder, address indexed operator, uint48 until)
```

#### AmountDisclosed

SHOULD trigger when a pointer amount is publicly disclosed through implementation-specific mechanisms.

```solidity
event AmountDisclosed(bytes32 indexed handle, uint256 amount)
```

### Callback Details

Transfer functions suffixed with `andCall` execute a callback to the `to` address AFTER all transfer logic is completed. The callback calls the `onConfidentialTokenReceived` function with the from address, actual amount sent, and given `callData` bytes (the last parameter for `andCall` functions). The callback flow is as follows:

- If `address(to).code.length == 0` the callback is a no-op and returns successfully.
- Call [`onConfidentialTokenReceived(address, bytes32, bytes)`](#onconfidentialtokenreceived) on `to`.
- If the function call reverts, revert.
- If the function call returns the false boolean, attempt to transfer back the tokens to the original holder and return.

### Contract Receivers

For a contract to receive a transfer with a callback, it MUST implement the `onConfidentialTokenReceived` function:

#### onConfidentialTokenReceived

If the callback is unsuccessful, the function SHOULD revert or return a pointer to the false boolean.

The token will attempt to return tokens from the receiver to the sender if false is returned. Note that this reversal may fail if the receiver spends tokens as part of the callback.

```solidity
function onConfidentialTokenReceived(address from, bytes32 amount, bytes calldata data) external returns (bytes32 success);
```

## Rationale

### Technology Agnostic Design

Using `bytes32` allows implementations using pointer based systems and privacy mechanisms including FHE systems, zero-knowledge proofs, secure enclaves, or future technologies to be compliant.

### Operator Model

Time-limited operators provide granular control while enabling DeFi protocol integration and natural permission expiration. This approach reduces the load on the external system by removing the need to track approval amounts.

### Data Parameter

The `bytes calldata data` parameter in transfer functions allows implementations to include cryptographic proofs, access permissions, or other privacy-mechanism-specific information.

## Implementation Considerations

Implementations SHOULD clearly document their privacy guarantees and cryptographic assumptions. Different privacy mechanisms may be incompatible at the cryptographic level. Implementations SHOULD document how their pointers can be unwrapped and interacted with.

## Security Considerations

Security depends on the underlying pointer based mechanism. Implementations must guard against side-channel attacks and ensure proper key management for offchain operations.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
