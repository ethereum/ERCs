---
title: Onchain IP Asset and License Registry
description: Policy-neutral registry for IP assets, content-addressed license terms, and verifiable license agreements with signed provenance.
author: Jeroen Ost (@jeroost)
discussions-to: https://ethereum-magicians.org/t/onchain-ip-asset-and-license-registry/29792
status: Draft
type: Standards Track
category: ERC
created: 2026-06-30
requires: 165, 712, 721, 1271
---


## Abstract

This ERC defines a policy-neutral registry for intellectual-property assets,
content-addressed license terms, and license agreements. Assets and agreements
may be registry-tracked or bound to [ERC-721](./eip-721.md) tokens. The standard
provides globally scoped identifiers, machine-readable terms, constant-work agreement
verification, bounded discovery, signed provenance, and extensible policy hooks
while preserving mandatory caller authorization. It applies to off-chain,
onchain, and hybrid works and standardizes mechanism rather than policy.

## Motivation

Owning an ERC-721 token and holding rights to a work are different. Licensing
information generally remains in legal documents and platform databases that
contracts cannot inspect, forcing applications to implement incompatible
rights records.

This ERC defines a neutral registry for answering three questions: what is the
work and who administers it, under what terms may it be used, and who currently
holds an active agreement? Deployments choose their own eligibility,
jurisdiction, governance, and trust policies through hooks and documented
authorization roles. This supports both institutional and permissionless uses
without selecting a privileged registry.

Machine-readable discovery is also necessary for autonomous software that must
inspect terms and agreement state before acquiring or using licensed material.

### Relationship to existing approaches

[ERC-5218](./eip-5218.md) and [ERC-5554](./eip-5554.md) define token-centered
rights and licensing interfaces.
Story Protocol provides an integrated IP-asset, licensing, and graph system on
its own network. They overlap with this proposal in capabilities, but use
different deployment and identity models:

| Approach | Asset / agreement model | Terms and relationships |
| --- | --- | --- |
| ERC-5218 / ERC-5554 | ERC-721-centered records with contract-local ids | URI- or interface-defined rights and token-centered relationship operations |
| Story Protocol | Protocol-specific IP accounts and modules | Integrated licensing and graph facilities |
| This ERC | Registry records that may be non-tokenized or ERC-721-bound, with globally scoped `(chainId, registry, id)` references | Content-addressed machine-readable terms, bounded agreement discovery, and provenance records usable by future graph ERC extensions |

This proposal neither requires nor modifies those systems; mappings are an
off-chain indexing concern. Standardized adapters are future work for separate
ERC extensions.

### Overview

*This section is non-normative. It builds the mental model the normative
Specification then pins down.*

#### Three records

| Record | Purpose |
| --- | --- |
| **IP asset** (`assetId`) | Identifies a work, its declared authors, administrative owner, and metadata. |
| **License terms** (`termsId`) | Immutable, reusable licensing conditions, identified by a hash of their contents. |
| **License agreement** (`agreementId`) | Records a grant binding one asset, terms record, and licensee. |

An owner **attaches** registered terms to an asset to publish a standing offer:
qualifying callers can obtain agreements without further owner approval.
Attachment alone grants no rights. An asset may have many attached terms and
agreements.

The **administrative owner** controls an asset's registry record: metadata,
terms attachment, grants, and revocation. It is distinct from the declared
authors and asserts no legal title. For registry-tracked assets and agreements
(`NONE`), the registry stores the current administrative owner or licensee. For
ERC-721-bound records (`ERC721`), the current token holder supplies that role.

#### Mechanism, not policy

Deployments choose eligibility rules, such as identity or jurisdiction
requirements. **Pre-flight hooks** let anyone query those rules before
submitting a transaction: `canRegister`, `canUpdateMetadata`, `canTransferAsset`,
`canTransferAgreement`, `canAttachTerms`, `canDetachTerms`, `canLicense`,
`canRevoke`, and `canDerive`.

These are read-only (`view`) functions returning `(bool ok, bytes32 reason)`.
For example, `canLicense` asks whether policy permits a prospective licensee
to obtain an agreement. `ok` reports approval or denial of the proposed action;
`reason` is a deployment-defined denial code (zero on approval). Returning a
code rather than reverting lets clients inspect a refusal without attempting
the transaction.

State-changing functions check their required hooks against current state and
revert with `HookDenied(reason)` on denial. A favorable pre-flight result
neither authorizes a caller nor guarantees a later transaction will succeed.
`canDerive` is advisory: it queries policy on deriving a work from a parent
asset but is not a mandatory registration gate.

#### Agreement verification and discovery

An agreement is active when it has a current licensee and is not expired,
revoked, or frozen. Given an `agreementId` (called a **witness**),
`isActiveAgreementHolder(agreementId, assetId, party)` checks whether `party`
holds that active agreement for `assetId` without scanning other agreements.
This is the constant-work verification path.

If no agreement ID is known,
`activeAgreementsOf(assetId, party, cursor, limit)` searches in pages.
`limit` bounds records examined, not matches returned; an empty page alone
does not establish absence, which requires completing the scan. These views
report registry state, not legal validity or permission for a contemplated use.

#### Cross-registry / cross-chain references

Any record can be named globally by a canonical string of the form
`<prefix>:<chainId>:<registry>/<id>`:

```
ipid:<chainId>:<registry>/<assetId>              # an IP asset
ipterms:<chainId>:<registry>/<termsId>           # a license terms object
ipagreement:<chainId>:<registry>/<agreementId>   # a license agreement
```

An asset may include a **derivation attestation**: a signed statement of its
parent works, or an explicit statement that it is original. Each parent is
identified by a `ParentRef`, the structured `(chainId, registry, assetId)` form.
References support off-chain resolution and indexing, not onchain verification
of remote state. §2 defines their canonical syntax.

#### A typical licensing flow

1. Alice calls `register` for a song and receives an `assetId`.
2. She calls `registerTerms` to obtain a `termsId`, then `attachTerms` to publish the offer.
3. Bob queries `canLicense`, then calls `acquireAgreement`; if the transaction's checks pass, he receives an `agreementId`.
4. A marketplace uses Bob's `agreementId` to check his active-holder state and separately evaluates the terms for his proposed use.
5. Expiry, revocation, or freezing the agreement makes it inactive without deleting its record.

#### What this ERC does *not* do

The core does not perform royalty distribution, fee collection, royalty-stream
tokenization, derivation-graph traversal, dispute resolution, legal enforcement,
or cross-chain verification. Standardized mechanisms for these capabilities and
concrete identity, jurisdiction, delegation, and governance schemes are future
work for separate ERC extensions, not dependencies of this proposal. Deployments
may apply their own policy through the hooks and protected roles defined here.
[ERC-165](./eip-165.md) conformance proves interface shape, not honesty.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in RFC 2119 and RFC 8174.

A conforming registry implements the `IIPAssetRegistry` interface (which
inherits `ITermsRegistry`) and returns `true` from ERC-165 `supportsInterface`
for the ERC-165 id, the `IIPAssetRegistry` id **`0x72117f80`**, and the
`ITermsRegistry` id **`0x38c7f550`**.

### 1. Data model and types

This section defines the shared enums, structs, and well-known constants
referenced throughout the interface. They are the canonical ABI: a conforming
registry MUST use these declarations verbatim.

#### 1.1 Tokenization modes

```solidity
enum AssetTokenization { NONE, ERC721 }
enum AgreementTokenization { NONE, ERC721 }
```

These enums are closed because delegated ownership is safe only for token kinds
whose semantics the core defines. New kinds require a superseding or extension
ERC, not runtime governance. `NONE` stores an owner or licensee; `ERC721`
delegates that role to the bound token holder. Other bindings MUST use `NONE`.

#### 1.2 Authorship

```solidity
struct Author {
    address author;          // MAY be address(0) for anonymous authorship
    uint256 shareNumerator;
}
```

The `authors` array, including every author address and share numerator, and
`sharesDenominator` MUST be fixed at registration and MUST NOT be modified
thereafter, including through administrative or extension operations.

Each author's share is an integer numerator over a per-asset
`sharesDenominator` chosen at registration. When `authors.length > 0`, the sum
of all `shareNumerator` values MUST equal `sharesDenominator` and
`sharesDenominator` MUST be greater than zero; when
`authors.length == 0`, `sharesDenominator` is unconstrained and SHOULD be zero.
The canonical representation is the exact fraction. Registries SHOULD expose a
basis-points helper for [ERC-2981](./eip-2981.md)-style consumers but MUST NOT
store shares as basis points.

#### 1.3 Derivation

```solidity
struct ParentRef {
    uint256 chainId;
    address registry;
    bytes32 assetId;
}

struct DerivationAttestation {
    ParentRef[] parents;     // MAY be empty (explicit "original work")
    address     issuer;      // address(0) only in the canonical empty struct
    bytes       signature;   // EOA: canonical ECDSA; contract issuer: ERC-1271
    bytes       metadata;
    bytes32     registrationHash;
}
```

