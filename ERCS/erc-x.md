---
eip: x
title: Cancelation for ERC-7540 Tokenized Vaults
description: Extension of ERC-7540 with cancelation support
author: Jeroen Offerijns (@hieronx)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2025-02-18
requires: 165, 7540
---

## Abstract

The following standard extends [ERC-7540](./eip-7540.md) by adding support for asynchronous cancelation flows.

## Motivation

Shares or assets locked for Requests can be stuck in the Pending state. For some use cases, such as redeeming from a pool of long-dated real-world assets, this can take a considerable amount of time.

This standard expands the scope Asynchronous ERC-7540 Vaults by adding cancelation support.

## Specification

### Definitions:

The existing definitions from [ERC-7540](./eip-7540.md) apply.

### Cancelation Lifecycle

After submission, cancelation Requests go through Pending, Claimable, and Claimed stages. An example lifecycle for a deposit cancelation Request is visualized in the table below.

| **State**   | **User**                         | **Vault** |
|-------------|---------------------------------|-----------|
| Pending     | `cancelDepositRequest(requestId, controller)` | `pendingCancelDepositRequest[controller] = true` |
| Claimable   |                                 | *Internal cancelation fulfillment*:  `pendingCancelDepositRequest[controller] = false`; `claimableCancelDepositRequest[controller] = assets` |
| Claimed     | `claimCancelDepositRequest(requestId, receiver, controller)`      | `claimableDepositRequest[controller] -= assets`; `asset.balanceOf[receiver] += assets` |

Requests MUST NOT skip or otherwise short-circuit the Claim state. In other words, to initiate and claim a Request, a user MUST call both cancel* and the corresponding Claim function separately, even in the same block. Vaults MUST NOT "push" tokens onto the user after a Request, users MUST "pull" the tokens via the Claim function.

Requests MAY skip straight from the Pending to the Claimable stage, in the case of synchronous cancelation flows.

While a deposit cancelation Request is Pending, new deposit Requests are blocked. Likewise, while a redeem cancelation Request is Pending, new redeem Requests are blocked.

### Methods

#### cancelDepositRequest

Submits a Request for asynchronous deposit cancelation. This places the Request in Pending state, with a corresponding increase in `pendingCancelDepositRequest` for the full amount of the pending deposit Request. 

When the cancelation is Pending, new deposit Requests are blocked and `requestDeposit` MUST revert.

When the cancelation is Claimable, `claimableCancelDepositRequest` will be increased for the `controller`. `claimCancelDepositRequest` can subsequently be called by `controller` to receive `assets`. A Request MAY transition straight to Claimable state but MUST NOT skip the Claimable state.

`controller` MUST equal `msg.sender` unless the `controller` has approved the `msg.sender` as an operator.

MUST emit the `CancelDepositRequest` event.

```yaml
- name: cancelDepositRequest
  type: function
  stateMutability: nonpayable

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address
  outputs:
```

#### pendingCancelDepositRequest

Whether the given `requestId` and `controller` have a pending deposit cancelation Request.

MUST NOT show any variations depending on the caller.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

```yaml
- name: pendingCancelDepositRequest
  type: function
  stateMutability: view

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address

  outputs:
    - name: isPending
      type: bool
```

#### claimableCancelDepositRequest

The amount of `assets` in Claimable cancelation state for the `controller` to claim.

MUST NOT show any variations depending on the caller.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

```yaml
- name: claimableCancelDepositRequest
  type: function
  stateMutability: view

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address

  outputs:
    - name: assets
      type: uint256
```

#### claimCancelDepositRequest

Claims the deposit cancelation Request with `requestId` and `controller`.

Transfers `assets` to `receiver`.

`controller` MUST equal `msg.sender` unless the `controller` has approved the `msg.sender` as an operator.

MUST emit the `ClaimCancelDepositRequest` event.

```yaml
- name: claimCancelDepositRequest
  type: function
  stateMutability: nonpayable

  inputs:
    - name: requestId
      type: uint256
    - name: receiver
      type: address
    - name: controller
      type: address
  outputs:
```

#### cancelRedeemRequest

Submits a Request for asynchronous redeem cancelation. This places the Request in Pending state, with a corresponding increase in `pendingCancelRedeemRequest` for the full amount of the pending redeem Request. 

When the cancelation is Pending, new redeem Requests are blocked and `requestRedeem` MUST revert.

When the cancelation is Claimable, `claimableCancelRedeemRequest` will be increased for the `controller`. `claimCancelRedeemRequest` can subsequently be called by `controller` to receive `shares`. A Request MAY transition straight to Claimable state but MUST NOT skip the Claimable state.

