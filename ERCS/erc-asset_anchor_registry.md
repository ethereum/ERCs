---
eip: XXXX
title: Asset Anchor Registry Interface
description: A registry interface for registry-scoped token-to-anchor bindings for off-chain asset claims
author: Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)
discussions-to: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
status: Draft
type: Standards Track
category: ERC
created: 2026-07-04
requires: 165
---

## Abstract

This ERC defines interfaces for registries that bind token contracts or token
IDs to anchor records representing claims about off-chain assets. Each anchor
contains separate commitments to a claimed legal basis and supporting evidence.
Bindings distinguish whole-contract scope from token-ID scope, enforce
registry-scoped exclusivity, and preserve immutable binding history.

Token-side interfaces allow contracts to declare the same registry and anchor,
enabling consumers to verify both sides of a binding. A lifecycle interface
defines structured metadata, expiry, re-attestation, and permanent
deactivation. An optional recovery interface permits disputed bindings to be
invalidated without deleting their historical records.

The resulting records provide durable, registry-scoped binding provenance for
consumers that require an auditable lifecycle history.

This ERC does not establish the existence, ownership, legal validity, or value
of an off-chain asset.

## Motivation

A token can claim in metadata that it represents an off-chain asset, but that
claim does not provide a common interface for another contract to determine:

- which registry record the token claims;
- whether the registry records the same token-to-anchor relationship;
- whether the binding is exclusive within that registry;
- whether the binding applies to an entire token contract or one token ID; or
- whether the anchor is active, expired, deactivated, or invalidated.

Deployments subject to institutional or regulatory oversight often need a
durable answer to which token tuple was recorded against an asset claim, when
the binding was established, and whether it remains current. This ERC makes
registry-scoped exclusivity and immutable binding history explicit without
asserting that the underlying claim is legally valid or factually correct.

Without a mutually queryable structure, the relationship remains
assertion-only tokenization: the token can describe an off-chain asset, but an
independent consumer cannot verify the claimed token-to-record relationship
through a common interface.

Applications consequently rely on implementation-specific metadata and
registries. The same asset claim can be represented differently by each issuer,
and consumers cannot inspect a binding through a common interface.

This ERC standardizes the structural relationship between a registry anchor
and a token contract or token ID. The guarantee is intentionally limited to one
registry instance. Registry operators remain responsible for deciding which
claims they accept, and consumers remain responsible for deciding which
registries they trust.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

An **anchor** is a registry record containing commitments and metadata for an
off-chain asset claim.

A **contract binding** binds an anchor to an entire token contract. This is
appropriate when one contract represents one claimed asset or instrument.

A **token-ID binding** binds an anchor to one token ID within a token contract.

A **binding tuple** is `(token, bindingScope, tokenId)`.

A **valid binding** is a recorded binding that has not been invalidated through
`IAssetAnchorRegistryRecovery`. Binding validity is distinct from lifecycle
activity.

An **active anchor** is an anchor that has not been permanently deactivated and
whose metadata has not expired.

### Binding Scopes

Implementations MUST use the following scope identifiers, replacing `XXXX`
with this ERC's assigned number:

```solidity
bytes32 constant BINDING_SCOPE_CONTRACT =
    keccak256("ERC-XXXX:BINDING_SCOPE:CONTRACT");

bytes32 constant BINDING_SCOPE_TOKEN_ID =
    keccak256("ERC-XXXX:BINDING_SCOPE:TOKEN_ID");
```

For `BINDING_SCOPE_CONTRACT`, `tokenId` MUST equal `0` as a canonical unused
value.

For `BINDING_SCOPE_TOKEN_ID`, every `uint256` value is valid, including token ID
`0`. Token ID `0` MUST NOT be interpreted as a contract-binding sentinel.

### Metadata Encoding

Registration metadata MUST be ABI encoded as the following ordered tuple:

