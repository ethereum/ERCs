---
eip: xxxx
title: Universal Account Recovery Standard (UARS)
description: A standard method to recover a smart account ownership.
author: Artem Chystiakov (@arvolear) <artem@rarilabs.com>
discussions-to: https://ethereum-magicians.org/t/eip-xxxx-universal-account-recovery-standard-uars/24080
status: Draft
type: Standards Track
category: ERC
created: 2025-05-07
---

## Abstract

Introduce a universal account abstraction recovery mechanism `recoverOwnership(newOwner, provider, proof)` along with recovery provider management functions for smart accounts to securely update their owner.

## Motivation

Account abstraction and the "contractization" of EOAs are important Ethereum milestones for improving on-chain UX and off-chain security. A wide range of smart accounts emerge daily, aiming to simplify the steep onboarding curve for new users. The ultimate smart account experience is to never ask them to deal with private keys, yet still allow for full account control and ownership recovery. With the developments in the ZKAI and ZK2FA fields, settling on a common mechanism may even open the doors for "account recovery provider marketplaces" to emerge.

The UARS aims to define a flexible interface for *any* smart account to implement, allowing users to actively manage their account recovery providers and restore the ownership of an account in case of a private key loss.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

A smart account willing to support UARS MUST implement the following interface:

```solidity
pragma solidity ^0.8.20;

/**
 * @notice Defines a common account recovery interface for smart accounts to implement.
 */
interface IAccountRecovery {
    /**
     * MUST be emitted in the `recoverOwnership` function upon successful recovery.
     */
    event OwnershipRecovered(address indexed oldOwner, address indexed newOwner);
    
    /**
     * MUST be emitted in the `addRecoveryProvider` function.
     */
    event RecoveryProviderAdded(address indexed provider);

    /**
     * MUST be emitted in the `removeRecoveryProvider` function.
     */
    event RecoveryProviderRemoved(address indexed provider);

    // bytes4(keccak256("recoverOwnership(address,address,bytes)"))
    bytes4 internal constant MAGIC = 0x3cfb167d;

    /**
     * @notice An `onlyOwner` function to add a new recovery provider.
     * SHOULD be access controlled.
     * 
     * @param provider the address of a recovery provider (ZKP verifier) to add.
     * @param addData custom optional data for the recovery provider.
     */
    function addRecoveryProvider(address provider, bytes memory addData) external;

    /**
     * @notice An `onlyOwner` function to remove an existing recovery provider.
     * SHOULD be access controlled.
     * 
     * @param provider the address of a previously added recovery provider to remove.
     * @param removeData custom optional data for the recovery provider.
     */
    function removeRecoveryProvider(address provider, bytes memory removeData) external;

    /**
     * @notice A view function to check if a provider has been previously added.
     * 
     * @param provider the provider to check.
     * @return true if the provider exists in the account, false otherwise.
     */
    function recoveryProviderExists(address provider) external view returns (bool);

    /**
     * @notice A non-view function to recover ownership of a smart account.
     * MUST check that `provider` exists in the account or is `address(0)`.
     * MUST update the account owner to `newOwner` if `proof` verification succeeds.
     * MUST return `MAGIC` if the ownership change is successful.
     * 
     * @param newOwner the address of a new owner.
     * @param provider the address of a recovery provider.
     * @param proof an encoded proof of recovery (ZKP/ZKAI, signature, etc).
     * @return magic the `MAGIC` if recovery is successful, otherwise any other value.
     */
    function recoverOwnership(
        address newOwner,
        address provider,
        bytes memory proof
    ) external returns (bytes4 magic);
}
```

## Rationale

The UARS is expected to work with *any* account abstraction standard to allow for maximum account recovery flexibility. Whether it is [EIP-4337](./eip-4337.md) or [EIP-7702](./eip-7702.md), a particular smart account provider may support account recovery by simply implementing a common interface.

The standard does not define access control rules on `addRecoveryProvider` and `removeRecoveryProvider` functions, instead prioritizing compatibility with a variety of smart accounts. 

## Backwards Compatibility

This EIP is fully backwards compatible.

## Security Considerations

There are several security concerns to point out:

- It is up to a smart account developer to properly access control `addRecoveryProvider` and `removeRecoveryProvider` functions.
- A smart account user may be "fished" to add a malicious recovery provider to their account (a provider may be an ERC20 token in disguise). Then by calling a `recoverOwnership` function, a `proof` may be concealed as a `transfer` operation that drains a user's account.
- The `recoverOwnership` function is non-view and calling the passed `provider` may potentially have critical side-effects. 

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
