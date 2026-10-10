# ERC-8373 on-chain consumer

A Solidity implementation of the consumer half of the verification procedure: read the artifact's
anchor time from a substrate, resolve the in-force binding from the anchored chain, apply the cutoff
rule, and delegate the PQ companion check.

The other files in this directory are the conformance assets. This is a consumer that reproduces
them.

## Layout

| File | What it is |
|------|------------|
| `src/IPQKeyBindingConsumer.sol` | The consumer interface, the anchor-substrate and companion-verifier interfaces, and four enums |
| `src/PQCutoffEnforcer.sol` | Reference enforcer |
| `test/CutoffVectors.t.sol` | Drives the enforcer with `pq-key-binding-v1.cutoff-vectors.json` |
| `test/PQCutoffEnforcer.t.sol` | Unit tests for the rule, the chain, and access control |
| `test/VectorChain.sol` | Reads a case's declared chain without flattening its four shapes |

## Testing

```
forge test
```

Reproduces all 26 published v1 cutoff cases on four fields: `decision`, `evidence`,
`resolution_reason` and `rule`. The runner builds each case's own chain, including the ones that
declare an unavailable chain, an empty chain, an un-anchored binding or a delayed activation. A
declared state the enforcer cannot be driven into fails the suite rather than being skipped.

## Design notes

Four enums rather than one verdict, because the ERC requires an unverifiable to carry a reason and
requires that reason to be a closed enumeration on-chain. `PQEvidence` says what could be
established, `PQDecision` is a projection of that plus the cutoff, `PQReason` says how the chain
resolved, and `PQRule` says which limb of the cutoff rule fired. The zero value of each is the safe
one, so an uninitialised or unread path degrades to a refusal that establishes nothing.

`pre_baseline` and ended authority are separate values on purpose. They are opposite answers, and
collapsing them admits artifacts whose authority was deliberately ended.

An un-anchored binding is admitted into the chain and then never allowed to govern, rather than
rejected at registration. Rejecting reads as stricter and is weaker: a binding that cannot enter the
chain cannot be reported either, and the ERC asks for an unreadable anchor to surface as
unverifiable with a reason.

## Safety

Experimental software, provided as is. Not audited. Written to pin the semantics of the rule
readably rather than to be gas-efficient or production-ready. The PQ side of proof-of-possession is
not verifiable in the EVM today and is delegated, not assumed. Include your own tests and get an
audit before relying on any of it.