```solidity
struct AnchorMetadata {
    bytes32 assetClass;
    bytes32 jurisdiction;
    uint64 attestationDate;
    uint64 expiresAt;
    bytes uri;
    bytes extensions;
}
```

The canonical encoding is:

```solidity
abi.encode(
    metadata.assetClass,
    metadata.jurisdiction,
    metadata.attestationDate,
    metadata.expiresAt,
    metadata.uri,
    metadata.extensions
)
```

`assetClass` and `jurisdiction` MUST NOT be `bytes32(0)`.
`attestationDate` MUST NOT be `0` and MUST NOT be later than
`block.timestamp`. `expiresAt` MUST be later than `attestationDate` and MUST NOT
be earlier than `block.timestamp` at registration. `uri` MUST NOT be empty.
`extensions` MAY be empty.

`assetClass` SHOULD be a domain-separated identifier from a documented
taxonomy. When an anchor has one primary country jurisdiction, `jurisdiction`
SHOULD be a domain-separated identifier derived from its uppercase ISO 3166-1
alpha-2 code.

The URI identifies where a consumer can retrieve material corresponding to the
anchor commitments. This ERC does not require a particular URI scheme or
guarantee availability.

### Registry Interface

```solidity
interface IAssetAnchorRegistry {
    struct AnchorRecord {
        bytes32 anchorId;
        bytes32 legalHash;
        bytes32 evidenceHash;
        address boundToken;
        bytes32 bindingScope;
        uint256 boundTokenId;
        uint64 registeredAt;
        bool active;
    }

    event AnchorRegistered(
        bytes32 indexed anchorId,
        bytes32 legalHash,
        bytes32 evidenceHash
    );

    event TokenBound(
        bytes32 indexed anchorId,
        address indexed token,
        bytes32 indexed bindingScope,
        uint256 tokenId
    );

    event AnchorDeactivated(bytes32 indexed anchorId, string reason);

    event AnchorReattested(
        bytes32 indexed anchorId,
        uint64 oldExpiresAt,
        uint64 newExpiresAt,
        uint64 newAttestationDate
    );

    function registerAnchor(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) external returns (bytes32 anchorId);

    function bindToken(
        bytes32 anchorId,
        address token,
        bytes32 bindingScope,
        uint256 tokenId
    ) external;

    function registerAndBind(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata,
        address token,
        bytes32 bindingScope,
        uint256 tokenId
    ) external returns (bytes32 anchorId);

    function getAnchor(bytes32 anchorId)
        external
        view
        returns (AnchorRecord memory);

    function isBound(bytes32 anchorId) external view returns (bool);
}
```

### Registration

`registerAnchor` and `registerAndBind` MUST reject `bytes32(0)` for
`legalHash` or `evidenceHash`.

The anchor identifier MUST be derived as:

```solidity
anchorId = keccak256(abi.encode(legalHash, evidenceHash));
```

The same `(legalHash, evidenceHash)` pair therefore produces the same
`anchorId` within and across implementations of this ERC. A registry MUST
reject an `anchorId` that it has already registered.

On successful registration, the registry MUST:

- store the supplied hashes and derived `anchorId`;
- store `registeredAt` as `uint64(block.timestamp)`;
- initialize `boundToken` to `address(0)`;
- initialize `bindingScope` to `bytes32(0)`;
- initialize `boundTokenId` to `0`;
- initialize `active` to `true`; and
- emit `AnchorRegistered`.

The mechanism for authorizing registration is implementation-defined.
Implementations MUST document their authorization policy.

### Binding

`bindToken` MUST reject an unknown anchor, an inactive or expired anchor, a zero
token address, an unsupported binding scope, and an anchor whose binding fields
have already been set.

Before recording a binding, the registry MUST ensure that no valid anchor is
already associated with the same binding tuple. The uniqueness key SHOULD be
derived as:

```solidity
keccak256(abi.encode(token, bindingScope, tokenId))
```