Absence has exactly one encoding: `issuer == address(0)`, empty `parents`,
`signature`, and `metadata`, and `registrationHash == bytes32(0)`. A zero issuer
with any other nonempty or nonzero field is malformed and registration MUST
revert with `MalformedDerivationAttestation()`; implementations MUST NOT silently
ignore those fields. A present attestation has a nonzero issuer. Its `parents`
MAY still be empty, which is a signed explicit "original work" statement rather
than absence.

The signing digest is normative. The [EIP-712](./eip-712.md) domain is
`EIP712Domain("IPAssetRegistry", "1", chainId, registry)`. Type strings are
exactly:

```text
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
Author(address author,uint256 shareNumerator)
ParentRef(uint256 chainId,address registry,bytes32 assetId)
AssetData(bytes32 assetType,uint8 tokenization,address tokenCollection,uint256 tokenId,bytes32 contentHash)
Registration(bytes32 salt,address registrant,address owner,bytes32 authorsHash,uint256 sharesDenominator,bytes32 assetDataHash,bytes32 metadataURIHash)
Derivation(uint256 chainId,address registry,bytes32 assetId,bytes32 registrationHash,bytes32 parentsHash,bytes32 metadataHash)
```

Each type hash is `keccak256(bytes(typeString))`. `authorsHash` and
`parentsHash` are `keccak256(abi.encodePacked(elementHashes))`, preserving array
order, where each element hash is `keccak256(abi.encode(typeHash, fields...))`.
`assetDataHash` hashes the `AssetData` type hash and exact supplied asset fields.
`registrationHash` hashes the `Registration` type hash, `salt`, the intended
`registrant` (`msg.sender`), `owner`, `authorsHash`, `sharesDenominator`,
`assetDataHash`, and `keccak256(bytes(metadataURI))`.

The signed struct hash is `keccak256(abi.encode(DERIVATION_TYPEHASH, chainId,
registry, assetId, registrationHash, parentsHash, keccak256(metadata)))`; the
digest is the standard `keccak256("\x19\x01" || domainSeparator || structHash)`.
The registry MUST recompute the registration hash and require it equals the
value in the attestation. If `issuer` has no code, it MUST recover `issuer` from
a 65-byte `r || s || v` ECDSA signature over the digest; `v` MUST be 27 or 28
and `s` MUST use [EIP-2](./eip-2.md)'s low-`s` canonical form. If `issuer` has
code, it MUST instead call [ERC-1271](./eip-1271.md)
`isValidSignature(bytes32,bytes)` with `(digest, signature)` via `staticcall`
with at most 100,000 gas, and accept only an exact, canonical 32-byte ABI
encoding of `bytes4(0x1626ba7e)`. A reverted, over-budget, malformed, or
non-magic response MUST reject registration. Contract signatures are opaque;
the EOA signature-length and `v`/`s` rules do not apply to them.

A `ParentRef` references a parent asset by its canonical
`(chainId, registry, assetId)` tuple, so provenance edges cross registries and
chains. A `DerivationAttestation` is a dedicated structural field on the asset
record — **not** a generic asset-claim (§5). It is OPTIONAL, set only at
registration, and immutable thereafter (§9).

#### 1.4 License terms

```solidity
struct LicenseTerms {
    // 1. Universal frame
    uint64  expiry;            // absolute unix-seconds hard deadline; 0 = none
    uint64  duration;          // seconds from agreement creation; 0 = none
    bool    transferable;      // may the resulting LicenseAgreement be transferred
    bool    revocable;         // permits ordinary owner revocation
    bool    sublicensable;     // recorded assertion; no core sublicense action
    bool    exclusive;         // does this grant preclude others on the same scope
    bytes32 jurisdictionScope; // well-known: keccak256("worldwide"), keccak256("JP"), …

    // 2. Mandatory rights summary (comparable across every termsType)
    RightsSummary rights;

    // 3. Authoritative legal text
    string  uri;
    bytes32 contentHash;

    // 4. Domain-specific rights
    bytes32 termsType;         // content-addressed schema id, or bytes32(0) for none
    bytes   rightsData;        // ABI-encoded per termsType's schema
}

enum Ternary  { UNSPECIFIED, YES, NO }
enum FeeModel { UNSPECIFIED, FREE, ONE_TIME, RECURRING, USAGE_BASED, EXTERNAL }

struct RightsSummary {
    Ternary  commercialUse;       // YES = commercial use permitted
    Ternary  derivativesAllowed;  // YES = derivative works permitted
    Ternary  attributionRequired; // YES = attribution required
    FeeModel feeModel;            // coarse, amount-free classifier
}
```

`LicenseTerms` comprises a universal frame, mandatory rights summary, optional
legal-text anchor `(uri, contentHash)`, and domain-specific
`(termsType, rightsData)`. `expiry` and `duration` determine agreement expiry.
The registry enforces `transferable` only for `NONE` and `revocable` for both
agreement tokenization modes; `sublicensable`,
`exclusive`, and `jurisdictionScope` are recorded for consumers. The frame MUST
NOT be extended per deployment.

`sublicensable` is only an assertion: it does not authorize a licensee to call
`createAgreement` or create a core sublicense relationship. Standardized onchain
sublicensing is future work for a separate ERC extension. Such an extension must
define the parent-agreement relationship, licensee grant authority, child
lifecycle and terms constraints, and its read/event surfaces.

`rights` is present on every `LicenseTerms`; the registry records it and MUST
NOT act on it. Its three dimensions are tri-state: `UNSPECIFIED` makes no
assertion; `YES` and `NO` do. `feeModel` classifies fee structure but MUST NOT
encode amounts, currencies, or settlement. This summary is a comparison floor:
`rightsData` MAY refine it but MUST NOT contradict it. When
`termsType == bytes32(0)`, the summary is the complete machine-readable rights
expression.

The optional `(uri, contentHash)` legal wrapper identifies the authoritative
human-readable instrument incorporated by reference. Deployments needing a
legally operative instrument SHOULD populate it; enforceability remains an
off-chain question.

When the legal wrapper is present, `contentHash` MUST equal
`keccak256(documentBytes)`, where `documentBytes` is the exact canonical byte
sequence selected by the publisher for the legal document resolved through
`uri`. Consumers MUST hash that sequence without Unicode normalization,
line-ending conversion, reserialization, or other content transformation. The
same human-readable text serialized differently therefore has a different hash.
The URI scheme and retrieval mechanism are not standardized. The wrapper is
absent when `uri == ""` and `contentHash == bytes32(0)`; a non-empty `uri` MUST
have a non-zero matching `contentHash`, and a non-zero `contentHash` MUST have a
non-empty `uri`. `registerTerms` MUST otherwise revert with
`IncompleteLegalWrapper()`.

The four layers MUST NOT contradict one another. Protocol behavior follows the
universal frame; legal prose cannot override it. `rightsData` and legal text MAY
add detail but MUST NOT negate or broaden a machine-readable assertion;
`UNSPECIFIED` permits them to supply missing meaning. The core cannot detect
semantic conflicts. Consumers MUST reject or flag conflicting terms, and
MUST NOT select whichever layer is more favorable. Correction requires a new
`termsId`; existing terms and agreements MUST NOT be rewritten.

#### 1.5 Parameter bundles

```solidity
struct RegistrationParams {
    bytes32           salt;              // assetId = keccak256(abi.encode(chainId, registry, registrant, salt)); registrant = msg.sender
    address           owner;             // NONE: non-zero owner; ERC721: MUST be zero
    Author[]          authors;
    uint256           sharesDenominator;
    bytes32           assetType;
    AssetTokenization tokenization;
    address           tokenCollection;   // ERC721: non-zero contract; ignored for NONE
    uint256           tokenId;           // ignored when tokenization == NONE
    string            metadataURI;
    bytes32           contentHash;
    DerivationAttestation derivationAttestation; // all fields empty/zero to omit
}

struct AgreementParams {
    bytes32                assetId;
    bytes32                termsId;               // MUST be locally registered and attached
    address                party;               // NONE: licensee (non-zero); ERC721: ignored
    AgreementTokenization  agreementTokenization;
    address                agreementCollection; // ERC721: non-zero; ignored for NONE
    uint256                agreementTokenId;     // ignored when agreementTokenization == NONE
    bytes                  licenseParams;        // opaque to the core; forwarded to canLicense
    bytes32                acceptanceHash;       // optional commitment; bytes32(0) = absent
}

enum AgreementCreationMode { GRANT, ACQUIRE }

struct AgreementEvidence {
    address               licensor;              // administrative owner snapshot
    address               createdBy;             // actual transaction caller
    address               initialLicensee;
    uint64                createdAt;
    AgreementCreationMode creationMode;
    bytes32               licenseParamsHash;
    bytes32               acceptanceHash;
}
```

#### 1.6 Well-known constants

The ERC defines well-known `bytes32` asset types as `keccak256` of short
lowercase ASCII strings. Implementers MAY use any other value (conventionally
`keccak256(<descriptive string>)`); no core function dispatches on `assetType`.

