// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IPAssetTypes
/// @notice Shared types, structs, enums and well-known constants used by the
///         IPAssetRegistry interface and its consumers.
///
/// File-level declarations (Solidity ≥ 0.8.8) so types and constants can be
/// imported and reused without going through a wrapping library.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// @notice Tokenization mode of an IP Asset.
/// @dev    Intentionally closed: ERC-1155 and ERC-6551 are deliberately not
///         enumerated. Assets bound to other token
///         standards register with `NONE`.
enum AssetTokenization {
    NONE,
    ERC721
}

/// @notice Tokenization mode of a LicenseAgreement.
///         Symmetric with the IP-asset `AssetTokenization` enum:
///         a license agreement is either registry-tracked (`NONE`, single
///         stored licensee) or bound to a single ERC-721 token (licensee =
///         token holder). ERC-1155 is intentionally NOT supported: multi-holder
///         editions break per-seat revocation and per-agreement activity,
///         and have no clean unassigned state.
enum AgreementTokenization {
    NONE,
    ERC721
}

/// @notice How a LicenseAgreement was created.
enum AgreementCreationMode {
    GRANT,
    ACQUIRE
}

// ---------------------------------------------------------------------------
// Authorship
// ---------------------------------------------------------------------------

/// @notice One author of an IP Asset together with their share.
/// @dev    Shares are expressed as integer numerators over a per-asset
///         `sharesDenominator`. `author` MAY be `address(0)` for
///         anonymous authorship.
struct Author {
    address author;
    uint256 shareNumerator;
}

// ---------------------------------------------------------------------------
// Derivation
// ---------------------------------------------------------------------------

/// @notice Reference to a parent IP Asset, identifiable across registries and
///         chains via the canonical (chainId, registry, assetId) tuple.
struct ParentRef {
    uint256 chainId;
    address registry;
    bytes32 assetId;
}

/// @notice Signed attestation about the provenance of an IP Asset.
/// @dev    Set at registration only and immutable thereafter.
///         `parents` MAY be empty (explicit "original work" attestation).
///         Absence has one canonical encoding: `issuer == address(0)`, empty
///         `parents`, `signature`, and `metadata`, and zero `registrationHash`.
///         A zero issuer with any other nonempty field is invalid.
///         `registrationHash` commits to the intended registrant and complete
///         registration payload. `signature` MUST use the exact EIP-712
///         encoding in the ERC's Specification §1.3 (Derivation).
///         NOTE: this is a dedicated structural field on the asset record,
///         NOT a generic asset-claim. The name avoids the word
///         "Claim" deliberately to prevent confusion with the claims
///         registry interface.
struct DerivationAttestation {
    ParentRef[] parents;
    address     issuer;
    bytes       signature;
    bytes       metadata;
    bytes32     registrationHash;
}

// ---------------------------------------------------------------------------
// License terms
// ---------------------------------------------------------------------------

/// @notice Tri-state used by the mandatory rights summary. `UNSPECIFIED`
///         means the terms make no machine-readable assertion on this dimension
///         (the domain `rightsData` or the legal text governs); `YES` / `NO`
///         are affirmative, cross-catalog-comparable assertions.
enum Ternary {
    UNSPECIFIED,
    YES,
    NO
}

/// @notice Coarse, amount-free fee-model classifier. It carries NO
///         amounts, currencies, tokens, or payment logic — those belong to the
///         payment extension. It classifies only how a fee (if any) is
///         structured, so agents can filter and cost-optimize offers.
enum FeeModel {
    UNSPECIFIED,  // no assertion
    FREE,         // no fee to license
    ONE_TIME,     // single up-front fee
    RECURRING,    // periodic / subscription fee
    USAGE_BASED,  // metered (per-play, per-call, per-seat, …)
    EXTERNAL      // negotiated / settled out of band
}

/// @notice Mandatory rights summary carried by EVERY `LicenseTerms` regardless
///         of `termsType`. It gives agents a guaranteed, comparable
///         vocabulary across catalogs. The domain `rightsData` MAY refine these
///         dimensions but MUST NOT contradict them.
struct RightsSummary {
    Ternary  commercialUse;       // YES = commercial use permitted
    Ternary  derivativesAllowed;  // YES = derivative works permitted
    Ternary  attributionRequired; // YES = attribution required
    FeeModel feeModel;            // coarse, amount-free (see FeeModel)
}

/// @notice The terms under which an IP Asset may be used.
/// @dev    Four layers:
///         1. Universal frame — agreement-level properties (expiry through
///            `jurisdictionScope`) invariant across asset types and
///            jurisdictions.
///         2. Mandatory rights summary — `rights`, a small always-present,
///            cross-`termsType`-comparable vocabulary.
///         3. Authoritative legal text — `(uri, contentHash)`.
///         4. Domain-specific rights — `(termsType, rightsData)` where
///            `termsType` is a content-addressed schema id, or `bytes32(0)`
///            when the summary is the complete machine-readable expression.
///         All layers MUST be semantically consistent. Legal text and
///         `rightsData` do not override machine-readable assertions.
struct LicenseTerms {
    // 1. Universal frame
    uint64  expiry;            // absolute unix-seconds hard deadline; 0 = none
    uint64  duration;          // seconds from agreement creation; 0 = none
    bool    transferable;
    bool    revocable;         // permits ordinary owner revocation; force revocation remains possible
    bool    sublicensable;     // recorded assertion only; no core sublicense action
    bool    exclusive;
    bytes32 jurisdictionScope;