On successful binding, the registry MUST set `boundToken`, `bindingScope`, and
`boundTokenId` and emit `TokenBound`. These three historical fields MUST NOT be
modified after they are set, including after deactivation or invalidation.

`registerAndBind` MUST apply the same registration and binding requirements
atomically.

The mechanism for authorizing binding is implementation-defined. It MUST
prevent an unrelated caller from binding another registrar's unbound anchor.

If `token` exposes `anchorRegistry()`, the returned address MUST equal the
registry performing the binding. A registry MAY bind a token that does not
implement a token-side interface. Such a record is a registry-side binding only
and does not constitute mutually declared binding under this ERC.

### Registry Queries

`getAnchor` MUST return the complete stored record and MUST revert for an
unknown `anchorId`.

`isBound` MUST return `true` when `boundToken` is not `address(0)`, regardless
of lifecycle activity or recovery invalidation. It MUST return `false` for a
known but unbound anchor and MUST revert for an unknown `anchorId`.

### Lifecycle Interface

Every compliant registry MUST implement the lifecycle interface because anchor
activity and expiry are part of the common verification model:

```solidity
interface IAssetAnchorRegistryLifecycle {
    function getMetadata(bytes32 anchorId)
        external
        view
        returns (AnchorMetadata memory);

    function registeredBy(bytes32 anchorId)
        external
        view
        returns (address);

    function isActive(bytes32 anchorId) external view returns (bool);

    function deactivateAnchor(
        bytes32 anchorId,
        string calldata reason
    ) external;

    function reattest(
        bytes32 anchorId,
        uint64 newExpiresAt,
        uint64 newAttestationDate
    ) external;
}
```

`getMetadata`, `registeredBy`, and `isActive` MUST revert for an unknown
anchor.

`registeredBy` MUST return the address that successfully registered the anchor
and MUST NOT change after registration.

`isActive` MUST return `false` if `AnchorRecord.active` is `false` or if
`block.timestamp > expiresAt`. An anchor remains active at the exact
`expiresAt` timestamp.

`deactivateAnchor` MUST be restricted to authorized callers, set `active` to
`false`, and emit `AnchorDeactivated`. Manual deactivation is permanent and
MUST NOT be reversed by `reattest`.

`reattest` MUST be restricted to an authorized caller and MUST reject a
manually deactivated anchor. `newAttestationDate` MUST NOT be `0`, later than
`block.timestamp`, or earlier than the existing `attestationDate`.
`newExpiresAt` MUST be later than `block.timestamp`, later than
`newAttestationDate`, and not earlier than the existing `expiresAt`. Successful
re-attestation MUST emit `AnchorReattested`.

### Recovery Interface

Binding recovery is OPTIONAL. A registry that permits disputed bindings to be
invalidated MUST implement:

```solidity
interface IAssetAnchorRegistryRecovery {
    event TokenBindingInvalidated(
        bytes32 indexed anchorId,
        address indexed token,
        bytes32 indexed bindingScope,
        uint256 tokenId,
        bytes32 reasonHash
    );

    function invalidateTokenBinding(
        bytes32 anchorId,
        bytes32 reasonHash
    ) external;

    function isBindingValid(bytes32 anchorId)
        external
        view
        returns (bool);
}
```

`invalidateTokenBinding` MUST be restricted to an authorized recovery role. It
MUST reject an unknown, unbound, or previously invalidated anchor and a zero
`reasonHash`.

Successful invalidation MUST:

- preserve `boundToken`, `bindingScope`, and `boundTokenId`;
- make `isBindingValid(anchorId)` return `false`;
- permanently deactivate the anchor;
- emit `AnchorDeactivated` if the anchor was active; and
- emit `TokenBindingInvalidated`.

An implementation MAY free the binding tuple so that a different anchor can be
bound to it. If it does so, the invalidated record MUST remain historically
queryable and MUST NOT itself be rebound.