| Constant | Preimage |
| --- | --- |
| `ASSET_TYPE_AUDIO`     | `"audio"` |
| `ASSET_TYPE_VIDEO`     | `"video"` |
| `ASSET_TYPE_IMAGE`     | `"image"` |
| `ASSET_TYPE_TEXT`      | `"text"` |
| `ASSET_TYPE_SOFTWARE`  | `"software"` |
| `ASSET_TYPE_DATASET`   | `"dataset"` |
| `ASSET_TYPE_MODEL`     | `"model"` |
| `ASSET_TYPE_PATENT`    | `"patent"` |
| `ASSET_TYPE_ALGORITHM` | `"algorithm"` |

Further well-known constants are defined:

```solidity
bytes32 constant JURISDICTION_WORLDWIDE = keccak256("worldwide");
bytes32 constant TERMS_TYPE_GENERIC_V1  =
    0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa;
```

`JURISDICTION_WORLDWIDE` is the conventional global scope; other scopes use
ISO 3166-1 alpha-2 by convention.
`TERMS_TYPE_GENERIC_V1` is the **only** well-known `termsType` defined by this
ERC. It equals `keccak256(schemaBytes)`, where `schemaBytes` is exactly the UTF-8
encoding of the single JSON line below, from its first `{` through its final
`}`, with no byte-order mark, surrounding whitespace, or line terminator.
The code fences and all surrounding prose are excluded. Consumers MUST NOT
reserialize the JSON, normalize Unicode, or otherwise transform those bytes.

```json
{"schema":"generic-license-v1","encoding":"Solidity ABI, one tuple argument","abi":"(bool,bool,bool,string)","fields":[["commercialUse","true permits use intended to generate direct or indirect revenue; false restricts use to non-commercial purposes"],["derivativesAllowed","true permits derivative works; false prohibits them; non-commercial restrictions also apply to derivatives"],["attributionRequired","true requires author credit when using or distributing the work or its derivatives; false imposes no attribution requirement"],["attributionTemplate","UTF-8 credit format when attributionRequired is true; MAY contain {authorName}, {assetTitle}, {licenseName}, {licenseURI}, {year}; consumers SHOULD substitute recognized placeholders and leave others verbatim; SHOULD be empty when attributionRequired is false; a nonempty template MUST NOT imply attributionRequired"]],"summary":"Each boolean MUST match the corresponding RightsSummary value: true=YES, false=NO; UNSPECIFIED is invalid for these three dimensions","frame":"expiry, duration, transferable, revocable, sublicensable, exclusive, jurisdictionScope remain in the outer LicenseTerms; protocol behavior follows that frame","legal":"The uri/contentHash wrapper is optional; applicable law and consistent legal text determine commercial-use and derivative-work boundaries; legal text MAY add detail but MUST NOT contradict the frame, summary, or payload","validation":"Consumers MUST reject invalid ABI encodings and reject or flag conflicting terms layers; the core stores rightsData without semantic validation"}
```

This block fixes the schema's layout and semantics independently of editorial
changes elsewhere in the ERC. Changing its canonical bytes requires a new
`termsType`. Additional standardized domain schemas are future work for ERC
extensions; they are not prerequisites for using the schema defined here.

##### The `generic-license-v1` rights schema

`generic-license-v1` is the minimal, asset-type-agnostic rights schema so that
simple registrations need not choose a domain-specific one. For
`termsType == TERMS_TYPE_GENERIC_V1`, `LicenseTerms.rightsData` MUST be the ABI
encoding (`abi.encode(...)`) of exactly this struct, in this field order:

```solidity
struct GenericLicenseV1Rights {
    bool   commercialUse;         // may the licensee use the asset commercially
    bool   derivativesAllowed;    // may the licensee create derivative works
    bool   attributionRequired;   // must the licensee credit the author(s)
    string attributionTemplate;   // how to render attribution; "" when not required
}
```

For each of the three duplicated dimensions, the outer summary and decoded
generic boolean MUST satisfy:

| `RightsSummary` value | Generic boolean | Valid? |
| --- | --- | --- |
| `YES` | `true` | Yes |
| `YES` | `false` | No |
| `NO` | `false` | Yes |
| `NO` | `true` | No |
| `UNSPECIFIED` | either value | No |

The strict `UNSPECIFIED` rule is required because a boolean always makes an
assertion. Terms using `TERMS_TYPE_GENERIC_V1` MUST therefore specify
`commercialUse`, `derivativesAllowed`, and `attributionRequired` as `YES` or
`NO` in the summary and encode the matching booleans. The core stores
`rightsData` opaquely and does not perform this semantic validation; conforming
generic-schema decoders, hooks, catalogs, and agents MUST reject a mismatch.

`commercialUse` covers direct or indirect revenue; legal text defines its
boundaries. `derivativesAllowed` permits derivative works, whose legal meaning
may be domain-specific. `attributionRequired` controls whether credit is
required; a non-empty template alone does not. `attributionTemplate` is
free-form UTF-8 and MAY use `{authorName}`, `{assetTitle}`, `{licenseName}`,
`{licenseURI}`, and `{year}` placeholders. When attribution is required, consumers
SHOULD substitute recognized placeholders and leave others verbatim; the template
SHOULD be empty when attribution is not required. Attribution applies when using
or distributing the work or its derivatives. Permitted derivatives remain
subject to any non-commercial restriction.

Decoders MUST reject invalid encodings. Legal text MAY add detail but MUST
remain consistent with §1.4. A schema revision requires a new `termsType`.

### 2. Identity and registration

Canonical functions: `register`, `assetExists`, `chainId`.

- An asset is identified by a `bytes32 assetId` unique within its registry,
  derived as `keccak256(abi.encode(chainId, registry, registrant, salt))`,
  where `registrant` is the registering caller (`msg.sender`) and `salt` is
  caller-chosen. The canonical global identifier is the tuple
  `(chainId, registry, assetId)`, encoded as `ipid:<chainId>:<registry>/<assetId>`.
- Canonical references use `<prefix>:<chainId>:<registry>/<id>`.
  `<chainId>` is nonzero [EIP-155](./eip-155.md) base-10 without leading zeros;
  `<registry>` is a lowercase `0x`-prefixed 20-byte address; `<id>` is lowercase
  `0x`-prefixed `bytes32`. The prefixes are `ipid`, `ipterms`, and
  `ipagreement`.
- `chainId()` MUST return the nonzero EIP-155 chain id captured from
  `block.chainid` at deployment and MUST remain unchanged for the registry's
  lifetime, even if live `block.chainid` changes after a fork. Deployment with
  chain id zero MUST revert. This captured value MUST be used consistently in
  asset and agreement identifiers, canonical references, and the EIP-712 domain.
- `register` MUST accept the `RegistrationParams` bundle (salt, owner, authors +
  `sharesDenominator`, assetType, tokenization + token binding, metadata pointer,
  optional derivation attestation) and MUST refuse when `canRegister` denies.
  The registrant (`msg.sender`) is transient and MUST NOT gain ongoing
  authority.
- **Tokenization-dependent registration invariants.** For
  `AssetTokenization.NONE`, `params.owner` MUST be non-zero and is stored as the
  initial administrative owner; `params.tokenCollection` and `params.tokenId`
  are ignored and MUST be stored as `address(0)` and `0`. For
  `AssetTokenization.ERC721`, `params.owner` MUST equal `address(0)` because
  ownership is delegated rather than supplied. The zero value is canonical and
  remains part of the signed `Registration` payload when a derivation
  attestation is present.

  For `ERC721`, `params.tokenCollection` MUST be a non-zero address containing
  contract code. During registration the registry MUST call
  `ownerOf(params.tokenId)` with the same 100,000-gas stipend and exact
  canonical 32-byte address-word validation used by `ownerOf`. A revert,
  over-budget call, malformed result, or zero returned holder MUST reject
  registration. The binding is stored, but the holder is not cached.
  `AssetRegistered.owner` MUST be the non-zero holder resolved by that
  registration-time query, not `params.owner`.
- **Asset content hash.** `RegistrationParams.contentHash` commits to the exact
  original-work bytes:
  `contentHash = keccak256(originalWorkBytes)`. Consumers MUST NOT normalize,
  transcode, or reserialize before hashing. Structured works require a
  deterministic representation such as a canonical manifest; this ERC
  establishes byte identity, not semantic equivalence. `metadataURI` describes
  how to retrieve those bytes and is not itself hashed unless selected as the
  representation. `contentHash` is immutable and MUST be nonzero for `NONE`; it
  MAY be zero for `ERC721`.

### 3. Asset read paths

Canonical functions: `ownerOf`, `authorsOf`, `tokenizationOf`, `assetTypeOf`,
`metadataOf`, `derivationAttestationOf`, `attachedTermsOf`, `agreementCountOf`,
`agreementAtIndex`, `activeAgreementsOf`.

- All read paths MUST be permissionless `view`s and MUST NOT revert on unknown
  ids. `ownerOf`/`getLicensee` delegate to `IERC721(collection).ownerOf`
  for `ERC721`, using a 100,000-gas stipend and accepting exactly one
  canonical 32-byte address word. A reverting, over-budget, or malformed query
  reads as `address(0)`.