    // 2. Mandatory rights summary
    RightsSummary rights;

    // 3. Authoritative legal text
    string  uri;
    bytes32 contentHash;       // keccak256 of exact canonical legal-document bytes

    // 4. Domain-specific rights
    bytes32 termsType;         // bytes32(0) = no domain schema; summary suffices
    bytes   rightsData;
}

// ---------------------------------------------------------------------------
// Registration parameter bundles
// ---------------------------------------------------------------------------

/// @notice Parameters to `register`. Bundled to keep call signatures readable.
struct RegistrationParams {
    bytes32           salt;              // assetId = keccak256(abi.encode(chainId, registry, registrant, salt)); registrant = msg.sender
    address           owner;             // NONE: non-zero owner; ERC721: MUST be zero
    Author[]          authors;
    uint256           sharesDenominator; // MUST be > 0 when authors is non-empty
    bytes32           assetType;
    AssetTokenization tokenization;
    address           tokenCollection;   // ERC721: non-zero contract; ignored for NONE
    uint256           tokenId;           // ignored when tokenization == NONE
    string            metadataURI;
    bytes32           contentHash;       // keccak256 of exact original-work representation bytes
    DerivationAttestation derivationAttestation; // all fields empty/zero to omit
}

/// @notice Parameters to `createAgreement`. The owner of an asset (or a party
///         the implementation authorizes on the owner's behalf under its own
///         delegation policy — the core defines no operator role) typically
///         calls this to grant a license to a licensee. A license always has a
///         licensee at creation: for `NONE` it is `party`; for `ERC721` it is
///         the holder of the non-zero bound collection, which MUST resolve to
///         a non-zero address at creation.
struct AgreementParams {
    bytes32                assetId;
    bytes32                termsId;                // MUST be locally registered and attached
    address                party;                  // NONE: licensee, MUST be non-zero. ERC721: ignored (licensee = token holder)
    AgreementTokenization  agreementTokenization;
    address                agreementCollection;    // ERC721: MUST be non-zero; ignored for NONE
    uint256                agreementTokenId;       // ignored when agreementTokenization == NONE
    bytes                  licenseParams;          // opaque to the core; forwarded to the `canLicense` hook
    bytes32                acceptanceHash;         // optional commitment to acceptance evidence; bytes32(0) = absent
}

/// @notice Immutable evidence captured when a LicenseAgreement is created.
/// @dev `licensor` is the asset's administrative owner at creation, not an
///      assertion that the address held the underlying legal rights.
///      `acceptanceHash` is a commitment only; its evidentiary meaning depends
///      on the terms and the `canLicense` policy that validated acquisition.
struct AgreementEvidence {
    address               licensor;
    address               createdBy;
    address               initialLicensee;
    uint64                createdAt;
    AgreementCreationMode creationMode;
    bytes32               licenseParamsHash;
    bytes32               acceptanceHash;
}

// ---------------------------------------------------------------------------
// Well-known constants
// ---------------------------------------------------------------------------

/// @dev Well-known asset type identifiers. Implementers MAY use any
///      other `bytes32` value, conventionally `keccak256(<descriptive
///      lowercase ASCII string>)`.
bytes32 constant ASSET_TYPE_AUDIO     = keccak256("audio");
bytes32 constant ASSET_TYPE_VIDEO     = keccak256("video");
bytes32 constant ASSET_TYPE_IMAGE     = keccak256("image");
bytes32 constant ASSET_TYPE_TEXT      = keccak256("text");
bytes32 constant ASSET_TYPE_SOFTWARE  = keccak256("software");
bytes32 constant ASSET_TYPE_DATASET   = keccak256("dataset");
bytes32 constant ASSET_TYPE_MODEL     = keccak256("model");
bytes32 constant ASSET_TYPE_PATENT    = keccak256("patent");
bytes32 constant ASSET_TYPE_ALGORITHM = keccak256("algorithm");

/// @dev Well-known jurisdiction scope identifiers.
///      Per-jurisdiction codes follow ISO 3166-1 alpha-2 by convention
///      (e.g. keccak256("JP"), keccak256("US")).
bytes32 constant JURISDICTION_WORLDWIDE = keccak256("worldwide");

/// @dev The only well-known terms-type schema id shipped by this ERC.
///      keccak256 of the exact UTF-8 canonical JSON line in the ERC's
///      Specification §1.6, excluding its Markdown fence and line terminator.
///      `test/SchemaHash.t.sol` reproduces the hash from that inline definition.
///      A schema revision requires a new termsType; other standardized domain
///      schemas are future ERC extension work, not part of the core.
bytes32 constant TERMS_TYPE_GENERIC_V1 =
    0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa;
