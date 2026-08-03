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
{
  "sendPacked(bytes data)": {
    "fields": [
        {
        "path": "data",
        "layout": {
          "type": "object",
          "fields": [
              { "name": "to",     "schema": { "type": "address" } },
              { "name": "amount", "schema": { "type": "uint", "bytes": 32 } }
            ]
          }
        }
      ]
    }
}
```

Every `layout` node consumes a well-defined, computable number of bytes from its buffer.
The `switch`'s path-sourced form is an exception as it reads an already-resolved value instead of parsing bytes.

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

An `object`'s field entries may carry `format`,`params`, `label` and `schema` parameters.
This allows a packed field to declare how it should be displayed using relative paths to that object's own sibling members.

```json
{ "name": "callData", "schema": { "type": "bytes" }, "label": "Execution", "format": "calldata",
  "params": { "calleePath": "target", "amountPath": "value" } }
```

### `bitfield`

A fixed-width value whose individual bits or bit ranges each carry independent, named meaning – unlike `object`, whose fields are always byte-aligned and never overlap.

```json
{ "type": "bitfield", "bytes": 20, "fields": [
  { "name": "beforeSwap", "bit": 7 },
  { "name": "poolId",     "bits": [19, 8] }
]}
```

Each entry is either `{name, bit}` (a single flag, decoded as `bool`) or `{name, bits: [hi, lo]}` (an inclusive bit range, decoded as an unsigned integer).

### `switch`

The mechanism that allows the decoding to choose the format based on a certain parameter decoded previously. Represents a common pattern of carrying the decoding format flag separately form the data being decoded.

```json
{ "execute(uint8 kind,bytes data)": {
  "fields": [
    { "path": "data", "switch": {
      "expression": { "path": "kind" },
      "cases": {
        "0x00": { "(address to,uint256 amount)": {
          "fields": [
            { "path": "to",     "label": "To" },
            { "path": "amount", "label": "Amount" }
          ]
        }},
        "0x01": { "(address from,address to,uint256 amount,uint256 deadline)": {
          "fields": [
            { "path": "from",     "label": "From" },
            { "path": "to",       "label": "To" },
            { "path": "amount",   "label": "Amount" },
            { "path": "deadline", "label": "Deadline", "format": "date", "params": { "encoding": "timestamp" } }
          ]
        }}
      }
    }}
  ]
}}
```

When a `switch` case's tuple resolves to an array (`(...)[]`), its own `fields` can address that array's elements with `.[]` in place of the missing array name, e.g. `.[].callData`.
`#.` inside a case's own `fields` still resolves against the absolute root of the structured data.

`switch` can also appear as a `layout` node instead of a field-level key:

```json
{ "exampleCall(uint256 outputReference)": {
      "fields": [
        { "path": "outputReference", "label": "Save result as", "layout": {
          "type": "switch",
          "expression": { "type": "uint", "bytes": 32, "mask": "0xfff0000000000000000000000000000000000000000000000000000000000000" },
          "cases": {
            "0xba10000000000000000000000000000000000000000000000000000000000000": { "label": "Set by an earlier step, not known yet", "intent": "info" },
            "$default": { "format": "raw" }
          }
        }}
      ]
  }
}
```

`mask` is available on any `switch` expression and is applied to the raw value before matching `cases`.
It lets a dispatch tag share space with unrelated bits, as with `UniversalRouter`'s revert-allowed flag in the Test Case below.

Inside a `layout` tree, `switch`'s inline form may also use `payloadFrom` in place of `$index`, naming a sibling ABI-decoded array to read at the same index as the enclosing `sequence` element.

### `operation`

An optional parameter for the ERC-7730's `format: "calldata"` record.
Allow specifying the actual EVM operation used when executing the call.
Supported values are:

1. CALL
2. DELEGATECALL
3. CREATE
4. CREATE2
5. CALLCODE (legacy opcode)

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

A wallet MUST resolve the matched target's own `intent`/`interpolatedIntent`/`fields` using the bound `args` values in place of that target's own decoded parameters, applying the same unknown-selector fallback if `to`'s descriptor has no entry matching `signature`.

A [structured data format specification](./erc-7730.md) MAY declare a top-level `switch` in place of `intent`/`fields`, redirecting the entire call to a different, unrelated function via `interaction` based on one of its own decoded parameters.

