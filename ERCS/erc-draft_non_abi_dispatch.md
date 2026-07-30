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

[ERC-7730](./erc-7730.md) describes how to clear-sign structured data by decoding calldata as a Solidity ABI function call, then formatting the resulting named fields. This works as long as every value in the call is itself ABI-encoded. It breaks down for a common and growing class of contracts that accept one ABI-encoded `bytes` (or `bytes[]`) argument and then interpret its raw content using their own private encoding — packed structs, bit-packed flags, a tag that selects one of several possible payload shapes, or an offset pointing to data stored elsewhere in that same buffer. Gnosis Safe's `MultiSend`, Uniswap's Universal Router and hook addresses, and ERC-7579 modular accounts all do this, and none of it can be described in ERC-7730 today; such fields must be left as opaque, unreadable bytes. It also breaks down entirely for contract-creation calls, which have no function selector at all — a real, common, security-critical transaction type ERC-7730 has no vocabulary for.

This ERC adds three new keys to an ERC-7730 [field format specification](./erc-7730.md#field-format-specification) — `layout`, `switch`, and `interaction` — that let an author describe the internal structure of such a field, which structure applies where the field's shape depends on a tag value, and how to describe a call synthesized from already-decoded pieces rather than sliced out of contiguous bytes. Where a field's raw bytes already are a complete, contiguous call (selector and ABI-encoded arguments together), this ERC deliberately does not duplicate ERC-7730's own [embedded calldata](./erc-7730.md#embedded-calldata) mechanism (`format: "calldata"`) — it only extends that mechanism with one param, `operation`, for the one thing it cannot already express: a nested call that is a `DELEGATECALL` rather than a plain call. It also adds a reserved `$fallback` key to `display.formats` for contracts that dispatch with no selector at all. Everything else about ERC-7730 (context binding, metadata, top-level selector matching, path syntax) is unchanged; this ERC only extends what a single field's `path` can resolve into, and how a contract's entry point is matched in the first place.

## Motivation

Look at what a `display.formats` entry can describe today: a Solidity function signature, decoded with the standard ABI rules, giving named parameters that `fields` entries point `path` at. That covers the overwhelming majority of contract calls. It does not cover contracts whose calldata carries a second, private encoding layer inside one of those ABI parameters:

- **Safe's `MultiSend.multiSend(bytes transactions)`** — `transactions` is not ABI-encoded. It is a tightly packed, back-to-back sequence of `(operation, to, value, dataLength, data)` records, repeated until the buffer runs out. Each record's own `data` is, in turn, a normal call to some other contract.
- **Uniswap's Universal Router `execute(bytes commands, bytes[] inputs)`** — `commands` is one raw opcode byte per sub-action (with a flag bit for "allowed to revert"); `inputs[i]` is separately ABI-encoded, but *which* ABI type it decodes as depends on the opcode at `commands[i]`.
- **ERC-7579 modular accounts, `execute(bytes32 mode, bytes executionCalldata)`** — `mode` packs five sub-fields into one word; `executionCalldata`'s shape (a single packed call, or an ABI-encoded array of calls) depends on one byte of `mode`.
- **Uniswap v4 hook addresses** — up to 14 independent permission flags (`beforeSwap`, `afterSwap`, and others) live in specific low-order bits of the 160-bit hook address itself; the same address value is simultaneously "an address" and "a bitmask," with no byte alignment between the two meanings.
- **Safe's `execTransaction(...,bytes signatures)`** — `signatures` is a sequence of fixed 65-byte records, but a record signing with a contract (rather than an EOA) repurposes one of its own fields as an offset into a shared tail region appended after every record, where the actual, variable-length signature data lives — the one shape in this ERC's entire survey that needs genuine pointer-style indirection *within* a custom-packed buffer, not just a fixed or tag-selected structure.
- **Contract-creation transactions** — a `CREATE`/`CREATE2` deployment, or a generic deterministic-deployment factory taking raw bytecode as an argument, has no function selector at all. There is nothing for ERC-7730's selector-matching to match against, and no vocabulary for describing constructor arguments appended to, or embedded within, compiler-specific creation bytecode.

None of this is exotic or rare. It is how batching, modular accounts, and generic-purpose routers already work across the ecosystem, and account-abstraction adoption is only going to produce more of it. A wallet with no way to describe these fields has no way to clear-sign them beyond showing raw hex — which is exactly the blind, trust-me signing experience ERC-7730 exists to eliminate.

The goal here is narrow on purpose. This ERC does not attempt to become a general-purpose binary serialization language (no attempt is made to describe Protobuf, Borsh, or arbitrary custom formats in full generality). It describes exactly the small set of shapes observed in real, widely used contracts: fixed-width packed fields, repeated records read until the buffer ends, and tag-selected payload types. Constructs are added because a real case needs them, not because they might be useful someday.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This ERC defines three additional keys usable in an ERC-7730 [field format specification](./erc-7730.md#field-format-specification): `layout`, `switch`, and `interaction`. A field format specification MUST NOT combine `layout` with `format`; the two are alternative ways of turning a field's raw value into something displayable, and `layout` takes over that job entirely for the field it is attached to. `interaction` is likewise mutually exclusive with `format` and `layout` — it describes a call synthesized from already-decoded values rather than any single bytes value being displayed or parsed. `switch` MAY be combined with any of the three, since it only decides *which* `layout`, ABI type, or nested structured format governs a field — it does not itself produce a displayable value.

### `layout`

`layout` describes the internal byte structure of a `bytes` field. Its value is a *layout node*. A layout node is one of the following types:

**Anchoring `layout` on an already-decoded scalar.** `layout` is normally attached to a field whose raw `bytes` have not been interpreted yet. It MAY also be attached to a field whose value was already produced by ordinary Solidity ABI decoding, or by an enclosing `object`/`bitfield` layout node — [Path addressing](#path-addressing) already treats the two sources the same way — if that value's declared or inferred type is a single-word elementary type: `uintN`/`intN`, `bool`, `address`, or a fixed-size `bytesN`. In that case the layout tree operates on the value's canonical 32-byte big-endian encoding as its buffer, exactly as if those 32 bytes had been sliced out of a larger one. This is not extended to dynamic types (`bytes`, `string`, arrays, tuples) — no known case needs it, and "canonical encoding" is not a single well-defined byte sequence for them the way it is for a 32-byte word. See [Rationale](#rationale) for the motivating case.

**Primitive nodes**

```json
{ "type": "uint", "bytes": 1, "endian": "be" }
{ "type": "bytes", "length": 20 }
{ "type": "address" }
{ "type": "bool" }
```

`uint.bytes` is the width in bytes (1, 2, 4, 8, 16, or 32). `endian` is `"be"` or `"le"`, defaulting to `"be"` — every known EVM-side use case packs data big-endian, matching Solidity's own word layout; `"le"` exists only so this vocabulary does not need to change if a future non-EVM companion reuses it. `address` is sugar for a 20-byte `bytes` node. `bytes.length` MAY be a fixed integer, a `lengthFrom` reference to an earlier sibling field's decoded value (see `object` below), or omitted entirely on the last field of an `object`, meaning "consume whatever bytes remain in the enclosing buffer."

**`bitfield`** — a fixed-width value (same width rules as `uint`) whose individual bits or bit ranges each carry independent, named meaning:

```json
{ "type": "bitfield", "bytes": 20, "endian": "be", "fields": [
  { "name": "beforeSwap", "bit": 7 },
  { "name": "afterSwap", "bit": 6 },
  { "name": "poolId", "bits": [19, 8] }
]}
```

Each entry in `fields` is either `{ "name": ..., "bit": N }` (a single boolean flag at bit `N`, 0-indexed from the least significant bit, decoded as `bool`) or `{ "name": ..., "bits": [hi, lo] }` (an inclusive bit range, decoded as an unsigned integer). Bit positions are independent of, and MAY overlap arbitrarily within, the underlying value's byte boundaries — this is precisely what distinguishes `bitfield` from `object`, whose fields are always byte-aligned and never overlap. Named sub-fields are addressed exactly like `object` fields (by name); see [Path addressing](#path-addressing). `bitfield` consumes its declared `bytes` width regardless of how many of those bits are named — undeclared bits are simply not exposed as fields.

**`object`** — an ordered, unpadded concatenation of named fields:

```json
{
  "type": "object",
  "fields": [
    { "name": "operation",  "schema": { "type": "uint", "bytes": 1 } },
    { "name": "to",         "schema": { "type": "address" } },
    { "name": "value",      "schema": { "type": "uint", "bytes": 32 } },
    { "name": "dataLength", "schema": { "type": "uint", "bytes": 32 } },
    { "name": "data",       "schema": { "type": "bytes", "lengthFrom": "dataLength" } }
  ]
}
```

Fields are read strictly in order, byte-for-byte, with no alignment padding and no ABI head/tail indirection. This is the node that describes Safe MultiSend's per-entry record and ERC-7579's `mode` word.

**`sequence`** — repetition of one element node, read until the enclosing buffer is exhausted:

```json
{ "type": "sequence", "element": <node>, "count": "tillEnd" }
```

`"tillEnd"` is the only count mode this ERC defines, because it is the only one any known real case needs — Safe MultiSend repeats its record `object` until `transactions` runs out; Universal Router repeats a `switch` (below) once per byte of `commands`. Other termination modes (an explicit element count, a byte-length prefix) are left for a future revision if a real case needs them, rather than specified speculatively now.

**`pointer`** — a fixed-width value that is not itself the data of interest, but an offset to where that data actually lives, elsewhere in a named buffer:

```json
{ "type": "pointer", "bytes": 32, "containerPath": "#.signatures", "destination": <node> }
```

`bytes` is the width of the offset value, read at this node's normal sequential position — that read is all that counts toward the enclosing `object`/`sequence`'s byte accounting; nothing else about `pointer` consumes bytes at the cursor's current position. `containerPath` is REQUIRED and MUST resolve to a `bytes`-typed value (a wallet MUST reject a `containerPath` that resolves to anything else, rather than guess); it names the buffer the offset is a position *into* — not necessarily the buffer this `pointer` node itself is being read from, since a fixed-size record containing a pointer is often only one of several records sharing one common tail region. `destination` is any layout node, decoded starting at byte position `containerPath`'s buffer + the offset value just read; its decoded result becomes this field's value. There is no `anchor`-style mode parameter: the offset is always relative to the start of whatever buffer `containerPath` names, because that is the only relationship any known real case has — an implicit, unstated anchor was considered and rejected in favor of `containerPath` precisely because "relative to what" has no safe default once a real case is examined closely enough (see [Rationale](#rationale)).

This is Safe's `execTransaction` `signatures` field: a `sequence` of fixed 65-byte `(r, s, v)` records, where a record with `v == 0` repurposes `s` — ordinarily half of an ECDSA signature — as a `pointer` into the tail of the same `signatures` buffer, at which a length-prefixed EIP-1271 signature blob lives. See [Test Cases](#test-cases).

**`$index`** — inside the `element` of a `sequence`, or of a field iterated via `format: "array"` (a field whose value is already an ABI-decoded array, walked element-by-element rather than by consuming bytes), `$index` is a reserved token equal to the zero-based position of the element currently being processed. It is usable inside a `path` to correlate that element with the same-indexed value of a *different* sibling field — e.g. `commands[$index]`, read from inside an `inputs` element's `switch`, is the byte of the sibling `commands` sequence at the same position as the `inputs` element currently being resolved. This is Universal Router's actual structure: `commands` (raw `bytes`, one command per byte, parsed as a `sequence`) and `inputs` (already-decoded `bytes[]`, walked via `format: "array"`) are two separate fields advanced in lockstep by the same index, not one field nested inside the other — `$index` is what ties them together.

**Nested calldata reuses ERC-7730's own mechanism, not a layout node.** A field whose bytes — however they were reached, whether by ordinary ABI decoding or by a parent `layout` — are themselves a complete, contiguous call (a selector followed by ABI-encoded arguments) is described with ERC-7730's own [embedded calldata](./erc-7730.md#embedded-calldata) mechanism, `format: "calldata"`, addressed by an ordinary `path` into the (possibly `layout`-decoded) structure — see [Path addressing](#path-addressing), which already lets a `path` reach into `object` fields and `sequence` elements the same way it reaches into ABI-decoded ones. This is how Safe MultiSend's inner calls are described: the `data` field is parsed as plain `bytes` (its `dataLength` already covers the full selector-plus-arguments blob, unmodified from how Safe's own contract packs it), and a sibling top-level field entry with `path: "transactions[].data"` and `format: "calldata"` resolves it, using `calleePath`/`amountPath` to point back at `transactions[].to`/`transactions[].value`. The same pattern describes ERC-7579's batched executions: each element of the ABI-decoded `Execution[]` array has an ordinary `bytes callData` member, resolved by a field entry with `path: "executionCalldata[].callData"` and `format: "calldata"`, `params: {"calleePath": "executionCalldata[].target"}` — addressed at the same array index as its sibling `target`, the same by-index correlation ERC-7730 already uses for [array-valued formatting parameters](./erc-7730.md#field-format-specification). See [Rationale](#rationale) for why this ERC does not define its own parallel node for this instead.

This ERC extends `format: "calldata"`'s `params` with one new, optional key: `operation`, since ERC-7730's own definition has no way to express anything but a plain call. Its value is either a literal `"call"` (the default, identical to omitting `operation` entirely) or `"delegatecall"`, or an object choosing between them based on a tag:

```json
{ "expression": "<path to an already-decoded tag>", "cases": { "<tag value>": "call" | "delegatecall", "$default": "reject" } }
```

`expression`/`cases` (including the reserved `$default` case key) follow exactly the same rules as `switch` (below): a wallet MUST treat a tag value with no matching case, and no `$default` case supplied, as an [unknown selector](./erc-7730.md#unknown-selectors). When resolved to `"delegatecall"`, a wallet MUST make clear that the callee executes in the calling contract's own storage and identity (`DELEGATECALL` semantics), and MUST warn as strongly as it would for a raw, undescribed `delegatecall` if `to`'s descriptor cannot be resolved — a delegatecall to an unknown or unaudited target is a full account takeover, not a benign unknown call. Resolution of `to`'s own `display.formats` entry is otherwise unaffected by `operation`; only the execution-context semantics differ, not how the target function is looked up.

**`initCode`** — the bytes at this position are a contract-creation payload (raw creation bytecode, optionally followed by, or wrapped around, constructor arguments), matched against a small, explicit set of known, audited templates:

```json
{ "type": "initCode",
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

**Byte-width invariant.** Every `layout` node either consumes a well-defined, computable number of bytes from the buffer (all of the types above), or is explicitly declared non-consuming (`switch`'s path-sourced expression form, below, which reads an already-resolved value instead of parsing bytes; and `pointer`'s `destination`, which is decoded at a computed position in a named buffer rather than at the cursor). No node type may be ambiguous about whether, or how much, it advances the *cursor of the buffer it is being read from* — `pointer` does not violate this: its own `bytes` width is a fixed, ordinary consumption at its own position, and `destination`'s decode is a separate, explicitly-declared side read against `containerPath`'s buffer, not a claim about how far the enclosing `object`/`sequence` advances. A `layout` anchored directly on an already-decoded scalar (above) is a degenerate, trivially-satisfying case of this same invariant: there is no enclosing buffer to consume from or leave a remainder in, the buffer *is* the value's fixed 32-byte encoding in full, and the top-level node MUST consume it completely, the same rule applied everywhere else.

### Path addressing

Paths extend into `layout`-decoded fields the same way they already extend into ABI-decoded struct and array fields: by name for `object` and `bitfield` fields, by index for `sequence` elements. For example, given the `object` above, `#.transactions[0].to` refers to the `to` field of the first record. This is also what makes nested calldata resolvable without a dedicated layout node: a sibling top-level field entry can address `#.transactions[].data` directly and apply `format: "calldata"` to it, exactly as it would to any ordinary ABI-decoded `bytes` field. Similarly, once an `initCode` node's `templates` entry has matched, its `args` fields are addressed by name (or by tuple position, for an unnamed `abiType`), exactly as they would be for any other matched call.

**`#.` crosses `switch`/`layout` scope boundaries.** A `switch` case that decodes its payload into a tuple (`abiType`, or the tuple-plus-`intent`-plus-`fields` shorthand) introduces a new, local field scope for that case's own `fields`: a relative path there resolves against the just-decoded tuple, not the outer call. `#.`, however, MUST still resolve against the absolute root of the entire structured data — the outer call's own top-level decoded parameters — regardless of how many `switch`/`layout` scopes deep the path is written. This is needed whenever a case's decoded value must be paired with a sibling of the field the `switch` is attached to, not a sibling within the tuple itself — for instance, resolving a `switch`-matched `amountsIn[i]` against a token list that lives one level up, alongside `userData` rather than inside it (see the [`joinPool`/`exitPool` Test Case](#test-cases)). Base ERC-7730's own examples of `#.` never exercise this — every one resolves a flat, top-level sibling — so this ERC states the cross-scope behavior explicitly rather than leaving it to be inferred.

### `switch`

`switch` selects which type or layout governs a field, based on the value of an expression. The expression MAY come from two places:

1. **An already-resolved sibling path** — the ordinary case, used when the expression is a normal ABI-decoded parameter of the same call, decoded by nothing new at all:

```json
{
  "path": "data",
  "switch": {
    "expression": { "path": "schema" },
    "cases": {
      "0x1234...": { "abiType": "(address recipient,bool isHuman,uint256 score)" },
      "$default": "reject"
    }
  }
}
```

This is the shape needed by EAS (`schema` selects how to decode `data`), ERC-7683 (`orderDataType` selects how to decode `orderData`), and ERC-7579 (`mode`'s decoded `callType` sub-field selects how to decode `executionCalldata`). As shorthand, `{"path": "<path>"}` MAY be written as the bare string `"<path>"` wherever only a path reference is needed and no inline byte-level parsing (`type`/`bytes`/`mask`) applies — used this way for `operation`'s `expression` above, and for `switch`'s `expression` whenever it is a plain sibling-path reference.

2. **Inline, read from the buffer at the current cursor position** — used only inside a `layout` tree, when the expression itself has to be parsed out of raw bytes rather than looked up as an already-decoded value:

```json
{ "type": "switch",
  "expression": { "type": "uint", "bytes": 1, "mask": "0x3f" },
  "payloadFrom": "inputs",
  "cases": {
    "0x00": { "abiType": "(address recipient,uint256 amountIn,uint256 amountOutMin,bytes path,bool payerIsUser)" },
    "$default": "reject"
  }
}
```

`mask` is an optional bitmask applied to the expression's raw value before matching against `cases` keys — needed for Universal Router, where the top bit of the command byte is an unrelated "allow revert" flag and only the low 6 bits select the command. `payloadFrom` names a sibling array (`inputs`), read at the same index as the current element of the enclosing `sequence` — a correlated-array lookup already precedented by ERC-7730's existing rule that a formatting parameter array is "read at the same index as the current element being formatted."

In both forms, a case value is one of:

* `{ "abiType": "<solidity type or tuple>" }` — decode the payload using the ordinary Solidity ABI decoder.
* `{ "layout": <node> }` — recurse into this ERC's own layout language (any node).
* `{ "switch": {...} }` — nest another switch (for multi-level tag structures).
* `{ "<solidity type or tuple>": { "intent": ..., "fields": [...] } }` — decode using the tuple signature given as the key, exactly like `abiType`, and immediately apply the given `intent`/`fields` to the result, without a separate top-level `display.formats` entry. This is sugar for `abiType` followed by inline structured display; it exists because a `switch` case very often wants to say both "decode it like this" and "display it like this" together, and forcing every case through a two-step `abiType`-then-somewhere-else-defined-fields indirection added no value in the surveyed cases (Universal Router's command table, most notably).
* `{ "format": "<base ERC-7730 format>" }` — stop: do not decode further, apply an ordinary base-ERC-7730 [field format](./erc-7730.md#field-format-specification) directly to the already-typed value in scope. This is for a case (very often `$default`) where the matched value needs no structural reinterpretation at all — it is already an ordinary value, just display it normally.
* `{ "label": "<text>", "intent": "info" | "warning" }` — stop: do not decode further, display `label` verbatim in place of any decoded value, with the given severity. This is for a case whose matched value has no meaningful decoded content to show at all — see the chained-reference example in [Test Cases](#test-cases), where a matched sentinel value stands for "a value only known once an earlier step in the same batch has executed on-chain," which is not a value a wallet can compute or display, only name.

Every `cases` map MAY include the reserved key `"$default"`, matched when no other case matches; its value is any of the case-value kinds above, or the literal string `"reject"`. A wallet MUST treat an expression value with no matching case, and no `$default` case present, the same way it treats an [unknown selector](./erc-7730.md#unknown-selectors): display a safe fallback and MUST NOT guess at a format. `$default` is an ordinary case, not a structurally different kind of thing — it MAY resolve to a full decode (as in the chained-reference example, where the *non*-sentinel branch is the one that needs `$default`), not only to `"reject"`.

### `switch` at the top of a structured data format specification

Every case above switches on an expression to reinterpret *one field's* bytes, while the rest of the call keeps its own fixed `intent` and `fields`. Some contracts have no such fixed meaning at all: the entire call exists only to be redirected, and which target function it becomes is the only thing worth describing. A [structured data format specification](./erc-7730.md#structured-data-format-specification) MAY declare a top-level `switch` object, with the same `expression`/`cases` shape (including `$default`) as above, instead of `intent`/`fields`. Its `expression` is a path to one of the outer call's own already-decoded parameters (never a raw-byte expression — there is no enclosing buffer to read one from at this level).

Because there is no bytes value being reinterpreted at this level, only two case-value forms are valid here: a nested `switch` (for an expression that further refines an already-matched case), or an `interaction` object naming a **different** target function outright — see below.

### `interaction`

`interaction` describes a call synthesized from already-decoded pieces, rather than a bytes value to be displayed directly or resolved via `format: "calldata"`. It is usable wherever a field format specification is (as an alternative to `format`/`layout`), and as a case value of a top-level `switch`:

```json
{ "interaction": {
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

**Why `switch` has two expression-sourcing forms instead of one.** Most of the surveyed cases (EAS, ERC-7683, ERC-7579) switch on an expression that is already sitting in an ordinary ABI-decoded field — no byte parsing is involved in getting it at all. Only Universal Router needs the expression pulled out of a raw byte mid-parse. Rather than forcing every case through a byte-oriented mental model, `switch` accepts a `path` directly.

**Why nested calldata reuses ERC-7730's own `calldata` format instead of a dedicated layout node.** An earlier iteration of this design had its own `call` layout node kind: declared directly as a field's `schema`/`layout`, it would recurse into ERC-7730's selector-matching itself. That worked, but it duplicated a mechanism ERC-7730 already has — [`format: "calldata"`](./erc-7730.md#embedded-calldata) already does exactly "this field's bytes are themselves a call to another contract, resolve them recursively," with `calleePath`/`selectorPath`/`amountPath`/`spenderPath` covering everything a `call` node did. Once this ERC's own [Path addressing](#path-addressing) rule lets an ordinary field entry's `path` reach into a `layout`-decoded `object`/`sequence` the same way it reaches into ABI-decoded ones, there is nothing left for a dedicated layout node to do that a sibling `format: "calldata"` field entry doesn't already do — parsing the bytes (plain `bytes`, consuming the right length) and interpreting them as a call become two separate, already-existing steps instead of one new fused one. The only real gap `format: "calldata"` had was `operation`: ERC-7730 has no concept of `DELEGATECALL` because an ordinary transaction field is never anything but a plain call. This ERC closes that one gap by adding `operation` as a new, optional param to the existing format, rather than re-deriving everything else `format: "calldata"` already does.

**Why `interaction` still exists as its own construct.** Unlike the case above, a call assembled from scattered, already-decoded values — no contiguous calldata bytes anywhere to point `format: "calldata"` at — has no equivalent already in ERC-7730. `interaction`'s `to`/`signature`/`args` shape is the minimum needed to express that: which target, which function (matched by signature text, since no selector was ever computed), and which already-decoded values bind to its arguments, in what order.

**Why the top-level `switch`/`interaction` form exists, and why it's the one exception to this ERC's evidence rule.** Every other construct in this ERC exists because a real, cited transaction needed it. This one does not have that grounding — no verified live transaction was found that reinterprets already-decoded parameters into a different function's argument list the way the [TieredExecutor example](../assets/erc-non-abi-dispatch/example-tiered-executor.json) does. It is included because the shape it targets — a small trusted relayer accepting a tag and a handful of generic-looking arguments, then re-dispatching to one of several unrelated target interfaces with a different argument order per target — is a common, plausible, and easily reachable governance/router pattern, structurally close to a `switch` over an enum parameter. Readers should weigh this construct with that in mind: it is motivated by generality, not by an observed case, unlike everything else here. If a real contract using this exact shape turns up, its transaction should replace the made-up one in the Test Cases section.

**Why `bitfield` is a distinct node type rather than a parameter on `uint`.** `object` and `sequence` both assume byte-aligned, non-overlapping fields — that assumption is load-bearing throughout the rest of this ERC (it's what makes the byte-width invariant a simple sum of child widths). `bitfield`'s named sub-fields can overlap arbitrarily within a shared width and carry no byte alignment at all, so keeping it a separate, clearly-labeled type (rather than, say, a `bits` option quietly attached to `uint`) makes it visually obvious, at the point a field is declared, that its sub-fields don't follow the rest of the language's byte-aligned norm. The motivating real case is Uniswap v4: hook contract addresses encode up to 14 independent permission flags in specific low-order bits of the 160-bit address value itself, verified against `Hooks.sol` and Uniswap's own v4 documentation.

**Why `initCode` is its own node type rather than a `switch` expression-sourcing mode.** An earlier version of this design considered folding creation-bytecode matching into `switch` as a fourth expression-sourcing mode (hash of a length-prefix of the buffer). That would have worked for the simplest case, but it doesn't generalize cleanly: some real creation-code templates append constructor arguments after a fixed prefix (a generic factory concatenating a template with a trailing ABI-encoded argument), while others — [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167) minimal proxies, verified against the standard's own bytecode listing — embed their one constructor-equivalent value (the implementation address) *between* a fixed prefix and a fixed suffix, with no ABI encoding at all. Expressing both shapes through a single scalar expression and a flat `cases` map would have needed the expression itself to somehow also carry "and here's where the matched region ends", which is exactly the kind of implicit, easy-to-get-wrong behavior the byte-width invariant exists to rule out elsewhere in this ERC. A dedicated node with explicit `prefix`/`suffix`/`args` fields makes the matched region's boundaries an explicit, checkable part of each template entry instead.

**Why `pointer` is its own node type, and why it needs `containerPath` rather than an implicit anchor.** Every other node in this ERC's layout language reads strictly forward from the cursor, which is what makes the byte-width invariant a simple, checkable sum. Safe's `execTransaction` breaks that on its own terms, not by choice of this ERC: verified against `Safe.sol`'s `checkNSignatures`/`checkContractSignature`, a signature record with `v == 0` repurposes its own `s` field — ordinarily half an ECDSA signature — as a byte offset into the *same* `signatures` buffer, pointing past all the fixed 65-byte records to a length-prefixed EIP-1271 blob shared by every contract-signer. No combination of `object`, `sequence`, or `bytes.lengthFrom` expresses "this value is a position to seek to, not data to read here" — `lengthFrom` only ever sizes a field from an already-read sibling's value, never repositions the cursor. An earlier version of this design left the offset's anchor implicit — always relative to the root of the enclosing `layout` tree — reasoning that only one anchor is evidenced, the same restraint applied to `sequence`'s `count`. That was reconsidered: `pointer` can appear nested inside a `sequence`'s `element`, several scopes below whatever "the enclosing layout tree" means informally, and Safe's own offset is relative to the *entire* `signatures` array, not to the 65-byte record the pointer happens to sit inside — exactly the kind of local-vs-root ambiguity this ERC's [Path addressing](#path-addressing) `#.` rule already had to resolve explicitly once, for a different construct. `containerPath` removes the ambiguity by construction rather than defining a fallback rule for it: every `pointer` states, visibly, which buffer it reads against, reusing the same path-reference idiom `format: "calldata"`'s `calleePath`/`amountPath`/`spenderPath` already established, rather than inventing an implicit-default rule that would need its own careful, easy-to-get-wrong specification.

**Why `$fallback` is needed at all.** Every other selector-related mechanism in ERC-7730 and this ERC assumes a 4-byte selector exists to be computed and matched. The generic deterministic-deployment proxy that motivates `initCode` — the same, single contract, deployed at the identical address on nearly every EVM chain, that many real, well-known contracts (including Uniswap's own Permit2) are deployed through — has no selector at all; its calldata is `salt ‖ initCode`, dispatched by a raw fallback. Without `$fallback`, `initCode` would have no contract it could actually be demonstrated on, since every other candidate factory this research pass found either has a normal ABI wrapper around its bytecode argument (already describable with plain `abiType`, no new construct needed) or turned out, on inspection, to build its creation code internally rather than receiving it as literal calldata at all.

**Why `layout` may anchor on an already-decoded scalar.** Balancer's `BalancerRelayer`/`BatchRelayerLibrary` — the `multicall`-based contract Balancer's own frontend and third-party "zap" integrations use to chain a `joinPool`/`exitPool`/`swap` sequence in one transaction — accepts ordinary ABI-decoded `uint256` amount fields (`maxAmountsIn[i]`, `outputReference`) that are *sometimes* not amounts at all: if the top 12 bits equal `0xba1`, the value is a "chained reference," a pointer to a storage slot the relayer will populate from an *earlier* step's output during execution of this same transaction, not a literal quantity (verified against `BaseRelayerLibraryCommon.sol`'s `_isChainedReference`). Every other tag-dispatch case in this ERC (EAS's `schema`, ERC-7683's `orderDataType`, ERC-7579's `mode`) reads its tag from a field genuinely separate from the value it governs. This one does not — the tag and the value it governs are the same field, examined under a mask. Rather than invent a self-referencing mode of `switch`'s path-sourced form (which would need its own reasoning about read/write ordering and cycles), this ERC reuses the existing, already-masked, inline `switch` node verbatim, and only generalizes *where* a `layout` tree is allowed to start: on the canonical encoding of a value ABI decoding already produced, not only on bytes still waiting to be parsed. This keeps one masking mechanism in the ERC instead of two.

**Why `$default` moved inside `cases` instead of staying a sibling key.** Originally `default` sat next to `cases`, and every example gave it the value `"reject"` — implying, without saying so, that `default` was structurally special: a fail-closed escape hatch, not really "a case" the way the entries in `cases` are. The chained-reference case above breaks that implication: its `$default` branch is the *common*, expected value (an ordinary amount), and the entry that needs special handling is the sentinel — an inversion of every prior example. Once `default` can legitimately hold a full decode instead of only `"reject"`, it is not structurally different from any other entry in `cases` — it only differs in its matching rule ("nothing else matched" instead of "matched this literal"). Moving it into `cases` under a reserved `$default` key makes that equivalence explicit, and matches the reserved-token convention this ERC already uses for `$index` and `$fallback`, rather than introducing a third way of marking a key as reserved. `initCode`'s `default` is deliberately left as a sibling key, unrenamed: it has no `cases` map to fold into (`templates` is a list, matched structurally, not a value map), and its value is, and remains, restricted to the literal `"reject"` — it was never a case candidate for this treatment in the first place.

**Why two new case-value kinds, `format` and `label`, and not one.** The chained-reference case needs both ends of the same problem solved: its `$default` branch has nothing unusual to say — the value is exactly what its ABI type already claims, so it needs a way to say "stop, this is fine, just display it normally" without an author re-deriving `intent`/`fields` for a plain amount. Its sentinel branch has the opposite problem: there is no value to compute or format at all — the real quantity is written by an earlier step's execution, after signing, and no construct in this ERC (or in ERC-7730 itself) can display a value that does not yet exist. `format` and `label` are the minimum needed for each half: `format` hands the value to ERC-7730's own existing formatting, unchanged; `label` displays fixed text in place of a value, for exactly the case where "unknown, and unknowable ahead of time" is itself the only honest thing to show. Neither is specific to Balancer — both are general terminal case-value kinds usable anywhere a `switch` case has nothing left to structurally decode, which is precisely the same "narrow but evidence-motivated" bar every other construct in this ERC was held to.

**Why `#.` crossing `switch`/`layout` scope boundaries is stated explicitly rather than left implied.** Building the `joinPool`/`exitPool` Test Case surfaced a real gap: `switch`-decoded fields like `userData`'s `amountsIn[i]` need to be displayed as token amounts, which requires pairing them with a token list (`request.assets`) that is not inside `userData` at all — it is a sibling of `userData`, one level up in the outer call. Base ERC-7730 defines `#.` as the root of the structured data, which reads as though it should handle this, but every actual use of `#.` in ERC-7730's own spec text and asset examples (checked exhaustively: one inline example plus three asset files) resolves a flat, top-level sibling — none of them cross out of a nested decode the way a `switch` case's local tuple scope requires. Left unstated, two conformant implementations could reasonably disagree on whether `#.` reaches past a `switch`/`layout` scope at all. This ERC resolves that ambiguity in favor of the more useful behavior — `#.` always reaches the true root — rather than requiring every such pairing to be left unresolved.

**Why positional binding, and why `args` may reorder.** ERC-7730 already treats parameter *names* as non-canonical for the purpose of selector matching — only position and type are. An `interaction` that redirects to a different function has no shared parameter names to align by in the first place (the outer call's `account`/`amount` mean nothing to the target function's own signature), so positional binding by the target's declared order is the only definition that is well-defined at all, and it is the same rule ERC-7730 already applies elsewhere, not a new one.

## Backwards Compatibility

This ERC only adds new, optional keys to a field format specification (`layout`, `switch`, `interaction`), plus one new, optional param (`operation`) to ERC-7730's own `format: "calldata"`, plus two new terminal case-value kinds (`format`, `label`) usable inside any `switch`'s `cases`. A descriptor that does not use them is unaffected, and a wallet implementing only ERC-7730 without this extension can safely ignore fields that use them, applying the existing [unknown field / raw fallback](./erc-7730.md) behavior. `$default` replacing a sibling `default` key is a pre-Draft naming change with no live adopters to migrate — see the [naming note](#test-cases) on this file's own not-yet-migrated example descriptors.

## Test Cases

Seven of the nine examples below are real, mined transactions, decoded from raw calldata (not an explorer's rendered summary) and cross-checked against at least one independent source. An eighth demonstrates `initCode`/`$fallback` against real, named, well-known contracts rather than one specific transaction. The ninth, `TieredExecutor`, is explicitly a made-up contract — see its own description below and the caveat in [Rationale](#rationale). Each is a full, standalone ERC-7730 descriptor file under [`../assets/erc-non-abi-dispatch/`](../assets/erc-non-abi-dispatch/) rather than a snippet, so it can be read with all the surrounding `context`/`metadata`/`display` structure intact.

### Safe `MultiSend`

Ethereum mainnet, tx [`0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e`](https://etherscan.io/tx/0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e). A Safe at `0xCa087C9e22bC97059d8fd6e25956835Ec205782B` delegatecalls `MultiSendCallOnly` (`0x40A2aCCbd92BCA938b02010E17A5b8929b49130D`) to batch six CTC ([`0xa3ee21c306a700e682abcdfe9baa6a08f3820419`](https://etherscan.io/address/0xa3ee21c306a700e682abcdfe9baa6a08f3820419)) `transfer` calls to six different recipients in one transaction. The 918-byte `transactions` buffer decodes (record 0 of 6) to `operation=CALL`, `to=0xa3ee21c306a700e682abcdfe9baa6a08f3820419`, `value=0`, `dataLength=68`, and `data` resolving, via `format: "calldata"`, into a normal `transfer(address,uint256)` sending `40000000000000000000000` (40,000 CTC) to `0x6ba2c52a959f0544e00aea60fe576463fe5fc38d`; the remaining five records follow the same shape, and the buffer is consumed exactly with no slack, confirming the `tillEnd` parse.

Full descriptor: [`example-safe-multisend.json`](../assets/erc-non-abi-dispatch/example-safe-multisend.json).

### Safe `execTransaction` (`pointer`)

Ethereum mainnet, Safe transaction hash [`0xe6cffb80c9521e152bc97b2bee23140bad634ecb02f9d5dcd57320b1cea95b60`](https://etherscan.io/tx/0xe6cffb80c9521e152bc97b2bee23140bad634ecb02f9d5dcd57320b1cea95b60), executed 2026-03-27. The Safe at `0xa5C629E04E563355c30885B62928fd6E03558548` — itself co-owned by GnosisDAO's own Safe (`0x0DA0C3e52C977Ed3cBc641fF02DD271c3ED55aFe`), confirmed via the Safe Transaction Service's `owners` index, which lists 14 Safes GnosisDAO's Safe is itself an owner of — delegatecalls (`operation=1`) `MultiSend` (`0x9641d764fc13c8B624c04430C7356C1C7C8102e2`) to batch 13 ERC-20 `transfer` calls, the buffer consumed exactly. `signatures` (195 bytes, three 65-byte records, sorted ascending by signer address) decodes to: record 0, `v=1` (`APPROVED_HASH`) from `0x1B0C638616Ed79dB430Edbf549ad9512FF4a8ed1`, `r` holding that same address and `s` unused (zero); records 1 and 2, ordinary `v=27` ECDSA signatures. All three are independently confirmed against the Safe Transaction Service's own per-signer `signatureType` field (`APPROVED_HASH`, `EOA`, `EOA`).

No `v=0` (`CONTRACT_SIGNATURE`) record — the one that actually exercises `pointer` — was found despite a real search: GnosisDAO's Safe co-signs at least 268 executed transactions across the Safes it owns (sampled directly via the Transaction Service), and every sampled confirmation is `EOA` or `APPROVED_HASH`. This suggests `approveHash` (a separate, simpler pre-validation transaction, surfacing as an ordinary `v=1` record in the child Safe) is how nested-Safe co-signing is actually done in practice, even though `CONTRACT_SIGNATURE` is a real, protocol-supported, currently-reachable path — verified directly against `Safe.sol`'s `checkNSignatures`/`checkContractSignature` (see [Rationale](#rationale)), not against a mined transaction. The descriptor's `pointer`-driven branch is marked accordingly.

Full descriptor: [`example-safe-exectransaction.json`](../assets/erc-non-abi-dispatch/example-safe-exectransaction.json).

### Uniswap Universal Router

Ethereum mainnet, tx [`0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba`](https://etherscan.io/tx/0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba), calling `execute(bytes,bytes[],uint256)` on the Universal Router at `0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`. `commands = 0x000004`: command 0 (`0x00`, `V3_SWAP_EXACT_IN`) sends `amountIn=3425828840000000000000` EURe through the path `EURe → EUR0 → EURC` with `payerIsUser=true`; command 1 (`0x00` again) swaps `amountIn=5138743260000000000000` EURe directly to EURC; command 2 (`0x04`, `SWEEP`) sweeps native ETH with `amountMinimum=0` back to the swapper. All three command bytes had their top (revert-flag) bit unset; token identities and pool fees were confirmed independently via each token's `symbol()`/`decimals()`.

Full descriptor: [`example-universal-router.json`](../assets/erc-non-abi-dispatch/example-universal-router.json).

### ERC-7579 `execute`

Base mainnet, Biconomy Nexus accounts (an ERC-7579 reference implementation), function selector `0xe9ae5c53`. Single-call example: tx [`0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1`](https://basescan.org/tx/0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1) — `mode` has `callType=0x00`, and `executionCalldata` decodes to `target=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC on Base), `value=0`, `callData` recursing into `transfer(0x3C97112223b1AD104Cf2ac022e450Ef862652b93, 1)`. Batch-call example: tx [`0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c`](https://basescan.org/tx/0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c) — `callType=0x01`, decoding to three executions (a native ETH transfer, a DAI `transfer`, and a USDC `transfer`) all to the same recipient, a single-UserOperation "sweep to one address" pattern. Both the mode layout and the callType-driven switch were confirmed against Nexus's own `ModeLib.sol`.

Full descriptor: [`example-erc7579-execute.json`](../assets/erc-non-abi-dispatch/example-erc7579-execute.json).

### Circle CCTP message

Base → Ethereum, 50,000 USDC. Burn tx [`0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f`](https://basescan.org/tx/0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f) on Base; mint tx [`0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f`](https://etherscan.io/tx/0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f) on Ethereum. The 248-byte `message` decodes to `sourceDomain=6` (Base), `destinationDomain=0` (Ethereum), `nonce=764152`, `sender`/`recipient` as the two chains' TokenMessenger contracts, `destinationCaller=0x0` (permissionless relay); the nested `messageBody` decodes to `burnToken` = Base USDC, `mintRecipient`/`messageSender` both the same self-relaying address, `amount=50000000000` (50,000 USDC). The 132-byte `messageBody` is consumed exactly.

Full descriptor: [`example-cctp-message.json`](../assets/erc-non-abi-dispatch/example-cctp-message.json). Note the descriptor's `context.contract` address is a placeholder — see the file's own `$comment`.

### EAS attestation

Optimism mainnet, schema `#78` (UID `0xfdcfdad2dbe7489e0ce56b260348b7f14e8365a8a325aef9834818c00d46b31b`), string `string rpgfRound,address referredBy,string referredMethod` — Optimism's RetroPGF badgeholder-referral schema. Attestation [`0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41`](https://optimism.easscan.org/attestation/view/0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41), tx `0x820e5b8404f1ec62b47459e538151e54fb598b729dcb461087456bb856abf595`, decodes to `rpgfRound="4"`, `referredBy=0x0000000000000000000000000000000000000342`, `referredMethod="Friend"`. `schema` and `data` are already-decoded ABI sibling fields of `attest()`'s own parameters, so no `layout` node is needed at all here — just `switch` sourced from a path. (A simpler, single-field schema also exists at scale — Coinbase's "Verified Account" schema, UID `0xf8b05c79f090979bf4a80270aba232dff11a10d9ca55c4f88de95317970f0de9`, `bool verifiedAccount`, 720,000+ attestations on Base — useful as a minimal case, but the RetroPGF one exercises both static and dynamic ABI types.)

Full descriptor: [`example-eas-attestation.json`](../assets/erc-non-abi-dispatch/example-eas-attestation.json). Note the descriptor's `context.contract` address is a placeholder — see the file's own `$comment`.

### ERC-7683 order

Base mainnet, tx [`0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09`](https://basescan.org/tx/0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09), calling `open((uint32,bytes32,bytes) order)` on Across's `AcrossOriginSettler` (`0x4afb570AC68BfFc26Bb02FdA3D801728B0f93C9E`) — a self-bridge of 1 USDC from Base to Arbitrum. `orderDataType = 0x9df4b782e7bbc178b3b93bfe8aafb909e84e39484d7f3c59f400f1b4691f85e2`, independently confirmed as `keccak256("AcrossOrderData(address inputToken,uint256 inputAmount,address outputToken,uint256 outputAmount,uint256 destinationChainId,bytes32 recipient,address exclusiveRelayer,uint256 depositNonce,uint32 exclusivityPeriod,bytes message)")`, decoding to `inputToken`/`outputToken` = USDC on Base/Arbitrum, `inputAmount=1000000`, `outputAmount=981521` (the relayer's fee), `destinationChainId=42161`, `recipient` equal to the sender, and empty `exclusiveRelayer`/`depositNonce`/`exclusivityPeriod`/`message`. Note this uses the same typehash-switch shape as the EAS example above — different ecosystem, same construct.

Full descriptor: [`example-erc7683-order.json`](../assets/erc-non-abi-dispatch/example-erc7683-order.json).

### Deterministic deployment proxy (`initCode` / `$fallback`)

The generic deterministic-deployment proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C` ("Nick's method") is deployed at this identical address on nearly every EVM chain and dispatches via a raw fallback — calldata is exactly `salt (32 bytes) ‖ initCode`, fed directly into `CREATE2`; there is no selector at all, which is what motivates `$fallback`. It is used to deploy many well-known contracts deterministically, including Uniswap's own Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`, the same address on every chain it's deployed to). The descriptor's second template is [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167)'s minimal-proxy creation code, byte-exact and fully verified against the standard's own bytecode listing: a 20-byte prefix (`0x3d602d80600a3d3981f3363d3d373d3d3d363d73`), a 20-byte embedded implementation address, and a 15-byte suffix (`0x5af43d82803e903d91602b57fd5bf3`) — 55 bytes total, with no ABI encoding involved at all, which is why `initCode` needed a `suffix` concept rather than just "prefix, then trailing ABI args."

Unlike the six examples above, this one demonstrates a mechanism against real, named, well-known contracts rather than one specific mined transaction. The Permit2 template's `prefix.hash`/`prefix.length` are explicitly marked as placeholders in the file — computing them requires Permit2's exact, compiler-version-specific creation bytecode, which was not independently re-derived for this example.

Full descriptor: [`example-deterministic-deployment-proxy.json`](../assets/erc-non-abi-dispatch/example-deterministic-deployment-proxy.json).

### `TieredExecutor` (made-up example)

A small, illustrative Solidity contract written for this ERC — [`TieredExecutor.sol`](../assets/erc-non-abi-dispatch/TieredExecutor.sol) — is **not deployed anywhere**; unlike every other example above, no real transaction exists for it. It demonstrates the top-level `switch`/`interaction` form: `executeOperation(address target, Operation op, address account, uint256 amount)` takes an enum expression `op` and two generic-looking arguments, and re-dispatches to one of two unrelated target interfaces — `IRewardVault.grantReward(address,uint256)` for `op=1`, `ILegacyToken.creditAccount(uint256,address)` for `op=2` — each with a different parameter order, resolved from the same `account`/`amount` values by positional binding.

Full descriptors: [`example-tiered-executor.json`](../assets/erc-non-abi-dispatch/example-tiered-executor.json) (the dispatching contract), [`example-reward-vault.json`](../assets/erc-non-abi-dispatch/example-reward-vault.json) and [`example-legacy-token.json`](../assets/erc-non-abi-dispatch/example-legacy-token.json) (the two target interfaces it recurses into, each an independently-authored descriptor resolved the same way any other embedded-calldata target would be).

> **Naming note:** the linked example files under [`../assets/erc-non-abi-dispatch/`](../assets/erc-non-abi-dispatch/) for the original six real-transaction cases (Safe `MultiSend`, Universal Router, ERC-7579, CCTP, EAS, ERC-7683) plus `TieredExecutor`'s three files still use this ERC's pre-rename vocabulary (`kind`, `struct`, `dispatch`, `tag`, and the now-removed `call` layout node) and have not yet been migrated to `type`/`object`/`switch`/`expression`/`format: "calldata"`. [`example-all-syntax-human.json5`](../assets/erc-non-abi-dispatch/example-all-syntax-human.json5) uses the current naming throughout for the three formats it covers (MultiSend, Universal Router, ERC-7579) and is the reference for what the migrated shape looks like; migrating the other files to match is open follow-up work. `example-safe-exectransaction.json`, and the separate Balancer relayer descriptors referenced from the `layout`-on-scalar and `#.` scope-crossing discussions above, already use the current naming throughout, having been authored after the rename.

## Reference Implementation

TBD

## Security Considerations

A `layout`/`switch`/`interaction` interpreter is new parsing surface on a hardware wallet, decoding attacker-influenced (calldata is provided by whoever submits the transaction) bytes. Implementations MUST bound recursion depth (embedded-calldata resolution, nested `switch`, `pointer`, and `interaction` can all recurse arbitrarily deep in principle), MUST treat any length (`lengthFrom`, or a `sequence`'s implicit `tillEnd` walk) that would read past the end of the underlying buffer as invalid input, and MUST fail closed — applying the [unknown selector](./erc-7730.md#unknown-selectors) fallback — rather than displaying a partially decoded or best-guess value when a `layout` or `switch` does not cleanly match the actual bytes. `operation` resolving to `"delegatecall"` is a particularly high-severity case of this: a wallet MUST fail closed exactly as hard for an unresolvable delegatecall target as it would for one with no descriptor at all, never falling back to treating it as a plain call.

`pointer` widens this surface specifically: a wallet MUST treat an offset (plus `destination`'s consumed width) that would read outside `containerPath`'s buffer as invalid input, the same fail-closed rule as any other out-of-bounds read. Recursion here is not merely theoretical: Safe's own `checkContractSignature` calls back into `isValidSignature` on the signing contract, which — if that contract is itself a Safe — recurses into that Safe's own `checkNSignatures` over its own `signatures` buffer, i.e. a `destination` that is itself another `pointer`-bearing `signatures` sequence. A wallet MUST bound this depth and fail closed past it, rather than parsing an attacker-supplied chain of nested signature buffers to unbounded depth.

`initCode` template matching is exact-bytes (or exact-hash) matching against a fixed template. A wallet MUST NOT treat a partial or fuzzy prefix/suffix match as a match — an attacker who can get even one byte accepted as "close enough" could potentially get unrelated, unaudited bytecode displayed as if it were a known, trusted template. Authors MUST keep `templates` entries pinned to one specific compiler version and settings; the same source recompiled differently produces different bytecode and MUST be treated as an entirely distinct, separately-audited template, never as a "should still basically match" variant of an existing one.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
