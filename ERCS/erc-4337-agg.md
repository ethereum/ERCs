---
eip:
description: An account abstraction improvement proposal which enables multiple UserOperations to be authenticated using a single shared signature parameter.
title: Signature Aggregation for Account Abstraction
author: Vitalik Buterin (@vbuterin), Yoav Weiss (@yoavw), Dror Tirosh (@drortirosh), Shahaf Nacson (@shahafn), Alex Forshtat (@forshtat), Kristof Gazso (@kristofgazso), Tjaden Hess (@tjade273)
discussions-to:
status: Draft
type: Standards Track
category: ERC
created:
requires: 4337, 7562
---

## Abstract

## Motivation

## Specification

* Support aggregated signature (e.g. BLS)
* **Aggregator** - a helper contract trusted by accounts to validate an aggregated signature. Bundlers/Clients whitelist the supported aggregators.

```solidity
function handleAggregatedOps(
    UserOpsPerAggregator[] calldata opsPerAggregator,
    address payable beneficiary
);

struct UserOpsPerAggregator {
    PackedUserOperation[] userOps;
    IAggregator aggregator;
    bytes signature;
}
```

* If the account does not support signature aggregation, it MUST validate that the signature is a valid signature of the `userOpHash`, and
  SHOULD return SIG_VALIDATION_FAILED (and not revert) on signature mismatch. Any other error MUST revert.

An account that works with aggregated signature, should return its signature aggregator address in the "sigAuthorizer" return value of validateUserOp.
It MAY ignore the signature field.


* `handleAggregatedOps` can handle a batch that contains userOps of multiple aggregators (and also requests without any aggregator)
* `handleAggregatedOps` performs the same logic below as `handleOps`, but it must transfer the correct aggregator to each userOp, and also must call `validateSignatures` on each aggregator before doing all the per-account validation.


### Using Signature Aggregator

A signature aggregator exposes the following interface

```solidity
interface IAggregator {

  function validateUserOpSignature(PackedUserOperation calldata userOp)
  external view returns (bytes memory sigForUserOp);

  function aggregateSignatures(PackedUserOperation[] calldata userOps) external view returns (bytes memory aggregatesSignature);

  function validateSignatures(PackedUserOperation[] calldata userOps, bytes calldata signature) view external;
}
```

* An account signifies it uses signature aggregation returning its address from `validateUserOp`.
* During `simulateValidation`, this aggregator is returned to the bundler as part of the `aggregatorInfo` struct.
* The bundler should first accept the aggregator (aggregators must be staked. bundler should verify it is not throttled/banned)
* To accept the UserOp, the bundler must call **validateUserOpSignature()** to validate the userOp's signature.
  This method returned an alternate signature (usually empty) that should be used during bundling.
* The bundler MUST call `validateUserOp` a second time on the account with the UserOperation using that returned signature, and make sure it returns the same value.
* **aggregateSignatures()** must aggregate all UserOp signatures into a single value.
* Note that the above methods are helper methods for the bundler. The bundler MAY use a native library to perform the same validation and aggregation logic.
* **validateSignatures()** MUST validate the aggregated signature matches for all UserOperations in the array, and revert otherwise.
  This method is called on-chain by `handleOps()`

```solidity
struct AggregatorStakeInfo {
    address aggregator;
    StakeInfo stakeInfo;
}
```

The account MAY return an aggregator. See [Using Signature Aggregator](#using-signature-aggregator)

* Sort UserOps by aggregator, to create the lists of UserOps-per-aggregator.
* For each aggregator, run the aggregator-specific code to create aggregated signature, and update the UserOps


* **code: -32506** - transaction rejected because wallet specified unsupported signature aggregator
    * The `data` field SHOULD contain an `aggregator` value

## Rationale

## Backwards Compatibility

## Reference Implementation

## Security Considerations

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