- Unknown assets return exact sentinels: `assetExists == false`, owner
  `address(0)`, authors `([], 0)`, tokenization `(NONE, address(0), 0)`, asset
  type `bytes32(0)`, metadata `("", bytes32(0))`, a zero derivation attestation,
  two empty attached-terms arrays, and agreement count `0`.
- `agreementAtIndex` returns `bytes32(0)` when its asset is unknown or its index
  is not less than `agreementCountOf(assetId)`; an invalid index is not a
  precondition violation and MUST NOT revert.
- Both `activeAgreementsOf` overloads scan the stable per-asset index.
  `limit` bounds records examined, not returned; the party overload returns only
  active agreements held by `party`. An empty page proves absence only when
  `nextCursor == agreementCountOf(assetId)`. For
  `cursor <= agreementCountOf(assetId)`, zero `limit` returns that cursor.
  Unknown assets return cursor `0`; out-of-range cursors on known assets return
  the agreement count. These calls MUST NOT overflow or revert.

### 4. Asset mutation

Canonical functions: `updateMetadata(assetId, newURI)`, `transferOwnership`.

- Both functions require the current owner or an **authorized delegate**,
  independently of hook policy. Throughout this ERC, an authorized delegate is
  an address authorized to act for the named party under the registry's
  delegation policy. Delegation mechanisms are implementer-defined, and
  registries MUST document their policy.
- `contentHash` is a registration-time anchor and is immutable; `updateMetadata`
  moves only the descriptive metadata URI and MUST NOT change the committed
  original-work bytes. It MUST enforce `canUpdateMetadata`.
  `transferOwnership` applies to `NONE` assets, MUST enforce
  `canTransferAsset(assetId, currentOwner, newOwner)`, and MUST revert
  for `ERC721` (ownership lives in the token contract).

### 5. Asset claims

Canonical functions: `addClaim`, `revokeClaim`, `getClaim`, `getClaimIssuers`,
`setTrustedIssuer`, `isTrustedIssuer`. The claim shape is inspired by
[ERC-3643](./eip-3643.md), but the core defines no topics or signature encoding
and does not dispatch on trust.
Signatures are stored verbatim and are issuer-scheme-specific; consumers MUST
know the scheme, verify signatures off chain, and choose trusted issuers.

`addClaim` and `revokeClaim` require the named issuer or its authorized
delegate. `setTrustedIssuer` requires the documented governance authority. Each successful trust
change, including removal, MUST emit `TrustedIssuerChanged`.

Each `(assetId, topicId)` MAY have one current record per issuer. Revocation
retains the record and sets `revoked == true`; `getClaimIssuers` returns only
non-revoked issuers. Add/replace and revoke operations MUST emit
`AssetClaimAdded` and `AssetClaimRevoked`. Missing claims return
`(bytes(""), bytes(""), 0, false)`; unknown issuer lists are empty and unknown
trust entries are false. These reads MUST NOT revert.

Industry identifiers such as ISWC, ISRC, ISNI, ISBN, and DOI use
implementer-defined topics (conventionally `keccak256` of the lowercase scheme)
and canonical UTF-8 identifier data. Standardized topic and signature schemes
are future work for ERC extensions.

### 6. License terms and attachment

Canonical functions: `registerTerms`, `termsExists`, `getTerms` (the
local terms-storage role, factored into the inherited `ITermsRegistry`
interface), plus `attachTerms`, `detachTerms`.

- Terms MUST be registered in the asset registry before attachment. Identical
  terms mirrored elsewhere retain the same `termsId`; remote `ipterms:`
  references are for off-chain discovery only.
- Attachment and detachment are owner-controlled. The caller MUST be the
  asset's current administrative owner or its authorized delegate.
  Authorization is mandatory and independent of `canAttachTerms` and
  `canDetachTerms`; permissive hooks MUST NOT authorize unrelated callers.
- **Attachment is standing acquisition authorization.** While attached,
  qualifying callers may invoke `acquireAgreement` without contemporaneous
  owner approval, subject to creation invariants and
  `canLicense(assetId, termsId, caller, licenseParams, acceptanceHash)`.
  Attachments persist across ownership changes until detached; the owner at
  acquisition is captured as licensor.
- `attachmentParameters` is opaque configuration available to hooks. Attachment
  grants no rights and creates no agreement.
- `attachTerms` MUST require `termsExists(termsId)`. Both creation paths MUST
  require the same `termsId` to remain attached and locally registered.
  `getTerms` MUST revert for an unknown id.

- `termsId = keccak256(abi.encode(terms))`, using the canonical encoding defined
  below; terms are immutable and reusable. Re-registering a known `termsId`
  MUST succeed, return that id, leave stored terms unchanged, and emit no event.
- **Canonical terms encoding.** `terms` MUST be encoded as one `LicenseTerms`
  tuple argument using the Solidity ABI specification. Its canonical ABI type is
  `(uint64,uint64,bool,bool,bool,bool,bytes32,(uint8,uint8,uint8,uint8),string,bytes32,bytes32,bytes)`;
  the nested tuple is `RightsSummary`, and each enum is encoded using its declared
  `uint8` ordinal. Field order is exactly the declaration order in §1.4. Packed,
  textual, field-by-field, or implementation-defined encodings are non-conforming.
  In particular, `abi.encode(terms.expiry, ...)` is not interchangeable with
  `abi.encode(terms)`: the latter encodes one dynamic tuple argument and therefore
  includes its top-level offset. Implementations in other languages MUST produce
  exactly the same bytes as Solidity's `abi.encode(terms)`. A future change to
  either struct's shape or field order requires a new ERC revision and MUST NOT
  silently redefine existing `termsId` values.

  The following vectors are normative. Hex strings are the complete output of
  `abi.encode(terms)`.

  **Vector 1 — all fields zero/default**

  ```text
  terms = LicenseTerms(0, 0, false, false, false, false, 0x00…00,
          RightsSummary(UNSPECIFIED, UNSPECIFIED, UNSPECIFIED, UNSPECIFIED),
          "", 0x00…00, 0x00…00, hex"")
  encodedLength = 576
  encoded =
  0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
  termsId = 0x6c30a113f027b95c15f0b7b763866b623f284f67fc293aada6eb6ea598397db5
  ```

  **Vector 2 — populated static and dynamic fields**

  ```text
  expiry = 2000000000
  duration = 31536000
  transferable = true
  revocable = true
  sublicensable = false
  exclusive = true
  jurisdictionScope = 0x1111111111111111111111111111111111111111111111111111111111111111
  rights = RightsSummary(YES, NO, YES, ONE_TIME)
  uri = "ipfs://terms"
  contentHash = 0x2222222222222222222222222222222222222222222222222222222222222222
  termsType = 0x3333333333333333333333333333333333333333333333333333333333333333
  rightsData = hex"010203"
  encodedLength = 640
  encoded =
  0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000773594000000000000000000000000000000000000000000000000000000000001e1338000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111111111111111111111111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000001e0222222222222222222222222222222222222222222222222222222222222222233333333333333333333333333333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000000c697066733a2f2f7465726d73000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030102030000000000000000000000000000000000000000000000000000000000
  termsId = 0x65ab60a127daf191b77e3597eabe71e4e3aab8f79852fa6169d2874cb9be322e
  ```
- Reattaching the same `termsId` updates
  `attachmentParameters` in place and MUST emit
  `TermsAttached(assetId, termsId, attachmentParameters)` with
  the complete new value. The same event is emitted for an initial attachment,
  allowing indexers to reconstruct current parameters without transaction
  calldata.
- Detachment MUST enforce `canDetachTerms` and emit `TermsDetached`. It blocks
  both agreement-creation paths from creating future agreements under that
  attachment, but MUST NOT invalidate, rewrite, or deactivate agreements
  already created from it.
- `LicenseTerms` is public in transaction calldata and through `getTerms`; see
  Security Considerations.

### 7. License agreements and activity

Canonical functions: `createAgreement`, `acquireAgreement`, `transferAgreement`,
`agreementOf`, `getLicensee`, `activeAgreementsOf`,
`isActiveAgreementHolder`, `isAgreementActive`.

- **Canonical agreement ID.** Let `agreementIndex` be
  `agreementCountOf(assetId)` immediately before the agreement is appended.
  Both creation paths MUST return:

  ```solidity
  agreementId = keccak256(
      abi.encode(chainId(), address(this), assetId, agreementIndex)
  );
  ```

  Here `chainId()` is the issuing registry's canonical chain identifier.
  The encoded field types are exactly `(uint256,address,bytes32,uint256)`.
  Packed, textual, reordered, block-number-dependent, timestamp-dependent, or
  implementation-defined encodings are non-conforming. The resulting ID MUST
  be non-zero and MUST NOT identify an existing agreement. An implementation
  encountering either condition MUST revert with
  `AgreementIdCollision(agreementId)` rather than overwrite or reuse a record.
  Agreement indices and IDs are append-only and MUST NOT be reused after
  revocation, expiry, freezing, or any other lifecycle change. The globally
  canonical identity remains `(chainId(), address(this), agreementId)`, or
  its `ipagreement:` representation.
