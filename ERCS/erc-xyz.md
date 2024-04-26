---
eip: XXXX
title: ERC20 Payment reference extension
description: A minimal standard interface for ERC20 tokens allowing users to include a unique identifier (payment reference) for each transaction to help distinguish and associate payments with orders and invoices.
author: Radek Svarz (@radeksvarz)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-erc20-payment-reference-extension/19826
status: Draft
type: Standards Track
category: ERC
created: 2024-04-26
requires: 20, 165
---

## Abstract

The ERC20 token standard has become the most widely used token standard on the Ethereum network. However, it does not provide a built-in mechanism for including a payment reference (message) in token transfers. This proposal extends the existing ERC20 token standard by adding minimal methods to include a payment reference in token transfers and transferFrom operations. The addition of a payment reference can help users, merchants, and service providers to associate and reconcile individual transactions with specific orders or invoices.

## Motivation

The primary motivation for this proposal is to improve the functionality of the ERC20 token standard by providing a mechanism for including a payment reference in token transfers, similar to the traditional finance systems where payment references are commonly used to associate and reconcile transactions with specific orders, invoices or other financial records.

Currently, users and merchants who want to include a payment reference in their transactions must rely on off chain external systems or custom payment proxy implementations. In traditional finance systems, payment references are often included in wire transfers and other types of electronic payments, making it easy for users and merchants to manage and reconcile their transactions.

By extending the existing ERC20 token standard with payment reference capabilities, this proposal will help bridge the gap between traditional finance systems and the world of decentralized finance, providing a more seamless experience for users, merchants, and service providers alike.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

Any contract complying with EIP-20 when extended with this ERC, MUST implement the following interface:
```
// The EIP-165 identifier of this interface is 0xxxxxxx - to be updated once ERC number is assigned

interface IERCXXXX {

function transfer(address to, uint256 amount, bytes calldata paymentReference) external returns (bool);

function transferFrom(address from, address to, uint256 amount, bytes calldata paymentReference) external returns (bool);

event Transfer(address indexed from, address indexed to, uint256 amount, bytes indexed paymentReference);

}
```

These `transfer` and `transferFrom` functions MUST emit `Transfer` event with paymentReference parameter.

`paymentReference` parameter MAY be empty - example: `emit Transfer(From, To, amount, "");`

`paymentReference` parameter is not limited in length by design, users are motivated to keep it short by calldata and log data gas costs.

Transfers of 0 amount MUST be treated as normal transfers and fire the `Transfer` event.


## Rationale

### Parameter name

The choice to name the added parameter paymentReference was made to align with traditional banking terminology, where payment references are widely used to associate and reconcile transactions with specific orders, invoices or other financial records.

The paymentReference parameter name also helps to clearly communicate the purpose of the parameter and its role in facilitating the association and reconciliation of transactions. By adopting terminology that is well-established in the financial industry, the proposal aims to foster a greater understanding and adoption of the extended ERC20 token standard.

## Backwards Compatibility

This extension is fully backwards compatible with the existing ERC20 token standard. The new functions can be used alongside the existing transfer and transferFrom functions. Existing upgradable ERC20 tokens can be upgraded to include the new functionality without impact on the storage layout; new ERC20 tokens can choose to implement the payment reference features based on their specific needs.

ERC20 requires its `Transfer(address indexed _from, address indexed _to, uint256 _value) ` event to be emitted during transfers, thus there will be duplicitous data logged (from, to, amount) in two events.

## Security Considerations

Payment reference privacy: Including payment references in token transfers may expose sensitive information about the transaction or the parties involved. Implementers and users SHOULD carefully consider the privacy implications and ensure that payment references do not reveal sensitive information. To mitigate this risk, implementers can consider using encryption or other privacy-enhancing techniques to protect payment reference data.

Manipulation of payment references: Malicious actors might attempt to manipulate payment references to mislead users, merchants, or service providers. This can lead to:
1. **Legal risks**: The beneficiary may face legal and compliance risks if the attacker uses illicit funds, potentially impersonating or flagging the beneficiary of involvement in money laundering or other illicit activities.
  
2. **Disputes and refunds**: The user might discover they didn't make the payment, request a refund or raise a dispute, causing additional administrative work for the beneficiary.

To mitigate this risk, implementers can consider using methods to identify proper sender and to generate unique and verifiable related payment references.

## Reference Implementation

```
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

interface IERC20PaymentReference {
    /**
     * @dev Emitted when `amount` tokens are moved from one account (`from`) to
     * another (`to`) with reference (`paymentReference`).
     *
     * Note that `amount` may be zero.
     */
    event Transfer(
        address indexed from, address indexed to, uint256 amount, bytes indexed paymentReference
    );

    /**
     * @notice Moves `amount` tokens from the caller's account to `to` with `paymentReference`.
     *
     * @dev Returns a boolean value indicating whether the operation succeeded.
     *
     * MUST emit a {ERC20.Transfer} (to comply with ERC20) and this ERCS's {Transfer} event.
     */
    function transfer(address to, uint256 amount, bytes calldata paymentReference) external returns (bool);

    /**
     * @notice Moves `amount` tokens from `from` to `to` with `paymentReference` using the
     * allowance mechanism. `amount` is then deducted from the caller's allowance.
     *
     * @dev Returns a boolean value indicating whether the operation succeeded.
     *
     * MUST emit a {ERC20.Transfer} (to comply with ERC20) and this ERCS's {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount, bytes calldata paymentReference)
        external
        returns (bool);
}

/**
 * @dev Implementation of the ERC20 payment reference extension.
 */
contract ERC20PaymentReference is ERC20, IERC20PaymentReference {
    /**
     * @notice A standard ERC20 token transfer with a extra payment reference
     * @dev The underlying `transfer` function is assumed to handle the actual token transfer logic. This adds reference
     * tracking.
     * @param to The address of the recipient where the tokens will be sent.
     * @param amount The number of tokens to be transferred.
     * @param paymentReference A bytes field to include a payment reference, reference signature or other relevant data.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transfer(address to, uint256 amount, bytes calldata paymentReference) public virtual returns (bool) {
        emit Transfer(_msgSender(), to, amount, paymentReference);
        return transfer(to, amount);
    }

    /**
     * @notice A delegated token transfer with an optional payment reference
     * @dev Requires prior approval from the token owner. The underlying `transferFrom` function is assumed to handle
     * allowance and transfer logic.
     * @param from The address of the token owner who has authorized the transfer.
     * @param to The address of the recipient where the tokens will be sent.
     * @param amount The number of tokens to be transferred.
     * @param paymentReference An optional bytes field to include a payment reference, reference signature or other
     * relevant data.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 amount, bytes calldata paymentReference)
        public
        virtual
        returns (bool)
    {
        emit Transfer(from, to, amount, paymentReference);
        return transferFrom(from, to, amount);
    }
}

```

## Copyright
Copyright and related rights waived via CC0.

## Citation
Please cite this document as:
Name Radek Svarz (@radeksvarz), "ERC-XXXX: ERC20 Payment reference extension" Ethereum Improvement Proposals, no. xxxx, mmm yyyy. [Online serial]. Available: https://eips.ethereum.org/EIPS/eip-xxxx.