`controller` MUST equal `msg.sender` unless the `controller` has approved the `msg.sender` as an operator.

MUST emit the `CancelRedeemRequest` event.

```yaml
- name: cancelRedeemRequest
  type: function
  stateMutability: nonpayable

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address
  outputs:
```

#### pendingCanceRedeemRequest

Whether the given `requestId` and `controller` have a pending redeem cancelation Request.

MUST NOT show any variations depending on the caller.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

```yaml
- name: pendingCanceRedeemRequest
  type: function
  stateMutability: view

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address

  outputs:
    - name: isPending
      type: bool
```

#### claimableCancelRedeemRequest

The amount of `shares` in Claimable cancelation state for the `controller` to claim.

MUST NOT show any variations depending on the caller.

MUST NOT revert unless due to integer overflow caused by an unreasonably large input.

```yaml
- name: claimableCancelRedeemRequest
  type: function
  stateMutability: view

  inputs:
    - name: requestId
      type: uint256
    - name: controller
      type: address

  outputs:
    - name: shares
      type: uint256
```

#### claimCancelRedeemRequest

Claims the redeem cancelation Request with `requestId` and `controller`.

Transfers `assets` to `receiver`.

`controller` MUST equal `msg.sender` unless the `controller` has approved the `msg.sender` as an operator.

MUST emit the `ClaimCancelRedeemRequest` event.

```yaml
- name: claimCancelRedeemRequest
  type: function
  stateMutability: nonpayable

  inputs:
    - name: requestId
      type: uint256
    - name: receiver
      type: address
    - name: owner
      type: address
  outputs:
```

### Events

#### CancelDepositRequest

`controller` has requested cancelation of their deposit Request with request ID `requestId`. `sender` is the caller of the `cancelDepositRequest` which may not be equal to the `controller`.

MUST be emitted when a deposit cancelation Request is submitted using the `cancelDepositRequest` method.

```yaml
- name: CancelDepositRequest
  type: event

  inputs:
    - name: controller
      indexed: true
      type: address
    - name: requestId
      indexed: true
      type: uint256
    - name: sender
      indexed: false
      type: address
```

#### CancelDepositClaim

`controller` has claimed their deposit cancelation Request with request ID `requestId`. `receiver` is the destination of the `assets`. `sender` is the caller of the `claimCancelDepositRequest` which may not be equal to the `controller`.

MUST be emitted when a deposit cancelation Request is submitted using the `claimCancelDepositRequest` method.

```yaml
- name: CancelDepositClaim
  type: event

  inputs:
    - name: controller
      indexed: true
      type: address
    - name: receiver
      indexed: true
      type: address
    - name: requestId
      indexed: true
      type: uint256
    - name: sender
      indexed: false
      type: address
    - name: assets
      indexed: false
      type: uint256
```

#### CancelRedeemRequest

`controller` has requested cancelation of their deposit Request with request ID `requestId`. `sender` is the caller of the `cancelRedeemRequest` which may not be equal to the `controller`.

MUST be emitted when a deposit cancelation Request is submitted using the `cancelRedeemRequest` method.

```yaml
- name: CancelRedeemRequest
  type: event

  inputs:
    - name: controller
      indexed: true
      type: address
    - name: requestId
      indexed: true
      type: uint256
    - name: sender
      indexed: false
      type: address
```

#### CancelRedeemClaim

`controller` has claimed their redeem cancelation Request with request ID `requestId`. `receiver` is the destination of the `shares`. `sender` is the caller of the `claimCancelRedeemRequest` which may not be equal to the `controller`.

MUST be emitted when a redeem cancelation Request is submitted using the `claimCancelRedeemRequest` method.

```yaml
- name: CancelRedeemClaim
  type: event

  inputs:
    - name: controller
      indexed: true
      type: address
    - name: receiver
      indexed: true
      type: address
    - name: requestId
      indexed: true
      type: uint256
    - name: sender
      indexed: false
      type: address
    - name: shares
      indexed: false
      type: uint256
```

### [ERC-165](./eip-165.md) support

Smart contracts implementing this Vault standard MUST implement the [ERC-165](./eip-165.md) `supportsInterface` function.

Asynchronous deposit Vaults with cancelation support MUST return the constant value `true` if `0x8bf840e3` is passed through the `interfaceID` argument.

Asynchronous redemption Vaults with cancelation support MUST return the constant value `true` if `0xe76cffc7` is passed through the `interfaceID` argument.

## Backwards Compatibility

The interface is fully backwards compatible with [ERC-7540](./eip-7540.md).

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
