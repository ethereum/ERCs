---
eip: XXXX
title: Verifiable Cross Rollup Links
description: Identifiers for verifying the source of cross rollup inputs and corresponding shared settlement mechanisms.
author: Bo Du (@notbdu), Ian Norden (@i-norden)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2025-01-23
---

## Abstract

Interoperability between Ethereum rollups should be ultimately secured by the L1. This means that cross rollup transactions need to be verifiable at settlement time.

We propose cross rollup input identifiers that contain information uniquely identifying its source or origin.

This informs the underlying native or non native proof system which transactions contain cross rollup inputs that need to be verified.

This ERC does not cover messaging mechanics (e.g. push or pull) or attempt to establish a messaging interface. It aims to be flexible enough that any form of interoperability UX can be applied on top.

The identifier format for cross rollup inputs should be agnostic to the rollup framework, proof system and messaging mechanics used. 

We propose using a pointer to a generic log or event emitted on the origin rollup or a storage key as an identifier. These pointers form "cross rollup links" which can be cryptographically linked to the block headers of communicating rollups and validated at settlement time.

## Motivation

Currently, there is no standard way for different rollup frameworks to: 

- Specify which transactions contain cross rollup inputs.
- Verify that the source of a cross rollup input is valid.

This means that different rollup stacks today cannot settle cross rollup transactions together on the L1.

Settlement time validation of cross rollup inputs in a rollup cluster means that intra-cluster interoperability becomes fully trust-minimized. This would enable rollups of different rollup frameworks to join or leave the clusters they want to share fast trust-minimized communication with. 

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Identifiers

The `LogIdentifier` specification below borrows heavily from Optimism's [message identifier](https://github.com/ethereum-optimism/specs/blob/main/specs/interop/messaging.md#message-identifier) format. It uniquely identifies a log emitted on the origin rollup.

Both identifiers should be verifiable by cryptographically linking them to the execution results (e.g. block header) produced by communicating rollups (and the L1). The creation of either identifier creates a "cross rollup link" between the execution of the origin and the destination rollup. This cross rollup link can either be pessimistically or optimistically validated depending on the type of proof system used.

```solidity
struct LogIdentifier {
    uint256 chainid;
    uint256 blocknumber;
    address account;
    uint256 txIndex;
    uint256 logIndex;
}
```

| Name          | Type      | Description                                                                     |
|---------------|-----------|---------------------------------------------------------------------------------|
| `chainid`     | `uint256` | The chain id of the rollup that emitted the log                                 |
| `blocknumber` | `uint256` | Block number in which the log was emitted                                       |
| `account`     | `address` | Account that emits the log                                                      |
| `txIndex`     | `uint256` | The index of the transaction in the array of all transactions in the block      |
| `logIndex`    | `uint256` | The index of the log in the array of all logs emitted in the transaction        |


```solidity
struct StorageIdentifier {
    uint256 chainid;
    address origin;
    uint256 blocknumber;
    bytes32 storageKey;
}
```

| Name          | Type      | Description                                                                     |
|---------------|-----------|---------------------------------------------------------------------------------|
| `chainid`     | `uint256` | The chain id of the rollup with the specified storage key                       |
| `blocknumber` | `uint256` | Block number in which the log was emitted                                       |
| `account`     | `address` | Account that emits the log                                                      |
| `storagekey`  | `bytes32` | The key in the state tree of a rollup                                           |

The value of either log or storage identifiers is a opaque `byte` payload which is considered a validated cross chain input after the identifier is checked.

Note that `LogIdentifier` is better suited for intra block interoperability due to `StorageIdentifier` requiring intra block state roots which most execution environments do not provide (this greatly increases execution overhead).

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

We include both log and storage identifiers which cover two types of execution results - ephemeral and persistent. Logs are ephemeral execution results since they are tied to the transaction and specific block. Storage writes are persistent execution results since they are persisted to disk and across blocks.

Additionally, only fields that contribute to the verifiability of the source of the cross rollup input are included. Fields that inform messaging mechanics such as `destinationChainId` (e.g. p2p vs. broadcast) are intentionally left out.

Both a transaction index and a log index are included in the `LogIdentifier` due to increased indexing requirements to determine a block level log index. 

## Backwards Compatibility

Exsiting rollup framework settlement mechanism's execution result contains a state root and addiional information. This ERC proposes that the execution results be extended to include unvalidated "cross rollup links" that must be matched to a valid origin or source.

## Security Considerations

The security of the underlying proof systems determine how secure cross rollup communication is. Within a rollup cluster, communication is as secure as the settlement mechanism of the most insecure rollup.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
