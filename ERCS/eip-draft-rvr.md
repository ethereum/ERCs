---
title: Recomputable Verification Receipts
description: A six-field receipt using content-addressed claim, evidence-set, profile, and result identities.
author: Pavlo Tvardovskyi (@pipavlo82)
discussions-to: https://ethereum-magicians.org/t/recomputable-verification-receipts-rvr/29521
status: Draft
type: Standards Track
category: ERC
created: 2026-08-29
---

## Abstract

This ERC defines Recomputable Verification Receipts (RVR), a six-field receipt format built from content-addressed claim, evidence-set, profile, and result identities for independently recomputing profile-defined verification results. An RVR commits to a claim, an evidence-set closure, a Verification Profile, and one canonical result while keeping the semantic verification outcome separate from the status of a later recomputation. The format does not make a producer implementation authoritative and does not require an on-chain registry.

## Motivation

A stored boolean, verifier signature, or digest of an opaque report does not identify the claim, evidence closure, verification procedure, byte encoding, result semantics, and external context needed to derive the result again. Different implementations can therefore appear to agree while evaluating different inputs or interpreting the same data differently.

RVR makes those dependencies explicit and content-addressed. It separates two questions that are commonly collapsed:

- What did the identified verification procedure conclude?
- Could an independent implementation run that procedure and derive the identical canonical result?

This distinction is useful when Ethereum applications exchange off-chain verification results, optionally commit their digests on-chain, or compose semantic verification with observation commitments, proof-verifier interfaces, confidential-policy proofs, provenance records, or authenticated requests. An on-chain anchor can establish inclusion or ordering of receipt bytes, but it does not by itself establish that the committed semantic result is reproducible.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Terminology

The following terms are used:

- **Receipt**: the exact six-field RVR object.
- **Verification Profile**: the content-addressed authority defining one deterministic verification procedure, its proposition, closure, result contract, and reason codes.
- **Canonical result**: the single profile-defined result object from which receipt `outcome` and `reasonCode` are projected.
- **Evidence-set descriptor**: the content-addressed list of evidence-member identities and availability states.
- **Profile package root**: the explicit root against which profile-pinned dependency paths are resolved.
- **Gate rejection**: rejection of malformed, contradictory, or incompletely committed input before a verification outcome or recomputation status can be validly reported.
- **Candidate input**: the claim and evidence closure supplied for an independent recomputation against a fixed receipt and Verification Profile.

### Independent status axes

The verification outcome is semantic and MUST be one of:

| Outcome | Meaning |
| --- | --- |
| `VERIFIED` | The profile-defined proposition is satisfied under the committed closure. |
| `REFUTED` | The profile-defined proposition is contradicted under the committed closure. |
| `UNVERIFIABLE` | The profile-defined procedure completed and produced an identified indeterminate result that is neither `VERIFIED` nor `REFUTED`. |

A profile MUST define the exact conditions and reason codes for every outcome. `UNVERIFIABLE` is not limited to unavailable evidence. A profile MAY use it for unavailable decisive evidence, insufficient quorum, ambiguity, an undecidable relation, or another explicitly defined indeterminate state.

The recomputation status concerns a later independent run and MUST be one of:

| Status | Meaning |
| --- | --- |
| `REPRODUCED` | The candidate claim, evidence set, profile, and canonical result identities equal those committed by the receipt. |
| `DIVERGED` | Required dependencies were available and evaluation completed, but a candidate input identity or canonical result identity differed. |
| `CANNOT_RECOMPUTE` | A required profile dependency or committed-present payload could not be resolved, or a required profile dependency resolved to bytes that failed its immutable pin, so evaluation could not legitimately run. |

The recomputation status is not a seventh receipt field. It is the output of applying the recomputation procedure to a receipt and supplied dependencies.

An `UNVERIFIABLE` result MAY be `REPRODUCED`. `CANNOT_RECOMPUTE` MUST NOT be converted into `UNVERIFIABLE`, `REFUTED`, `DIVERGED`, or a default false value.

### Receipt

An RVR receipt MUST be a JSON object with exactly these six members and no others:

