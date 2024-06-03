---
eip: x
title: Readable Typed Signatures for Smart Accounts
description: Nested typed data structure for readable replay-safe signatures
author: vectorized (@vectorized), Sihoon Lee (@push0ebp), Francisco Giordano (@frangio), Im, Juno (@junomonster), howydev (@howydev), 0xcuriousapple (0xcuriousapple)
discussions-to: https://ethereum-magicians.org/t/readable-typed-signatures-for-smart-accounts
status: Draft
type: Standards Track
category: ERC
created: 2024-05-28
requires: 712, 1271
---

## Abstract

This proposal defines a nested [EIP-712](./eip-712.md) typed structure and wrapped signature scheme for [ERC-1271](./erc-1271.md) verification. 

It prevents signature replays when multiple smart accounts are owned by a single Externally Owned Account (EOA), while allowing signed contents to be readable during signature requests.

## Motivation

Smart accounts can verify signatures with via [ERC-1271](./erc-1271.md) using the `isValidSignature` function.

```solidity
function isValidSignature(
    bytes32 hash,
    bytes calldata signature
) external override view returns (bytes4) {
    if (ECDSA.recover(hash, signature) == owner) {
        return 0x1626ba7e;
    } else {
        return 0xffffffff;
    }
}
```

This straightforward implementation allows signatures to be replayed.

This can be prevented if the application contract that calls `isValidSignature` incorporates the address of the smart account into `hash`. Unfortunately, many popular applications (e.g. Permit2) do not do this.

Hence, many major smart account implementations perform defensive rehashing: the hash is rehashed on the smart account to incorporate its own address into the final hash to be verified. 

Existing approaches either include a simple form of [EIP-712](./eip-712.md), or a non-standard `keccak256(abi.encode(hash, address(this), ...))`. This suffice to prevent replays, but it makes the contents of the final hash opaque during the signature request.

Standardizing the defensive rehashing scheme will offer the following benefits:
- Coordinate integration efforts across smart accounts.
- Preventing ecosystem fragmentation in the rehashing schemes, thus improving developer and user experience.
- Provide a well-tested and peer-reviewed reference implementation with minimal compromises.

To promote account abstraction without ecosystem fragmentation, this proposal is crafted with the following objectives:

- Supported by all wallet clients that already supports [EIP-712](./eip-712.md).
- Implementable with smart account code and frontend JavaScript code. Browser plugins can be developed to inject JavaScript to wrap the signatures accordingly in a wallet client agnostic way.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

## Typed Data Sign Workflow 

<!-- Structure Definition and Signature Wrapping Scheme -->

## Personal Sign Workflow 

<!-- Structure Definition -->



TBD.

## Backwards Compatibility

TBD.

## Reference Implementation

TBD.

## Security Considerations

TBD.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
