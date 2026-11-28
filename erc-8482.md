---
eip: 8482
title: Autonomous Self-Refunding Merchant Settlement
description: A non-custodial smart contract checkout standard that enforces atomic settlement and autonomous self-refunds for underpaid or expired invoices.
author: Lambert Van Sittert (@Lambertvs)
discussions-to: https://ethereum-magicians.org/t/erc-8482-autonomous-self-refunding-merchant-settlement/30162
status: Draft
type: Standards Track
category: ERC
created: 2026-11-01
requires: 20
---

## Abstract

This standard defines a trustless, non-custodial merchant settlement interface and architecture. Current cryptocurrency payment gateways (e.g., BVNK, BitPay) instruct payers to transfer ERC-20/TRC-20 tokens directly to raw unmonitored external addresses. When an underpayment or fee shortfall occurs, centralized sweepers absorb funds into proprietary corporate master vaults while backend webhooks flag orders as incomplete, trapping payer funds with zero protocol-level remediation.

This ERC specifies an immutable escrow and checkout contract interface where:

1. Invoices settle atomically upon exact or cumulative payment;
2. Underpaid funds remain locked in smart contract escrow with zero merchant custody; and
3. Payers can autonomously trigger a deterministic refund upon expiration without merchant consent or intermediary intervention.

## Motivation

Retail consumers and merchants are currently forced to rely on centralized payment processors that operate as opaque financial black boxes:

- The Shortfall Trap: Network fee deductions often result in minor underpayments (e.g., 57.33 USDT received vs 64.66 USDT expected).
- Unjust Enrichment: Centralized gateways sweep underpaid tokens into multi-million dollar master vaults to preserve liquidity, while flagging orders as unfulfilled.
- Support Stonewalling: Merchants disclaim liability ("address not provided by us"), processors refuse retail consumers ("we only service B2B merchants"), and trapped funds become unallocated corporate float.

By standardizing a smart contract settlement interface, Web3 wallets (e.g., MetaMask, Trust Wallet) can warn users against sending funds to raw deposit addresses and instead mandate interactions with verifiable, self-refunding smart contract checkouts.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC_SovereignCheckout {
    enum InvoiceStatus { Active, Settled, Refunded, Cancelled }

    struct Invoice {
        bytes32 invoiceId;
        address merchant;
        address payer;
        address refundAddress;
        address token;
        uint256 expectedAmount;
        uint256 amountPaid;
        uint256 expiryTimestamp;
        InvoiceStatus status;
    }

    event InvoiceCreated(bytes32 indexed invoiceId, address indexed merchant, address indexed token, uint256 expectedAmount, uint256 expiryTimestamp);
    event PaymentReceived(bytes32 indexed invoiceId, address indexed payer, uint256 amount, uint256 totalPaid, uint256 remaining);
    event InvoiceSettled(bytes32 indexed invoiceId, address indexed merchant, uint256 totalAmount);
    event AutonomousRefundClaimed(bytes32 indexed invoiceId, address indexed recipient, uint256 amountRefunded);
    event InvoiceCancelled(bytes32 indexed invoiceId);

    function createInvoice(bytes32 invoiceId, address token, uint256 expectedAmount, uint256 durationSeconds) external;
    function payInvoice(bytes32 invoiceId, uint256 amount, address refundAddress) external;
    function claimRefund(bytes32 invoiceId) external;
    function merchantCancelAndRefund(bytes32 invoiceId) external;
}
```

### Rationale

- No Merchant Custody Before Settlement: To protect the payer, tokens deposited into the escrow MUST NOT be transferable by the merchant unless amountPaid >= expectedAmount.
- Autonomous Refund Path: The claimRefund function MUST be permissionless to allow automated keeper networks or payers to reclaim tokens immediately once block.timestamp > expiryTimestamp.

## Security Considerations

1. Reentrancy Protection: All state changes (status = Refunded, amountPaid = 0) must occur prior to token transfers following the Checks-Effects-Interactions pattern.
2. Fee-on-Transfer Tokens: If tokens with transfer fees are utilized, accounting must be based on balance differentials rather than raw parameter amounts.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
