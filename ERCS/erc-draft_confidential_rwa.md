---
eip: xxxx
title: Confidential Real World Asset Token
description: Compliance checks, spendable balances, and transfer enforcement for confidential tokens representing real world assets.
author: Aryeh Greenberg (@arr00)
discussions-to: xxxx
status: Draft
type: Standards Track
category: ERC
created: 2026-09-24
requires: 165, 7984
---

## Abstract

This ERC extends [ERC-7984](./eip-7984.md) with a minimal interface for defining tokenized real world assets. It provides a pair of plaintext eligibility checks, a confidential validation function answering whether a specific transfer is permitted, a confidential figure for the portion of a balance that is currently spendable, and an access restricted forced transfer. Amounts remain confidential pointers throughout. The standard constrains the behavior of minting, burning, halting, and freezing without mandating interfaces for them, leaving issuance and restriction mechanics to implementations.

## Motivation

Real world assets carry obligations that ordinary fungible tokens do not. Holders must be eligible to receive and transfer assets, transfers must satisfy rules that depend on the amount being moved, portions of a balance may be unspendable due to an issuer freeze or a vesting schedule, and an issuer may be required to move assets without a holder's consent.

[ERC-3643](./eip-3643.md) and [ERC-7943](./eip-7943.md) address these needs for tokens whose balances are public. Neither translates to a token whose balances and transfer amounts are confidential pointers.

Confidentiality complicates this. Determining if a transfer is compliant depends on confidential data and therefore must be confidential itself. Yet parties wish to have easy access to compliance information to enable smart-contract interactions and applications. A standard for confidential real world assets must serve both needs without letting either compromise the other.

This standard defines the minimum interface that does so, adapting prior compliance standards to a confidential token.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Token

Compliant tokens MUST implement [ERC-7984](./eip-7984.md) and [ERC-165](./eip-165.md). The `supportsInterface` function MUST return `true` when the `interfaceID` argument is `0x00000000`.

All amounts are confidential pointers represented as `bytes32` values, as defined by [ERC-7984](./eip-7984.md). The mechanism by which a pointer is resolved, and the mechanism by which an account is authorized to resolve one, are implementation specific.

Functions accepting a confidential pointer as input also take a `bytes calldata data` parameter. This parameter may carry cryptographic proofs, authorization grants, or other mechanism specific material used to properly process the pointer. Contracts MUST accept empty input in cases where the confidential pointer is sufficient on its own.

### Interface

```solidity
interface IERCXXXX is IERC7984 {
    event ConfidentialCanTransfer(address indexed operator, address indexed from, address indexed to, bytes32 allowed);

    event ConfidentialAvailableBalanceOf(address indexed account, bytes32 indexed amount);

    event ConfidentialForcedTransfer(address indexed from, address indexed to, bytes32 indexed amount);

    function canSend(address sender) external view returns (bool);

    function canReceive(address receiver) external view returns (bool);

    function confidentialCanTransfer(
        address operator,
        address from,
        address to,
        bytes32 amount,
        bytes calldata data
    ) external returns (bytes32);

    function confidentialAvailableBalanceOf(address account) external returns (bytes32);

    function forceConfidentialTransferFrom(
        address from,
        address to,
        bytes32 amount,
        bytes calldata data
    ) external returns (bytes32);
}
```

### Methods

- #### `canSend`

  Returns whether `sender` is eligible to send the asset, ignoring any amount.
  - MUST NOT revert.
  - MUST NOT encode quantitative rules. Amount based restrictions and limitation checks belong in `confidentialCanTransfer`.

  ```solidity
  function canSend(address sender) external view returns (bool)
  ```

- #### `canReceive`

  Returns whether `receiver` is eligible to receive the asset, ignoring any amount.
  - MUST NOT revert.
  - MUST NOT encode quantitative rules. Amount based restrictions and limitation checks belong in `confidentialCanTransfer`.

  ```solidity
  function canReceive(address receiver) external view returns (bool)
  ```

- #### `confidentialCanTransfer`

  Returns a pointer to a boolean indicating whether `operator` may move `amount` from `from` to `to`.
  - MUST return a pointer to false OR revert if `canSend(from)` returns false, unless `from` is the zero address.
  - MUST return a pointer to false OR revert if `canReceive(to)` returns false, unless `to` is the zero address.
  - MUST return a pointer to false OR revert if any other rule would prevent the transfer (such as vesting, balance caps, etc).
  - MUST return a pointer to false if `amount` exceeds the value returned by `confidentialAvailableBalanceOf(from)`, unless `from` is the zero address.
  - MUST NOT return a pointer to false solely because `operator` is not an authorized operator for `from`. Operator authorization is enforced by [ERC-7984](./eip-7984.md). The `operator` parameter exists so that rules constraining who may initiate a transfer can be expressed.
  - MUST emit `ConfidentialCanTransfer` with the returned pointer.

  ```solidity
  function confidentialCanTransfer(address operator, address from, address to, bytes32 amount, bytes calldata data) external returns (bytes32)
  ```

