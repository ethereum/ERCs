---
title: Non-ABI Encoded Fields for ERC-7730
description: Describes packed, bit-packed, and tag-dispatched byte encodings inside ERC-7730 fields that are not plain Solidity ABI
author: TBD
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-07-26
requires: 7730
---

## Abstract

[ERC-7730](./erc-7730.md) describes how to clear-sign structured data by decoding calldata as a Solidity ABI function call, then formatting the resulting named fields. This works as long as every value in the call is itself ABI-encoded. It breaks down for a common and growing class of contracts that accept one ABI-encoded `bytes` (or `bytes[]`) argument and then interpret its raw content using their own private encoding — packed structs, bit-packed flags, or a tag that selects one of several possible payload shapes. Gnosis Safe's `MultiSend`, Uniswap's Universal Router and hook addresses, and ERC-7579 modular accounts all do this, and none of it can be described in ERC-7730 today; such fields must be left as opaque, unreadable bytes. It also breaks down entirely for contract-creation calls, which have no function selector at all — a real, common, security-critical transaction type ERC-7730 has no vocabulary for.

This ERC adds two new keys to an ERC-7730 [field format specification](./erc-7730.md#field-format-specification) — `layout` and `dispatch` — that let an author describe the internal structure of such a field and, where the field's shape depends on a tag value, which structure applies. It also adds a reserved `$fallback` key to `display.formats` for contracts that dispatch with no selector at all. Everything else about ERC-7730 (context binding, metadata, top-level selector matching, path syntax) is unchanged; this ERC only extends what a single field's `path` can resolve into, and how a contract's entry point is matched in the first place.

## Motivation

Look at what a `display.formats` entry can describe today: a Solidity function signature, decoded with the standard ABI rules, giving named parameters that `fields` entries point `path` at. That covers the overwhelming majority of contract calls. It does not cover contracts whose calldata carries a second, private encoding layer inside one of those ABI parameters:

- **Safe's `MultiSend.multiSend(bytes transactions)`** — `transactions` is not ABI-encoded. It is a tightly packed, back-to-back sequence of `(operation, to, value, dataLength, data)` records, repeated until the buffer runs out. Each record's own `data` is, in turn, a normal call to some other contract.
- **Uniswap's Universal Router `execute(bytes commands, bytes[] inputs)`** — `commands` is one raw opcode byte per sub-action (with a flag bit for "allowed to revert"); `inputs[i]` is separately ABI-encoded, but *which* ABI type it decodes as depends on the opcode at `commands[i]`.
- **ERC-7579 modular accounts, `execute(bytes32 mode, bytes executionCalldata)`** — `mode` packs five sub-fields into one word; `executionCalldata`'s shape (a single packed call, or an ABI-encoded array of calls) depends on one byte of `mode`.
- **Uniswap v4 hook addresses** — up to 14 independent permission flags (`beforeSwap`, `afterSwap`, and others) live in specific low-order bits of the 160-bit hook address itself; the same address value is simultaneously "an address" and "a bitmask," with no byte alignment between the two meanings.
- **Contract-creation transactions** — a `CREATE`/`CREATE2` deployment, or a generic deterministic-deployment factory taking raw bytecode as an argument, has no function selector at all. There is nothing for ERC-7730's selector-matching to match against, and no vocabulary for describing constructor arguments appended to, or embedded within, compiler-specific creation bytecode.

None of this is exotic or rare. It is how batching, modular accounts, and generic-purpose routers already work across the ecosystem, and account-abstraction adoption is only going to produce more of it. A wallet with no way to describe these fields has no way to clear-sign them beyond showing raw hex — which is exactly the blind, trust-me signing experience ERC-7730 exists to eliminate.

The goal here is narrow on purpose. This ERC does not attempt to become a general-purpose binary serialization language (no attempt is made to describe Protobuf, Borsh, or arbitrary custom formats in full generality). It describes exactly the small set of shapes observed in real, widely used contracts: fixed-width packed fields, repeated records read until the buffer ends, and tag-selected payload types. Constructs are added because a real case needs them, not because they might be useful someday.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This ERC defines two additional keys usable in an ERC-7730 [field format specification](./erc-7730.md#field-format-specification): `layout` and `dispatch`. A field format specification MUST NOT combine `layout` with `format`; the two are alternative ways of turning a field's raw value into something displayable, and `layout` takes over that job entirely for the field it is attached to. `dispatch` MAY be combined with either, since it only decides *which* `layout` or ABI type governs a field — it does not itself produce a displayable value.

### `layout`

`layout` describes the internal byte structure of a `bytes` field. Its value is a *layout node*. A layout node is one of the following kinds:

**Primitive nodes**

```json
{ "kind": "uint", "bytes": 1, "endian": "be" }
{ "kind": "bytes", "length": 20 }
{ "kind": "address" }
{ "kind": "bool" }
```

`uint.bytes` is the width in bytes (1, 2, 4, 8, 16, or 32). `endian` is `"be"` or `"le"`, defaulting to `"be"` — every known EVM-side use case packs data big-endian, matching Solidity's own word layout; `"le"` exists only so this vocabulary does not need to change if a future non-EVM companion reuses it. `address` is sugar for a 20-byte `bytes` node. `bytes.length` MAY be a fixed integer, a `lengthFrom` reference to an earlier sibling field's decoded value (see `struct` below), or omitted entirely on the last field of a `struct`, meaning "consume whatever bytes remain in the enclosing buffer."

**`bitfield`** — a fixed-width value (same width rules as `uint`) whose individual bits or bit ranges each carry independent, named meaning:

```json
{ "kind": "bitfield", "bytes": 20, "endian": "be", "fields": [
  { "name": "beforeSwap", "bit": 7 },
  { "name": "afterSwap", "bit": 6 },
  { "name": "poolId", "bits": [19, 8] }
]}
```

Each entry in `fields` is either `{ "name": ..., "bit": N }` (a single boolean flag at bit `N`, 0-indexed from the least significant bit, decoded as `bool`) or `{ "name": ..., "bits": [hi, lo] }` (an inclusive bit range, decoded as an unsigned integer). Bit positions are independent of, and MAY overlap arbitrarily within, the underlying value's byte boundaries — this is precisely what distinguishes `bitfield` from `struct`, whose fields are always byte-aligned and never overlap. Named sub-fields are addressed exactly like `struct` fields (by name); see [Path addressing](#path-addressing). `bitfield` consumes its declared `bytes` width regardless of how many of those bits are named — undeclared bits are simply not exposed as fields.

**`struct`** — an ordered, unpadded concatenation of named fields:

```json
{
  "kind": "struct",
  "fields": [
    { "name": "operation",  "schema": { "kind": "uint", "bytes": 1 } },
    { "name": "to",         "schema": { "kind": "address" } },
    { "name": "value",      "schema": { "kind": "uint", "bytes": 32 } },
    { "name": "dataLength", "schema": { "kind": "uint", "bytes": 32 } },
    { "name": "data",       "schema": { "kind": "bytes", "lengthFrom": "dataLength" } }
  ]
}
```

Fields are read strictly in order, byte-for-byte, with no alignment padding and no ABI head/tail indirection. This is the node that describes Safe MultiSend's per-entry record and ERC-7579's `mode` word.

**`sequence`** — repetition of one element node, read until the enclosing buffer is exhausted:

```json
{ "kind": "sequence", "element": <node>, "count": "tillEnd" }
```

`"tillEnd"` is the only count mode this ERC defines, because it is the only one any known real case needs — Safe MultiSend repeats its record `struct` until `transactions` runs out; Universal Router repeats a `dispatch` (below) once per byte of `commands`. Other termination modes (an explicit element count, a byte-length prefix) are left for a future revision if a real case needs them, rather than specified speculatively now.

**`call`** — the bytes at this position are themselves calldata to another contract; resolve them by re-running ERC-7730's own [selector matching](./erc-7730.md#selector-matching-contracts), recursively:

```json
{ "kind": "call", "to": "to", "length": 68 }
```

`call` is a byte-consuming node like `bytes`: it accepts the same `length` / `lengthFrom` / implicit-remainder-of-enclosing-buffer rules, so exactly how many bytes it consumes is never ambiguous. `to` is a path (relative to the enclosing `struct`) to the address to recurse into. Having consumed its bytes, a wallet MUST treat the first 4 bytes as a selector and the rest as ABI-encoded arguments, then MUST treat the result exactly as it would a top-level transaction: look up a matching `display.formats` entry (in this file, in an `includes` file, or in the descriptor registry) for that `to`/selector pair, and if none is found, apply the same fallback as an [unknown selector](./erc-7730.md#unknown-selectors).

This is how Safe MultiSend's inner calls are described. Note that `call` is declared directly as the `schema` of the `data` field itself — there is no separate sibling field for "the nested call"; the fact that a slice of bytes *is* a nested call is a property of that slice's own declared type, not something bolted on next to it.

`call` need not sit inside a `struct`. A field whose bytes were obtained by ordinary ABI decoding (not by a parent `layout` at all) MAY also declare `layout` directly as a `call` node, meaning "this ABI-decoded `bytes` field is itself calldata to another contract." This is how ERC-7579's batched executions are described: each element of the ABI-decoded `Execution[]` array has an ordinary `bytes callData` member, and a second field entry with `path: "executionCalldata[].callData"` and `layout: {"kind": "call", "to": "executionCalldata[].target"}` recurses into it, addressed at the same array index as its sibling `target` — the same by-index correlation ERC-7730 already uses for [array-valued formatting parameters](./erc-7730.md#field-format-specification).

**`initCode`** — the bytes at this position are a contract-creation payload (raw creation bytecode, optionally followed by, or wrapped around, constructor arguments), matched against a small, explicit set of known, audited templates:

```json
{ "kind": "initCode",
  "length": 1497,
  "templates": [
    {
      "id": "example-template",
      "prefix": { "hash": "0x<keccak256 of the exact N-byte prefix>", "length": 1477 },
      "args": { "abiType": "(address singleton)" }
    }
  ],
  "default": "reject"
}
```

`initCode` is byte-consuming like `bytes` (`length` / `lengthFrom` / implicit remainder). Once its bytes are consumed, a wallet MUST attempt each entry in `templates`, **in declaration order**, and use the first that structurally matches:

1. Compare the first `prefix.length` bytes of the consumed region against `prefix`: either byte-for-byte, if `prefix.literal` (an inline hex string) is given, or by comparing `keccak256` of that exact-length slice against `prefix.hash`. Exactly one of `literal` or `hash`+`length` MUST be present. If the consumed region is shorter than `prefix.length`, or the comparison fails, this template does not match; proceed to the next.
2. If the template also declares a `suffix` (same `literal` or `hash`+`length` shape), compare it the same way against the *last* `suffix.length` bytes of the consumed region. If it does not match, this template does not match; proceed to the next.
3. Otherwise, this template matches. Apply `args` — either `{ "abiType": "<tuple>" }` (ordinary ABI decoding) or `{ "layout": <node> }` (this ERC's own layout language) — to the bytes strictly between the end of `prefix` and the start of `suffix` (or, if no `suffix` is declared, to everything after `prefix` through the end of the consumed region).

If no template matches, a wallet MUST apply `default: "reject"` — the same [unknown selector](./erc-7730.md#unknown-selectors) fallback used everywhere else in this ERC: display a safe fallback and MUST NOT guess at a decoding. `"reject"` is the only defined value for `default`.

`prefix`'s two forms exist for different template sizes: `literal` is legible and auditable at a glance for short, fixed templates (a minimal proxy's handful of bytes); `hash` avoids inlining an entire compiled contract's creation bytecode for large templates, at the cost of the match no longer being visually verifiable from the descriptor text alone. Authors are responsible for computing `hash` values from the exact compiler output (version and settings) they intend to match — a single compiler flag change produces different bytecode and a different hash, silently falling through to `reject` rather than misdecoding.

### `$fallback`

Some contracts — notably generic deterministic-deployment proxies (see [Test Cases](#test-cases)) — expose no ABI-selected function at all; every call reaches a single raw fallback. `display.formats` MAY use the reserved key `"$fallback"` for exactly this case: a [structured data format specification](./erc-7730.md#structured-data-format-specification) matched whenever calldata does not correspond to any selector-based entry in the same file, whose `fields`/`layout` describe the entirety of `data` directly, with no selector-stripping step. `$fallback` MUST NOT be combined with selector-keyed entries that could themselves match the same calldata; wallets MUST prefer a matching selector-keyed entry over `$fallback` when both are present and only one is intended to apply. This does not change `display.formats` selector matching for any contract that has a normal ABI — it only gives contracts that genuinely have none a way to be described at all.

**Byte-width invariant.** Every `layout` node either consumes a well-defined, computable number of bytes from the buffer (all of the kinds above), or is explicitly declared non-consuming (only `dispatch`'s path-sourced tag form, below, which reads an already-resolved value instead of parsing bytes). No node kind may be ambiguous about whether, or how much, it advances the cursor.

### Path addressing

Paths extend into `layout`-decoded fields the same way they already extend into ABI-decoded struct and array fields: by name for `struct` and `bitfield` fields, by index for `sequence` elements. For example, given the `struct` above, `#.transactions[0].to` refers to the `to` field of the first record; `#.transactions[1].data.to` refers into a nested `call`'s own resolved fields, addressed using that resolved function's own parameter names, once matched. Similarly, once an `initCode` node's `templates` entry has matched, its `args` fields are addressed by name (or by tuple position, for an unnamed `abiType`), exactly as they would be for any other matched call.

### `dispatch`

`dispatch` selects which type or layout governs a field, based on the value of a tag. The tag MAY come from two places:

1. **An already-resolved sibling path** — the ordinary case, used when the tag is a normal ABI-decoded parameter of the same call, decoded by nothing new at all:

```json
{
  "path": "data",
  "dispatch": {
    "tag": { "path": "schema" },
    "cases": {
      "0x1234...": { "abiType": "(address recipient,bool isHuman,uint256 score)" }
    },
    "default": "reject"
  }
}
```

This is the shape needed by EAS (`schema` selects how to decode `data`), ERC-7683 (`orderDataType` selects how to decode `orderData`), and ERC-7579 (`mode`'s decoded `callType` sub-field selects how to decode `executionCalldata`).

2. **Inline, read from the buffer at the current cursor position** — used only inside a `layout` tree, when the tag itself has to be parsed out of raw bytes rather than looked up as an already-decoded value:

```json
{ "kind": "dispatch",
  "tag": { "kind": "uint", "bytes": 1, "mask": "0x3f" },
  "payloadFrom": "inputs",
  "cases": {
    "0x00": { "abiType": "(address recipient,uint256 amountIn,uint256 amountOutMin,bytes path,bool payerIsUser)" }
  },
  "default": "reject"
}
```

`mask` is an optional bitmask applied to the tag's raw value before matching against `cases` keys — needed for Universal Router, where the top bit of the command byte is an unrelated "allow revert" flag and only the low 6 bits select the command. `payloadFrom` names a sibling array (`inputs`), read at the same index as the current element of the enclosing `sequence` — a correlated-array lookup already precedented by ERC-7730's existing rule that a formatting parameter array is "read at the same index as the current element being formatted."

In both forms, a case value is one of:

* `{ "abiType": "<solidity type or tuple>" }` — decode the payload using the ordinary Solidity ABI decoder.
* `{ "layout": <node> }` — recurse into this ERC's own layout language (any node, including `call`).
* `{ "dispatch": {...} }` — nest another dispatch (for multi-level tag structures).

A wallet MUST treat a tag value with no matching case, and no `default` case supplied, the same way it treats an [unknown selector](./erc-7730.md#unknown-selectors): display a safe fallback and MUST NOT guess at a format.

### `dispatch` at the top of a structured data format specification

Every case above dispatches on a tag to reinterpret *one field's* bytes, while the rest of the call keeps its own fixed `intent` and `fields`. Some contracts have no such fixed meaning at all: the entire call exists only to be redirected, and which target function it becomes is the only thing worth describing. A [structured data format specification](./erc-7730.md#structured-data-format-specification) MAY declare a top-level `dispatch` object, with the same `tag`/`cases`/`default` shape as above, instead of `intent`/`fields`. Its `tag` is a path to one of the outer call's own already-decoded parameters (never a raw-byte tag — there is no enclosing buffer to read one from at this level).

Because there is no bytes value being reinterpreted at this level, only two case-value forms are valid here: a nested `dispatch` (for a tag that further refines an already-matched case), or a `call` object naming a **different** target function outright:

```json
{ "call": {
    "to": "<path>",
    "signature": "<canonical function signature>",
    "args": [ { "path": "<path>" } | { "value": "<literal>" }, ... ]
} }
```

`to` is a path to the target address. `signature` is the target's canonical Solidity signature — a wallet MUST resolve it against `to`'s own `display.formats` entry exactly as it would any other call, but by matching the signature directly rather than by computing and comparing a selector, since no selector was ever computed for this call (see [Rationale](#rationale)). `args` positionally binds values to that signature's declared parameter order — each entry is either `path` (a reference to one of the outer call's own decoded values) or `value` (a literal) — reusing the existing `path`/`value` duality of a [field format specification](./erc-7730.md#field-format-specification). Position and type govern the binding, exactly as ERC-7730 already treats parameter names as non-canonical for selector matching; `args` need not preserve the order values arrived in at the outer call.

A wallet MUST resolve the matched target's own `intent`, `interpolatedIntent`, and `fields` using the bound `args` values in place of that target's own decoded parameters, and MUST apply the [unknown selector](./erc-7730.md#unknown-selectors) fallback if `to`'s descriptor has no entry matching `signature`.

## Rationale

**Why a JSON node tree and not a compact string grammar.** ERC-7730 already describes ABI function signatures and EIP-712 types as strings, so a string grammar (e.g. an extended fragment syntax) might seem consistent. It was rejected here because these payloads are not universally pre-understood the way Solidity ABI is — a string grammar for them would need its own bespoke parser, on top of the ABI parser wallets already carry, and a new string-grammar parser is exactly the class of code that has historically produced hardware-wallet parsing bugs. A JSON node tree reuses the same tree-walking wallets already do for `fields` and `group`.

**Why the vocabulary is this small.** Every node and mode above exists because one of the real cases surveyed while designing this ERC needs it, not because it seemed generally useful. `sequence` has exactly one termination mode because no known case needs another. `mask` exists only because Universal Router's command byte shares space with a flag bit. Padded/aligned struct variants, bit-level fields narrower than a byte, and non-`tillEnd` sequence termination are all left out deliberately; they can be added later, non-breaking, if a real case turns up.

**Why `dispatch` has two tag-sourcing forms instead of one.** Most of the surveyed cases (EAS, ERC-7683, ERC-7579) dispatch on a tag that is already sitting in an ordinary ABI-decoded field — no byte parsing is involved in getting the tag at all. Only Universal Router needs the tag pulled out of a raw byte mid-parse. Rather than forcing every case through a byte-oriented mental model, `dispatch` accepts a `path` directly.

**Why `call` recurses into the whole top-level algorithm instead of its own resolution rule.** Safe MultiSend's inner calls are, from the perspective of the target contract, ordinary top-level calls — they have their own `to` address and their own selector. This works with no dispatch table of any kind because the 4-byte-selector shape isn't an ERC-7730 convention being imposed on the data — it's forced on whoever built the MultiSend batch by the target contract's own compiled dispatcher (Solidity, and most other languages, generate exactly this selector-check-and-jump at the top of every contract's bytecode). Reusing ERC-7730's existing selector-matching and fallback behavior, rather than inventing a parallel mechanism, means a MultiSend entry calling a well-described ERC-20 `approve` gets exactly the same display it would get as a standalone transaction, with no separate code path to keep correct — and it composes for free: if a batch happened to call another MultiSend, or another contract using this very ERC's constructs, recursive resolution picks up that target's own `layout`/`dispatch` declarations with no special-casing.

**Why `call` is folded into a field's own `schema`/`layout` instead of being a sibling field.** An earlier iteration of this design added a `data` field for the raw bytes and a separate `call` field pointing at it — two names for one byte range, one saying "these are bytes" and the other saying "now recurse into those same bytes." That's redundant, and worse, it leaves the "is this a nested call" fact detached from the value it describes. Declaring `call` directly as a field's `schema` (or its `layout`, for a field that arrived via ordinary ABI decoding rather than a parent `layout`) makes "is a nested call" a property of the field's own declared type — indistinguishable in structure from any other typed field, and impossible to declare in two contradictory ways for the same bytes.

**Why the top-level `dispatch`/direct-`call` form exists, and why it's the one exception to this ERC's evidence rule.** Every other construct in this ERC exists because a real, cited transaction needed it. This one does not have that grounding — no verified live transaction was found that reinterprets already-decoded parameters into a different function's argument list the way the [TieredExecutor example](../assets/erc-non-abi-dispatch/example-tiered-executor.json) does. It is included because the shape it targets — a small trusted relayer accepting a tag and a handful of generic-looking arguments, then re-dispatching to one of several unrelated target interfaces with a different argument order per target — is a common, plausible, and easily reachable governance/router pattern, structurally close to a `switch` over an enum parameter. Readers should weigh this construct with that in mind: it is motivated by generality, not by an observed case, unlike everything else here. If a real contract using this exact shape turns up, its transaction should replace the made-up one in the Test Cases section.

**Why `bitfield` is a distinct node kind rather than a parameter on `uint`.** `struct` and `sequence` both assume byte-aligned, non-overlapping fields — that assumption is load-bearing throughout the rest of this ERC (it's what makes the byte-width invariant a simple sum of child widths). `bitfield`'s named sub-fields can overlap arbitrarily within a shared width and carry no byte alignment at all, so keeping it a separate, clearly-labeled kind (rather than, say, a `bits` option quietly attached to `uint`) makes it visually obvious, at the point a field is declared, that its sub-fields don't follow the rest of the language's byte-aligned norm. The motivating real case is Uniswap v4: hook contract addresses encode up to 14 independent permission flags in specific low-order bits of the 160-bit address value itself, verified against `Hooks.sol` and Uniswap's own v4 documentation.

**Why `initCode` is its own node kind rather than a `dispatch` tag-sourcing mode.** An earlier version of this design considered folding creation-bytecode matching into `dispatch` as a fourth tag-sourcing mode (hash of a length-prefix of the buffer). That would have worked for the simplest case, but it doesn't generalize cleanly: some real creation-code templates append constructor arguments after a fixed prefix (a generic factory concatenating a template with a trailing ABI-encoded argument), while others — [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167) minimal proxies, verified against the standard's own bytecode listing — embed their one constructor-equivalent value (the implementation address) *between* a fixed prefix and a fixed suffix, with no ABI encoding at all. Expressing both shapes through a single scalar "tag" and a flat `cases` map would have needed the tag itself to somehow also carry "and here's where the matched region ends", which is exactly the kind of implicit, easy-to-get-wrong behavior the byte-width invariant exists to rule out elsewhere in this ERC. A dedicated node with explicit `prefix`/`suffix`/`args` fields makes the matched region's boundaries an explicit, checkable part of each template entry instead.

**Why `$fallback` is needed at all.** Every other selector-related mechanism in ERC-7730 and this ERC assumes a 4-byte selector exists to be computed and matched. The generic deterministic-deployment proxy that motivates `initCode` — the same, single contract, deployed at the identical address on nearly every EVM chain, that many real, well-known contracts (including Uniswap's own Permit2) are deployed through — has no selector at all; its calldata is `salt ‖ initCode`, dispatched by a raw fallback. Without `$fallback`, `initCode` would have no contract it could actually be demonstrated on, since every other candidate factory this research pass found either has a normal ABI wrapper around its bytecode argument (already describable with plain `abiType`, no new construct needed) or turned out, on inspection, to build its creation code internally rather than receiving it as literal calldata at all.

**Why positional binding, and why `args` may reorder.** ERC-7730 already treats parameter *names* as non-canonical for the purpose of selector matching — only position and type are. A dispatch case that redirects to a different function has no shared parameter names to align by in the first place (the outer call's `account`/`amount` mean nothing to the target function's own signature), so positional binding by the target's declared order is the only definition that is well-defined at all, and it is the same rule ERC-7730 already applies elsewhere, not a new one.

## Backwards Compatibility

This ERC only adds new, optional keys to a field format specification. A descriptor that does not use `layout` or `dispatch` is unaffected, and a wallet implementing only ERC-7730 without this extension can safely ignore fields that use them, applying the existing [unknown field / raw fallback](./erc-7730.md) behavior.

## Test Cases

Six of the eight examples below are real, mined transactions, decoded from raw calldata (not an explorer's rendered summary) and cross-checked against at least one independent source. A seventh demonstrates `initCode`/`$fallback` against real, named, well-known contracts rather than one specific transaction. The eighth, `TieredExecutor`, is explicitly a made-up contract — see its own description below and the caveat in [Rationale](#rationale). Each is a full, standalone ERC-7730 descriptor file under [`../assets/erc-non-abi-dispatch/`](../assets/erc-non-abi-dispatch/) rather than a snippet, so it can be read with all the surrounding `context`/`metadata`/`display` structure intact.

### Safe `MultiSend`

Ethereum mainnet, tx [`0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e`](https://etherscan.io/tx/0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e). A Safe at `0xCa087C9e22bC97059d8fd6e25956835Ec205782B` delegatecalls `MultiSendCallOnly` (`0x40A2aCCbd92BCA938b02010E17A5b8929b49130D`) to batch six CTC ([`0xa3ee21c306a700e682abcdfe9baa6a08f3820419`](https://etherscan.io/address/0xa3ee21c306a700e682abcdfe9baa6a08f3820419)) `transfer` calls to six different recipients in one transaction. The 918-byte `transactions` buffer decodes (record 0 of 6) to `operation=CALL`, `to=0xa3ee21c306a700e682abcdfe9baa6a08f3820419`, `value=0`, `dataLength=68`, and `data` recursing via `call` into a normal `transfer(address,uint256)` sending `40000000000000000000000` (40,000 CTC) to `0x6ba2c52a959f0544e00aea60fe576463fe5fc38d`; the remaining five records follow the same shape, and the buffer is consumed exactly with no slack, confirming the `tillEnd` parse.

Full descriptor: [`example-safe-multisend.json`](../assets/erc-non-abi-dispatch/example-safe-multisend.json).

### Uniswap Universal Router

Ethereum mainnet, tx [`0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba`](https://etherscan.io/tx/0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba), calling `execute(bytes,bytes[],uint256)` on the Universal Router at `0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`. `commands = 0x000004`: command 0 (`0x00`, `V3_SWAP_EXACT_IN`) sends `amountIn=3425828840000000000000` EURe through the path `EURe → EUR0 → EURC` with `payerIsUser=true`; command 1 (`0x00` again) swaps `amountIn=5138743260000000000000` EURe directly to EURC; command 2 (`0x04`, `SWEEP`) sweeps native ETH with `amountMinimum=0` back to the swapper. All three command bytes had their top (revert-flag) bit unset; token identities and pool fees were confirmed independently via each token's `symbol()`/`decimals()`.

Full descriptor: [`example-universal-router.json`](../assets/erc-non-abi-dispatch/example-universal-router.json).

### ERC-7579 `execute`

Base mainnet, Biconomy Nexus accounts (an ERC-7579 reference implementation), function selector `0xe9ae5c53`. Single-call example: tx [`0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1`](https://basescan.org/tx/0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1) — `mode` has `callType=0x00`, and `executionCalldata` decodes to `target=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC on Base), `value=0`, `callData` recursing into `transfer(0x3C97112223b1AD104Cf2ac022e450Ef862652b93, 1)`. Batch-call example: tx [`0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c`](https://basescan.org/tx/0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c) — `callType=0x01`, decoding to three executions (a native ETH transfer, a DAI `transfer`, and a USDC `transfer`) all to the same recipient, a single-UserOperation "sweep to one address" pattern. Both the mode layout and the callType-driven dispatch were confirmed against Nexus's own `ModeLib.sol`.

Full descriptor: [`example-erc7579-execute.json`](../assets/erc-non-abi-dispatch/example-erc7579-execute.json).

### Circle CCTP message

Base → Ethereum, 50,000 USDC. Burn tx [`0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f`](https://basescan.org/tx/0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f) on Base; mint tx [`0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f`](https://etherscan.io/tx/0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f) on Ethereum. The 248-byte `message` decodes to `sourceDomain=6` (Base), `destinationDomain=0` (Ethereum), `nonce=764152`, `sender`/`recipient` as the two chains' TokenMessenger contracts, `destinationCaller=0x0` (permissionless relay); the nested `messageBody` decodes to `burnToken` = Base USDC, `mintRecipient`/`messageSender` both the same self-relaying address, `amount=50000000000` (50,000 USDC). The 132-byte `messageBody` is consumed exactly.

Full descriptor: [`example-cctp-message.json`](../assets/erc-non-abi-dispatch/example-cctp-message.json). Note the descriptor's `context.contract` address is a placeholder — see the file's own `$comment`.

### EAS attestation

Optimism mainnet, schema `#78` (UID `0xfdcfdad2dbe7489e0ce56b260348b7f14e8365a8a325aef9834818c00d46b31b`), string `string rpgfRound,address referredBy,string referredMethod` — Optimism's RetroPGF badgeholder-referral schema. Attestation [`0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41`](https://optimism.easscan.org/attestation/view/0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41), tx `0x820e5b8404f1ec62b47459e538151e54fb598b729dcb461087456bb856abf595`, decodes to `rpgfRound="4"`, `referredBy=0x0000000000000000000000000000000000000342`, `referredMethod="Friend"`. `schema` and `data` are already-decoded ABI sibling fields of `attest()`'s own parameters, so no `layout` node is needed at all here — just `dispatch` sourced from a path. (A simpler, single-field schema also exists at scale — Coinbase's "Verified Account" schema, UID `0xf8b05c79f090979bf4a80270aba232dff11a10d9ca55c4f88de95317970f0de9`, `bool verifiedAccount`, 720,000+ attestations on Base — useful as a minimal case, but the RetroPGF one exercises both static and dynamic ABI types.)

Full descriptor: [`example-eas-attestation.json`](../assets/erc-non-abi-dispatch/example-eas-attestation.json). Note the descriptor's `context.contract` address is a placeholder — see the file's own `$comment`.

### ERC-7683 order

Base mainnet, tx [`0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09`](https://basescan.org/tx/0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09), calling `open((uint32,bytes32,bytes) order)` on Across's `AcrossOriginSettler` (`0x4afb570AC68BfFc26Bb02FdA3D801728B0f93C9E`) — a self-bridge of 1 USDC from Base to Arbitrum. `orderDataType = 0x9df4b782e7bbc178b3b93bfe8aafb909e84e39484d7f3c59f400f1b4691f85e2`, independently confirmed as `keccak256("AcrossOrderData(address inputToken,uint256 inputAmount,address outputToken,uint256 outputAmount,uint256 destinationChainId,bytes32 recipient,address exclusiveRelayer,uint256 depositNonce,uint32 exclusivityPeriod,bytes message)")`, decoding to `inputToken`/`outputToken` = USDC on Base/Arbitrum, `inputAmount=1000000`, `outputAmount=981521` (the relayer's fee), `destinationChainId=42161`, `recipient` equal to the sender, and empty `exclusiveRelayer`/`depositNonce`/`exclusivityPeriod`/`message`. Note this uses the same typehash-dispatch shape as the EAS example above — different ecosystem, same construct.

Full descriptor: [`example-erc7683-order.json`](../assets/erc-non-abi-dispatch/example-erc7683-order.json).

### Deterministic deployment proxy (`initCode` / `$fallback`)

The generic deterministic-deployment proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C` ("Nick's method") is deployed at this identical address on nearly every EVM chain and dispatches via a raw fallback — calldata is exactly `salt (32 bytes) ‖ initCode`, fed directly into `CREATE2`; there is no selector at all, which is what motivates `$fallback`. It is used to deploy many well-known contracts deterministically, including Uniswap's own Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`, the same address on every chain it's deployed to). The descriptor's second template is [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167)'s minimal-proxy creation code, byte-exact and fully verified against the standard's own bytecode listing: a 20-byte prefix (`0x3d602d80600a3d3981f3363d3d373d3d3d363d73`), a 20-byte embedded implementation address, and a 15-byte suffix (`0x5af43d82803e903d91602b57fd5bf3`) — 55 bytes total, with no ABI encoding involved at all, which is why `initCode` needed a `suffix` concept rather than just "prefix, then trailing ABI args."

Unlike the six examples above, this one demonstrates a mechanism against real, named, well-known contracts rather than one specific mined transaction. The Permit2 template's `prefix.hash`/`prefix.length` are explicitly marked as placeholders in the file — computing them requires Permit2's exact, compiler-version-specific creation bytecode, which was not independently re-derived for this example.

Full descriptor: [`example-deterministic-deployment-proxy.json`](../assets/erc-non-abi-dispatch/example-deterministic-deployment-proxy.json).

### `TieredExecutor` (made-up example)

A small, illustrative Solidity contract written for this ERC — [`TieredExecutor.sol`](../assets/erc-non-abi-dispatch/TieredExecutor.sol) — is **not deployed anywhere**; unlike every other example above, no real transaction exists for it. It demonstrates the top-level `dispatch`/direct-`call` form: `executeOperation(address target, Operation op, address account, uint256 amount)` takes an enum tag `op` and two generic-looking arguments, and re-dispatches to one of two unrelated target interfaces — `IRewardVault.grantReward(address,uint256)` for `op=1`, `ILegacyToken.creditAccount(uint256,address)` for `op=2` — each with a different parameter order, resolved from the same `account`/`amount` values by positional binding.

Full descriptors: [`example-tiered-executor.json`](../assets/erc-non-abi-dispatch/example-tiered-executor.json) (the dispatching contract), [`example-reward-vault.json`](../assets/erc-non-abi-dispatch/example-reward-vault.json) and [`example-legacy-token.json`](../assets/erc-non-abi-dispatch/example-legacy-token.json) (the two target interfaces it recurses into, each an independently-authored descriptor resolved the same way any other nested `call` target would be).

## Reference Implementation

TBD

## Security Considerations

A `layout`/`dispatch` interpreter is new parsing surface on a hardware wallet, decoding attacker-influenced (calldata is provided by whoever submits the transaction) bytes. Implementations MUST bound recursion depth (`call` and nested `dispatch` can recurse arbitrarily deep in principle), MUST treat any length (`lengthFrom`, or a `sequence`'s implicit `tillEnd` walk) that would read past the end of the underlying buffer as invalid input, and MUST fail closed — applying the [unknown selector](./erc-7730.md#unknown-selectors) fallback — rather than displaying a partially decoded or best-guess value when a `layout` or `dispatch` does not cleanly match the actual bytes.

`initCode` template matching is exact-bytes (or exact-hash) matching against a fixed template. A wallet MUST NOT treat a partial or fuzzy prefix/suffix match as a match — an attacker who can get even one byte accepted as "close enough" could potentially get unrelated, unaudited bytecode displayed as if it were a known, trusted template. Authors MUST keep `templates` entries pinned to one specific compiler version and settings; the same source recompiled differently produces different bytecode and MUST be treated as an entirely distinct, separately-audited template, never as a "should still basically match" variant of an existing one.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