- Every agreement has a licensee at creation and captures its local terms'
  lifecycle frame.
- `createAgreement` is a grant by the current asset owner or its authorized
  delegate, independently of `canLicense`. It binds
  `params.assetId` and `params.termsId` and records the current nonzero owner as
  licensor. For `NONE`, `params.party` is the nonzero initial licensee and the
  ignored token binding MUST be stored as zero. For `ERC721`, `params.party`
  MUST be stored as zero, the collection MUST be nonzero, and its bounded
  `ownerOf(tokenId)` result MUST be a nonzero initial licensee. The hook call is:

  ```solidity
  canLicense(
      params.assetId,
      params.termsId,
      initialLicensee,
      params.licenseParams,
      params.acceptanceHash
  )
  ```

  `initialLicensee` is the effective licensee above, never `msg.sender` merely
  because it submitted the grant.
- `acquireAgreement` uses the active attachment as standing owner
  authorization and requires no owner transaction or signature. It MUST create
  a registry-tracked agreement with
  `agreementTokenization == AgreementTokenization.NONE`,
  `party == msg.sender`, `agreementCollection == address(0)`, and
  `agreementTokenId == 0`. It binds the supplied `assetId` and `termsId`,
  requires an observable nonzero owner as licensor, and invokes
  `canLicense(assetId, termsId, msg.sender, licenseParams, acceptanceHash)`.

  Both paths MUST record:

  | Field | `createAgreement` | `acquireAgreement` |
  | --- | --- | --- |
  | `licensor` | current asset owner | current asset owner |
  | `createdBy` | `msg.sender` | `msg.sender` |
  | `initialLicensee` | effective `NONE` party or token holder | `msg.sender` |
  | `createdAt` | `uint64(block.timestamp)` | `uint64(block.timestamp)` |
  | `creationMode` | `GRANT` | `ACQUIRE` |
  | `licenseParamsHash` | `keccak256(params.licenseParams)` | `keccak256(licenseParams)` |
  | `acceptanceHash` | `params.acceptanceHash` | supplied `acceptanceHash` |
  | captured `revocable` | `terms.revocable` | `terms.revocable` |

  They use the same ID, indexing, event, and failure rules. The captured
  `transferable` and `revocable` values MUST equal the terms values. A later
  token burn or failed owner query makes an ERC-721 agreement inactive without deleting it.
- **Effective expiry.** At creation, the registry MUST convert the terms'
  absolute `expiry` and relative `duration` into one immutable absolute
  agreement expiry. Let `createdAt` be the agreement's creation timestamp and:

  ```solidity
  relativeExpiry = duration == 0 ? 0 : createdAt + duration;
  effectiveExpiry =
      expiry == 0 ? relativeExpiry
    : relativeExpiry == 0 ? expiry
    : min(expiry, relativeExpiry);
  ```

  Both zero means perpetual. If the addition exceeds `uint64`, creation MUST
  revert with `AgreementExpiryOverflow(termsId)`. If the
  resulting non-zero deadline is not later than `createdAt`, creation MUST
  revert with `TermsAlreadyExpired(termsId, effectiveExpiry)`;
  conforming registries MUST NOT create agreements that are already inactive.
  `agreementOf` and `LicenseAgreementCreated` expose `effectiveExpiry`, not the
  source `duration`. Later terms reuse computes a new deadline from that
  agreement's own `createdAt`, still capped by the absolute `expiry`.
- For `NONE`, `transferAgreement` requires the current licensee or its authorized
  delegate, captured `transferable == true`, and
  `canTransferAgreement(agreementId, currentLicensee, to)`. Hook approval alone never
  authorizes a caller. ERC-721 transfers occur outside the registry, which MUST
  NOT claim to enforce transferability or hook policy; restricted terms require
  a suitable token contract or `NONE`. A contrary token transfer does not
  deactivate the agreement, and activity views do not attest transfer
  compliance.
- `agreementOf` MUST return the all-zero ABI tuple for an unknown agreement:
  enum fields are `NONE` / `GRANT` and all other fields are zero. `getLicensee`
  MUST return `address(0)`, while
  `isAgreementActive` and `isActiveAgreementHolder` MUST return false for an
  unknown agreement. `isActiveAgreementHolder` MUST also return false when the
  agreement does not bind `assetId` or `party == address(0)`.
- `isAgreementActive` is true iff the agreement has a current licensee and is
  not expired, revoked, or frozen. All activity views MUST be non-reverting.
- **Attestation scope (normative).** `isActiveAgreementHolder`, `isAgreementActive`, and
  `activeAgreementsOf` attest **only to onchain agreement state in the queried
  registry**: that an agreement binding `P` to terms on `A` exists and is
  currently non-expired, non-revoked, and non-frozen. A `true` result MUST NOT be
  read as an assertion that the license is legally valid or enforceable in any
  jurisdiction, that the licensor held the rights it purported to grant, or that
  any off-chain condition (payment, KYC, acceptance of the legal text) was
  performed. Consumers MUST combine this state with applicable terms, trust,
  and off-chain checks.

### 8. Revocation and administrative paths

Canonical functions: `revokeAgreement`, `forceRevokeAgreement`, `freezeAsset`,
`unfreezeAsset`, `freezeAgreement`, `unfreezeAgreement`.

- **Ordinary revocation is owner-authorized and hook-gated.** The caller of
  `revokeAgreement(agreementId, reason)` MUST be the current administrative
  owner of the bound asset or its authorized delegate. This caller
  authorization is mandatory and independent of hook policy. If the agreement's
  captured `revocable` is false, `revokeAgreement` MUST revert, regardless of
  `canRevoke`; this bars ordinary owner revocation, not legal termination.
  Otherwise the function MUST
  invoke `canRevoke(agreementId, msg.sender, reason)` against current state and
  MUST revert with `HookDenied(denialReason)` when it returns `ok == false`.
  A permissive `canRevoke` result MUST NOT authorize an unrelated caller.
- **Force revocation is a separate break-glass path.**
  `forceRevokeAgreement(agreementId, reason)` MUST be restricted to the
  registry's documented administrative or governance authority and MUST NOT
  invoke or depend on `canRevoke` or `revocable`. It exists for exceptional intervention such
  as court orders, sanctions, or takedowns; ordinary owner/delegate revocation
  MUST use `revokeAgreement`.
- **Agreement revocation and agreement freeze affect activity.**
  `revokeAgreement`, `forceRevokeAgreement`, and `freezeAgreement` MUST make
  that agreement behave as nonexistent for `isActiveAgreementHolder`,
  `activeAgreementsOf`, and `isAgreementActive`, but MUST NOT delete its record.
  Both revocation paths are permanent; `unfreezeAgreement` reverses an
  agreement freeze.
- **Asset freeze affects future writes, not existing agreements.**
  `freezeAsset` MUST reject new `attachTerms`, `createAgreement`, and
  `acquireAgreement` calls for that asset. It MUST NOT revoke, freeze,
  deactivate, or otherwise alter an existing agreement; existing agreements
  remain active according to their own expiry, revocation, agreement-freeze,
  and current-licensee state. `unfreezeAsset` restores the blocked creation
  paths. Whether asset ownership transfer or terms detachment remains available
  while frozen is implementer policy.
- Authorization for administrative paths is implementer-defined;
  `freezeParty`/`recoverAsset` are deliberately out of core.

### 9. Derivation and composition

- A derivation attestation is OPTIONAL, set only at registration, immutable, and
  signed by its `issuer` using the EIP-712 digest and issuer-specific ECDSA or
  ERC-1271 verification in §1.3. The
  signed digest binds the intended registrant, complete registration payload,
  parents, and metadata. The core stores it and verifies the
  signature; it MUST NOT validate parent usage, walk graphs, or enforce parent
  terms. `canDerive` is the pre-flight.

### 10. Pre-flight hooks

Canonical functions: `canRegister`, `canUpdateMetadata`, `canTransferAsset`,
`canTransferAgreement`, `canAttachTerms`, `canDetachTerms`, `canLicense`,
`canRevoke`, `canDerive`.
All are `view`, permissionless, and return `(bool ok, bytes32 reason)` — denying
with `ok == false` and a `reason` code (never revert on policy; the write
reverts with `HookDenied(reason)`), and MUST NOT revert on unknown ids. Existence is normative; policy is not.

`canTransferAsset` governs administrative ownership transfers of `NONE` assets;
`canTransferAgreement` governs licensee transfers of `NONE` agreements. Each
hook's ID belongs to its named namespace, even if both record kinds share the
same ID bytes. Implementations MUST NOT infer the record kind by probing both
ID maps. Neither hook gates external ERC-721 transfers.

### 11. Events

Event emission is part of conformance, not merely an ABI declaration. Each
successful invocation listed below MUST emit exactly one instance of its
required event with the stated values. A reverted call emits no persistent
event because all of its logs are reverted with the transaction.