```text
claimDigest
evidenceSetDigest
verificationProfileDigest
outcome
reasonCode
resultDigest
```

The four digest members MUST be 64 lowercase hexadecimal characters without a prefix and identify SHA-256 digests. `outcome` MUST be one of the three verification outcomes. `reasonCode` MUST be a member of the Verification Profile's committed verification reason-code namespace.

The receipt is accompanied by, but does not embed, the claim object, evidence-set descriptor and payloads, Verification Profile package, and canonical result object.

### Canonical byte contract

All identity-bearing RVR JSON objects MUST use `rvr-canonical-json-v0`.

Its input domain consists only of JSON null, booleans, Unicode scalar-value strings, arrays, and objects. JSON numbers are forbidden. Quantities such as byte lengths MUST be encoded as canonical unsigned decimal strings matching `^(?:0|[1-9][0-9]*)$`, with no sign and no leading zeros except for the single string `0`.

Canonicalization MUST apply these rules:

1. Reject duplicate object keys after JSON string decoding.
2. Reject lone Unicode surrogate code points. A well-formed escaped surrogate pair represents its single Unicode scalar value.
3. Apply no Unicode normalization.
4. Encode null as `null` and booleans as `true` or `false`.
5. Encode strings using the exact string-escaping rules below.
6. Preserve array order and duplicates.
7. Sort object keys by ascending Unicode scalar-value sequence.
8. Emit no insignificant whitespace.
9. Encode the resulting canonical string exactly once as UTF-8.

String encoding MUST emit an opening quotation mark, process each Unicode scalar value in order, and emit a closing quotation mark. The exact escapes are:

| Scalar value | Emitted sequence |
| --- | --- |
| `U+0022` quotation mark | `\"` |
| `U+005C` reverse solidus | `\\` |
| `U+0008` | `\b` |
| `U+0009` | `\t` |
| `U+000A` | `\n` |
| `U+000C` | `\f` |
| `U+000D` | `\r` |
| Other `U+0000` through `U+001F` | `\u00xx`, using exactly two lowercase hexadecimal digits |
| Every other Unicode scalar value | Its literal UTF-8 encoding |

The solidus `U+002F`, line separator `U+2028`, and paragraph separator `U+2029` MUST be literal. No other optional JSON escape spelling is permitted. These rules apply to both object keys and string values.

### Identity rules

The following identities MUST be computed over exact canonical bytes:

```text
claimDigest =
  SHA-256(rvr-canonical-json-v0(claim))

verificationProfileDigest =
  SHA-256(rvr-canonical-json-v0(verificationProfile))

resultDigest =
  SHA-256(rvr-canonical-json-v0(canonicalResult))
```

The SHA-256 output MUST be encoded as lowercase hexadecimal without a prefix.

### Evidence set

An evidence-set descriptor MUST be an object with exactly:

```text
schema
members
```

`schema` identifies the profile-pinned evidence-set contract. `members` MUST be a non-empty array. Member IDs MUST be unique.

A present member MUST contain exactly:

```text
id
status = PRESENT
mediaType
byteLength
digest
```

`byteLength` MUST be the canonical unsigned decimal length of the exact raw payload bytes. `digest` MUST be the SHA-256 digest of those exact bytes. A resolved `PRESENT` member MUST have exactly one supplied payload whose byte length and digest match the descriptor. If the committed-present payload cannot be resolved, the descriptor remains valid but recomputation MUST return `CANNOT_RECOMPUTE` with `evaluationPerformed = false` and MUST NOT run evaluation.

An unavailable member MUST contain exactly:

```text
id
status = UNAVAILABLE
reasonCode
```

An unavailable member MUST have no supplied payload. The profile determines whether and how that committed availability state affects the semantic result.

Before evidence-set canonicalization, `members` MUST be normalized by ascending member `id` under Unicode scalar-value ordering. The evidence-set identity is:

```text
evidenceSetDigest =
  SHA-256(rvr-canonical-json-v0(normalizedEvidenceSetDescriptor))
```

Every input capable of changing the verification outcome MUST be included in the committed evidence closure or identified by an immutable commitment or snapshot defined by the Verification Profile. Outcome-relevant ambient input is forbidden.

