---
eip: XXXX
title: Cross Rollup Links
description: An identifier for uniquely identifying the source of a cross rollup input and corresponding shared settlement mechanism.
author: Bo Du (@notbdu), Ian Norden (@i-norden)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2025-10-14
---

## Abstract

A cross rollup input identifier contains information that uniquely identifies its source or origin.

This informs the underlying native or non native proof system which transactions contain cross rollup inputs that need to be verified.

This ERC does not cover messaging mechanics (e.g. push or pull) or attempt to establish a messaging interface. It aims to be flexible enough that any form of interoperability UX can be applied on top.

The identifier format for cross rollup inputs should be agnostic to the rollup framework, proof system and messaging mechanics used. 

We propose using a pointer to a generic log or event emitted on the origin rollup as an identifier. These pointers form "cross rollup links" which can be cryptographically linked to the block headers of communicating rollups and validated at settlement time.

## Motivation

Currently, there is no standard way for different rollup frameworks to: 

- Specify which transactions contain cross rollup inputs.
- Verify that the source of a cross rollup input is valid.

This means that different rollup stacks today cannot settle cross rollup transactions together on the L1.

Settlement time validation of cross rollup inputs in a rollup cluster means that intra-cluster interoperability becomes fully trust-minimized. This would enable rollups of different rollup frameworks to join or leave the clusters they want to share fast trust-minimized communication with. 

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Identifier

The `Identifier` specification below borrows heavily from Optimism's [message identifier](https://github.com/ethereum-optimism/specs/blob/main/specs/interop/messaging.md#message-identifier) format. It uniquely identifies a log emitted on the origin rollup.

The `Identifier` is able to be cryptographically linked to the block header produced by communicating rollups (and the L1). The creation of an `Identifier` creates a "cross rollup link" between the execution of the origin and the destination rollup. This cross rollup link can either be pessimistically or optimistically validated depending on the type of proof system used.

```solidity
struct Identifier {
    address origin;
    uint256 blocknumber;
    uint256 transactionIndex;
    uint256 logIndex;
    uint256 chainid;
}
```

| Name          | Type      | Description                                                                     |
|---------------|-----------|---------------------------------------------------------------------------------|
| `origin`      | `address` | Account that emits the log                                                      |
| `blocknumber` | `uint256` | Block number in which the log was emitted                                       |
| `txIndex`     | `uint256` | The index of the transaction in the array of all transactions in the block      |
| `logIndex`    | `uint256` | The index of the log in the array of all logs emitted in the transaction        |
| `chainid`     | `uint256` | The chain id of the rollup that emitted the log                                  |


### Settlement

Rollup frameworks are then expected to use this information at settlement time to validate all cross rollup inputs. This means that we now introduce a dependency of a single rollup STF on the STF of communicating rollups in a cluster. There are two general approaches for implementing this cross rollup dependency - shared or chained settlement.

[shared_or_chained_settlement](../assets/erc-XXX/shared_or_chained_settlement.png)

Shared settlement means:
- All rollups in a cluster share the same L1 bridge.
- The result of all rollup STFs is proposed at the same time including proofs for all cross rollup links. 
    - Validation of individual STFs and cross rollup links occurs at the same time.

Chained settlement means:
- All rollups in a cluster do not share the same L1 bridge.
- The result of an individual rollup STF is proposed to its own bridge along with a list of unvalidated cross rollup links.
- The final validation of the individual rollup STF is now pending the final validation of all cross rollup links pending validation.

## Rationale




## Backwards Compatibility


## Security Considerations


## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