### `$index`

A mechanism for element in a `sequence` to reference their position for indexing into other `sequence` or array-like parameters.

```json
{ "execute(bytes commands,bytes[] inputs)": {
  "fields": [
    { "path": "commands", "layout": { "type": "sequence", "element": { "type": "uint", "bytes": 1 } } },
    { "path": "inputs[]", "switch": {
      "expression": { "path": "commands[$index]" },
      "cases": {
        "0x00": { "(address to)": {
          "fields": [
            { "path": "to", "label": "To" }
          ]
        }}
      }
    }}
  ]
}}
```
## Test Cases

### Safe{Wallet} - `MultiSend` Contract

The `MultiSend` contract encodes the data in the following format:

```
/**
* @notice Sends multiple transactions and reverts all if one fails.
* @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of:
*                     1. _operation_ as a {uint8}, 0 for a `CALL` or 1 for a `DELEGATECALL` (=> 1 byte),
*                     2. _to_ as an {address} (=> 20 bytes),
*                     3. _value_ as a {uint256} (=> 32 bytes),
*                     4. _data_ length as a {uint256} (=> 32 bytes),
*                     5. _data_ as {bytes}.
function multiSend(bytes memory transactions) public payable;
*/
```
#### What makes this encoding unusual
1. The `transactions` count is not provided at all - the code has to iteratively decode the entire data array until it is exhausted.
2. The `data` field has a dynamic size that is specified as a separate sibling parameter.

Using ERC-0000, this input can easily be described for Clear Singing – see [MultiSend Example](../assets/erc-non-abi-dispatch/example-safe-multisend.json).

### Uniswap v4 - `UniversalRouter` Contract

The `UniversalRouter` contract encodes the data in the following format:

```
/// @notice Executes encoded commands along with provided inputs. Reverts if deadline has expired.
/// @param commands A set of concatenated commands, each 1 byte in length
/// @param inputs An array of byte strings containing abi encoded inputs for each command
/// @param deadline The deadline by which the transaction must be executed
function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
```

#### What makes this encoding unusual

1. `commands` is not an ABI `bytes[]` or `uint8[]` – it is a `bytes` value packed with one `command id` byte, decoded as a `sequence` until the input is exhausted, exactly like the `runCommands` example above.
2. Each command byte also carries a flag in its high bit (`0x80`/`0b10000000`, "allow this command to revert") alongside the actual `command id` in its low 6 bits (`0x3f`/`0b00111111`), so the extracted value must be masked before it can be matched against a `cases` table.
3. `inputs` is a regular ABI `bytes[]`, but the ABI type of `inputs[i]` is only known by decoding `commands[i]` – the format of one array must be resolved by indexing into a **sibling array** at the same position, which is the `$index` mechanism described above.

Using ERC-0000, this input can be described for Clear Signing – see [Universal Router Example](../assets/erc-non-abi-dispatch/example-universal-router.json).

### ERC-7579 `execute` function

The [ERC-7579](./erc-7579.md) `execute` function, which encodes the data in the following format:


| CallType | ExecType | Unused  | ModeSelector | ModePayload |
| -------- | -------- | ------- | ------------ | ----------- |
| 1 byte   | 1 byte   | 4 bytes | 4 bytes      | 22 bytes    |

```solidity
function execute(bytes32 mode, bytes calldata executionCalldata) external payable;
```

The `mode` value determines how `executionCalldata` itself must be decoded:
- `CALLTYPE = 0x00` (single call): `executionCalldata` is `abi.encodePacked(target, value, callData)`.
- `CALLTYPE = 0x01` (batch call): `executionCalldata` is a regularly ABI-encoded `Execution(address target, uint256 value, bytes callData)[]`.
- `CALLTYPE = 0xff` (delegatecall): `executionCalldata` is `abi.encodePacked(target, callData)`, with **no `value` field**.

#### What makes this encoding unusual

1. `mode` is a single `bytes32` packed with five sub-fields of uneven, non-32-byte-aligned widths (1/1/4/4/22 bytes).
2. The format of the second parameter, `executionCalldata`, is dependent on the first byte of the first parameter, `mode` – similar to the pattern used by `UniversalRouter`, but more complicated since the indication is a single byte inside a fixed-size `bytes32` rather than a whole named parameter.
3. The three `CALLTYPE`s are not just different tuples of the same shape – `single` and `delegatecall` use packed encoding, with no `value` field for `delegatecall`, while `batch` uses standard padded ABI encoding of a struct array, so `executionCalldata` decoding changes shape entirely between cases.