RVR does not require evidence to be globally public. Required committed dependencies need only be resolvable by the recomputer under the profile's rules. If a member is committed as present but its payload cannot be resolved, the status is `CANNOT_RECOMPUTE` and evaluation MUST NOT be reported as performed.

Reproducing a result derived from an `UNAVAILABLE` descriptor proves that the descriptor contained that state and that the profile derived the result correctly. It does not by itself prove the historical fact that evidence was objectively impossible to obtain. A profile requiring proof of absence or unavailability MUST commit that proof as evidence or immutable external context.

### Verification Profile

The Verification Profile is the semantic authority. A producer implementation, signer, or registry is not authoritative merely because it emitted or stored a receipt.

A Verification Profile MUST be an `rvr-canonical-json-v0` object and MUST commit, directly or through exact immutable dependency identities, to:

- a unique profile identifier;
- the exact verification specification;
- the exact proposition established by each possible canonical result;
- a pinned conformance-vector set;
- the canonical serializer and byte contract;
- the receipt, claim, evidence-set, and canonical-result contracts;
- result-hash and receipt-projection rules;
- the verification, recomputation, and gate-rejection reason-code namespaces;
- profile-specific constraints;
- dependency-resolution rules;
- every required outcome-relevant external-context commitment.

`profileId` MUST match `[A-Za-z0-9][A-Za-z0-9._-]*`.

The verification specification and canonical-result contract MUST jointly make the recomputation target unambiguous. A profile MAY define deterministic derivation of a semantic result, or a deterministic verification relation over an already-produced artifact. It MUST NOT claim that a nondeterministic judgment was reproduced merely because an authenticated artifact containing that judgment was verified.

The common profile envelope MUST contain these members:

```text
schema
profileId
profileSchemaContract
dependencyResolution
verificationSpecification
conformanceVectorSet
canonicalByteContract
schemaContracts
evidenceSetContract
canonicalResultContract
resultHashRules
reasonCodeNamespace
externalContextPolicy
```

The common envelope and every common nested object defined below MUST reject
additional members. Profile-specific semantics belong in the pinned
verification specification, schemas, and constraints rather than as
unidentified envelope extensions.

A dependency identity MUST contain exactly:

```text
id
path
sha256
requiredForRecomputation
```

`id` MUST be unique within its containing dependency set. `path` MUST follow the resolution rules below. `sha256` MUST be a lowercase hexadecimal SHA-256 digest. `requiredForRecomputation` MUST be a boolean. Any dependency whose bytes can affect validation, evaluation, the canonical result, or recomputation status MUST set `requiredForRecomputation` to `true`. A dependency marked `false` MUST be non-semantic conformance or provenance material and MUST NOT influence recomputation.

`profileSchemaContract` MUST identify both the generic manifest schema and a profile-specific constraints schema. The constraints schema MUST NOT be parsed or applied before its exact bytes match its committed digest.

`profileSchemaContract` MUST contain exactly `manifest` and `constraints`,
each encoded as a dependency identity. `dependencyResolution` MUST contain
exactly `base`, `pathFormat`, `locatorRole`, and `verificationOrder`, with the
following values:

```text
base = SUPPLIED_PROFILE_PACKAGE_ROOT
pathFormat = relative-posix-no-empty-dot-dotdot-or-colon-segments
locatorRole = NORMATIVE_PACKAGE_RELATIVE_PATH
verificationOrder = resolve-read-sha256-match-use
```

`verificationSpecification` MUST be one dependency identity.

`conformanceVectorSet` MUST identify its member files and an aggregate digest. The aggregate digest MUST be SHA-256 over UTF-8 rows sorted by path, with each row encoded exactly as:

```text
<path>\t<SHA-256(exact-file-bytes)>\n
```

`conformanceVectorSet` MUST contain exactly `id`, `members`, `digest`, and
`digestRule`. `members` MUST be a non-empty array of dependency identities,
paths MUST be sorted by Unicode scalar-value sequence for the aggregate, and
`digestRule` MUST equal
`sha256-utf8-sorted-path-tab-file-sha256-lf-rows`.

