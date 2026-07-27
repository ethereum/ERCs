# Parked feature: dispatch over live chain state

Status: **not part of the companion ERC yet.** Parked pending [ethereum/ERCs#1738](https://github.com/ethereum/ERCs/pull/1738) ("Intent mutability") landing, since this idea is a direct extension of that PR's mechanism and shouldn't be specified independently of it.

## The problem this would address

Safe's `execTransactionFromModule`/Guard model, and similar "arbitrary installed extension" patterns, hand calldata to a contract that is:
- arbitrary and unbounded in general (any address the Safe owners enabled as a module), so
- there is no protocol-fixed schema to write a single descriptor against, the way there is for `MultiSend` (one fixed packed layout) or Universal Router (one bounded, enumerable command set).

The companion ERC's own Rationale (and the accompanying "10 impossible use-cases" exercise) currently treats this as out of scope: an arbitrary Module is fundamentally unboundable, full stop. That's still correct for the *general* case. But it's more pessimistic than necessary for the common real case: an owner enables one or a small number of *specific, known, audited* modules/guards (a spending-limit module, a specific Zodiac Roles configuration, a specific recovery module), and for exactly those known configurations, a descriptor author could, in principle, describe the resulting behavior precisely.

## PR #1738's mechanism (as landed/proposed today)

`context.contract.stateRefs`: an array of storage-slot preconditions —

```json
{
  "slot": "0x<storage slot>",
  "expectedValue": "0x<expected value>",
  "mask": "0x<optional bitmask>",
  "chainId": "<optional, for cross-contract refs>",
  "address": "<optional, for cross-contract refs>",
  "description": "human-readable explanation"
}
```

A wallet verifies live state matches `expectedValue` (masked, if `mask` is given) before trusting the descriptor's claimed intent. This is a **binary gate**: match → descriptor applies; mismatch → descriptor is stale, fall back to opaque signing. `context.contract.proxy` (typed EIP-1967/1822/2535 verification with `expectedImplementations`) is the same idea specialized to upgradeable-proxy implementation slots.

Also notable: #1738 has its own normative **omission rule** — anything whose intent depends on unexpressible factors (which includes arbitrary Module/Guard calldata) MUST be omitted from `display.formats` entirely. That's the PR's current, explicit answer to this exact problem: give up, don't describe it.

## The proposed extension: state as a dispatch tag, not just a gate

`stateRefs` only ever answers yes/no against one pinned expectation. What Module/Guard calldata actually needs is *selection*: "depending on which known, audited configuration is currently live, here is which interpretation applies" — a multi-way choice, not a single check. That is exactly what this companion ERC's `dispatch` construct already does for calldata-sourced tags; the extension is a **fourth tag-sourcing mode**, reading the tag from live chain state instead of from calldata, a decoded sibling field, or a hashed prefix:

```json
{ "kind": "dispatch",
  "tag": { "kind": "stateRef", "address": "@.to", "slot": "0x<guard storage slot>" },
  "cases": {
    "0x000000000000000000000000<auditedGuardAddress>": { "call": { "to": "@.to", "signature": "execTransaction(...)", "args": [ /* ... */ ] } }
  },
  "default": "reject"
}
```

Everything downstream of `tag` resolution is unchanged: the same `cases` map, the same case-value polymorphism (`abiType` / `layout` / `call` / nested `dispatch`), the same fail-closed `default: "reject"` for anything not explicitly enumerated.

This composes with #1738 rather than duplicating it: `stateRefs`/`proxy` would remain the *static* precondition layer ("this descriptor doesn't even apply unless..."), and a `stateRef`-tagged `dispatch` would be the *dynamic selection* layer on top ("...and depending on which of several known-audited configurations is live, here's which interpretation to use").

## What this does and does not solve

- **Does not** make arbitrary, unaudited Module/Guard calldata describable. That remains, correctly, unboundable — no descriptor language changes that.
- **Does** extend coverage to the case where the live module/guard is one of a small, enumerated, audited set the descriptor author explicitly listed — the same bounded, sparse, fail-closed shape every other `dispatch` table in this ERC already has.
- **Inherits** a real infrastructure requirement #1738 already introduces, not a new one: the wallet needs live chain-read access at signing time (a storage read, or, if generalized further, a `staticcall` return value), which most hardware wallets get via a companion app rather than standalone.

## Why this is parked, not drafted

- #1738 is still an open PR under active review (reviewer questions outstanding on diamond binding grain, omission-rule strictness, and whether preconditions should support view-function calls — the last of which is directly relevant to whether a `stateRef` tag should eventually generalize beyond raw storage slots to `staticcall` results too).
- Specifying a dependent extension before the mechanism it extends has stabilized risks having to redo this the moment #1738's own `stateRefs` shape changes during review.
- Revisit once #1738 lands: re-derive the exact `stateRef`/`slot`/`mask` shape from whatever #1738 actually ships (not from this snapshot), and decide whether `dispatch`'s fourth tag-sourcing mode belongs in this companion ERC or in a further, separate companion.
