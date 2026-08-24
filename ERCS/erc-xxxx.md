---
eip: xxxx
title: Delegated Signed HTTP Requests
description: Delegation Grants for ERC-8128 authenticated requests
author: Jacopo Ranalli (@jacopo-eth) <jacopo@slice.so>, Domenico Macellaro (@zerohex-eth) <dom@slice.so>
discussions-to: https://ethereum-magicians.org/t/erc-8128-signed-http-requests-with-ethereum/27515
status: Draft
type: Standards Track
category: ERC
created: 2026-08-04
requires: 155, 191, 712, 1271, 6492, 7702, 8128
---

## Abstract

This proposal extends [ERC-8128](./erc-8128.md) with recursive, attenuating [EIP-712](./eip-712.md) Delegation Grants. A root Ethereum Account can authorize a delegate, which can authorize another delegate, while the leaf authenticates a bounded HTTP request without sharing the root key. The complete chain accompanies each request, so a verifier need not pre-register or store Delegation Grants.

## Motivation

Ethereum Accounts need short-lived, audience-bound, revocable delegation rather than exposing unrestricted root keys. Common uses include human-approved session keys and keys used by automated agents. Recursive grants allow a delegate to further attenuate authority while requiring every child to narrow, never broaden, what it receives.

Reusable authority is also a human approval boundary. EIP-712 lets a wallet render every grant field before approval, avoiding an opaque HTTP signature base for long-lived authority. The leaf request remains an ERC-8128 HTTP Message Signature, so request verification and human authorization use encodings suited to their different consumers.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

This proposal requires the complete ERC-8128 Request Signature profile. It references, and does not redefine, ERC-8128 request binding, content integrity, replay storage, candidate parsing, limits, Universal Account verification, and failure selection.

### 1. Definitions

- **Root Account**: the Account in the first grant's `issuer`; it is the authenticated Principal.
- **Delegate**: an Account receiving authority in one grant.
- **Delegation Grant**: the EIP-712 `Delegation` value and its embedded signature.
- **Delegation Link**: the deterministic CBOR encoding of one Delegation Grant in the delegation field.
- **Delegation Chain**: the ordered links `g0` through `gN`.
- **Leaf Delegate**: the final grant's `delegate`; it is the Request Signature Signer.
- **Effective Audience**, **Effective Permissions**, **Effective Components**, **Effective Maximum Request Validity**, and **Effective Non-Replayable Requirement**: the authority remaining after applying attenuation through the chain.

All other terms have the meanings defined by ERC-8128.

### 2. HTTP Fields and Signature Class

The extension defines the ERC-8128-Delegation field as an RFC 9651 Dictionary. Its members are consecutive keys `g0`, `g1`, ... `gN` in that order. Each value is an RFC 9651 Byte Sequence containing one Delegation Link in the deterministic CBOR encoding specified in Section 3.2.

The Delegated Request Signature has the exact RFC 9421 String parameter `tag="erc8128-delegated"`. Its `keyid` identifies the Leaf Delegate. It MUST cover the exact delegation-field component with the `sf` parameter:

```text
"erc-8128-delegation";sf
```

That component authenticates the parsed and strictly serialized whole Dictionary. Missing that coverage yields `delegation_not_covered`.

No separate RFC 9421 authorization signature exists. Each grant signature is embedded in its link, and the request signature covers the entire chain.

A verifier implementing ERC-8128 but not this extension recognizes the class only if configured to do so; recognition without support yields `unsupported_delegation`. The candidate MUST NOT be reinterpreted as `erc8128` or another class.

### 3. Delegation Grants

#### 3.1 EIP-712 Type

The exact EIP-712 primary type is:

```solidity
struct Delegation {
    string issuer;
    string delegate;
    string[] audiences;
    bytes32 id;
    uint64 epoch;
    uint64 validAfter;
    uint64 validUntil;
    uint32 maxRequestValiditySeconds;
    bool delegateIsEOA;
    bool requireNonReplayable;
    string[] requiredComponents;
    string[] permissions;
    bytes32 parentGrantHash;
}
```

The type string is:

```text
Delegation(string issuer,string delegate,string[] audiences,bytes32 id,uint64 epoch,uint64 validAfter,uint64 validUntil,uint32 maxRequestValiditySeconds,bool delegateIsEOA,bool requireNonReplayable,string[] requiredComponents,string[] permissions,bytes32 parentGrantHash)
```

The EIP-712 domain has exactly these fields:

```text
name: "ERC-8128 Delegation"
version: "1"
chainId: the chain ID in issuer
```