`canonicalByteContract` MUST identify `rvr-canonical-json-v0` and its rules exactly as specified by this ERC.

`canonicalByteContract` MUST contain exactly `id`, `encoding`, `domain`,
`objectKeyOrder`, `arrayOrder`, `unicode`, `numbers`, `stringEscaping`,
`solidus`, `lineSeparators`, and `whitespace`. Their exact values MUST be:

```text
id = rvr-canonical-json-v0
encoding = UTF-8
domain = null-boolean-unicode-scalar-string-array-object
objectKeyOrder = unicode-scalar-value-ascending
arrayOrder = preserved-with-duplicates
unicode = scalar-values-only-no-normalization
numbers = forbidden
stringEscaping = rvr-json-string-escaping-v0
solidus = literal
lineSeparators = U+2028-and-U+2029-literal
whitespace = none
```

`schemaContracts` MUST be a non-empty array of dependency identities with
unique IDs.

`evidenceSetContract` and `canonicalResultContract` MUST identify exact schema bytes and JSON Schema pointers. `canonicalResultContract` MUST define JSON Pointer projections for `outcome` and `reasonCode`. The pinned verification specification and result contract MUST define the exact proposition represented by the result.

`evidenceSetContract` MUST contain exactly `schemaPath`, `schemaSha256`,
`schemaPointer`, and `digestRule`. `canonicalResultContract` MUST contain
exactly `schemaPath`, `schemaSha256`, `schemaPointer`, `outcomeProjection`, and
`reasonCodeProjection`. The evidence-set `digestRule` MUST equal
`sha256-utf8-rvr-canonical-json-v0-normalized-member-order`.

`resultHashRules` MUST require SHA-256 over the exact `rvr-canonical-json-v0` canonical result bytes and lowercase hexadecimal output without a prefix.

`resultHashRules` MUST contain exactly `algorithm`, `input`, `encoding`, and
`output`, with the following values:

```text
algorithm = SHA-256
input = rvr-canonical-json-v0(canonicalResult)
encoding = UTF-8-exactly-once
output = lowercase-hex-no-prefix
```

`reasonCodeNamespace` MUST enumerate all permitted verification, recomputation, and gate-rejection reason codes. Each set MUST contain unique values.

`reasonCodeNamespace` MUST contain exactly `verification`, `recomputation`,
and `gateRejections`, each encoded as an array of strings.

`externalContextPolicy` MUST forbid uncommitted ambient inputs and MUST enumerate every immutable external-context commitment required by the profile. Mutable chain state, registry state, time, policy, model output, resolver output, or API response MUST NOT affect a reproducible outcome unless frozen by a profile-defined immutable commitment or snapshot.

`externalContextPolicy` MUST contain exactly `mode`, `ambientInputs`, and
`immutableCommitments`. `ambientInputs` MUST equal `FORBIDDEN`, and
`immutableCommitments` MUST be an array of profile-defined immutable identity
strings.

### Dependency resolution

The recomputer MUST receive an explicit profile package root with the profile package. A dependency path is a normative package-relative locator, not a process-working-directory path, URL, Git reference, or advisory hint.

Dependency paths:

- MUST use `/` as the separator;
- MUST be relative;
- MUST NOT contain empty, `.` or `..` segments;
- MUST NOT contain reverse solidus or colon characters;
- MUST resolve within the supplied package root, including after resolving filesystem links.

For each dependency, the only permitted order is:

```text
resolve under the supplied profile package root
  -> read exact bytes once
  -> verify SHA-256 against the committed digest
  -> parse or use those same verified bytes
```

Bytes MUST NOT influence validation or evaluation before their committed digest matches. Re-reading a locator after verification and using different bytes is forbidden.

The generic profile schema is the bootstrap contract supplied to the verifier. After strict parsing, the profile's generic-schema pin MUST identify byte-for-byte that same bootstrap schema. The profile-specific constraints schema MUST be hash-verified before parsing or application.

### Canonical result and receipt projections

