// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {
    AssetTokenization,
    AgreementTokenization,
    AgreementEvidence,
    Author,
    ParentRef,
    DerivationAttestation,
    RegistrationParams,
    AgreementParams
} from "./IPAssetTypes.sol";
import {IERC165} from "./IERC165.sol";
import {ITermsRegistry} from "./ITermsRegistry.sol";

/// @title IIPAssetRegistry
/// @notice Canonical interface for an ERC IP-licensing registry.
///
/// Exposes the ERC's core registry operations in a single Solidity surface.
/// Organised into the following sections;
/// see the banner comments for navigation:
///
///   1.  Identity & Registration
///   2.  Asset read paths
///   3.  Asset mutation
///   4.  Asset claims
///   5.  License terms
///   6.  Terms attachment
///   7.  License agreements
///   8.  Agreement activity
///   9.  Revocation
///   10. Pre-flight hooks
///   11. Administrative paths
///   12. ERC-165
///   13. Events
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

    /// @notice Register an IP asset and return its identifier.
    /// @dev For `NONE`, `params.owner` MUST be non-zero and token-binding fields
    ///      are ignored. For `ERC721`, `params.owner` MUST be zero, collection
    ///      MUST be a non-zero contract, and bounded canonical `ownerOf(tokenId)`
    ///      MUST resolve a non-zero initial owner, which `AssetRegistered` emits.
    function register(RegistrationParams calldata params)
        external returns (bytes32 assetId);

    /// @notice Check whether an asset is registered.
    /// @dev Returns false for unknown assets.
    function assetExists(bytes32 assetId) external view returns (bool);

    /// @notice The nonzero EIP-155 chain id captured at deployment.
    /// @dev    MUST remain unchanged even if `block.chainid` changes after
    ///         deployment.
    function chainId() external view returns (uint256);

    // =====================================================================
    // Asset read paths
    // =====================================================================

    /// @notice The administrative owner of an asset.
    /// @dev    For `NONE` returns the stored owner; for `ERC721` delegates to
    ///         `IERC721(collection).ownerOf(tokenId)` with no caching. The
    ///         delegated call MUST use a 100,000-gas stipend and accept
    ///         exactly one canonical 32-byte address word:
    ///         a reverting, over-budget, or malformed call yields `address(0)`
    ///         (ownerless), never a propagated failure. Returns
    ///         `address(0)` for unknown assets.
    function ownerOf(bytes32 assetId) external view returns (address);

    /// @notice Return the declared authors and share denominator of an asset.
    /// @dev Unknown assets return an empty array and denominator 0.
    function authorsOf(bytes32 assetId)
        external view returns (Author[] memory authors, uint256 sharesDenominator);

    /// @notice Return an asset's tokenization mode and token binding.
    /// @dev Unknown assets return `(NONE, address(0), 0)`.
    function tokenizationOf(bytes32 assetId)
        external view returns (AssetTokenization tokenization, address tokenCollection, uint256 tokenId);

    /// @notice Return an asset's type identifier.
    /// @dev Unknown assets return `bytes32(0)`.
    function assetTypeOf(bytes32 assetId) external view returns (bytes32);

    /// @notice Return an asset's metadata URI and original-work content hash.
    /// @dev Unknown assets return `("", bytes32(0))`.
    function metadataOf(bytes32 assetId)
        external view returns (string memory metadataURI, bytes32 contentHash);

    /// @notice Provenance attestation for the asset.
    /// @dev    Dedicated structural field, NOT a generic asset-claim.
    ///         Unknown assets return the zero attestation: empty arrays/bytes,
    ///         `address(0)`, and `bytes32(0)`.
    function derivationAttestationOf(bytes32 assetId)
        external view returns (DerivationAttestation memory);

    /// @notice Return an asset's attached terms and their parameters.
    /// @dev Unknown assets return two empty arrays.
    function attachedTermsOf(bytes32 assetId)
        external view returns (
            bytes32[] memory termsIds,
            bytes[] memory attachmentParameters
        );

    /// @notice Total number of license agreements ever created on the asset.
    /// @dev    The per-asset agreement set is append-only: revoked, expired,
    ///         and frozen agreements are retained, so indices in
    ///         `[0, agreementCountOf(assetId))` are stable and safe to
    ///         paginate over. Returns 0 for unknown assets (MUST NOT revert).
    function agreementCountOf(bytes32 assetId) external view returns (uint256);

    /// @notice The agreement id at a stable index of the asset's append-only
    ///         agreement set.
    /// @dev    Returns `bytes32(0)` without reverting when the asset is unknown
    ///         or `index >= agreementCountOf(assetId)`.
    function agreementAtIndex(bytes32 assetId, uint256 index)
        external view returns (bytes32 agreementId);

    /// @notice Paginated enumeration of the asset's active
    ///         agreements — those that have a licensee and are not
    ///         expired, revoked, or frozen.
    /// @dev    Examines up to `limit` agreements starting at stable index
    ///         `cursor` and returns the active subset together with
    ///         `nextCursor`, the index at which a caller resumes. `limit`
    ///         bounds the number of records *examined* (not the number
    ///         returned), so gas is bounded regardless of how many are active;
    ///         a returned page MAY therefore hold fewer than `limit` ids (or
    ///         none) while agreements still remain. Callers iterate until
    ///         `nextCursor == agreementCountOf(assetId)`, which signals the
    ///         enumeration is complete. When `cursor <= agreementCountOf(assetId)`,
    ///         a zero `limit` returns the input `cursor` without examining
    ///         records. MUST NOT revert on unknown assets or out-of-range cursors
    ///         (returns an empty page and
    ///         `nextCursor == agreementCountOf(assetId)`).
    function activeAgreementsOf(bytes32 assetId, uint256 cursor, uint256 limit)
        external view returns (bytes32[] memory agreementIds, uint256 nextCursor);

    // =====================================================================
    // Asset mutation
    // =====================================================================

    /// @notice Update the asset's off-chain metadata pointer.
    /// @dev    Only the mutable `metadataURI` moves. `contentHash` is a
    ///         registration-time anchor of the original work and is immutable;
    ///         it is therefore NOT a parameter here and is reported in
    ///         the `AssetRegistered` event.
    function updateMetadata(bytes32 assetId, string calldata newURI) external;

    /// @notice Transfer administrative ownership of a registry-tracked asset.
    /// @dev Transfers administrative ownership of a `NONE` asset. Requires the
    ///      current owner or an explicitly authorized delegate, independently
    ///      of `canTransferAsset(assetId, currentOwner, newOwner)`.
    ///      The write MUST also enforce that hook; ERC721 assets transfer via
    ///      the bound token contract instead.
    function transferOwnership(bytes32 assetId, address newOwner) external;

    // =====================================================================
    // Asset claims
    // =====================================================================

    /// @notice Add or replace an issuer's claim about an asset.
    /// @dev Caller MUST be the named issuer or authorized to act for it under
    ///      the registry's documented policy.
    function addClaim(
        bytes32 assetId,
        bytes32 topicId,
        address issuer,
        bytes calldata data,
        bytes calldata signature
    ) external;

    /// @notice Revoke an issuer's claim about an asset.
    /// @dev Caller MUST be the named issuer or authorized to act for it under
    ///      the registry's documented policy.
    function revokeClaim(bytes32 assetId, bytes32 topicId, address issuer) external;

    /// @notice Return an issuer's claim for an asset and topic.
    /// @dev An absent claim, including one queried for an unknown asset, returns
    ///      `(bytes(""), bytes(""), 0, false)`.
    function getClaim(bytes32 assetId, bytes32 topicId, address issuer)
        external view returns (
            bytes memory data,
            bytes memory signature,
            uint64 timestamp,
            bool revoked
        );

    /// @notice List the claim issuers for an asset and topic.
    /// @dev Unknown assets/topics return an empty array.
    function getClaimIssuers(bytes32 assetId, bytes32 topicId)
        external view returns (address[] memory);

    /// @notice Configure whether an issuer is trusted for a claim topic.
    /// @dev MUST be restricted to the registry's documented governance
    ///      authority and emit `TrustedIssuerChanged` on success.
    function setTrustedIssuer(bytes32 topicId, address issuer, bool trusted) external;

    /// @notice Check whether an issuer is trusted for a claim topic.
    /// @dev Unknown topic/issuer pairs return false.
    function isTrustedIssuer(bytes32 topicId, address issuer)
        external view returns (bool);

    // =====================================================================
    // License terms
    // =====================================================================
    //
    // `registerTerms`, `termsExists` and `getTerms` are inherited from
    // `ITermsRegistry`: every asset registry stores the terms used by its
    // assets and agreements locally.

    // =====================================================================
    // Terms attachment
    // =====================================================================

    /// @notice Publish or update an asset-level standing acquisition offer.
    /// @dev `termsId` MUST already be registered in this registry. While
    ///      attached, qualifying callers may call `acquireAgreement` without a
    ///      contemporaneous owner approval. Attachment itself grants no rights
    ///      and remains effective until detached.
    function attachTerms(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata attachmentParameters
    ) external;

    /// @notice Remove terms from an asset's standing acquisition offers.
    function detachTerms(bytes32 assetId, bytes32 termsId) external;

    // =====================================================================
    // License agreements
    // =====================================================================

    /// @notice Grant a license agreement for an asset under attached terms.
    /// @dev Caller MUST be the asset owner or an explicitly authorized delegate.
    ///      `canLicense.acquirer` is `params.party` for `NONE`, or the resolved
    ///      non-zero bound-token holder for `ERC721`, never `msg.sender` merely
    ///      because it submitted the grant. Ignored party/token fields are stored
    ///      as zero. Evidence captures current owner as licensor,
    ///      `createdBy == msg.sender`, the effective initial licensee,
    ///      `creationMode == GRANT`, `createdAt == block.timestamp`,
    ///      `licenseParamsHash == keccak256(params.licenseParams)`, and the exact
    ///      `params.acceptanceHash`.
    /// @return agreementId `keccak256(abi.encode(chainId(), address(this),
    ///         params.assetId, agreementIndex))`, where `agreementIndex` is the
    ///         asset's agreement count immediately before creation.
    function createAgreement(AgreementParams calldata params)
        external returns (bytes32 agreementId);

    /// @notice Acquire a license agreement under an asset's attached terms.
    /// @dev Uses the active attachment as standing owner authorization; no
    ///      contemporaneous owner transaction or signature is required. Always
    ///      creates a `NONE` agreement with `party == msg.sender` and a
    ///      zero token binding. Captures current owner as licensor,
    ///      `createdBy == initialLicensee == msg.sender`,
    ///      `creationMode == ACQUIRE`, `createdAt == block.timestamp`,
    ///      `licenseParamsHash == keccak256(licenseParams)`, and the exact
    ///      `acceptanceHash`; expiry and transferability come from resolved terms.
    /// @return agreementId The canonical id derived by the same rule as
    ///         `createAgreement`, using `assetId` and its pre-insertion count.
    function acquireAgreement(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata licenseParams,
        bytes32 acceptanceHash
    ) external returns (bytes32 agreementId);

    /// @notice Transfer a registry-tracked license agreement to a new licensee.
    /// @dev Secondary transfer of a registry-tracked (`NONE`) agreement.
    ///      Caller MUST be the current licensee or an explicitly authorized
    ///      delegate. This authorization is independent of `canTransferAgreement`.
    ///      Also subject to the terms' `transferable` flag and
    ///      `canTransferAgreement(agreementId, from, to)`.
    ///      ERC721 agreements transfer via the bound token contract instead;
    ///      the registry does not enforce or attest transfer-policy compliance.
    function transferAgreement(bytes32 agreementId, address to) external;

    /// @notice The agreement's immutable binding, creation evidence, and
    ///         effective absolute expiry, transferability, and ordinary
    ///         revocability captured by this registry.
    /// @dev    `evidence.acceptanceHash` is a commitment, not proof that the
    ///         core verified legal acceptance. Unknown ids return the all-zero
    ///         tuple: enum fields are `NONE` / `GRANT` and every other field is
    ///         its zero value.
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

    /// @notice The effective licensee of an agreement — the agreement-level
    ///         analogue of `ownerOf`. For `NONE` returns the stored `party`;
    ///         for `ERC721` delegates to `IERC721(collection).ownerOf(tokenId)`.
    ///         The raw `party` field from `agreementOf` is only meaningful for
    ///         `NONE`.
    /// @dev    Uses a 100,000-gas stipend and accepts exactly one canonical
    ///         32-byte address word. A reverting,
    ///         over-budget, or malformed `ownerOf` returns `address(0)` and the
    ///         agreement is treated as having no licensee for activity checks.
    ///         Returns `address(0)` for unknown agreements.
    function getLicensee(bytes32 agreementId) external view returns (address);

    // =====================================================================
    // Agreement activity
    // =====================================================================

    /// @notice Paginated discovery of active agreements held by `party` on
    ///         `assetId`.
    /// @dev    Uses the same stable cursor and examined-record limit as the
    ///         asset-wide overload. An empty page does not prove absence unless
    ///         `nextCursor == agreementCountOf(assetId)`. Each returned id must
    ///         be evaluated against its own terms. When
    ///         `cursor <= agreementCountOf(assetId)`, a zero `limit` returns the
    ///         input `cursor` without examining records. Unknown assets return
    ///         an empty page with `nextCursor == 0`; an out-of-range cursor on
    ///         a known asset returns an empty page with `nextCursor` equal to
    ///         that asset's agreement count.
    function activeAgreementsOf(
        bytes32 assetId,
        address party,
        uint256 cursor,
        uint256 limit
    ) external view returns (bytes32[] memory agreementIds, uint256 nextCursor);

    /// @notice Whether `party` is the current holder of the active agreement
    ///         `agreementId`, and that agreement binds `assetId`.
    /// @dev    Constant-work witness check. This reports lifecycle and holder
    ///         state only, not permission for a contemplated use. Returns false
    ///         for unknown agreements/assets and for `party == address(0)`.
    function isActiveAgreementHolder(bytes32 agreementId, bytes32 assetId, address party)
        external view returns (bool);

    /// @notice Whether an agreement has a current licensee and is not expired,
    ///         revoked, or frozen.
    /// @dev    This is an on-chain lifecycle-state predicate, not an assertion
    ///         of legal validity, enforceability, or permission for any use.
    ///         Returns false for unknown agreements.
    function isAgreementActive(bytes32 agreementId) external view returns (bool);

    // =====================================================================
    // Revocation
    // =====================================================================

    /// @notice Revoke a license agreement through the ordinary owner path.
    /// @dev Caller MUST be the bound asset's current owner or an explicitly
    ///      authorized delegate. MUST also enforce `canRevoke`.
    function revokeAgreement(bytes32 agreementId, bytes32 reason) external;

    /// @notice Revoke a license agreement through the administrative path.
    /// @dev Irreversible break-glass path restricted to the registry's
    ///      documented administrative or governance authority. Not hook-gated.
    function forceRevokeAgreement(bytes32 agreementId, bytes32 reason) external;

    // =====================================================================
    // Pre-flight hooks
    //
    // Every hook is `view`, permissionless to call, and does not revert on
    // unknown ids. Each returns `(bool ok, bytes32 reason)`: `ok == false`
    // denies (rather than reverting on policy denial), and `reason` is an
    // implementer-defined machine-readable code explaining a denial. When
    // `ok == true`, `reason` MUST be `bytes32(0)`; when `ok == false`, `reason`
    // SHOULD be a non-zero code (mirrors the `bytes32 reason` convention used
    // by revocation/freeze). The matching state-changing function reverts with
    // `HookDenied(reason)` so callers learn why off-chain via a code→message
    // map. Default-permissive (`return (true, bytes32(0))`) is allowed: the
    // existence of the hook is normative; the policy is not.
    // =====================================================================

    /// @notice Preview whether policy permits an asset registration.
    function canRegister(address registrant, RegistrationParams calldata params)
        external view returns (bool ok, bytes32 reason);

    /// @notice Preview whether policy permits an asset metadata update.
    function canUpdateMetadata(bytes32 assetId, string calldata newURI)
        external view returns (bool ok, bytes32 reason);

    /// @notice Policy hook for administrative ownership transfers of `NONE` assets.
    /// @dev `assetId` belongs only to the asset namespace, even if an agreement
    ///      has the same ID bytes. Does not gate external ERC721 transfers.
    function canTransferAsset(bytes32 assetId, address from, address to)
        external view returns (bool ok, bytes32 reason);

    /// @notice Policy hook for licensee transfers of `NONE` agreements.
    /// @dev `agreementId` belongs only to the agreement namespace, even if an
    ///      asset has the same ID bytes. Does not gate external ERC721 transfers.
    function canTransferAgreement(bytes32 agreementId, address from, address to)
        external view returns (bool ok, bytes32 reason);

    /// @notice Preview whether policy permits attaching terms to an asset.
    function canAttachTerms(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata attachmentParameters
    ) external view returns (bool ok, bytes32 reason);

    /// @notice Preview whether policy permits detaching terms from an asset.
    function canDetachTerms(bytes32 assetId, bytes32 termsId)
        external view returns (bool ok, bytes32 reason);

    /// @notice Preview whether policy permits creating a license agreement.
    /// @param licenseParams Opaque to the core ERC; carries implementer-specific
    ///        parameters supplied by the caller of `createAgreement` /
    ///        `acquireAgreement` (e.g. a rights-ratio confirmation, an off-chain
    ///        legal-acceptance signature, or parent-terms inheritance data) for
    ///        the policy to decode and verify. Mirrors `attachmentParameters` on
    ///        `canAttachTerms`.
    /// @param acceptanceHash Optional commitment to acceptance evidence that
    ///        the policy may validate against `licenseParams` and the terms.
    function canLicense(
        bytes32 assetId,
        bytes32 termsId,
        address acquirer,
        bytes calldata licenseParams,
        bytes32 acceptanceHash
    ) external view returns (bool ok, bytes32 reason);

    /// @notice Preview whether policy permits an ordinary agreement revocation.
    function canRevoke(bytes32 agreementId, address caller, bytes32 reason)
        external view returns (bool ok, bytes32 denialReason);

    /// @notice Get advisory policy guidance on deriving from a parent asset.
    function canDerive(bytes32 parentAssetId, address deriver)
        external view returns (bool ok, bytes32 reason);

    // =====================================================================
    // Administrative paths
    //
    // Break-glass operations. Authorization is implementer-controlled and
    // NOT hook-gated. `freezeParty` and `recoverAsset` are deliberately
    // NOT in the core.
    // =====================================================================

    /// @notice Block new terms attachments and agreement creation for an asset.
    /// @dev Existing agreements remain unaffected.
    function freezeAsset(bytes32 assetId, bytes32 reason) external;

    /// @notice Lift the freeze on new attachments and agreements for an asset.
    function unfreezeAsset(bytes32 assetId, bytes32 reason) external;

    /// @notice Temporarily make one agreement inactive without deleting it.
    function freezeAgreement(bytes32 agreementId, bytes32 reason) external;

    /// @notice Restore activity for a frozen agreement.
    function unfreezeAgreement(bytes32 agreementId, bytes32 reason) external;

    // =====================================================================
    // ERC-165 support
    //
    // `supportsInterface(bytes4)` is inherited from `IERC165`. A conforming
    // registry MUST return true for the ERC-165, `IIPAssetRegistry`, and
    // inherited `ITermsRegistry` interface ids.
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

    /// @dev `contentHash` is immutable, so it is NOT included: only the
    ///      mutable `metadataURI` changes. Together with the initial URI in
    ///      `AssetRegistered`, this event stream makes full URI history
    ///      reconstructable.
    event MetadataUpdated(
        bytes32 indexed assetId,
        address indexed updatedBy,
        string  oldURI,
        string  newURI,
        uint64  timestamp
    );

    /// @dev Emitted only for `tokenization == NONE`. ERC-721 transfers go
    ///      via the bound NFT contract.
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


    /// @dev Emitted only for `agreementTokenization == NONE`. Tokenized
    ///      transfers go via the bound token contract.
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