`issuer` and `delegate` MUST be canonical lowercase-address CAIP-10 Account IDs under ERC-8128's grammar. The domain `chainId` MUST equal the numeric `issuer` chain ID. `audiences` MUST be non-empty. `validUntil` MUST be greater than `validAfter`, and `maxRequestValiditySeconds` MUST be nonzero. Each `requiredComponents` entry MUST encode an RFC 9421 request component as its ASCII component name followed by any strictly serialized RFC 9651 parameters, without the outer quotes used in a signature base; examples are `@method`, `content-type`, and `@query-param;name="id"`. `@signature-params` and the delegation-field component from Section 2 are forbidden. Within each array, values SHOULD be unique.

A malformed or non-deterministic CBOR encoding, invalid UTF-8 in a text string, an incorrect element count or order, trailing bytes, an empty embedded signature, a non-canonical Account ID, an invalid domain relationship, a forbidden component, or any other structural violation in this paragraph yields `bad_delegation_field` before cryptography.

Array order is semantically irrelevant to Audience, permission, and component-set comparisons, but remains cryptographically significant. Signers and verifiers MUST hash arrays in encoded order and MUST NOT sort or otherwise canonicalize them before computing the EIP-712 digest.

The Account identified by `issuer` signs the EIP-712 digest. Universal Account verification from ERC-8128 is used, with the EIP-712 digest supplied directly to [ERC-1271](./eip-1271.md) or [ERC-6492](./eip-6492.md). A definitive invalid proof yields `bad_grant_signature`; unavailable classification or verification yields `grant_verification_unavailable`.

#### 3.2 Link Encoding and Limits

Each Byte Sequence is exactly one Delegation Link encoded as a definite-length CBOR array of 14 elements in this order:

| Index | Element | CBOR type and constraint |
| ---: | --- | --- |
| 1 | `issuer` | text string, canonical CAIP-10 |
| 2 | `delegate` | text string, canonical CAIP-10 |
| 3 | `audiences` | array of text strings |
| 4 | `id` | byte string, exactly 32 bytes |
| 5 | `epoch` | unsigned integer |
| 6 | `validAfter` | unsigned integer |
| 7 | `validUntil` | unsigned integer |
| 8 | `maxRequestValiditySeconds` | unsigned integer |
| 9 | `delegateIsEOA` | Boolean |
| 10 | `requireNonReplayable` | Boolean |
| 11 | `requiredComponents` | array of text strings |
| 12 | `permissions` | array of text strings |
| 13 | `parentGrantHash` | byte string, exactly 32 bytes |
| 14 | `signature` | non-empty byte string |