Each profile MUST define exactly one canonical-result contract. Every canonical result MUST contain profile-defined data sufficient to identify the exact proposition, semantic outcome, reason code, and relevant evaluation facts.

The receipt `outcome` MUST equal the result selected by the committed outcome projection. The receipt `reasonCode` MUST equal the result selected by the committed reason-code projection.

A receipt with contradictory top-level projection fields is invalid even if `resultDigest` correctly identifies the canonical result. This is a gate rejection, not `DIVERGED` or `REFUTED`.

### Recomputation procedure

Given a receipt, original canonical result, candidate claim and evidence, and a supplied profile package, a recomputer MUST perform these steps in order:

1. Strictly parse the receipt and generic Verification Profile envelope. Reject duplicate keys, forbidden numbers, lone surrogates, and schema-invalid shapes.
2. Recompute `verificationProfileDigest` and require equality with the receipt.
3. Resolve every required profile dependency using hash-before-parse rules and resolve every candidate evidence payload whose descriptor is committed as `PRESENT`. If a required profile dependency or committed-present payload cannot be resolved, return `CANNOT_RECOMPUTE` with `evaluationPerformed = false`. If a required profile dependency resolves to bytes whose SHA-256 digest does not equal its committed pin, return `CANNOT_RECOMPUTE` with `evaluationPerformed = false`; those bytes MUST NOT be parsed or used.
4. Validate the original receipt, canonical result identity, and result projections. Contradictory projections or malformed committed objects are gate rejections.
5. Validate the candidate evidence closure. Duplicate members, uncommitted outcome-relevant input, a resolved `PRESENT` payload whose byte length or digest does not match its descriptor, or an `UNAVAILABLE` member with a payload are gate rejections.
6. Recompute the candidate `claimDigest` and `evidenceSetDigest`.
7. Execute the profile's deterministic verification procedure and derive exactly one canonical result.
8. Recompute the canonical result bytes and `resultDigest`.
9. Return `REPRODUCED` only if the candidate claim, evidence-set, Verification Profile, and canonical-result identities equal the receipt commitments.
10. Otherwise, if evaluation completed under the fixed profile, return `DIVERGED` and preserve the newly derived verification outcome and reason code as diagnostic data.

A recomputer MUST NOT trust stored expected output in place of executing the verification procedure.

### Conformance requirements

A conforming profile suite MUST mechanically demonstrate at least:

- an identical recomputation producing `REPRODUCED`;
- an evaluated, internally self-consistent claim- or evidence-relevant mutation producing `DIVERGED` for the intended semantic reason rather than failing only because of unrelated descriptor drift;
- an original `UNVERIFIABLE` result independently producing `REPRODUCED`;
- an unavailable required normative dependency producing `CANNOT_RECOMPUTE` without evaluation;
- a required normative dependency resolving to bytes that fail its committed digest producing `CANNOT_RECOMPUTE` without parsing or evaluation;
- an unavailable committed-present evidence payload producing `CANNOT_RECOMPUTE` without evaluation;
- rejection of a resolved committed-present payload whose byte length or digest does not match its descriptor;
- a control proving that withholding or substituting the bytes of a dependency marked `requiredForRecomputation = false` cannot change validation, evaluation, the canonical result, or recomputation status;
- rejection of a contradictory receipt projection while preserving `resultDigest`;
- rejection of outcome-relevant hidden state;
- a hash-before-parse negative control for profile-specific constraints;
- at least one counterfactual demonstrating that the evaluator can fail for the intended semantic reason.

The local conformance entry point and continuous-integration entry point SHOULD execute the same logical gate.

## Rationale

### Acknowledgements

Special thanks to Tiago Merlini (@TMerlini), Fede / Baby Blue Viper
(@babyblueviper1), Faisal Firdani (@zexoverz), and Damon Zwicker
(@damonzwicker) for independent review, executable counterexamples, external
integration work, and semantic boundary analysis that materially improved
this proposal.

### Six receipt fields

The receipt contains only the identities and projections required to identify a verification result. Serializer, vector-set, schema, and specification digests are not copied into the receipt because they are already committed by `verificationProfileDigest`. Adding them would create redundant values that could contradict the profile.

