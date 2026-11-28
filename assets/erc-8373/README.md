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

Reproduces all 41 published v1 cutoff cases on four fields: `decision`, `evidence`,
`resolution_reason` and `rule`. The runner builds each case's own chain, including the ones that
declare an unavailable chain, an empty chain, an un-anchored binding, a delayed activation, their own consumer cutoff or further revocations. A
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

## Canonicalization facet (`pq_key_binding.v1/canonicalization`)

| File | What it is |
|------|------------|
| `pq-key-binding-v1.canonicalization.json` | The facet's two admission bounds (member name 64 escaped bytes, statement 6208 bytes) and their derivation |
| `pq-key-binding-v1.canonicalization-vectors.json` | 34 cases: the six published statements (including a per-agent statement with a nested subject), an ML-DSA-87-sized binding, each bound at exactly the limit and one past it, unsupported shapes (booleans, null, decimals, arrays, top-level arrays, nesting deeper than one level) kept separate from non-canonical inputs (whitespace, member order, lone surrogates, integers at ±2^53), and nested-member cases |
| `canonicalization_check.py` | Stdlib admission check that reproduces the vectors |

```
python3 canonicalization_check.py pq-key-binding-v1.canonicalization.json pq-key-binding-v1.canonicalization-vectors.json
```

An independent on-chain anchor enforces the size bound at admission and proves canonical-form violations by a one-segment fraud proof. It is not part of these assets.


## Signature fixtures (`pq_key_binding.v1/signatures`)

| File | What it is |
|------|------------|
| `pq-key-binding-v1.signature-vectors.json` | The exact bytes of the published signatures: the genesis binding's possession signature, rotation continuity and possession, and the revocation authorization (SLH-DSA-SHA2-192s, direct route), and one live ML-DSA-65 binding signed through a Nostr carrier (carrier-bound route). Each case carries negative controls: wrong context, pre-hash SHA-512 and SHA-256, the message as a hex string, wrong message, wrong key, mutated signature, and for the carrier case the direct route and a tampered carrier |
| `check_signatures.mjs` | Recomputes each message from the statement or the carrier, then checks the signature and every control under one contract: pure mode, empty context, message = the 32 raw bytes |

```
npm install --no-save @noble/post-quantum@0.7.1
node check_signatures.mjs pq-key-binding-v1.signature-vectors.json
```

The source records are unchanged; this file only collects their bytes. It backs the signature contract under discussion for the Specification (decision D2) and is not yet listed as normative there.

## Which files are normative

The ERC's Test Cases section lists the normative file per facet and governs. For convenience:

| Facet | Normative file | Notes |
|---|---|---|
| Binding statement | `pq-key-binding-v0.vectors.json` | No v1 exists. The v0 prefix is the profile it was published under, not a superseded set |
| Cutoff enforcement | `pq-key-binding-v1.cutoff-vectors.json` | Supersedes `pq-key-binding-v0.cutoff-vectors.json`, which is kept unchanged as the frozen base the v1 profile refines and is not a second target |
| Rotation | `pq-key-binding-v1.rotation-vectors.json` (+ `pq-key-binding-v0.rotation.json`) | Supersedes `pq-key-binding-v0.rotation-vectors.json`, kept unchanged |
| Revocation | `pq-key-binding-v1.revocation-vectors.json` (+ `pq-key-binding-v0.revocation.json`) | Supersedes `pq-key-binding-v0.revocation-vectors.json`, kept unchanged |
| Canonicalization | `pq-key-binding-v1.canonicalization-vectors.json` (+ `.canonicalization.json`) | Current |
| Recovery classes | `recovery-classes-vectors.json` | Current |

The Python checkers for the normative facets:

```
python3 cutoff_enforce.py pq-key-binding-v1.cutoff-vectors.json
python3 cutoff_enforce.py pq-key-binding-v1.rotation-vectors.json
python3 cutoff_enforce.py pq-key-binding-v1.revocation-vectors.json
python3 canonicalization_check.py pq-key-binding-v1.canonicalization.json pq-key-binding-v1.canonicalization-vectors.json
python3 recovery_check.py recovery-classes-vectors.json
```

`pq-key-binding-v0.per-agent-anchor.json` is an informative snapshot of one deployment's batch
anchor, not a conformance target. `pq-key-binding-v0.spec.md` is the working spec of the v0 profile.
It is informative only. Where it and the ERC text differ, the ERC text governs.