| Successful invocation | Required event |
| --- | --- |
| `register(params)` | `AssetRegistered(assetId, msg.sender, initialOwner, params.assetType, params.tokenization, params.metadataURI, params.contentHash)`, where `initialOwner` is `params.owner` for `NONE` or the holder resolved during registration for `ERC721`. |
| `register(params)` with a present derivation attestation | In addition to `AssetRegistered`, `DerivationAttestationRegistered(assetId, params.derivationAttestation.issuer, params.derivationAttestation.parents, params.derivationAttestation.metadata, params.derivationAttestation.registrationHash)`. No such event is emitted when the attestation has its canonical absent encoding. |
| `updateMetadata(assetId, newURI)` | `MetadataUpdated(assetId, msg.sender, oldURI, newURI, uint64(block.timestamp))`, including when `oldURI` equals `newURI`. |
| `transferOwnership(assetId, newOwner)` | `OwnershipTransferred(assetId, oldOwner, newOwner)`. This registry event applies only to `NONE`; an `ERC721` ownership transfer is observable from the bound token contract. |
| `addClaim(assetId, topicId, issuer, data, signature)` | `AssetClaimAdded(assetId, topicId, issuer, data)`, both for an initial claim and replacement of the current record. |
| `revokeClaim(assetId, topicId, issuer)` | `AssetClaimRevoked(assetId, topicId, issuer)`. |
| `setTrustedIssuer(topicId, issuer, trusted)` | `TrustedIssuerChanged(topicId, issuer, trusted, msg.sender)`, including removal of trust. |
| `registerTerms(terms)` that first stores `termsId` | `TermsRegistered(termsId, msg.sender, terms.termsType)`. Re-registration of an existing `termsId` MUST succeed without emitting `TermsRegistered` or any other event. |
| `attachTerms(assetId, termsId, attachmentParameters)` | `TermsAttached(assetId, termsId, attachmentParameters)`, both for an initial attachment and an in-place parameter replacement. |
| `detachTerms(assetId, termsId)` | `TermsDetached(assetId, termsId)`. |
| `createAgreement(params)` or `acquireAgreement(...)` | `LicenseAgreementCreated` containing the returned `agreementId`, exact asset and terms binding, complete stored `AgreementEvidence`, normalized tokenization-dependent party binding, and captured `expiry`, `transferable`, and `revocable` values. |
| `transferAgreement(agreementId, to)` | `LicenseAgreementTransferred(agreementId, oldLicensee, to)`. This registry event applies only to `NONE`; an `ERC721` agreement transfer is observable from the bound token contract. |
| `revokeAgreement(agreementId, reason)` or `forceRevokeAgreement(agreementId, reason)` | `LicenseAgreementRevoked(agreementId, msg.sender, reason)`. |
| `freezeAsset(assetId, reason)` | `AssetFrozen(assetId, msg.sender, reason)`. |
| `unfreezeAsset(assetId, reason)` | `AssetUnfrozen(assetId, msg.sender, reason)`. |
| `freezeAgreement(agreementId, reason)` | `LicenseAgreementFrozen(agreementId, msg.sender, reason)`. |
| `unfreezeAgreement(agreementId, reason)` | `LicenseAgreementUnfrozen(agreementId, msg.sender, reason)`. |

Indexed parameters MUST follow the per-event declarations in the complete
interface below. `LicenseAgreementCreated` carries the complete immutable
creation state so an indexer does not need historical transaction calldata to
reconstruct an agreement. Except for transfers of externally bound ERC-721
tokens, every successful core lifecycle mutation therefore has a mandatory
registry event.

### 12. ERC-165

`supportsInterface` MUST return `true` for the ERC-165 id, the
`IIPAssetRegistry` id `0x72117f80`, and the `ITermsRegistry` id `0x38c7f550`.

### 13. Canonical interface

The complete canonical interface follows as one dependency-free Solidity
compilation unit. It includes `IERC165` and every enum and struct referenced by
the core interfaces. The declarations repeat the normative data model from §1
so this block can be compiled without imports or material outside this ERC.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

enum AssetTokenization {
    NONE,
    ERC721
}

enum AgreementTokenization {
    NONE,
    ERC721
}

enum AgreementCreationMode {
    GRANT,
    ACQUIRE
}

enum Ternary {
    UNSPECIFIED,
    YES,
    NO
}

enum FeeModel {
    UNSPECIFIED,
    FREE,
    ONE_TIME,
    RECURRING,
    USAGE_BASED,
    EXTERNAL
}

struct Author {
    address author;
    uint256 shareNumerator;
}

struct ParentRef {
    uint256 chainId;
    address registry;
    bytes32 assetId;
}

struct DerivationAttestation {
    ParentRef[] parents;
    address issuer;
    bytes signature;
    bytes metadata;
    bytes32 registrationHash;
}

struct RightsSummary {
    Ternary commercialUse;
    Ternary derivativesAllowed;
    Ternary attributionRequired;
    FeeModel feeModel;
}

struct LicenseTerms {
    uint64 expiry;
    uint64 duration;
    bool transferable;
    bool revocable;
    bool sublicensable;
    bool exclusive;
    bytes32 jurisdictionScope;
    RightsSummary rights;
    string uri;
    bytes32 contentHash;
    bytes32 termsType;
    bytes rightsData;
}

struct RegistrationParams {
    bytes32 salt;
    address owner;
    Author[] authors;
    uint256 sharesDenominator;
    bytes32 assetType;
    AssetTokenization tokenization;
    address tokenCollection;
    uint256 tokenId;
    string metadataURI;
    bytes32 contentHash;
    DerivationAttestation derivationAttestation;
}

struct AgreementParams {
    bytes32 assetId;
    bytes32 termsId; // MUST be locally registered and attached
    address party;
    AgreementTokenization agreementTokenization;
    address agreementCollection;
    uint256 agreementTokenId;
    bytes licenseParams;
    bytes32 acceptanceHash;
}

struct AgreementEvidence {
    address licensor;
    address createdBy;
    address initialLicensee;
    uint64 createdAt;
    AgreementCreationMode creationMode;
    bytes32 licenseParamsHash;
    bytes32 acceptanceHash;
}

interface ITermsRegistry is IERC165 {
    error IncompleteLegalWrapper();

    /// @dev Re-registering an existing id returns it without state changes or events.
    function registerTerms(LicenseTerms calldata terms) external returns (bytes32 termsId);

    function termsExists(bytes32 termsId) external view returns (bool);
    function getTerms(bytes32 termsId) external view returns (LicenseTerms memory);
}
interface IIPAssetRegistry is IERC165, ITermsRegistry {
    error InvalidChainId();
    error MalformedDerivationAttestation();
    error HookDenied(bytes32 reason);
    error AgreementIdCollision(bytes32 agreementId);
    error TermsAlreadyExpired(bytes32 termsId, uint64 effectiveExpiry);
    error AgreementExpiryOverflow(bytes32 termsId);

    // =====================================================================
    // Identity & Registration
    // =====================================================================
    function register(RegistrationParams calldata params)
        external returns (bytes32 assetId);
    function assetExists(bytes32 assetId) external view returns (bool);
    function chainId() external view returns (uint256);

    // =====================================================================
    // Asset read paths
    // =====================================================================
    function ownerOf(bytes32 assetId) external view returns (address);
    function authorsOf(bytes32 assetId)
        external view returns (Author[] memory authors, uint256 sharesDenominator);
    function tokenizationOf(bytes32 assetId)
        external view returns (AssetTokenization tokenization, address tokenCollection, uint256 tokenId);
    function assetTypeOf(bytes32 assetId) external view returns (bytes32);
    function metadataOf(bytes32 assetId)
        external view returns (string memory metadataURI, bytes32 contentHash);
    function derivationAttestationOf(bytes32 assetId)
        external view returns (DerivationAttestation memory);
    function attachedTermsOf(bytes32 assetId)
        external view returns (
            bytes32[] memory termsIds,
            bytes[] memory attachmentParameters
        );
    function agreementCountOf(bytes32 assetId) external view returns (uint256);
    function agreementAtIndex(bytes32 assetId, uint256 index)
        external view returns (bytes32 agreementId);
    function activeAgreementsOf(bytes32 assetId, uint256 cursor, uint256 limit)
        external view returns (bytes32[] memory agreementIds, uint256 nextCursor);

    // =====================================================================
    // Asset mutation
    // =====================================================================
    function updateMetadata(bytes32 assetId, string calldata newURI) external;

    function transferOwnership(bytes32 assetId, address newOwner) external;

    // =====================================================================
    // Asset claims
    // =====================================================================
    function addClaim(
        bytes32 assetId,
        bytes32 topicId,
        address issuer,
        bytes calldata data,
        bytes calldata signature
    ) external;
    function revokeClaim(bytes32 assetId, bytes32 topicId, address issuer) external;
    function getClaim(bytes32 assetId, bytes32 topicId, address issuer)
        external view returns (
            bytes memory data,
            bytes memory signature,
            uint64 timestamp,
            bool revoked
        );
    function getClaimIssuers(bytes32 assetId, bytes32 topicId)
        external view returns (address[] memory);
    function setTrustedIssuer(bytes32 topicId, address issuer, bool trusted) external;
    function isTrustedIssuer(bytes32 topicId, address issuer)
        external view returns (bool);