The receipt itself is not self-addressed. `resultDigest` identifies the canonical result, not the receipt object containing it.

### Profile authority

Different domains require different claims, evidence, reason codes, and external-context rules. Placing those semantics in a content-addressed Verification Profile permits independent implementations without treating one producer binary as authoritative.

The exact proposition is profile-bound because successful execution of different deterministic procedures can establish different facts. Re-deriving a policy decision and verifying a proof emitted by a committed interpreter are not interchangeable even if both procedures are deterministic.

### Evidence-set identity

A single evidence-blob digest cannot express multiple inputs, explicit unavailability, media types, or independently resolvable members. The evidence-set descriptor closes every outcome-relevant input while allowing payloads to remain separately stored or private.

### No mandatory registry

RVR is a portable artifact format. A receipt digest MAY be anchored by an application, but this ERC does not define a registry, settlement mechanism, timestamp authority, or finality rule. Anchoring bytes does not upgrade their semantic meaning.

### Relationship to neighboring proposals

RVR is complementary to application-layer mechanisms that authenticate requests, commit observations, prove private-policy evaluation, record provenance, or verify inference proofs.

[ERC-8354](./eip-8354.md) defines confidential agent policy verdicts. RVR does not define its proof system or policy semantics; a Verification Profile can identify such a deterministic proof-verification relation and its committed inputs.

[ERC-8004](./eip-8004.md) defines agent identity, reputation, and validation registries. RVR requires neither an agent identity nor a registry.

The open Observation Commitment Protocol, AI Inference Proof Verification Interfaces, AI Input Provenance, and Delegated Signed HTTP Requests proposals address commitment, proof, provenance, and authorization layers. RVR addresses the distinct layer of reproducing a profile-defined semantic result over committed verification inputs.

## Backwards Compatibility

This ERC introduces a new off-chain artifact format and does not change Ethereum consensus, transaction validity, existing contracts, or existing receipt formats.

Experimental pre-standard RVR profiles remain identified by their exact profile bytes and digests. This ERC does not retroactively reinterpret those profiles. Applications adopting this ERC MUST use a profile whose exact specification and contracts conform to this document.

## Test Cases

All strings in this section are shown without a trailing line feed unless explicitly stated.

### Canonical bytes

| Input value | Exact canonical UTF-8 text | SHA-256 |
| --- | --- | --- |
| Empty object | `{}` | `44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a` |
| Object inserted as `z`, then `a` | `{"a":false,"z":true}` | `2d4c5e658033e60d493bb262f74a47856d87537f8084d73a2f7b16fb1221f181` |
| String containing `U+2028 U+2029` | exact bytes `22 e2 80 a8 e2 80 a9 22` | `e3a0e2262ac7790f4df36b522a8fbdd4ee3370d568eb15dc25c5f1775f14ed6c` |

The following inputs MUST be rejected before identity computation:

- any JSON number;
- duplicate decoded object keys;
- a lone high or low surrogate;
- an optional escape spelling where this ERC requires a literal scalar value.

Arrays `["a","a","b"]` and `["a","b","a"]` MUST produce different canonical bytes. Strings encoded as precomposed `U+00E9` and decomposed `U+0065 U+0301` MUST produce different canonical bytes.

### Identity example

For exact evidence bytes `abc`, the SHA-256 digest is:

```text
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

The canonical claim bytes are:

```json
{"evidenceMember":"artifact","expectedDigest":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","operation":"SHA256_EQUALS","schema":"rvr.claim.sha256-equals.v0"}
```

Its `claimDigest` is:

```text
1a3e1868528b22a4a7b33943922cc968ae84c5d3a8b588b56ccb17c6e4d022c9
```

The normalized evidence-set descriptor bytes are:

```json
{"members":[{"byteLength":"3","digest":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","id":"artifact","mediaType":"application/octet-stream","status":"PRESENT"}],"schema":"rvr.evidence-set.v0"}
```

Its `evidenceSetDigest` is:

```text
ad2e277f24b256b63cbdfffefa750fa2fea84b93dea0cb18a38ba52ec66e2f99
```

The canonical result bytes are:

```json
{"evaluation":{"evidenceMember":"artifact","expectedDigest":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","observedDigest":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","operation":"SHA256_EQUALS"},"outcome":"VERIFIED","reasonCode":"rvr.example.digest_match","schema":"rvr.canonical-result.example.v0"}
```

Its `resultDigest` is:

```text
6b5d6e0529e10b3bda66e187b774942cab2d7e69a579222f4892168bb28894dd
```

### Status separation

| Original result | Independent condition | Required recomputation status |
| --- | --- | --- |
| `VERIFIED` | All identities and canonical result bytes are identical | `REPRODUCED` |
| `UNVERIFIABLE` | All identities and canonical result bytes are identical | `REPRODUCED` |
| Any outcome | Evaluation completes but candidate evidence produces a different canonical result | `DIVERGED` |
| Any outcome | A required profile dependency is unavailable | `CANNOT_RECOMPUTE` |
| Any outcome | Receipt outcome contradicts the canonical-result projection | Gate rejection |
| Any outcome | Uncommitted outcome-relevant state is supplied | Gate rejection |

## Security Considerations

### Misleading unavailability

A producer can commit misleading `UNAVAILABLE` state. Reproduction proves correct derivation from that committed descriptor, not objective historical unavailability. Profiles requiring a stronger claim must commit evidence proving absence or unavailability.

### Signatures and anchors do not upgrade semantics

A signature can authenticate an artifact and an on-chain transaction can anchor its bytes. Neither establishes that the artifact's semantic result is correct or reproducible. Such mechanisms are evidence inputs unless the profile defines a stronger proposition.

### Nondeterministic judgments

A profile MUST NOT label a nondeterministic judgment `REPRODUCED` merely because another implementation produced similar prose or the same coarse verdict. It MAY reproduce deterministic sub-checks or a deterministic verification relation over an authenticated judgment artifact, but the profile must name that narrower proposition.

### Procedure completeness

`REPRODUCED` establishes stability under the profile-defined procedure; it does not establish that the procedure is complete with respect to any broader claim not committed by the Verification Profile.

### Mutable external context

Live RPC responses, registries, clocks, mutable policies, model endpoints, and resolver results can change outcomes. They MUST NOT influence a reproducible result unless the profile commits an immutable snapshot and exact resolution rules. An unavailable required snapshot produces `CANNOT_RECOMPUTE`.

### Canonicalization disagreement

Host-language JSON defaults differ in key ordering, escaping, number handling, normalization, and treatment of malformed Unicode. Implementations MUST use the byte contract in this ERC and MUST execute negative vectors. Agreement between two implementations is not a substitute for the normative byte definition.

### Dependency substitution and time-of-check/time-of-use

Applying a schema or specification before checking its digest permits substituted bytes to influence validation. Re-reading a dependency after verification permits time-of-check/time-of-use substitution. Implementations MUST hash before parsing and use the same verified bytes.

### Incomplete evidence closure

If an outcome-relevant input is omitted, a result may appear reproducible while depending on hidden state. Implementations MUST reject incomplete closure and MUST NOT report `REPRODUCED`.

### Hash collisions

RVR identity relies on SHA-256 collision and second-preimage resistance. A future hash transition requires a newly identified profile and explicit migration rules. Existing profile identities MUST NOT be reinterpreted under another hash function.

### Confidential evidence

RVR does not require globally public evidence. Applications must separately control authorization, disclosure, retention, and transport. A party lacking a required private dependency reports `CANNOT_RECOMPUTE`; it must not infer `REFUTED` from non-disclosure.

### Resource exhaustion

Profiles can reference large evidence sets or expensive verification procedures. Profiles SHOULD define size and resource limits. Implementations MAY refuse work exceeding local limits, but such refusal MUST NOT be reported as a semantic verification outcome.

### Producer and implementation authority

A producer implementation is not authoritative. Contract and profile identity define semantics; implementations provide evidence of conformance. A verifier signature MUST NOT override a profile mismatch, failed closure, contradictory projection, or divergent canonical result.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