The encoding MUST follow the core deterministic encoding requirements of [RFC 8949 Section 4.2.1](https://www.rfc-editor.org/rfc/rfc8949#section-4.2.1). It is further restricted to unsigned integers, byte strings, text strings, arrays, and the one-byte simple values false and true. Byte strings, text strings, and arrays MUST use definite lengths, every CBOR head MUST use its shortest form, the top-level array MUST have exactly the element count and order above, and no trailing bytes are permitted. Any violation of this data model or these encoding requirements, including maps, tags, floats, negative integers, null, undefined, all other simple values, indefinite lengths, malformed or non-deterministic encodings, and invalid UTF-8 text strings, MUST be rejected as `bad_delegation_field`. There is no wire-version element and no legacy ABI fallback.

CBOR arrays are permitted to nest only at `audiences`, `requiredComponents`, and `permissions`; nesting deeper than the top-level array and one field array MUST be rejected as `bad_delegation_field`, and decoders SHOULD bound nesting depth accordingly.

The field MUST contain at least `g0`, use consecutive lowercase decimal indices without leading zeroes, contain no other member, and preserve ascending member order. A violation yields `bad_delegation_field`.

ERC-8128's candidate and signature-field limits apply across Direct and Delegated candidates. This extension adds these defaults:

| Input | Default limit |
| --- | ---: |
| Combined ERC-8128-Delegation field | 16 KiB |
| Delegation Link Byte Sequence | 8 KiB |
| Entries in any one grant array | 32 |
| UTF-8 bytes in any one text string | 256 |

The combined-field and Delegation Link byte limits MUST be enforced before CBOR decoding. The array-entry and text-string limits MUST be enforced during CBOR decoding. Exceeding any limit yields `delegation_too_large` before cryptography. Deployments MAY use smaller documented limits.

Deployments with lower HTTP field limits SHOULD reduce chain depth or per-grant limits accordingly.

#### 3.3 Grant Semantics

`audiences` contains canonical RFC 6454 origins. Each value MUST be the ASCII serialization of a non-opaque origin, without a trailing slash, trailing-dot host, wildcard, path, query, or fragment. It MUST use `https`. Verifiers MUST NOT repair a non-canonical value.

`id` is the revocation handle. Issuers SHOULD use a unique value for every grant. Reusing one intentionally groups all grants with that `(issuer address, id)` for collective revocation.

`epoch` is the current registry epoch of this grant's `issuer` address. `validAfter` and `validUntil` define the grant's absolute validity window. A deployment MAY configure a maximum grant window; exceeding it yields `grant_validity_too_long` before cryptography. With ERC-8128 skew `s`, `now < validAfter - s` yields `grant_not_yet_valid` and `now > validUntil + s` yields `grant_expired`.

`maxRequestValiditySeconds` separately bounds each Request Signature's `request.expires - request.created` window, even when the grant remains valid for longer. Exceeding the effective value yields `delegation_request_validity_exceeded`. A request whose own window is not contained within the leaf grant window, allowing skew only at the grant `validAfter` boundary, yields `request_outside_grant_window`.

`delegateIsEOA` is a permanent statement about this grant's own `delegate`, not a current account-code observation. When true on the leaf link, the Delegated Request Signature MUST use strict local ECDSA and MUST reject wrappers or contract callbacks even if the address later obtains code. When false, ERC-8128 Universal Account verification applies. The value constrains only verification of that delegate's Delegated Request Signature when this grant is the leaf; a mid-chain delegate's signature over a child grant always uses Universal Account verification.

`requireNonReplayable=true` requires the Delegated Request Signature to be Non-Replayable under ERC-8128: it includes a nonce, and the verifier atomically consumes that nonce. `false` adds no grant-level replay restriction; verifier and route policy can still require Non-Replayable posture or reject Replayable requests. A Replayable request when any link sets `requireNonReplayable=true` yields `delegation_nonce_required`.

`requiredComponents` is the grant-defined minimum set of request component identifiers, in addition to the mandatory delegation-field component, that the Delegated Request Signature must cover. A signer may cover more, and route policy may require more. Request-Bound or Class-Bound classification remains determined by ERC-8128. Replay posture and request binding remain independent ERC-8128 axes. If the verifier cannot reconstruct a required derived component or process one of its parameters, it yields `delegation_components_unsupported`. If the verifier supports the component but the request omits it, it yields `delegation_components_uncovered`.

`permissions` contains case-sensitive service-defined capabilities with AND route semantics. Unknown tokens grant no authority. A verifier need not implement application permissions to accept a chain whose every `permissions` array is empty on a route that requires none. A verifier unable to process permissions yields `unsupported_permissions` only when at least one link has non-empty `permissions`. The route's required permissions are always compared with the chain's Effective Permissions. A valid authenticated chain missing any route-required permission yields `insufficient_permissions` with HTTP 403.

#### 3.4 Recursive Continuity and Attenuation

For `g0`, `parentGrantHash` MUST be 32 zero bytes. For every child `g[i]`, where `i > 0`:

- `g[i].issuer` MUST equal `g[i-1].delegate` as a canonical CAIP-10 ID; and
- `g[i].parentGrantHash` MUST equal the EIP-712 digest of `g[i-1]`.

The Delegated Request Signature `keyid` MUST equal `gN.delegate`; inequality yields `delegate_mismatch`. A nonzero `g0.parentGrantHash`, an issuer/delegate continuity failure, or a parent-grant-digest mismatch yields `delegation_chain_discontinuous`.

The Principal is the Root Account `g0.issuer`, and the Signer is `gN.delegate`.

Each child MUST monotonically attenuate its parent:

- the child `audiences` set is a subset of the parent Effective Audience;
- a non-empty child `permissions` is a subset of the parent Effective Permissions; empty child `permissions` inherits those parent permissions;
- `validAfter >= parent.validAfter` and `validUntil <= parent.validUntil`;
- `maxRequestValiditySeconds <= parent.maxRequestValiditySeconds`;
- Effective Non-Replayable Requirement is the logical OR of `requireNonReplayable` over every link; and
- Effective Components are the union of all `requiredComponents` sets.

Because empty child `permissions` inherits, a child cannot attenuate non-empty Effective Permissions to the empty set. A child cannot relax an earlier Non-Replayable requirement because the effective value remains true.

For `g0`, Effective Audience is `audiences`, Effective Permissions are `permissions` including the empty set, Effective Maximum Request Validity is `maxRequestValiditySeconds`, Effective Components are `requiredComponents`, and Effective Non-Replayable Requirement is `requireNonReplayable`. After each valid child link, Effective Audience becomes the child `audiences`, Effective Maximum Request Validity becomes the child `maxRequestValiditySeconds`, Effective Components become the running union, Effective Permissions become the child's non-empty `permissions` or remain inherited when the child `permissions` is empty, and Effective Non-Replayable Requirement becomes the running logical OR. The chain's effective values are those obtained after processing `gN`. Any per-link subset, window, or maximum-request-validity violation yields `delegation_attenuation_violation`.

The default maximum chain depth is four links. A deployment MAY configure another positive maximum and MUST document it. Exceeding it yields `delegation_chain_too_long` before cryptography.

### 4. Verification

#### 4.1 Candidate Evaluation

Delegated candidates participate in ERC-8128 Candidate Evaluation and Limits. A verifier supporting both classes counts both exact tags against one default budget of eight and evaluates them in `Signature-Input` Dictionary wire order. An RFC 9651 syntax error remains a whole-field `signature_input_invalid`; only a well-formed candidate that fails this extension is skippable.

Within a Delegated candidate, grant-window checks (`grant_not_yet_valid`, `grant_expired`) MUST precede the ERC-8128 request-window checks for failure selection. Implementations MAY physically reorder those checks only when the externally observable result remains the grant-window code.

Before any account-classification RPC, the verifier MUST validate field and chain limits, wire structure, CAIP-10 and domain relationships, continuity, attenuation, grant and request times, Audience, request binding, delegation-field coverage, component support and coverage, content digest, permission-processing capability, Principal policy, and replay posture. Each deployment MUST document its account-classification RPC budget; the default maximum per request is `2 + chain depth`.

The verifier then processes a candidate in this order:

1. Reconstruct the effective request origin from the trusted effective target URI. Absence from the Effective Audience yields `audience_mismatch`.
2. Verify the leaf Request Signature first. Use strict local ECDSA when `gN.delegateIsEOA` is true; otherwise use ERC-8128 Universal Account verification. Invalidity yields `bad_signature`; unavailability yields `signature_verification_unavailable`.
3. Compute each EIP-712 digest, then verify link signatures from `gN` through `g0` using Universal Account verification or a Section 4.2 cache. Invalidity yields `bad_grant_signature`; unavailability yields `grant_verification_unavailable`.
4. Check revocation for every link as specified in Section 5. A revoked link yields `authorization_revoked`; an epoch mismatch yields `authorization_epoch_mismatch`; unavailable state yields `revocation_unavailable`.
5. Enforce all route-required permissions unconditionally against Effective Permissions, yielding `insufficient_permissions` when any is absent.
6. For a nonce, atomically consume the ERC-8128 replay key `(Leaf Signer, nonce)` last. Without a nonce, enforce ERC-8128 early-invalidation policy.
7. Select the candidate as winner.

The request-window, component, permission, and other local checks can be calculated before RPC. A verifier MUST NOT emit `insufficient_permissions` for a candidate whose proofs have not verified. ERC-8128's observable-equivalence and nonce rules apply.

Successful authentication returns:

```ts
{
  principal: RootAccountId,
  signer: LeafDelegateAccountId,
  delegated: true,
  binding: "request-bound" | "class-bound",
  replay: "non-replayable" | "replayable",
  delegationIds: Bytes32[]
}
```

#### 4.2 Grant-Proof Cache

A verifier MAY cache only a positive Universal Account result for a grant. The cache key is the collision-free pair `(grant digest, signature bytes)`. The digest already binds every grant and domain field. Cache invalidation MUST account for SCA state according to deployment policy. This cache never replaces Section 5 revocation checks.

### 5. Canonical Revocation Registry

The Ethereum mainnet (`eip155:1`) deployment is canonical and defines the registry address and runtime code hash. Each grant uses the registry at that address on the EIP-155 chain identified by its `issuer`. A verifier MUST derive the registry chain from `issuer`, verify the runtime code hash, and MUST NOT substitute another chain or registry address. An issuer on another chain therefore selects the corresponding deployment on that chain.

The reference deployment MUST use deterministic CREATE2, and this proposal will fix its address and runtime code hash before it advances beyond Draft. A registry on another chain MUST use that address and runtime code hash. Until those values are populated, production deployments MUST NOT claim conformance to this extension. Absence, code-hash mismatch, or unavailability of the required deployment yields `revocation_unavailable`.

| Property | Canonical value |
| --- | --- |
| Reference chain | Ethereum mainnet (`eip155:1`) |
| Address | To be assigned by the deterministic reference deployment |
| Runtime code hash | To be assigned by the deterministic reference deployment |

The complete external interface is:

```solidity
interface IERCXXXXRevocationRegistry {
    function status(address issuer, bytes32 id)
        external view returns (bool isRevoked, uint64 currentEpoch);
    function revoke(bytes32 id) external;
    function revokeBySig(address issuer, bytes32 id, bytes calldata sig) external;
    function advanceEpoch() external returns (uint64 newEpoch);

    event Revoked(address indexed issuer, bytes32 indexed id);
    event EpochAdvanced(address indexed issuer, uint64 newEpoch);
}
```

`revoke(id)` permanently revokes `(msg.sender, id)`. `advanceEpoch()` increments and returns `msg.sender`'s independent `uint64` epoch, thereby invalidating every outstanding grant of that issuer whose epoch differs. Epochs start at zero, advance monotonically, and MUST NOT wrap. The registry MUST provide neither individual unrevocation nor epoch reduction.

Both `revoke` and a successful `revokeBySig` MUST emit `Revoked`. `advanceEpoch` MUST emit `EpochAdvanced` with the returned value.

`revokeBySig` is relayable. `sig` signs this EIP-712 value:

```solidity
struct Revocation {
    address issuer;
    bytes32 id;
}
```

Its type string is `Revocation(address issuer,bytes32 id)`. Its domain name is "ERC-8128 Delegation Registry", its version is `1`, its chain ID is the chain on which the registry is deployed, and its `verifyingContract` is the canonical registry address. The registry MUST require the signed `issuer` to equal the function argument. It uses strict low-`s` ECDSA when `issuer` has no code on that chain and ERC-1271 when it has code, supplying the EIP-712 digest directly. Replaying the message is harmless because revocation is permanent.

For every link, the verifier calls `status(address(g[i].issuer), g[i].id)` on the chain identified by `g[i].issuer`. A grant is active only when `isRevoked == false` and `currentEpoch == g[i].epoch`.

Before signing a grant, its issuer MUST read `currentEpoch` from that chain's registry and copy it into `epoch`.

A positive status cache entry MUST bind the registry chain and address, issuer address, `id`, and signed `epoch`. Its TTL MUST NOT exceed the remaining grant lifetime. It also MUST NOT exceed 60 seconds unless the deployment documents a larger client-visible bound. That TTL is the maximum revocation-propagation delay. An expired entry cannot be extended stale-while-error. Verifiers SHOULD read at a finalized height and MUST document their reorganization policy.

Registry or provider failure without an unexpired positive entry yields `revocation_unavailable`; accepting on error is forbidden.

### 6. Failure Responses

ERC-8128 failure codes and status rules apply unchanged. This extension adds:

```text
unsupported_delegation
bad_delegation_field
delegation_too_large
delegation_not_covered
delegate_mismatch
delegation_chain_too_long
delegation_chain_discontinuous
delegation_attenuation_violation
grant_not_yet_valid
grant_expired
grant_validity_too_long
request_outside_grant_window
delegation_request_validity_exceeded
delegation_components_unsupported
delegation_components_uncovered
delegation_nonce_required
audience_mismatch
unsupported_permissions
insufficient_permissions
bad_grant_signature
grant_verification_unavailable
authorization_revoked
authorization_epoch_mismatch
revocation_unavailable
```

`delegation_too_large` and `delegation_chain_too_long` use HTTP 400. `insufficient_permissions` uses 403. `grant_verification_unavailable` and `revocation_unavailable` use 503. All other extension failures use 401. Each 401 MUST include ERC-8128's `eth-http-sig` challenge with its `error` parameter. When a response body is sent, the ERC-8128 `reason` requirement applies.

This non-normative index maps extension codes to conditions:

| Code | Condition |
| --- | --- |
| `unsupported_delegation` | The extension class is recognized but unsupported |
| `bad_delegation_field` | The field, CBOR link, grant, or domain is structurally invalid |
| `delegation_too_large` | An extension byte, array, or text-string limit is exceeded |
| `delegation_not_covered` | The request omits whole-field `;sf` coverage |
| `delegate_mismatch` | Request `keyid` is not the Leaf Delegate |
| `delegation_chain_too_long` | Configured link depth is exceeded |
| `delegation_chain_discontinuous` | Issuer/delegate or parent-grant-digest continuity fails |
| `delegation_attenuation_violation` | A child broadens parent authority |
| `grant_not_yet_valid` | A grant window has not opened |
| `grant_expired` | A grant window has closed |
| `grant_validity_too_long` | A configured grant-window maximum is exceeded |
| `request_outside_grant_window` | The request window is outside the leaf grant |
| `delegation_request_validity_exceeded` | Request validity exceeds the effective grant maximum |
| `delegation_components_unsupported` | The verifier cannot process a component floor |
| `delegation_components_uncovered` | The request omits a supported component floor |
| `delegation_nonce_required` | Effective Non-Replayable Requirement forbids Replayable posture |
| `audience_mismatch` | Effective Audience excludes the request origin |
| `unsupported_permissions` | Non-empty permissions cannot be processed |
| `insufficient_permissions` | Effective Permissions omits a route requirement |
| `bad_grant_signature` | A grant proof is definitively invalid |
| `grant_verification_unavailable` | A grant proof cannot be classified or verified |
| `authorization_revoked` | Any link ID is revoked |
| `authorization_epoch_mismatch` | Any link epoch differs from its issuer's current epoch |
| `revocation_unavailable` | Registry state cannot be obtained |

## Rationale

### Embedded EIP-712 proofs

Each link is independently human-readable at signing time and independently verifiable. Embedding the proof eliminates RFC 9421 label correlation for reusable authority and makes recursive parent binding a digest equality. Carrying the complete chain removes verifier-side grant storage; replay and revocation checks retain their state requirements.

### Monotonic recursive authority

Subset, nested-window, maximum-request-validity, non-replayability, and component-union rules make every effective permission computable locally. No child can replace its parent context or regain authority removed earlier in the chain.

### Canonical registry deployment

The canonical address and runtime code hash make grant meaning independent of verifier-selected coordinates. Deriving the registry chain from `issuer` lets each Account use the chain on which it is defined.

## Backwards Compatibility

This Draft signed-schema change invalidates earlier grant and revocation signatures and wire vectors.

## Test Cases

The fixed private keys are public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Root | `0x0000000000000000000000000000000000000000000000000000000000000002` | `eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf` |
| Delegate A | `0x0000000000000000000000000000000000000000000000000000000000000003` | `eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69` |
| Delegate B | `0x0000000000000000000000000000000000000000000000000000000000000004` | `eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718` |

The clock is `1700000001`, skew is 30 seconds, the effective origin is `https://api.example`, all three accounts have no code, replay state is empty, permission processing is supported, the route requires `resource:read`, and Principal policy accepts Root. Neither a route request-validity maximum nor a grant-validity maximum is configured. The registry reports `(false, 7)` for Root and `(false, 3)` for Delegate A.

### EIP-712 grant vectors

`g0` is Root to Delegate A:

```json
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","audiences":["https://api.example","https://backup.example"],"id":"0x1111111111111111111111111111111111111111111111111111111111111111","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"delegateIsEOA":true,"requireNonReplayable":true,"requiredComponents":["@authority"],"permissions":["resource:read","resource:write"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
domainSeparator = 0xe75cfb820d01daf33b6457696c96272bcf1383d1e3b6da5d7ee1e9e993a5ce73
structHash_g0 = 0x82906303eba6d0fa5d1b6315869673e5e80e4cb0b19230f8b32cd5aeb9921536
digest_g0 = 0x4a274dc6f56120c748e8494b1e5d4d058849594fef1b885759eb97ea6d5c63c2
signature_g0 = 0x479e35478cb0051c60f6b7e9f5ccbf4680508efbf4f689dbec460322ad61d41b394997be2fab4c7f05893d6d60e8c211547925a69f5e575f8afe0f4d5dcfc8691c
```

`g1` is Delegate A to Delegate B:

```json
{"issuer":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","delegate":"eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718","audiences":["https://api.example"],"id":"0x2222222222222222222222222222222222222222222222222222222222222222","epoch":3,"validAfter":1699999500,"validUntil":1700001800,"maxRequestValiditySeconds":60,"delegateIsEOA":true,"requireNonReplayable":true,"requiredComponents":["@method"],"permissions":["resource:read"],"parentGrantHash":"0x4a274dc6f56120c748e8494b1e5d4d058849594fef1b885759eb97ea6d5c63c2"}
```

```text
structHash_g1 = 0xab39f11f8d1d4060992c0fc26f6c8e043d77db6e8afc52d4fd6f84780ab5be82
digest_g1 = 0x2a3352573606edaff0d80c092e6054fafd799302037d306af2c5446dfed638e8
signature_g1 = 0x5f10163c0c576641abebbd758589d380b283ecbabdb14e0d071b09a5d99af39570bc80e418c6a5888e068965073f38755fccead52d5830bb29e109a9fdccc00e1b
```

### Single-link request vector

The `g0` Byte Sequence is 343 bytes. Its exact uninterrupted base64 value is:

```text
jngzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeDNlaXAxNTU6MToweDY4MTNlYjkzNjIzNzJlZWY2MjAwZjNiMWRiYzNmODE5NjcxY2JhNjmCc2h0dHBzOi8vYXBpLmV4YW1wbGV2aHR0cHM6Ly9iYWNrdXAuZXhhbXBsZVggEREREREREREREREREREREREREREREREREREREREREREHGmVT7RgaZVP/EBg89fWBakBhdXRob3JpdHmCbXJlc291cmNlOnJlYWRucmVzb3VyY2U6d3JpdGVYIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWEFHnjVHjLAFHGD2t+n1zL9GgFCO+/T2idvsRgMirWHUGzlJl74vq0x/BYk9bWDowhFUeSWmn15XX4r+D01dz8hpHA==
```

For readability, `<G0>` in the following HTTP and signature-base blocks means the exact base64 bytes above. It MUST be substituted before parsing, transmission, hashing, or signing; the angle brackets are not part of the vector.

The complete request is:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
Signature: request=:GXzD4Ufm62IUiQU+yrwGx52V9nO34m3ZVw+ULKOFfnYisiECwMvf+6zrx5zPsXg516lSh+7Tulk5W0kIg/2FIhs=:
```

The exact 834-byte signature base is:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<G0>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
```

```text
H_request_g0 = 0xb11b7a98450116d11b50079fce56781818eefd4c3d4228edfc29ed084d98f2b7
S_request_g0 = 0x197cc3e147e6eb621489053ecabc06c79d95f673b7e26dd9570f942ca3857e7622b22102c0cbdffbacebc79ccfb17839d7a95287eed3ba59395b490883fd85221b
```

The expected Principal is Root and Signer is Delegate A. The request is Request-Bound and Non-Replayable, and only Delegate A's nonce is consumed.

### Depth-two request vector

The `g1` Byte Sequence is 302 bytes. Its exact uninterrupted base64 value is:

```text
jngzZWlwMTU1OjE6MHg2ODEzZWI5MzYyMzcyZWVmNjIwMGYzYjFkYmMzZjgxOTY3MWNiYTY5eDNlaXAxNTU6MToweDFlZmY0N2JjM2ExMGE0NWQ0YjIzMGI1ZDEwZTM3NzUxZmU2YWE3MTiBc2h0dHBzOi8vYXBpLmV4YW1wbGVYICIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAxplU+8MGmVT+AgYPPX1gWdAbWV0aG9kgW1yZXNvdXJjZTpyZWFkWCBKJ03G9WEgx0joSUseXU0FiElZT+8biFdZ65fqbVxjwlhBXxAWPAxXZkGr6711hYnTgLKD7Lq9sU4NBxsJpdma85VwvIDkGMaliI4GiWUHPzh1X8zq1S1YMLsp4Qmp/czADhs=
```

This vector uses the exact `g0` Byte Sequence above, followed by `g1`. In the following blocks, `<G0>` and `<G1>` MUST be substituted with their exact displayed base64 bytes before processing.

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:, g1=:<G1>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
Signature: request=:5LUwOoSsWH4LvBtg7RjWRTvubwx5IAf5qOA3Iug+Wf5D1myMWuwmmDcTED1ylafcJ6WJwYu9Llczq1g+7gL/axw=:
```

The exact 1245-byte signature base is:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<G0>:, g1=:<G1>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
```

```text
H_request_g1 = 0x60cd8c4caceb661cd173d1a5b02c89994f06c9b1dcebde049a00f08aa651bc86
S_request_g1 = 0xe4b5303a84ac587e0bbc1b60ed18d6453bee6f0c792007f9a8e03722e83e59fe43d66c8c5aec26983713103d7295a7dc27a589c18bbd2e5733ab583eee02ff6b1c
```

The expected Principal is Root and Signer is Delegate B. Effective Audience is `https://api.example`, Effective Permissions contain `resource:read`, Effective Components contain `@authority` and `@method`, Effective Non-Replayable Requirement is true, and only Delegate B's nonce is consumed.

### Negative and classification vectors

Each mutation starts from the applicable positive vector, leaves all signatures unchanged unless stated, and uses fresh replay state.

For the three-link rows, implementers extend the depth-two chain with a valid attenuated `g2` from Delegate B to private key `0x0000000000000000000000000000000000000000000000000000000000000005`, Account `eip155:1:0xe1ab8145f7e55dc933d51a18c793f901a3a0b276`. They sign `g2` with Delegate B and construct the corresponding leaf request signature with private key `0x...05`.

| Mutation or state | Expected result |
| --- | --- |
| Present the single-link candidate to a verifier that recognizes but does not implement this extension | `unsupported_delegation` |
| Remove `g0`, use `g01`, skip an index, add another member, corrupt CBOR or UTF-8, append trailing bytes, use a non-shortest CBOR head, or use an indefinite-length item | `bad_delegation_field` before cryptography |
| Exceed an extension field, link, array, or text-string limit | `delegation_too_large` with 400 before cryptography |
| Remove or alter `;sf` on delegation coverage | `delegation_not_covered` |
| Change request `keyid` away from the final delegate | `delegate_mismatch` |
| Configure maximum depth one and use the depth-two vector | `delegation_chain_too_long` with 400 |
| Change `g1.issuer`, its `parentGrantHash`, or `g0.parentGrantHash` and re-sign affected material | `delegation_chain_discontinuous` |
| Give `g1` a new Audience, `resource:admin`, a wider window, or `maxRequestValiditySeconds=61` | `delegation_attenuation_violation` |
| With `now=1699999469`, use the depth-two vector | `grant_not_yet_valid` |
| With `now=1700001831`, use the depth-two vector | `grant_expired` |
| Configure a 3599-second grant maximum and use `g0` | `grant_validity_too_long` |
| With `now=1700001771`, re-sign the request with `created=1700001741` and `expires=1700001801`, using the depth-two chain | `request_outside_grant_window` |
| Set request `expires-created` to 61 | `delegation_request_validity_exceeded` |
| Put an unsupported derived identifier in `requiredComponents` and re-sign the grant | `delegation_components_unsupported` |
| Add supported `content-type` to `requiredComponents`, re-sign, and omit it from request coverage | `delegation_components_uncovered` |
| Remove the nonce from either positive request without changing its grant | `delegation_nonce_required` |
| Change Effective Audience to exclude `https://api.example` | `audience_mismatch` |
| Use a verifier without permission processing for either positive vector | `unsupported_permissions` |
| Require `resource:write` on the depth-two route | authenticated `insufficient_permissions` with 403 |
| Flip one grant-signature bit and re-sign the request over the mutated field | `bad_grant_signature` after leaf proof |
| Make grant-issuer account classification unavailable | `grant_verification_unavailable` with 503 |
| Return `isRevoked=true` for `g1` | `authorization_revoked` |
| Return epoch 8 for Root or 4 for Delegate A | `authorization_epoch_mismatch` |
| Make registry state unavailable with no live positive entry | `revocation_unavailable` with 503 |
| Revoke the middle link in the three-link derived chain | `authorization_revoked` |
| Advance the middle link issuer's epoch in the three-link derived chain | `authorization_epoch_mismatch` |
| Put a well-formed failing Delegated candidate before either positive candidate | the later candidate wins; the failed nonce remains unused |

Implementations MUST also run every applicable ERC-8128 negative vector against the Delegated Request Signature. In particular, malformed `Signature-Input` remains a whole-field failure, while a well-formed invalid candidate is skippable.

## Reference Implementation

```ts
async function verifyDelegated(req: Request, candidate: Candidate, policy: Policy) {
  const links = decodeAndValidateLinks(req.delegationField, policy.limits);
  const chain = validateContinuityAndAttenuation(links);
  validateLocallyBeforeRpc(req, candidate, chain, policy);

  const leafProof = chain.leaf.delegateIsEOA
    ? verifyStrictEoa(candidate.keyid, eth191Hash(signatureBase(req, candidate)), candidate.sig)
    : await verifyUniversal(candidate.keyid, eth191Hash(signatureBase(req, candidate)), candidate.sig);
  if (!leafProof.valid) throw classifiedRequestProofFailure(leafProof);

  for (const link of [...links].reverse()) {
    const digest = eip712DelegationDigest(link.grant);
    const proof = grantCache.get([digest, link.signature])
      ?? await verifyUniversal(link.grant.issuer, digest, link.signature);
    if (!proof.valid) throw classifiedGrantProofFailure(proof);
  }

  for (const link of links) await requireActiveOnIssuerChain(link);
  requireRoutePermissions(chain.effectivePermissions, policy.requiredPermissions);
  await consumeLeafNonceLast(candidate, chain.leaf.delegate);
  return delegatedResult(chain);
}
```

## Security Considerations

### Human grant approval

Wallets SHOULD display the Issuer, Delegate, Audiences, validity window, maximum request validity, permissions, required components, Non-Replayable requirement, and parent relationship. Applications should avoid blind-signing typed-data JSON supplied by an untrusted party even though EIP-712 makes fields renderable.

### Permanent EOA attestations

`delegateIsEOA` preserves raw-key semantics for Delegated Request Signatures whenever that grant is the leaf during its lifetime; it does not change Universal Account verification of child-grant signatures. A Delegate migrating to an SCA cannot use that grant as a leaf through contract verification and needs a reissued grant. Issuers should keep such grants short.

### Revocation latency

The positive status-cache TTL is the maximum time a revocation can take to propagate. Clients need this bound before relying on emergency revocation.

### Registry-chain selection

Issuers SHOULD prefer Ethereum mainnet for the strongest settlement guarantees. An issuer whose SCA cannot be deployed on mainnet MAY instead use a supported chain on which it can be deployed and verified. Issuers SHOULD keep their grants on one chain whenever possible: one `advanceEpoch()` call then invalidates all of that issuer's outstanding grants on that registry, while grants spread across chains require advancing the epoch on each registry.

### RPC exhaustion and ordering

All local policy, time, coverage, digest, continuity, and attenuation checks precede RPC. The leaf proof precedes grant proofs, which proceed leaf-to-root. Deployments must enforce and document the account-classification budget and separately rate-limit registry reads.

### Replay space

The replay key remains `(Leaf Signer, nonce)`, so grants sharing a Signer also share replay space. This is benign: a collision can deny one of the Signer's own requests but cannot authenticate an unauthorized request. Signer-generated 128-bit randomness makes accidental collisions negligible.

### CORS, and transformations

Browser deployments need the delegation field in CORS allowlists. Intermediary transformation of the field or any covered component invalidates the Request Signature.

### Privacy and confidentiality

Account IDs, grant IDs, Audiences, and stable Delegate keys can correlate activity. Use distinct keys and IDs across unrelated contexts and narrow Audience sets. TLS is still required for confidentiality.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