Using ERC-0000, this input can be described for Clear Signing – see [ERC-7579 Execute Example](../assets/erc-non-abi-dispatch/example-erc7579-execute.json).

### Balancer Relayer `joinPool`/`exitPool`

The `BatchRelayerLibrary` contract reached via `BalancerRelayer.multicall` encodes pool-kind and per-action metadata as sibling ABI parameters, then encodes a *second*, independent tag inside `userData` itself:

```solidity
enum PoolKind { WEIGHTED, LEGACY_STABLE, COMPOSABLE_STABLE, COMPOSABLE_STABLE_V2 }

function joinPool(bytes32 poolId, PoolKind kind, address sender, address recipient,
  IVault.JoinPoolRequest memory request, uint256 value, uint256 outputReference) external payable;

function exitPool(bytes32 poolId, PoolKind kind, address sender, address payable recipient,
  IVault.ExitPoolRequest memory request, OutputReference[] calldata outputReferences) external payable;
```

#### What makes this encoding unusual

1. `BalancerRelayer.multicall(bytes[] data)` always `DELEGATECALL`s every batched element into one fixed library address – unlike `MultiSend`, there is no per-element operation or target choice, only the embedded call itself needs resolving.
2. `request.userData`'s meaning is tag-dispatched twice: once by `kind` (a sibling parameter of `joinPool`/`exitPool` itself), then again by a `JoinKind`/`ExitKind` enum read from `userData`'s own first 32 bytes – a `switch` nested inside a `switch`.
3. The same already-ABI-decoded `uint256` fields (`maxAmountsIn[i]`, `outputReference`, `bptAmountIn`) can be either a literal amount or a "chained reference" – a placeholder for a value only known once an earlier step in the same batched transaction has actually executed on-chain – distinguished purely by masking the value's own high bits, not by a separate tag field.

Using ERC-0000, this input can be described for Clear Signing – see [Balancer Relayer Multicall Example](../assets/erc-non-abi-dispatch/example-balancer-relayer-multicall.json) and [Balancer Relayer Library Example](../assets/erc-non-abi-dispatch/example-balancer-relayer-library.json).

### ERC-7683 `open`

The `AcrossOriginSettler` contract encodes the data in the following format:

```solidity
struct OnchainCrossChainOrder {
    uint32 fillDeadline;
    bytes32 orderDataType;
    bytes orderData;
}

function open(OnchainCrossChainOrder calldata order) external;
```

#### What makes this encoding unusual

1. `orderData`'s ABI type is selected by `orderDataType`, a `bytes32` equal to the `keccak256` hash of the target tuple's own Solidity type string (`keccak256("AcrossOrderData(address inputToken,...)")`) rather than a small, contract-defined enum – an open-ended, hash-keyed dispatch.
2. Both the tag and the payload are already plain sibling ABI parameters of `open` itself, so no `layout` node is needed – only `switch`.

Using ERC-0000, this input can be described for Clear Signing – see [ERC-7683 Order Example](../assets/erc-non-abi-dispatch/example-erc7683-order.json).

### `TieredExecutor` (artificial illustrative example)

The `TieredExecutor` contract encodes the data in the following format:

```solidity
enum Operation { None, GrantReward, CreditLegacy }

function executeOperation(address target, Operation op, address account, uint256 amount) external;
```

#### What makes this encoding unusual

1. `executeOperation` has no fixed meaning of its own at all – the entire call exists only to be redirected, and which target function it becomes requires a top-level `switch` instead of an ordinary `intent`/`fields` pair.
2. `account`/`amount` are generic-looking arguments with no inherent semantics – depending on `op`, they are bound to two unrelated target interfaces with a **different parameter order** via `interaction` rather than `format: "calldata"`. There is no contiguous calldata blob to slice out, only already-decoded values that need to be reassembled.
3. This contract is illustrative only, written for this ERC and not deployed anywhere.

Using ERC-0000, this input can be described for Clear Signing – see [TieredExecutor Example](../assets/erc-non-abi-dispatch/example-tiered-executor.json).

## Rationale

## Security Considerations

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