`isBindingValid` MUST return `true` only when an anchor is bound and has not
been invalidated. It MUST revert for an unknown anchor.

### Token Interfaces

Whole-contract bindings use:

```solidity
interface IAssetBoundToken is IERC165 {
    function anchorId() external view returns (bytes32);
    function anchorRegistry() external view returns (address);
    function isAnchorActive() external view returns (bool);
}
```

Token-ID bindings use:

```solidity
interface IAssetBoundTokenId is IERC165 {
    function anchorIdOf(uint256 tokenId)
        external
        view
        returns (bytes32);

    function anchorRegistry() external view returns (address);

    function isAnchorActiveFor(uint256 tokenId)
        external
        view
        returns (bool);
}
```

`anchorRegistry` MUST remain unchanged after deployment.

For `IAssetBoundToken`, `anchorId` MUST remain unchanged after deployment.

For `IAssetBoundTokenId`, `anchorIdOf(tokenId)` MUST revert when the token ID is
not bound. Once a nonzero anchor is declared for a token ID, that declaration
MUST NOT change.

`isAnchorActive` and `isAnchorActiveFor` MUST reflect lifecycle activity from
the declared registry. Consumers MUST query `isBindingValid` separately when
the registry implements the recovery interface.

### ERC-165 Detection

Compliant registries MUST implement [ERC-165](./erc-165.md) and return `true`
for `type(IAssetAnchorRegistry).interfaceId`.

Compliant registries MUST return `true` for
`type(IAssetAnchorRegistryLifecycle).interfaceId`. Registries implementing
recovery MUST also return `true` for
`type(IAssetAnchorRegistryRecovery).interfaceId`.

Compliant tokens MUST return `true` for the applicable token-side interface ID.

ERC-165 detects interface support. It does not prove correct behavior, transfer
enforcement, registrar trustworthiness, or the validity of an off-chain claim.

### Complete Binding Verification

A consumer treating a binding as mutually declared MUST verify all of the
following:

1. `getAnchor(anchorId)` returns the expected token, scope, and token ID.
2. `isBound(anchorId)` returns `true`.
3. `isActive(anchorId)` returns `true`.
4. `isBindingValid(anchorId)` returns `true` when recovery is implemented.
5. The token supports the applicable token-side interface.
6. The token reports the same registry and anchor.

Failure of any applicable check means the consumer MUST NOT treat the binding
as a current mutually declared binding.

## Rationale

### Why Use a Registry?

A separate registry allows the same binding interface to compose with fungible,
non-fungible, multi-token, permissioned, and future token standards. It also
provides one inspection surface for applications that do not control the token
implementation.

The registry does not create global truth. Consumers select which registry
operators and authorization policies they trust.

### Why Two Hashes?

Off-chain asset structures often distinguish the instrument or legal basis
from evidence about the referenced asset. Separate commitments preserve that
distinction without assigning universal semantics to either document set.

Deployments that do not need the distinction can commit to two separately
defined records. A zero hash is not available as an omission sentinel.

### Why a Deterministic Anchor Identifier?

Deriving `anchorId` from both commitments gives implementations the same
identifier for the same pair of bytes and makes duplicate registration within a
registry unambiguous. It does not deduplicate semantically equivalent documents
with different byte representations.

### Why Explicit Binding Scope?

Using token ID `0` to mean whole-contract binding prevents token ID `0` from
being bound as an actual ERC-721 or ERC-1155 token. Including an explicit scope
makes contract binding and token-ID-zero binding distinct.

### Why Split the Token Interfaces?

A whole-contract token has no meaningful `anchorIdOf` query, while a collection
with independently anchored token IDs has no meaningful contract-wide
`anchorId`. Separate interfaces avoid mandatory functions with misleading or
implementation-specific failure behavior.

### Why Separate Activity from Binding?