    // =====================================================================
    // License terms  (inherited from ITermsRegistry)
    //
    // `registerTerms`, `termsExists` and `getTerms` are declared by
    // `ITermsRegistry` and inherited here: every asset registry stores the
    // terms used by its assets and agreements locally.
    // =====================================================================

    // =====================================================================
    // Terms attachment
    // =====================================================================
    function attachTerms(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata attachmentParameters
    ) external;

    function detachTerms(bytes32 assetId, bytes32 termsId) external;

    // =====================================================================
    // License agreements
    // =====================================================================
    function createAgreement(AgreementParams calldata params)
        external returns (bytes32 agreementId);
    function acquireAgreement(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata licenseParams,
        bytes32 acceptanceHash
    ) external returns (bytes32 agreementId);
    function transferAgreement(bytes32 agreementId, address to) external;
    function agreementOf(bytes32 agreementId)
        external view returns (
            bytes32 assetId,
            bytes32 termsId,
            address party,
            AgreementTokenization agreementTokenization,
            address agreementCollection,
            uint256 agreementTokenId,
            AgreementEvidence memory evidence,
            uint64 expiry,
            bool transferable,
            bool revocable
        );
    function getLicensee(bytes32 agreementId) external view returns (address);

    // =====================================================================
    // Agreement activity
    // =====================================================================
    function activeAgreementsOf(
        bytes32 assetId,
        address party,
        uint256 cursor,
        uint256 limit
    ) external view returns (bytes32[] memory agreementIds, uint256 nextCursor);
    function isActiveAgreementHolder(bytes32 agreementId, bytes32 assetId, address party)
        external view returns (bool);
    function isAgreementActive(bytes32 agreementId) external view returns (bool);

    // =====================================================================
    // Revocation
    // =====================================================================
    function revokeAgreement(bytes32 agreementId, bytes32 reason) external;
    function forceRevokeAgreement(bytes32 agreementId, bytes32 reason) external;

    // =====================================================================
    // Pre-flight hooks
    //
    // Every hook is `view`, permissionless to call, and does not revert on
    // unknown ids. Each returns `(bool ok, bytes32 reason)`: `ok == false`
    // denies; `reason` is a machine-readable denial code (bytes32(0) when
    // `ok`). The matching write reverts with `HookDenied(reason)`.
    // Default-permissive (`return (true, bytes32(0))`) is allowed.
    // =====================================================================

    function canRegister(address registrant, RegistrationParams calldata params)
        external view returns (bool ok, bytes32 reason);

    function canUpdateMetadata(bytes32 assetId, string calldata newURI)
        external view returns (bool ok, bytes32 reason);
    function canTransferAsset(bytes32 assetId, address from, address to)
        external view returns (bool ok, bytes32 reason);

    function canTransferAgreement(bytes32 agreementId, address from, address to)
        external view returns (bool ok, bytes32 reason);

    function canAttachTerms(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata attachmentParameters
    ) external view returns (bool ok, bytes32 reason);

    function canDetachTerms(bytes32 assetId, bytes32 termsId)
        external view returns (bool ok, bytes32 reason);

    function canLicense(
        bytes32 assetId,
        bytes32 termsId,
        address acquirer,
        bytes calldata licenseParams,
        bytes32 acceptanceHash
    ) external view returns (bool ok, bytes32 reason);

    function canRevoke(bytes32 agreementId, address caller, bytes32 reason)
        external view returns (bool ok, bytes32 denialReason);

    function canDerive(bytes32 parentAssetId, address deriver)
        external view returns (bool ok, bytes32 reason);

    // =====================================================================
    // Administrative paths
    //
    // Break-glass operations. Authorization is implementer-controlled and
    // NOT hook-gated. `freezeParty` and `recoverAsset` are deliberately
    // NOT in the core.
    // =====================================================================
    function freezeAsset(bytes32 assetId, bytes32 reason) external;

    function unfreezeAsset(bytes32 assetId, bytes32 reason) external;
    function freezeAgreement(bytes32 agreementId, bytes32 reason) external;

    function unfreezeAgreement(bytes32 agreementId, bytes32 reason) external;

    // =====================================================================
    // ERC-165 support
    //
    // `supportsInterface(bytes4)` is inherited from `IERC165`. A conforming
    // registry MUST return true for the ERC-165 interface id, the
    // `IIPAssetRegistry` interface id, and the inherited `ITermsRegistry`
    // interface id.
    // =====================================================================

    // (supportsInterface inherited from IERC165)

    // =====================================================================
    // Events
    //
    // Indexing rule: identifiers (assetId, agreementId, termsId, topicId)
    // are `indexed` whenever they appear. Role addresses are `indexed`
    // when there is room. Free-form payload (URIs, hashes, struct arrays,
    // enums, opaque reason codes) is NOT `indexed`.
    // =====================================================================

    // -- Asset lifecycle --------------------------------------------------

    event AssetRegistered(
        bytes32 indexed assetId,
        address indexed registrant,
        address indexed owner,
        bytes32 assetType,
        AssetTokenization tokenization,
        string metadataURI,
        bytes32 contentHash
    );
    event MetadataUpdated(
        bytes32 indexed assetId,
        address indexed updatedBy,
        string  oldURI,
        string  newURI,
        uint64  timestamp
    );
    event OwnershipTransferred(
        bytes32 indexed assetId,
        address indexed from,
        address indexed to
    );

    event AssetFrozen(bytes32 indexed assetId, address indexed by, bytes32 reason);
    event AssetUnfrozen(bytes32 indexed assetId, address indexed by, bytes32 reason);

    event DerivationAttestationRegistered(
        bytes32 indexed assetId,
        address indexed issuer,
        ParentRef[] parents,
        bytes metadata,
        bytes32 registrationHash
    );

    // -- Asset claims -----------------------------------------------------

    event AssetClaimAdded(
        bytes32 indexed assetId,
        bytes32 indexed topicId,
        address indexed issuer,
        bytes data
    );

    event AssetClaimRevoked(
        bytes32 indexed assetId,
        bytes32 indexed topicId,
        address indexed issuer
    );

    event TrustedIssuerChanged(
        bytes32 indexed topicId,
        address indexed issuer,
        bool trusted,
        address indexed changedBy
    );

    // -- Terms lifecycle --------------------------------------------------

    event TermsRegistered(
        bytes32 indexed termsId,
        address indexed registrant,
        bytes32 indexed termsType
    );

    event TermsAttached(
        bytes32 indexed assetId,
        bytes32 indexed termsId,
        bytes attachmentParameters
    );

    event TermsDetached(
        bytes32 indexed assetId,
        bytes32 indexed termsId
    );

    // -- Agreement lifecycle ---------------------------------------------

    event LicenseAgreementCreated(
        bytes32 indexed agreementId,
        bytes32 indexed assetId,
        bytes32 indexed termsId,
        AgreementEvidence evidence,
        AgreementTokenization agreementTokenization,
        address agreementCollection,
        uint256 agreementTokenId,
        uint64 expiry,
        bool transferable,
        bool revocable
    );
    event LicenseAgreementTransferred(
        bytes32 indexed agreementId,
        address indexed from,
        address indexed to
    );

    event LicenseAgreementRevoked(
        bytes32 indexed agreementId,
        address indexed by,
        bytes32 reason
    );

    event LicenseAgreementFrozen(
        bytes32 indexed agreementId,
        address indexed by,
        bytes32 reason
    );

