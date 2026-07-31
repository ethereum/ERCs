---
title: Custom Encoding Layout for ERC-7730
description: Format to describes any non-standard byte encodings for ERC-7730
author: Alex Forshtat (@forshtat)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-07-26
requires: 7730
---

## Abstract
## Motivation

ERC-7730 provides a rich language for decoding the calldata inputs of smart contracts on Ethereum.

In practice, there are multiple contracts in active use on Ethereum that implement alternative encoding for their inputs, and it is not possible to deprecate all of them for the purpose of promoting Clear Signing.

Instead, we can add some features to ERC-7730 that would allow us to cover the most common non-standard encodings of smart contract inputs.

## Specification


### `layout`

The main mechanism for declaring any parameter whose contents cannot be expressed using Solidity-friendly ABI-encoded data structures. 

It can also be provided to values of other formats if these represent some nested data structures.

```json
{ "sendPacked(bytes data)": {
  "fields": [
    { "path": "data", "layout": { "type": "object", "fields": [
      { "name": "to",     "schema": { "type": "address" } },
      { "name": "amount", "schema": { "type": "uint", "bytes": 32 } }
    ]}}
  ]
}}
```

### `sequence`

The mechanism for declaring an iterative, array-like data structure not represented by an ABI-encoded `array` data layout.

The elements count for `sequence` parameters is optional, and decoding may continue until the input bytes are exhausted.  

For example, for a byte array with each byte representing a different element:

```json
{ "runCommands(bytes commands)": {
  "fields": [
    { "path": "commands", "layout": { "type": "sequence", "element": { "type": "uint", "bytes": 1 } } }
  ]
}}
```

### `object`

The mechanism for declaring an entry in a `sequence` data structure that is not represented by an ABI-encoded parameter.

It can also be used as a stand-in for any other complex data structure in the formating process.

```json
{ "batchCalls(bytes transactions)": {
  "fields": [
    { "path": "transactions", "layout": { "type": "sequence", "element": { "type": "object", "fields": [
      { "name": "operation", "schema": { "type": "uint", "bytes": 1 } },
      { "name": "to",        "schema": { "type": "address" } }
    ]}}}
  ]
}}
```

### `select`

The mechanism that allows the decoding to choose the format based on a certain parameter decoded previously. Represents a common pattern of carrying the decoding format flag separately form the data being decoded.

```json
{ "execute(uint8 kind,bytes data)": {
  "fields": [
    { "path": "data", "select": {
      "expression": { "path": "kind" },
      "cases": {
        "0x00": { "abiType": "(address to,uint256 amount)" },
        "0x01": { "abiType": "(address from,address to,uint256 amount,uint256 deadline)" }
      }
    }}
  ]
}}
```

### `interaction`

The mechanism to declare that some data represents an interaction with an external contract.

This is an equivalent of `calldata` format from ERC-7730 for contracts that perform their own encoding of the calldata, or execute `delegatecall` and `staticcall` operations.

```json
{ "executeSendReward(address account,uint256 amount)": {
  "fields": [
    { "path": "account", "label": "Account" },
    { "path": "amount",  "label": "Amount" },
    { "interaction": {
        "to": "target",
        "signature": "grantReward(address,uint256)",
        "args": [ { "path": "account" }, { "path": "amount" } ] } }
  ]
}}
```

### `$index`

A mechanism for element in a `sequence` to reference their position for indexing into other `sequence` or array-like parameters.

```json
{ "execute(bytes commands,bytes[] inputs)": {
  "fields": [
    { "path": "commands", "layout": { "type": "sequence", "element": { "type": "uint", "bytes": 1 } } },
    { "path": "inputs[]", "select": {
      "expression": { "path": "commands[$index]" },
      "cases": {
        "0x00": { "abiType": "(address to)" }
      }
    }}
  ]
}}
```

## Rationale

## Security Considerations

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
