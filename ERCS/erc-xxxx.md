---
eip: <to be assigned>
title: Self-Describing Encoding for `bytes` Parameters using EIP-712 Type Selectors
description: Defines a convention for self-describing structured data in `bytes` parameters using 4-byte selectors derived from EIP-712 type strings.
author: Andrew Richardson (@awrichar)
discussions-to: https://ethereum-magicians.org/t/proposal-standardized-encoding-for-extensible-bytes-parameters-using-eip-712-type-selectors/25649
status: Draft
type: Standards Track
category: ERC
created: 2025-10-30
requires: 712
---

## Abstract

This ERC standardizes a convention for tagging ABI-encoded structures placed inside `bytes` parameters with a compact type selector derived from the EIP-712 type string.
It also defines a canonical multi-payload wrapper, allowing multiple typed payloads to be carried in a single `bytes` parameter.

## Motivation

Many smart contract methods use a `bytes` parameter to support future extensibility—including common standards such as **ERC-721** and **ERC-1155**.
The convention of carrying extra data in a `bytes` parameter was also codified further in **ERC-5750**.

In many practical cases, the `bytes` payload may encode a structured type that must be ABI-decoded before it can be processed. However:

- Different contracts use different, ad-hoc conventions for distinguishing among possible payloads.
- A single contract may need to support multiple encodings.
- In more complex workflows, a payload may be propagated across multiple contracts, each of which may need to parse it differently.

Currently, there is no standardized convention for identifying the "type" of an encoded payload, nor for supporting multiple data items in a single bytes parameter.
This ERC defines a minimal, interoperable convention for self-describing payloads that remain compatible with existing ABI tooling.

## Specification

### Terms

- **Type string** — the canonical EIP-712 type string, e.g.
  `TransferNote(bytes32 reference,string comment,uint256 deadline)`
- **Type selector (`bytes4`)** — `keccak256(typeString)[0:4]`
- **Single-payload** — a selector followed by `abi.encode` of that struct’s fields
- **Multi-payload wrapper** — `DataList(bytes[] items)`; each `items[i]` is a valid single-payload

### Single-payload encoding

- An ABI-encoded struct is prefixed with a 4-byte selector.
- The selector is defined as the first 4 bytes of the keccak256 hash of its EIP-712 type string.

```
typeSelector(T) = bytes4(keccak256(bytes(T)))
encoding = typeSelector(T) ++ abi.encode(<fields of T>)
```

Example:

```
T = "TransferNote(bytes32 reference,string comment,uint256 deadline)"
keccak256(T) = 0xf91f3a243a886588394dfd70af07dce0ca18c55e402d76152d4cb300349c9e9d
selector = 0xf91f3a24
encoding = 0xf91f3a24 ++ abi.encode(reference, comment, deadline)
```

A consumer may look for a known selector before attempting to decode the data, and can easily distinguish between multiple different payloads that it knows how to accept.

### Multi-payload wrapper

- Uses a canonical wrapper type `DataList(bytes[] items)` with selector `0xae74f986`.
- Each element in the items array is itself a single-struct payload (with its own selector).

```
DataList(bytes[] items)
selector(DataList) = bytes4(keccak256("DataList(bytes[] items)")) = 0xae74f986
encoding = 0xae74f986 ++ abi.encode(items)
```

Each `items[i]` MUST be a valid single-payload as above.
Consumers can look for this well-known selector, and can then decode the list to be scanned recursively for recognized items.

### Decoding

- Read the first 4 bytes as the **selector**.
- If the selector is `0xae74f986`, decode the remainder as `(bytes[] items)` and parse each item recursively.
- If the selector is another recognized selector, the remainder should be parsed accordingly.
- Unknown selectors MUST be ignored.
- Order is not significant; producers SHOULD avoid duplicates.

## Rationale

- **EIP-712 reuse:** avoids new schema syntax and aligns with the signing ecosystem.
- **4-byte selectors:** mirror Solidity’s function selector convention for compactness.
- **Simple wrapper:** `DataList` provides multiplexing without special parsing or new ABI rules.

## Backwards Compatibility

Existing contracts that already accept arbitrary `bytes` remain compatible. Contracts unaware of this ERC can continue to treat the payload as opaque.

## Security Considerations

- **Payload bounds:** When parsing `DataList`, consumers SHOULD limit `items.length` and total payload size (for example ≤ 8 items and ≤ 8 KB).
- **Early exit:** Consumers SHOULD stop scanning once all expected selectors are found.
- **Unknown data:** Unrecognized items MUST be ignored safely.

## References

- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-5750: General Extensibility for Method Behaviors](https://eips.ethereum.org/EIPS/eip-5750)
- [ERC-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)
- [ERC-1155: Multi Token Standard](https://eips.ethereum.org/EIPS/eip-1155)

## Copyright

Copyright and related rights waived via [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/).
