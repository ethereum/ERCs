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

[ERC-7730](./erc-7730.md) describes how to clear-sign structured data by decoding calldata as a Solidity ABI function call, then formatting the resulting named fields. This works as long as every value in the call is itself ABI-encoded. It breaks down for a common and growing class of contracts that accept one ABI-encoded `bytes` (or `bytes[]`) argument and then interpret its raw content using their own private encoding — packed structs, bit-packed flags, or a tag that selects one of several possible payload shapes. Gnosis Safe's `MultiSend`, Uniswap's Universal Router and hook addresses, and ERC-7579 modular accounts all do this, and none of it can be described in ERC-7730 today; such fields must be left as opaque, unreadable bytes.

This ERC adds three new keys to an ERC-7730 [field format specification](./erc-7730.md#field-format-specification) — `layout`, `switch`, and `interaction` — that let an author describe the internal structure of such a field, which structure applies where the field's shape depends on a tag value, and how to describe a call synthesized from already-decoded pieces rather than sliced out of contiguous bytes. Where a field's raw bytes already are a complete, contiguous call (selector and ABI-encoded arguments together), this ERC deliberately does not duplicate ERC-7730's own [embedded calldata](./erc-7730.md#embedded-calldata) mechanism (`format: "calldata"`) — it only extends that mechanism with one param, `operation`, for the one thing it cannot already express: a nested call that is a `DELEGATECALL` rather than a plain call. Everything else about ERC-7730 (context binding, metadata, top-level selector matching, path syntax) is unchanged; this ERC only extends what a single field's `path` can resolve into.

## Motivation

Look at what a `display.formats` entry can describe today: a Solidity function signature, decoded with the standard ABI rules, giving named parameters that `fields` entries point `path` at. That covers the overwhelming majority of contract calls. It does not cover contracts whose calldata carries a second, private encoding layer inside one of those ABI parameters:

- **Safe's `MultiSend.multiSend(bytes transactions)`** — `transactions` is not ABI-encoded. It is a tightly packed, back-to-back sequence of `(operation, to, value, dataLength, data)` records, repeated until the buffer runs out. Each record's own `data` is, in turn, a normal call to some other contract.
- **Uniswap's Universal Router `execute(bytes commands, bytes[] inputs)`** — `commands` is one raw opcode byte per sub-action (with a flag bit for "allowed to revert"); `inputs[i]` is separately ABI-encoded, but *which* ABI type it decodes as depends on the opcode at `commands[i]`.
- **ERC-7579 modular accounts, `execute(bytes32 mode, bytes executionCalldata)`** — `mode` packs five sub-fields into one word; `executionCalldata`'s shape (a single packed call, or an ABI-encoded array of calls) depends on one byte of `mode`.
- **Uniswap v4 hook addresses** — up to 14 independent permission flags (`beforeSwap`, `afterSwap`, and others) live in specific low-order bits of the 160-bit hook address itself; the same address value is simultaneously "an address" and "a bitmask," with no byte alignment between the two meanings.

None of this is exotic or rare. It is how batching, modular accounts, and generic-purpose routers already work across the ecosystem, and account-abstraction adoption is only going to produce more of it. A wallet with no way to describe these fields has no way to clear-sign them beyond showing raw hex — which is exactly the blind, trust-me signing experience ERC-7730 exists to eliminate.

The goal here is narrow on purpose. This ERC does not attempt to become a general-purpose binary serialization language (no attempt is made to describe Protobuf, Borsh, or arbitrary custom formats in full generality). It describes exactly the small set of shapes observed in real, widely used contracts: fixed-width packed fields, repeated records read until the buffer ends, and tag-selected payload types. Constructs are added because a real case needs them, not because they might be useful someday.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This ERC defines three additional keys usable in an ERC-7730 [field format specification](./erc-7730.md#field-format-specification): `layout`, `switch`, and `interaction`. A field format specification MUST NOT combine `layout` with `format`; the two are alternative ways of turning a field's raw value into something displayable, and `layout` takes over that job entirely for the field it is attached to. `interaction` is likewise mutually exclusive with `format` and `layout` — it describes a call synthesized from already-decoded values rather than any single bytes value being displayed or parsed. `switch` MAY be combined with any of the three, since it only decides *which* `layout`, ABI type, or nested structured format governs a field — it does not itself produce a displayable value.

### `layout`

`layout` describes the internal byte structure of a `bytes` field. Its value is a *layout node*. A layout node is one of the following types:

**Anchoring `layout` on an already-decoded scalar.** `layout` is normally attached to a field whose raw `bytes` have not been interpreted yet. It MAY also be attached to a field whose value was already produced by ordinary Solidity ABI decoding, if that value's declared type is a single-word elementary type — `uintN`/`intN`, `bool`, `address`, or a fixed-size `bytesN`. In that case the layout tree operates on the value's canonical 32-byte big-endian ABI-word encoding as its buffer, exactly as if those 32 bytes had been sliced out of a larger one. This is not extended to dynamic types (`bytes`, `string`, arrays, tuples) — no known case needs it, and "canonical encoding" is not a single well-defined byte sequence for them the way it is for a 32-byte word. See [Rationale](#rationale) for the motivating case.

**Primitive nodes**

```json
{ "type": "uint", "bytes": 1, "endian": "be" }
{ "type": "bytes", "length": 20 }
{ "type": "address" }
{ "type": "bool" }
```

`uint.bytes` is the width in bytes, from 1 to 32. `endian` is `"be"` or `"le"`, defaulting to `"be"` — every known EVM-side use case packs data big-endian, matching Solidity's own word layout; `"le"` exists only so this vocabulary does not need to change if a future non-EVM companion reuses it. `address` is sugar for a 20-byte `bytes` node. `bytes.length` MAY be a fixed integer, a `lengthFrom` reference to an earlier sibling field's decoded value (see `object` below), or omitted entirely on the last field of an `object`, meaning "consume whatever bytes remain in the enclosing buffer."

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

**`$index`** — inside the `element` of a `sequence`, or of a field iterated via `format: "array"` (a field whose value is already an ABI-decoded array, walked element-by-element rather than by consuming bytes), `$index` is a reserved token equal to the zero-based position of the element currently being processed. It is usable inside a `path` to correlate that element with the same-indexed value of a *different* sibling field — e.g. `commands[$index]`, read from inside an `inputs` element's `switch`, is the byte of the sibling `commands` sequence at the same position as the `inputs` element currently being resolved. This is Universal Router's actual structure: `commands` (raw `bytes`, one command per byte, parsed as a `sequence`) and `inputs` (already-decoded `bytes[]`, walked via `format: "array"`) are two separate fields advanced in lockstep by the same index, not one field nested inside the other — `$index` is what ties them together.

**Nested calldata reuses ERC-7730's own mechanism, not a layout node.** A field whose bytes — however they were reached, whether by ordinary ABI decoding or by a parent `layout` — are themselves a complete, contiguous call (a selector followed by ABI-encoded arguments) is described with ERC-7730's own [embedded calldata](./erc-7730.md#embedded-calldata) mechanism, `format: "calldata"`, addressed by an ordinary `path` into the (possibly `layout`-decoded) structure — see [Path addressing](#path-addressing), which already lets a `path` reach into `object` fields and `sequence` elements the same way it reaches into ABI-decoded ones. This is how Safe MultiSend's inner calls are described: the `data` field is parsed as plain `bytes` (its `dataLength` already covers the full selector-plus-arguments blob, unmodified from how Safe's own contract packs it), and a sibling top-level field entry with `path: "transactions[].data"` and `format: "calldata"` resolves it, using `calleePath`/`amountPath` to point back at `transactions[].to`/`transactions[].value`. The same pattern describes ERC-7579's batched executions: each element of the ABI-decoded `Execution[]` array has an ordinary `bytes callData` member, resolved by a field entry with `path: "executionCalldata[].callData"` and `format: "calldata"`, `params: {"calleePath": "executionCalldata[].target"}` — addressed at the same array index as its sibling `target`, the same by-index correlation ERC-7730 already uses for [array-valued formatting parameters](./erc-7730.md#field-format-specification). See [Rationale](#rationale) for why this ERC does not define its own parallel node for this instead.

This ERC extends `format: "calldata"`'s `params` with one new, optional key: `operation`, since ERC-7730's own definition has no way to express anything but a plain call. Its value is either a literal `"call"` (the default, identical to omitting `operation` entirely) or `"delegatecall"`, or an object choosing between them based on a tag:

```json
{ "expression": "<path to an already-decoded tag>", "cases": { "<tag value>": "call" | "delegatecall", "$default": "reject" } }
```

`expression`/`cases` (including the reserved `$default` case key) follow exactly the same rules as `switch` (below): a wallet MUST treat a tag value with no matching case, and no `$default` case supplied, as an [unknown selector](./erc-7730.md#unknown-selectors). When resolved to `"delegatecall"`, a wallet MUST make clear that the callee executes in the calling contract's own storage and identity (`DELEGATECALL` semantics), and MUST warn as strongly as it would for a raw, undescribed `delegatecall` if `to`'s descriptor cannot be resolved — a delegatecall to an unknown or unaudited target is a full account takeover, not a benign unknown call. Resolution of `to`'s own `display.formats` entry is otherwise unaffected by `operation`; only the execution-context semantics differ, not how the target function is looked up.

**Byte-width invariant.** Every `layout` node either consumes a well-defined, computable number of bytes from the buffer (all of the types above), or is explicitly declared non-consuming (only `switch`'s path-sourced expression form, below, which reads an already-resolved value instead of parsing bytes). No node type may be ambiguous about whether, or how much, it advances the cursor. A `layout` anchored directly on an already-decoded scalar (above) is a degenerate, trivially-satisfying case of this same invariant: there is no enclosing buffer to consume from or leave a remainder in, the buffer *is* the value's fixed 32-byte encoding in full, and the top-level node MUST consume it completely, the same rule applied everywhere else.

### Path addressing

Paths extend into `layout`-decoded fields the same way they already extend into ABI-decoded struct and array fields: by name for `object` and `bitfield` fields, by index for `sequence` elements. For example, given the `object` above, `#.transactions[0].to` refers to the `to` field of the first record. This is also what makes nested calldata resolvable without a dedicated layout node: a sibling top-level field entry can address `#.transactions[].data` directly and apply `format: "calldata"` to it, exactly as it would to any ordinary ABI-decoded `bytes` field.

**`#.` crosses `switch`/`layout` scope boundaries.** A `switch` case that decodes its payload into a tuple via the tuple-signature-key shorthand introduces a new, local field scope for that case's own `fields`: a relative path there resolves against the just-decoded tuple, not the outer call. `#.`, however, MUST still resolve against the absolute root of the entire structured data — the outer call's own top-level decoded parameters — regardless of how many `switch`/`layout` scopes deep the path is written. This is needed whenever a case's decoded value must be paired with a sibling of the field the `switch` is attached to, not a sibling within the tuple itself — for instance, resolving a `switch`-matched `amountsIn[i]` against a token list that lives one level up, alongside `userData` rather than inside it (see the [`joinPool`/`exitPool` Test Case](#test-cases)). Base ERC-7730's own examples of `#.` never exercise this — every one resolves a flat, top-level sibling — so this ERC states the cross-scope behavior explicitly rather than leaving it to be inferred.

### `switch`

`switch` selects which type or layout governs a field, based on the value of an expression. The expression MAY come from two places:

1. **An already-resolved sibling path** — the ordinary case, used when the expression is a normal ABI-decoded parameter of the same call, decoded by nothing new at all:

```json
{
  "path": "data",
  "switch": {
    "expression": { "path": "schema" },
    "cases": {
      "0x1234...": { "(address recipient,bool isHuman,uint256 score)": { "fields": [
        { "path": "recipient", "label": "Recipient", "format": "addressName" },
        { "path": "isHuman",   "label": "Is human" },
        { "path": "score",     "label": "Score" }
      ]}},
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
    "0x00": { "(address recipient,uint256 amountIn,uint256 amountOutMin,bytes path,bool payerIsUser)": { "fields": [
      { "path": "recipient",     "label": "Recipient", "format": "addressName" },
      { "path": "amountIn",      "label": "Amount in" },
      { "path": "amountOutMin",  "label": "Minimum amount out" },
      { "path": "path",          "label": "Swap path" },
      { "path": "payerIsUser",   "label": "Pay from wallet" }
    ]}},
    "$default": "reject"
  }
}
```

`mask` is an optional bitmask applied to the expression's raw value before matching against `cases` keys — needed for Universal Router, where the top bit of the command byte is an unrelated "allow revert" flag and only the low 6 bits select the command. `payloadFrom` names a sibling array (`inputs`), read at the same index as the current element of the enclosing `sequence` — a correlated-array lookup already precedented by ERC-7730's existing rule that a formatting parameter array is "read at the same index as the current element being formatted."

In both forms, a case value is one of:

* `{ "layout": <node> }` — recurse into this ERC's own layout language (any node).
* `{ "switch": {...} }` — nest another switch (for multi-level tag structures).
* `{ "<solidity type or tuple>": { "intent": ..., "fields": [...] } }` — decode the payload using the ordinary Solidity ABI decoder for the tuple signature given as the key, and immediately apply the given `intent`/`fields` to the result, without a separate top-level `display.formats` entry. This exists because a `switch` case very often wants to say both "decode it like this" and "display it like this" together (Universal Router's command table, most notably).
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

**Why `layout` may anchor on an already-decoded scalar.** Balancer's `BalancerRelayer`/`BatchRelayerLibrary` — the `multicall`-based contract Balancer's own frontend and third-party "zap" integrations use to chain a `joinPool`/`exitPool`/`swap` sequence in one transaction — accepts ordinary ABI-decoded `uint256` amount fields (`maxAmountsIn[i]`, `outputReference`) that are *sometimes* not amounts at all: if the top 12 bits equal `0xba1`, the value is a "chained reference," a pointer to a storage slot the relayer will populate from an *earlier* step's output during execution of this same transaction, not a literal quantity (verified against `BaseRelayerLibraryCommon.sol`'s `_isChainedReference`). Every other tag-dispatch case in this ERC (EAS's `schema`, ERC-7683's `orderDataType`, ERC-7579's `mode`) reads its tag from a field genuinely separate from the value it governs. This one does not — the tag and the value it governs are the same field, examined under a mask. Rather than invent a self-referencing mode of `switch`'s path-sourced form (which would need its own reasoning about read/write ordering and cycles), this ERC reuses the existing, already-masked, inline `switch` node verbatim, and only generalizes *where* a `layout` tree is allowed to start: on the canonical encoding of a value ABI decoding already produced, not only on bytes still waiting to be parsed. This keeps one masking mechanism in the ERC instead of two.

**Why `$default` moved inside `cases` instead of staying a sibling key.** Originally `default` sat next to `cases`, and every example gave it the value `"reject"` — implying, without saying so, that `default` was structurally special: a fail-closed escape hatch, not really "a case" the way the entries in `cases` are. The chained-reference case above breaks that implication: its `$default` branch is the *common*, expected value (an ordinary amount), and the entry that needs special handling is the sentinel — an inversion of every prior example. Once `default` can legitimately hold a full decode instead of only `"reject"`, it is not structurally different from any other entry in `cases` — it only differs in its matching rule ("nothing else matched" instead of "matched this literal"). Moving it into `cases` under a reserved `$default` key makes that equivalence explicit, and matches the reserved-token convention this ERC already uses for `$index`, rather than introducing a second way of marking a key as reserved.

**Why two new case-value kinds, `format` and `label`, and not one.** The chained-reference case needs both ends of the same problem solved: its `$default` branch has nothing unusual to say — the value is exactly what its ABI type already claims, so it needs a way to say "stop, this is fine, just display it normally" without an author re-deriving `intent`/`fields` for a plain amount. Its sentinel branch has the opposite problem: there is no value to compute or format at all — the real quantity is written by an earlier step's execution, after signing, and no construct in this ERC (or in ERC-7730 itself) can display a value that does not yet exist. `format` and `label` are the minimum needed for each half: `format` hands the value to ERC-7730's own existing formatting, unchanged; `label` displays fixed text in place of a value, for exactly the case where "unknown, and unknowable ahead of time" is itself the only honest thing to show. Neither is specific to Balancer — both are general terminal case-value kinds usable anywhere a `switch` case has nothing left to structurally decode, which is precisely the same "narrow but evidence-motivated" bar every other construct in this ERC was held to.

**Why `#.` crossing `switch`/`layout` scope boundaries is stated explicitly rather than left implied.** Building the `joinPool`/`exitPool` Test Case surfaced a real gap: `switch`-decoded fields like `userData`'s `amountsIn[i]` need to be displayed as token amounts, which requires pairing them with a token list (`request.assets`) that is not inside `userData` at all — it is a sibling of `userData`, one level up in the outer call. Base ERC-7730 defines `#.` as the root of the structured data, which reads as though it should handle this, but every actual use of `#.` in ERC-7730's own spec text and asset examples (checked exhaustively: one inline example plus three asset files) resolves a flat, top-level sibling — none of them cross out of a nested decode the way a `switch` case's local tuple scope requires. Left unstated, two conformant implementations could reasonably disagree on whether `#.` reaches past a `switch`/`layout` scope at all. This ERC resolves that ambiguity in favor of the more useful behavior — `#.` always reaches the true root — rather than requiring every such pairing to be left unresolved.

**Why positional binding, and why `args` may reorder.** ERC-7730 already treats parameter *names* as non-canonical for the purpose of selector matching — only position and type are. An `interaction` that redirects to a different function has no shared parameter names to align by in the first place (the outer call's `account`/`amount` mean nothing to the target function's own signature), so positional binding by the target's declared order is the only definition that is well-defined at all, and it is the same rule ERC-7730 already applies elsewhere, not a new one.

## Backwards Compatibility

This ERC only adds new, optional keys to a field format specification (`layout`, `switch`, `interaction`), plus one new, optional param (`operation`) to ERC-7730's own `format: "calldata"`, plus two new terminal case-value kinds (`format`, `label`) usable inside any `switch`'s `cases`. A descriptor that does not use them is unaffected, and a wallet implementing only ERC-7730 without this extension can safely ignore fields that use them, applying the existing [unknown field / raw fallback](./erc-7730.md) behavior.

## Test Cases

Seven of the eight examples below are real, mined transactions, decoded from raw calldata (not an explorer's rendered summary) and cross-checked against at least one independent source. The eighth, `TieredExecutor`, is explicitly a made-up contract — see its own description below and the caveat in [Rationale](#rationale). Each is a full, standalone ERC-7730 descriptor file under [`../assets/erc-non-abi-dispatch/`](../assets/erc-non-abi-dispatch/) rather than a snippet, so it can be read with all the surrounding `context`/`metadata`/`display` structure intact.

### Safe `MultiSend`

Ethereum mainnet, tx [`0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e`](https://etherscan.io/tx/0x414ae5aaff729927d663ccaa027ea2284e47fa546cb73ce1dee481ee36a7138e). A Safe at `0xCa087C9e22bC97059d8fd6e25956835Ec205782B` delegatecalls `MultiSendCallOnly` (`0x40A2aCCbd92BCA938b02010E17A5b8929b49130D`) to batch six CTC ([`0xa3ee21c306a700e682abcdfe9baa6a08f3820419`](https://etherscan.io/address/0xa3ee21c306a700e682abcdfe9baa6a08f3820419)) `transfer` calls to six different recipients in one transaction. The 918-byte `transactions` buffer decodes (record 0 of 6) to `operation=CALL`, `to=0xa3ee21c306a700e682abcdfe9baa6a08f3820419`, `value=0`, `dataLength=68`, and `data` resolving, via `format: "calldata"`, into a normal `transfer(address,uint256)` sending `40000000000000000000000` (40,000 CTC) to `0x6ba2c52a959f0544e00aea60fe576463fe5fc38d`; the remaining five records follow the same shape, and the buffer is consumed exactly with no slack, confirming the `tillEnd` parse.

Full descriptor: [`example-safe-multisend.json`](../assets/erc-non-abi-dispatch/example-safe-multisend.json).

### Uniswap Universal Router

Ethereum mainnet, tx [`0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba`](https://etherscan.io/tx/0x3805667353244e8fb763d50b7dd3bdb8f176119b44fdbd0a4ad5629d851ebbba), calling `execute(bytes,bytes[],uint256)` on the Universal Router at `0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`. `commands = 0x000004`: command 0 (`0x00`, `V3_SWAP_EXACT_IN`) sends `amountIn=3425828840000000000000` EURe through the path `EURe → EUR0 → EURC` with `payerIsUser=true`; command 1 (`0x00` again) swaps `amountIn=5138743260000000000000` EURe directly to EURC; command 2 (`0x04`, `SWEEP`) sweeps native ETH with `amountMinimum=0` back to the swapper. All three command bytes had their top (revert-flag) bit unset; token identities and pool fees were confirmed independently via each token's `symbol()`/`decimals()`.

Full descriptor: [`example-universal-router.json`](../assets/erc-non-abi-dispatch/example-universal-router.json).

### ERC-7579 `execute`

Base mainnet, Biconomy Nexus accounts (an ERC-7579 reference implementation), function selector `0xe9ae5c53`. Single-call example: tx [`0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1`](https://basescan.org/tx/0x057b1df67f033ad77faba10e39f39dde273c225d62c3b36ef8547b3f51fad5c1) — `mode` has `callType=0x00`, and `executionCalldata` decodes to `target=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC on Base), `value=0`, `callData` recursing into `transfer(0x3C97112223b1AD104Cf2ac022e450Ef862652b93, 1)`. Batch-call example: tx [`0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c`](https://basescan.org/tx/0x26d34bf7aa5adb0642218422264a4034ffda5785be3354168eb478051664613c) — `callType=0x01`, decoding to three executions (a native ETH transfer, a DAI `transfer`, and a USDC `transfer`) all to the same recipient, a single-UserOperation "sweep to one address" pattern. Both the mode layout and the callType-driven switch were confirmed against Nexus's own `ModeLib.sol`.

Full descriptor: [`example-erc7579-execute.json`](../assets/erc-non-abi-dispatch/example-erc7579-execute.json).

### Circle CCTP message

Base → Ethereum, 50,000 USDC. Burn tx [`0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f`](https://basescan.org/tx/0x178632412a0eb4e642bfe30b1f80d0a4799ab400d4d1c76702ba01ba1458b57f) on Base; mint tx [`0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f`](https://etherscan.io/tx/0xa5ab46a57e89fe110df3269065c0c07a394f22fe7a769bb916a547c7c1b3e99f) on Ethereum. The 248-byte `message` decodes to `sourceDomain=6` (Base), `destinationDomain=0` (Ethereum), `nonce=764152`, `sender`/`recipient` as the two chains' TokenMessenger contracts, `destinationCaller=0x0` (permissionless relay); the nested `messageBody` decodes to `burnToken` = Base USDC, `mintRecipient`/`messageSender` both the same self-relaying address, `amount=50000000000` (50,000 USDC). The 132-byte `messageBody` is consumed exactly.

Full descriptor: [`example-cctp-message.json`](../assets/erc-non-abi-dispatch/example-cctp-message.json). Note the descriptor's `context.contract` address (`0xYourMessageTransmitterAddress`) is a placeholder — confirm the real deployment address for your target chain against [Circle's own docs](https://developers.circle.com/cctp/evm-smart-contracts) before use.

### EAS attestation

Optimism mainnet, schema `#78` (UID `0xfdcfdad2dbe7489e0ce56b260348b7f14e8365a8a325aef9834818c00d46b31b`), string `string rpgfRound,address referredBy,string referredMethod` — Optimism's RetroPGF badgeholder-referral schema. Attestation [`0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41`](https://optimism.easscan.org/attestation/view/0x1a7a222934cbab53dd1c8e85d34e5fdd6d17cfd62a18ad871e4bec4705fdaa41), tx `0x820e5b8404f1ec62b47459e538151e54fb598b729dcb461087456bb856abf595`, decodes to `rpgfRound="4"`, `referredBy=0x0000000000000000000000000000000000000342`, `referredMethod="Friend"`. `schema` and `data` are already-decoded ABI sibling fields of `attest()`'s own parameters, so no `layout` node is needed at all here — just `switch` sourced from a path. (A simpler, single-field schema also exists at scale — Coinbase's "Verified Account" schema, UID `0xf8b05c79f090979bf4a80270aba232dff11a10d9ca55c4f88de95317970f0de9`, `bool verifiedAccount`, 720,000+ attestations on Base — useful as a minimal case, but the RetroPGF one exercises both static and dynamic ABI types.)

Full descriptor: [`example-eas-attestation.json`](../assets/erc-non-abi-dispatch/example-eas-attestation.json). Note the descriptor's `context.contract` address (`0xYourEASAddress`) is a placeholder — confirm the real deployment address for your target chain against [attest.org's own docs](https://docs.attest.org) before use.

### ERC-7683 order

Base mainnet, tx [`0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09`](https://basescan.org/tx/0x73b3ca11e3733c78db8365086f64874879fb3a859b21c960ec072c2a95c5da09), calling `open((uint32,bytes32,bytes) order)` on Across's `AcrossOriginSettler` (`0x4afb570AC68BfFc26Bb02FdA3D801728B0f93C9E`) — a self-bridge of 1 USDC from Base to Arbitrum. `orderDataType = 0x9df4b782e7bbc178b3b93bfe8aafb909e84e39484d7f3c59f400f1b4691f85e2`, independently confirmed as `keccak256("AcrossOrderData(address inputToken,uint256 inputAmount,address outputToken,uint256 outputAmount,uint256 destinationChainId,bytes32 recipient,address exclusiveRelayer,uint256 depositNonce,uint32 exclusivityPeriod,bytes message)")`, decoding to `inputToken`/`outputToken` = USDC on Base/Arbitrum, `inputAmount=1000000`, `outputAmount=981521` (the relayer's fee), `destinationChainId=42161`, `recipient` equal to the sender, and empty `exclusiveRelayer`/`depositNonce`/`exclusivityPeriod`/`message`. Note this uses the same typehash-switch shape as the EAS example above — different ecosystem, same construct.

Full descriptor: [`example-erc7683-order.json`](../assets/erc-non-abi-dispatch/example-erc7683-order.json).

### Balancer Relayer `joinPool`/`exitPool`

Ethereum mainnet, Safe transaction hash [`0x9ebb8a7d7c085b3dde80c02f5bc44a1d32749104e2b17d17bf72d7f674ef1b34`](https://etherscan.io/tx/0x9ebb8a7d7c085b3dde80c02f5bc44a1d32749104e2b17d17bf72d7f674ef1b34), executed 2026-05-22. `BalancerRelayer.multicall` (`0x35Cea9e57A393ac66Aaa7E25C391D52C74B5648f`) batches three delegatecalls into `BatchRelayerLibrary` (`0xeA66501dF1A00261E3bB79D1E90444fc6A186B62`): a bundled `setRelayerApproval`, then two `exitPool` calls that unwind a nested LP position two levels deep — exiting a Weighted pool (`kind=0x00`, `ExitKind=0x01`, a literal `16,250.97` pool tokens) for, among other tokens, the BPT of a Stable pool nested inside it, then exiting that Stable pool (`kind=0x03`, `ExitKind=0x02`) using the just-received BPT amount directly as a chained reference (`0xba10...0`) — a value that cannot be known until the first `exitPool` has actually executed on-chain. Both `userData`'s `JoinKind`/`ExitKind` dispatch (sourced from the sibling `kind` parameter, not from `poolId`) and the chained-reference sentinel were confirmed against `VaultActions.sol`/`WeightedPoolUserData.sol`/`StablePoolUserData.sol`/`BasePoolUserData.sol` source, and both non-default branches against the cited transaction's own two `exitPool` calls.

Full descriptors: [`example-balancer-relayer-multicall.json`](../assets/erc-non-abi-dispatch/example-balancer-relayer-multicall.json) (the outer `multicall` entry point) and [`example-balancer-relayer-library.json`](../assets/erc-non-abi-dispatch/example-balancer-relayer-library.json) (`setRelayerApproval`/`joinPool`/`exitPool`, reached only via the multicall's delegatecalls — `joinPool` itself is not exercised by the cited transaction, unlike `exitPool`).

### `TieredExecutor` (made-up example)

A small, illustrative Solidity contract written for this ERC — [`TieredExecutor.sol`](../assets/erc-non-abi-dispatch/TieredExecutor.sol) — is **not deployed anywhere**; unlike every other example above, no real transaction exists for it. It demonstrates the top-level `switch`/`interaction` form: `executeOperation(address target, Operation op, address account, uint256 amount)` takes an enum expression `op` and two generic-looking arguments, and re-dispatches to one of two unrelated target interfaces — `IRewardVault.grantReward(address,uint256)` for `op=1`, `ILegacyToken.creditAccount(uint256,address)` for `op=2` — each with a different parameter order, resolved from the same `account`/`amount` values by positional binding.

Full descriptors: [`example-tiered-executor.json`](../assets/erc-non-abi-dispatch/example-tiered-executor.json) (the dispatching contract), [`example-reward-vault.json`](../assets/erc-non-abi-dispatch/example-reward-vault.json) and [`example-legacy-token.json`](../assets/erc-non-abi-dispatch/example-legacy-token.json) (the two target interfaces it recurses into, each an independently-authored descriptor resolved the same way any other embedded-calldata target would be).

Every example file under [`../assets/erc-non-abi-dispatch/`](../assets/erc-non-abi-dispatch/) uses this ERC's current vocabulary (`type`/`object`/`switch`/`expression`/`format: "calldata"`, `$default` inside `cases`) and validates against [`erc7730-non-abi-dispatch.schema.json`](../assets/erc-non-abi-dispatch/erc7730-non-abi-dispatch.schema.json), the companion JSON Schema extending ERC-7730's own.

## Reference Implementation

TBD

## Security Considerations

A `layout`/`switch`/`interaction` interpreter is new parsing surface on a hardware wallet, decoding attacker-influenced (calldata is provided by whoever submits the transaction) bytes. Implementations MUST bound recursion depth (embedded-calldata resolution, nested `switch`, and `interaction` can all recurse arbitrarily deep in principle), MUST treat any length (`lengthFrom`, or a `sequence`'s implicit `tillEnd` walk) that would read past the end of the underlying buffer as invalid input, and MUST fail closed — applying the [unknown selector](./erc-7730.md#unknown-selectors) fallback — rather than displaying a partially decoded or best-guess value when a `layout` or `switch` does not cleanly match the actual bytes. `operation` resolving to `"delegatecall"` is a particularly high-severity case of this: a wallet MUST fail closed exactly as hard for an unresolvable delegatecall target as it would for one with no descriptor at all, never falling back to treating it as a plain call.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