- #### `confidentialAvailableBalanceOf`

  Returns a pointer to the largest amount `account` could transfer at the time of the call, disregarding rules that depend on the recipient.
  - MUST be less than or equal to `confidentialBalanceOf(account)`.
  - MUST account for every restriction the implementation applies to the account's own balance, including issuer freezes, lockups, vesting schedules, and pledged amounts.
  - SHOULD NOT revert.
  - MUST emit `ConfidentialAvailableBalanceOf` with the returned pointer.

  ```solidity
  function confidentialAvailableBalanceOf(address account) external returns (bytes32)
  ```

- #### `forceConfidentialTransferFrom`

  Moves `amount` from `from` to `to`. Returns a pointer to the amount actually moved.
  - MUST be restricted in access.
  - MUST move 0 tokens if `amount` exceeds `confidentialBalanceOf(from)`.
  - MAY move 0 tokens if `amount` exceeds `confidentialAvailableBalanceOf(from)`
  - MUST revert if `canReceive(to)` returns false.
  - MUST NOT call `confidentialCanTransfer`.
  - MUST emit `ConfidentialTransfer` as defined by [ERC-7984](./eip-7984.md), in addition to `ConfidentialForcedTransfer`.

  ```solidity
  function forceConfidentialTransferFrom(address from, address to, bytes32 amount, bytes calldata data) external returns (bytes32)
  ```

### Events

- #### `ConfidentialForcedTransfer`

  ```solidity
  event ConfidentialForcedTransfer(address indexed from, address indexed to, bytes32 indexed amount)
  ```

- #### `ConfidentialCanTransfer`

  ```solidity
  event ConfidentialCanTransfer(address indexed operator, address indexed from, address indexed to, bytes32 allowed)
  ```

- #### `ConfidentialAvailableBalanceOf`

  ```solidity
  event ConfidentialAvailableBalanceOf(address indexed account, bytes32 indexed amount)
  ```

### Transfer Behavior

An implementation MUST NOT complete a transfer of an amount for which `confidentialCanTransfer` would resolve to false unless otherwise specified above.

Implementations SHOULD satisfy that requirement by transferring an amount of zero rather than reverting.

## Rationale

### Plaintext eligibility alongside a confidential predicate

This standard answers two distinct questions. The first is whether an address may send/receive an asset at all, which does not depend on any amount and is often derived from a non-confidential source such as an identity registry, allow-list, or block-list. The second is whether a particular transfer may proceed, which accounts for every rule, confidential and non-confidential alike, and whose result must therefore be confidential.

`canSend` and `canReceive` answer the first question in plaintext as `view` functions. Consumers must understand that the answer is not exhaustive: a transfer to or from an eligible address may still fail on a rule evaluated within `confidentialCanTransfer`. `confidentialCanTransfer` answers the second question as a confidential pointer, subsuming the first, and is consumed both by the token in the course of a transfer and by integrators informing a user whether a specific transfer would be permitted.

The two are not collapsible into a single function. Doing so would force an inherently public boolean to be delivered as a confidential pointer, which cannot drive control flow in an integrating contract and often cannot be read without sending a transaction. Conversely, it is often impossible or undesirable to return the result from `confidentialCanTransfer` as plaintext.

### The available balance is not a view function

Deriving the spendable portion of a balance often requires operations on confidential values, and pointer mechanisms usually require writing on-chain to operate on existing values. A `view` function therefore cannot produce a resolvable answer.

### Halting, freezing, and vesting are not in the interface

A halted token, a frozen balance, and an unfinished vesting schedule are all rules that determine whether a transfer may proceed. `confidentialCanTransfer` and `confidentialAvailableBalanceOf` already answer that question completely, so a separate accessor for each mechanism would add surface without adding information. Mandating one mechanism would also privilege it over the others an issuer may need. This core can be extended to support more specific use cases through additional standards or implementation extensions.

## Security Considerations

### Disclosure through reverts

A transfer that reverts when a compliance rule is not satisfied publicly discloses that a specific pair of addresses failed that rule, which may reveal details about the balance of the sender or recipient. Transferring zero avoids the disclosure but produces a transaction that appears successful while moving nothing. Integrating contracts must verify the returned amount rather than assuming a transfer of the requested size occurred.

### Available balance accounting

Where the available balance is derived by naively subtracting a restricted amount from a balance, a forced transfer or a permissioned burn that moves more than the available balance will underflow that subtraction. Ensure saturating subtraction is used in this situation.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