A binding is historical identity data. Activity is lifecycle status. Expiry or
deactivation can make an anchor operationally inactive without changing which
token was bound to it. Accordingly, `isBound` is not an activity check.

### Why an Optional Recovery Interface?

Permanent bindings are vulnerable to registrar compromise, key loss, and
binding-key squatting. Recovery allows an explicitly trusted administrator to
invalidate an operational binding while preserving its history. Deployments
that prefer absolute immutability can omit the recovery interface.

Recovery introduces substantial administrative trust and is therefore not part
of the minimum registry interface.

### Why Not Enforce Allocation Integrity?

Allocation constraints, such as ensuring that fractional token supply does not
represent more than a defined share of an asset, depend on the economic and
legal structure of the instrument. They are meaningful for some fungible
fractional claims but not for a single NFT representing one object or for a
registry record that does not express ownership percentages.

The registry therefore standardizes binding identity rather than issuance or
allocation rules. Tokens and application-specific contracts remain responsible
for enforcing any supply, fraction, or entitlement constraints.

### Why Leave Registry Governance Open?

Different deployments require different trust models. A registry may be
operated by one accountable issuer, a regulated registrar, a multisignature, a
DAO, or a permissionless protocol. Requiring one governance model would exclude
otherwise interoperable implementations without making their off-chain claims
more truthful.

Consumers select which registries and governance policies they trust. The
common interface makes those registries technically inspectable; it does not
make them equally trustworthy.

### Why Are Historical Binding Fields Immutable?

Changing a binding's token, scope, or token ID in place would erase the
relationship that consumers previously inspected. This ERC therefore preserves
those fields after deactivation and recovery invalidation, allowing auditors
and other consumers to determine which tuple was recorded and how its status
changed over time.

Field immutability does not mean that a binding remains active or valid.
Consumers must evaluate lifecycle activity and, when implemented, recovery
validity separately. If an implementation releases an invalidated tuple, the
invalidated record remains queryable and a replacement is stored as a separate
anchor. The guarantee remains scoped to one registry and does not establish
global one-token-to-one-asset uniqueness.

### Prior Art

[ERC-6956](./erc-6956.md) defines ERC-721 tokens bound one-to-one to physical
or digital assets, with operations authorized by oracle attestations of control.
This ERC is token-standard-neutral and standardizes a registry record binding,
not proof-of-control authorization.

[ERC-7929](./erc-7929.md) permanently binds one on-chain token to another and
mirrors ownership behavior. This ERC binds token contracts or token IDs to
records representing off-chain claims and does not define token-to-token
ownership hierarchies.

[ERC-6065](./erc-6065.md) defines an ERC-721 extension for tokenized real estate
with property identifiers and operating-agreement data. This ERC is not limited
to real estate or ERC-721 and does not prescribe asset-specific operations.

[ERC-3643](./erc-3643.md) and [ERC-7943](./erc-7943.md) define token behavior and
compliance-related interfaces. They do not define the registry-scoped
token-to-anchor relationship specified here. Tokens implementing either can
also implement a token-side interface from this ERC.

## Backwards Compatibility

This ERC introduces new interfaces and does not change existing token
standards. Existing token contracts can be recorded in a registry without
modification, but this produces only a registry-side binding.

An existing upgradeable token can add the applicable token-side interface. An
immutable token that lacks the interface requires a wrapper, adapter, or new
deployment to provide mutually declared binding. Consumers should distinguish a
registry-only record from a binding confirmed by both registry and token.

## Test Cases

Implementations should test at least the following cases:

- deterministic anchor derivation and duplicate rejection;
- rejection of zero hashes and malformed metadata;
- contract scope with `tokenId == 0`;
- rejection of contract scope with a nonzero token ID;
- token-ID scope with token ID `0`;
- separation of contract scope from token-ID-zero scope;
- rejection of duplicate anchor and duplicate valid binding tuple use;
- atomic registration and binding;
- expiry at, before, and after the inclusive boundary;
- permanent manual deactivation;
- monotonic re-attestation;
- token registry mismatch;
- complete mutually declared binding verification across registry and
  token-side queries;