    event LicenseAgreementUnfrozen(
        bytes32 indexed agreementId,
        address indexed by,
        bytes32 reason
    );
}
```

## Rationale

### Integrated licensing lifecycle

Assets, reusable terms, and agreements are separate records because they answer
different questions: what the work is, what conditions are offered, and who
holds a grant. They are standardized together because attachment authorization,
agreement creation, activity, and cross-record identity must compose
consistently. Splitting this lifecycle into unrelated interfaces would leave
these semantics to application-specific integration.

The core includes mutable asset claims because policy facts and external
identifiers change independently of structural authorship and provenance.
Schema discovery, identifier resolution, identity adapters, payment, royalties,
graph traversal, and dispute resolution are left to separate ERC extensions. This is
the principal scope trade-off: the core is broader than a token interface, but
narrower than a complete rights-management platform.

### Independent registries and global references

No canonical registry is selected. Independent deployments can share interfaces
while applying different governance, eligibility, and trust policies. Consumers
therefore choose which registries and issuers to trust; interface conformance
does not make a record authoritative.

The `(chainId, registry, id)` namespace identifies records without a central
resolver. A token-only identifier was rejected because registry-tracked assets,
terms, and agreements may have no token. The dedicated prefixes also distinguish
record kinds that could otherwise contain identical identifier bytes. References
identify records across systems but do not verify remote state or resolve
competing registrations.

### Registry-tracked and token-bound holders

The closed `{NONE, ERC721}` modes support both registry-tracked records and
existing single-holder tokens. An open token-kind field was rejected because the
registry could not safely interpret ownership without standardized semantics.
[ERC-1155](./eip-1155.md) balances, fungible shares, and other multi-holder
arrangements do not provide the single current owner or licensee assumed by the
core lifecycle and belong in extensions.

For ERC-721-bound records, the registry reads the live token holder instead of
caching ownership. Caching would become stale when tokens transfer without
notifying the registry. The trade-off is that registry hooks cannot constrain
external token transfers; deployments requiring registry-enforced transfer
policy use `NONE` or a cooperating token contract.

### Stable identity, authorship, and provenance

Caller-chosen salts make asset identifiers available before registration, which
allows derivation signatures to bind the intended asset and complete
registration payload. Counter-based identifiers cannot provide that property,
while content-hash-only identifiers create a single squattable registration
slot. Binding the registrant also prevents another caller who observes a
pending transaction from claiming its precomputed id with the same salt.

Authorship and exact fractional shares are immutable because downstream users
need a stable declared provenance record. Fixed basis points were rejected
because they cannot represent common fractions exactly; ERC-2981-style helpers
can derive rounded values for compatible consumers. Corrections use replacement
records and claims rather than rewriting history.

A derivation attestation is likewise fixed at registration and separate from
mutable claims. It provides attributable evidence of declared parentage without
requiring the registry to determine whether the declaration is factually or
legally valid.

### Layered and immutable terms

Prose-only terms were rejected because automated consumers could not compare
basic rights without retrieving and interpreting a legal document. A single
exhaustive rights structure was also rejected because licensing dimensions vary
across creative, software, data, patent, and other domains.

The selected model combines a fixed frame, a small mandatory rights summary, an
optional exact-byte legal anchor, and content-addressed domain data. This gives
all consumers a comparison floor while permitting domain-specific schemas.
Terms are immutable and stored locally so agreement behavior does not depend on
a mutable or unavailable external registry. Identical terms can still be
mirrored exactly under the same content-derived identifier.

Attaching terms publishes a standing offer but grants no rights. Separating the
offer from each agreement permits self-service acquisition without requiring an
owner transaction for every license while preserving owner control over which
offers remain available.

### Agreement identity and discovery

Grant and acquisition are separate operations because they represent different
authorization and evidence flows. Every agreement has an initial licensee;
unassigned agreement inventory was rejected because it would add a separate
assignment lifecycle and has no coherent meaning for bearer-token-bound
agreements.

Agreement identifiers and per-asset indices are append-only so expiry,
revocation, transfer, or freezing cannot erase historical identity. A caller
that already knows an agreement identifier can verify it in constant work.
Callers without that witness use bounded pagination. Maintaining an
always-current party index was rejected because ERC-721-bound agreements can
transfer outside the registry. Pagination bounds individual calls, although
total discovery work and storage still grow with history.

### Policy and legal boundaries

Pre-flight hooks standardize policy questions without making policy approval a
substitute for caller authorization. This permits identity, jurisdiction,
payment, and governance policies to vary by deployment while preserving common
write semantics. Exceptional freeze and force-revocation effects are
standardized, but their protected authorization model is left to each deployment
because no single recovery or legal-process model is universally appropriate.

Content hashes, signatures, claims, and agreement state provide verifiable
evidence, not legal adjudication. They do not establish authorship, underlying
rights, payment, permitted use, or enforceability.
[ERC-8004](./eip-8004.md) identity and x402 payment mechanisms may compose
through claims, hooks, and opaque parameters, but neither is required by the
core.

## Backwards Compatibility

This ERC is purely additive: it introduces new interfaces and changes no
existing standard. It requires ERC-165, treats ERC-721 as a first-class binding,
and is compatible-by-exclusion with [ERC-1155](./eip-1155.md)/
[ERC-6551](./eip-6551.md)/[ERC-3525](./eip-3525.md)/soulbound tokens via `NONE`.
It uses an ERC-3643-inspired claim shape, exposes ERC-2981-friendly author
shares, remains independent of ERC-5218 and ERC-5554, uses EIP-712 derivation
signatures, and may compose with—but does not depend on—ERC-8004 or x402.

## Test Cases

The deterministic terms-encoding vectors are included in §6, and the canonical
generic-schema hash preimage is included in §1.6. The reference implementation's
executable test suite also covers registration in both tokenization modes, id
derivation, bounded ERC-721 holder reads, authorization independent of hooks,
terms attachment, both agreement-creation paths, effective expiry,
transfer/revoke/freeze behavior, examined-record pagination, derivation
signatures, and ERC-165 support.

## Reference Implementation

The canonical interfaces are included in the Specification and, as Solidity
source files, in [`assets/erc-XXXX`](../assets/erc-XXXX/). A non-normative
reference implementation with its test suite will be published later. 
Neither defines requirements beyond this document; where they differ, this document prevails.

## Security Considerations

### Derivation signatures and provenance

EIP-712 provides domain separation but does not by itself prevent replay. The
derivation digest therefore binds the intended registrant, every registration
field, `chainId`, registry, `assetId`, parents, and metadata using §1.3's exact
encoding. Implementations must reject a registration-hash mismatch and an
existing `assetId`. A copied pending attestation cannot authorize altered asset
data or a different transaction sender.
Including the registering caller in `assetId` also prevents another caller
from taking the intended id by front-running with the same salt.
ERC-1271 validity is checked only at registration: a contract issuer may later
change its signing policy or cease to approve the signature. The bounded
`staticcall` prevents a hostile issuer from exhausting an unbounded amount of
gas or returning an oversized result to the registry.

A valid signature proves only that the issuer signed the attestation. It does
not prove that the issuer is trustworthy, that the declared parents were used,
or that the derivation was authorized. Consumers must apply their own issuer
trust, parent-license, and content-forensics checks.

### External calls and reentrancy

A delegated ERC-721 `ownerOf` call may revert, return malformed data, or consume
all forwarded gas. Implementations must use a gas-capped, success-checked read
and treat failure as no current holder rather than allowing an untrusted token
to break registry views or hooks. Token collections are untrusted contracts.

Implementations or extensions that add state-changing external calls must
apply checks-effects-interactions, an appropriate reentrancy guard, or both.

### Hooks and administrative authorization

`revocable == false` prevents ordinary owner revocation, not authorized force
revocation, agreement freeze, expiry, or legal termination. Consumers must
assess the registry's administrative authority independently of this flag.

A prior `canX` result is only a pre-flight result. State may change before the
transaction executes, so the corresponding write must evaluate and enforce the
current policy. A default-permissive hook does not demonstrate that any policy
was applied.

`freezeAsset`, `freezeAgreement`, and `forceRevokeAgreement` are not hook-gated.
Implementations must protect these administrative paths according to their
declared authorization model. Integrators should assess that model before
relying on a registry.

### Registry trust and verification scope

ERC-165 conformance proves only that a contract exposes an interface. It does
not establish that the registry, its issuers, or its records are honest.

`isActiveAgreementHolder`, `isAgreementActive`, and related views report only the current
onchain agreement state in the queried registry. They do not establish legal
validity, the licensor's underlying rights, permission for a contemplated use or
territory, payment, KYC, or acceptance of off-chain terms. Consumers must inspect
each active agreement's own terms. Cross-chain references are identifiers for off-chain
resolution and must not be treated as onchain verification of remote state.

### Denial of service and pagination

Callers of `activeAgreementsOf` must advance `nextCursor` until it equals
`agreementCountOf(assetId)`. Its `limit` bounds records examined, not records
returned.

Other array-returning views are not size-bounded by this ERC. Implementations
expecting large collections should provide pagination, and onchain consumers
should avoid depending on unbounded results.

### Public data and confidentiality

The complete `LicenseTerms` tuple is public through `registerTerms` transaction
calldata and `getTerms`, including the universal frame, rights summary,
`termsType`, and `rightsData`. "Opaque to the core" does not mean confidential.
Sensitive values must not be placed directly in those fields with an expectation
of secrecy.

Supplementary legal, pricing, or personal data may be kept in encrypted or
access-controlled off-chain content referenced by the public `uri` and committed
to by `contentHash`. This does not conceal machine-readable values already in
`LicenseTerms`. Private domain-specific values require a schema-defined
commitment or ciphertext in `rightsData` and additional off-chain or proof-aware
mechanisms. Standardizing those mechanisms is future work for ERC extensions;
the universal frame and mandatory rights summary remain public.

An asset `contentHash` commits to the exact original-work representation bytes,
not necessarily the document returned by `metadataURI`. Consumers resolve those
bytes according to the metadata and verify `keccak256(originalWorkBytes)`.
For a legal wrapper, consumers verify
`keccak256(documentBytes) == LicenseTerms.contentHash`. Neither check permits
text normalization, reserialization, or format conversion before hashing.

### Future ERC extension considerations

Future ERC extensions for settlement based on off-chain facts would inherit the
trust and manipulation risks of their oracle. This ERC provides no oracle or
dispute-resolution guarantee.

The core does not collect transfer or resale fees. Such fees are enforceable
only when the transfer or settlement path enforces them.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