- preservation of binding fields across deactivation and recovery invalidation;
- lifecycle event coverage for registration, binding, re-attestation,
  deactivation, and recovery invalidation;
- optional release of an invalidated binding tuple; and
- positive and negative ERC-165 detection.

## Reference Implementation

A Solidity reference implementation, unit tests, fuzz tests, invariants, and an
independent audit are linked from the discussion referenced in the preamble.
The implementation is illustrative; its access-control roles and deployment
model are not required by this ERC.

## Security Considerations

### Registry Trust

The registry proves only that its own state satisfies the specified structural
rules. A malicious or compromised registrar can register false claims with
validly formed hashes and metadata. Consumers should evaluate the registry's
operator, authorization policy, upgrade authority, and legal context.

### No Legal or Physical Truth Guarantee

Neither a hash nor a mutually declared token binding proves that an off-chain
asset exists, that documents are authentic, or that a token conveys a legal
right. Those determinations require external verification.

### Registration-to-Binding Races

Separate registration and binding create an interval in which an unauthorized
caller may attempt to bind an anchor. Implementations should restrict binding to
authorized parties. Registrars should use `registerAndBind` when atomicity is
required.

### Malicious Tokens and Interface Spoofing

A token can return arbitrary values from the token-side interfaces or falsely
claim ERC-165 support. Consumers should verify the registry record independently.
Registries that call token contracts during binding should use static calls and
handle malformed return data and reverts.

### Recovery Authority

A recovery administrator can invalidate legitimate bindings and, when the
implementation releases binding tuples, enable replacement anchors. Production
deployments should protect recovery authority with a multisignature,
governance, timelock, or equivalent controls. Consumers should monitor
`TokenBindingInvalidated` and `AnchorDeactivated` events.

Releasing an invalidated tuple does not change an immutable token-side anchor
declaration. A replacement can be mutually declared only when the token already
declares the replacement anchor or does not expose a token-side interface.

### Document Canonicalization

The registry treats `legalHash` and `evidenceHash` as opaque commitments. Two
representations of the same document can produce different hashes. Deployments
requiring interoperable document commitments should define a deterministic
normalization and bundle-hashing procedure.

### Data Availability

An on-chain commitment is not useful for verification if the committed material
cannot be retrieved. The registry does not guarantee URI persistence or data
availability. Deployments should use durable storage and availability policies.

### Multi-Registry and Cross-Chain Duplication

Independent registries or deployments on different chains can register claims
about the same off-chain asset. This ERC provides no global uniqueness or
cross-registry conflict resolution.

Because `anchorId` does not include a chain identifier or registry address,
consumers requiring globally scoped identity should use
`(chainId, registry, anchorId)` rather than `anchorId` alone. A companion system
that accepts only a bare `anchorId` can otherwise conflate records from
different registry domains.

### Expiry and Timestamp Dependence

Lifecycle status depends on `block.timestamp`, which block producers can vary
within protocol constraints. Applications should avoid relying on second-level
precision around an expiry boundary.

### Upgradeability

An upgradeable registry can alter binding behavior after consumers begin
relying on it. Upgrades must preserve historical binding fields to remain
compliant. Consumers should inspect proxy administration and upgrade policies.

### Institutional and Regulated Deployments

Deployments operating under institutional or regulatory controls should
document registration and binding authority, protect recovery and upgrade
authority with appropriate multisignature, timelock, governance, or equivalent
controls, and monitor all binding and lifecycle events.

Such deployments should also define how contested invalidations are reviewed
and how committed records are made available to authorized auditors. Conformance
with this ERC provides a common technical interface; it does not establish
regulatory status, legal sufficiency, or compliance with any jurisdiction's
requirements.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
