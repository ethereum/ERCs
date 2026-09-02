// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Topic of a claim. Each type has a distinct author, cadence, and question.
enum ClaimType {
    IDENTITY, // 0 - what is this asset, who issued it
    VALUATION, // 1 - what is it worth (NAV, price)
    MANDATE, // 2 - what this capital will allocate to
    TERMS, // 3 - subscription, redemption, fee terms
    COMPLIANCE, // 4 - who may hold or transact
    BACKING, // 5 - reserves or collateral behind it
    EVENT, // 6 - corporate actions, distributions, notices
    RISK // 7 - what risk framework or risk profile applies
}

/// @notice Lifecycle state of a claim. EXPIRED is time-derived and never stored.
enum ClaimState {
    PROPOSED, // 0
    VALID, // 1
    ACTIVE, // 2
    EXPIRED, // 3
    REVOKED // 4
}

/// @notice Role kind granted per (assetId, claimType).
enum RoleKind {
    AUTHOR, // 0 - proposes claims of a type
    VALIDATOR, // 1 - validates a proposed claim, or revokes a claim
    ACTIVATOR // 2 - activates a validated claim, or suspends an active one
}

/// @notice A signed, versioned claim about an asset.
/// @param assetId Registry key, keccak256(chainId, contract, subAssetId).
/// @param claimType Topic of the claim.
/// @param schemaId Off-chain schema the payload follows.
/// @param schemaHash Hash of the exact schema definition.
/// @param version Monotonic per (assetId, claimType).
/// @param validFrom Unix timestamp from which the claim is live.
/// @param validUntil Unix timestamp after which the claim expires, 0 = no expiry.
/// @param claimState PROPOSED, VALID, ACTIVE, EXPIRED, or REVOKED.
/// @param tags Public, indexable labels.
/// @param contentHash Hash of the off-chain payload.
/// @param author Signer (EOA or ERC-1271 contract).
/// @param uri Payload location.
struct RegulatedAssetClaim {
    bytes32 assetId;
    ClaimType claimType;
    bytes32 schemaId;
    bytes32 schemaHash;
    uint64 version;
    uint64 validFrom;
    uint64 validUntil;
    ClaimState claimState;
    bytes32[] tags;
    bytes32 contentHash;
    address author;
    string uri;
}

/// @title IRegulatedAssetClaimRegistry
/// @notice Registry for signed, versioned claims about regulated assets.
interface IRegulatedAssetClaimRegistry is IERC165 {
    /// @notice Emitted by `proposeClaim`.
    event ClaimProposed(bytes32 indexed assetId, ClaimType indexed claimType, uint64 version, address indexed author);
    /// @notice Emitted by `validateClaim`.
    event ClaimValidated(
        bytes32 indexed assetId, ClaimType indexed claimType, uint64 version, address indexed validator
    );
    /// @notice Emitted by `activateClaim`.
    event ClaimActivated(
        bytes32 indexed assetId, ClaimType indexed claimType, uint64 version, address indexed activator
    );
    /// @notice Emitted by `suspendClaim`.
    event ClaimSuspended(
        bytes32 indexed assetId, ClaimType indexed claimType, uint64 version, address indexed activator
    );
    /// @notice Emitted by `revokeClaim`.
    event ClaimRevoked(bytes32 indexed assetId, ClaimType indexed claimType, uint64 version, address indexed revoker);
    /// @notice Emitted by `grantRoleToClaimType`.
    event RoleGrantedToClaimType(bytes32 indexed assetId, ClaimType claimType, RoleKind kind, address indexed who);
    /// @notice Emitted by `revokeRoleToClaimType`.
    event RoleRevokedFromClaimType(bytes32 indexed assetId, ClaimType claimType, RoleKind kind, address indexed who);
    /// @notice Emitted by `registerAsset`.
    event AssetRegistered(
        bytes32 indexed assetId,
        address indexed contractAddr,
        uint256 subAssetId,
        uint256 chainId,
        address indexed registrant
    );
    /// @notice Emitted by `removeAsset`.
    event AssetRemoved(bytes32 indexed assetId, address indexed admin);

    /// @notice Grants a role for an asset and claim type.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param kind Role kind to grant.
    /// @param who Address receiving the role.
    function grantRoleToClaimType(bytes32 assetId, ClaimType claimType, RoleKind kind, address who) external;

    /// @notice Revokes a role for an asset and claim type.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param kind Role kind to revoke.
    /// @param who Address losing the role.
    function revokeRoleToClaimType(bytes32 assetId, ClaimType claimType, RoleKind kind, address who) external;

    /// @notice Checks whether an account holds a role.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param kind Role kind to check.
    /// @param who Address to check.
    /// @return True if `who` holds `kind` for the asset and claim type.
    function isAuthorized(bytes32 assetId, ClaimType claimType, RoleKind kind, address who) external view returns (bool);

    /// @notice Publishes a new proposed claim.
    /// @dev Signature is verified against `claim.author` over the EIP-712 Propose digest.
    /// @param claim Claim data being proposed.
    /// @param nonce Expected nonce of `claim.author`.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature Signature from `claim.author` (EIP-712, EIP-1271 supported).
    function proposeClaim(RegulatedAssetClaim calldata claim, uint256 nonce, uint64 deadline, bytes calldata signature)
        external;

    /// @notice Moves a proposed claim to valid.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param version Claim version.
    /// @param signer Validator address.
    /// @param nonce Expected nonce of `signer`.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature Signature from `signer`.
    function validateClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Moves a valid claim to active.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param version Claim version.
    /// @param signer Activator address.
    /// @param nonce Expected nonce of `signer`.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature Signature from `signer`.
    function activateClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Moves an active claim back to valid.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param version Claim version.
    /// @param signer Activator address.
    /// @param nonce Expected nonce of `signer`.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature Signature from `signer`.
    function suspendClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Moves a claim to revoked.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param version Claim version.
    /// @param signer Validator address.
    /// @param nonce Expected nonce of `signer`.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature Signature from `signer`.
    function revokeClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Returns active claims for an asset and claim type.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @return activeClaims Claims currently active and live for the asset and claim type.
    function getActiveClaims(bytes32 assetId, ClaimType claimType)
        external
        view
        returns (RegulatedAssetClaim[] memory activeClaims);

    /// @notice Returns one claim by exact asset, claim type, and version.
    /// @param assetId Asset registry key.
    /// @param claimType Claim type.
    /// @param version Claim version.
    /// @return The requested claim, with derived EXPIRED reported when applicable.
    function getClaim(bytes32 assetId, ClaimType claimType, uint64 version)
        external
        view
        returns (RegulatedAssetClaim memory);

    /// @notice Returns the next expected nonce for a signer.
    /// @param signer Signer address.
    /// @return Next nonce expected in a signature from `signer`.
    function nonces(address signer) external view returns (uint256);

    /// @notice Registers an asset reference in the registry.
    /// @param contractAddr Asset contract address, or zero for off-chain assets.
    /// @param subAssetId Asset-specific sub-identifier.
    /// @param chainId Chain where the asset reference exists.
    /// @return assetId The registry key derived from the asset reference.
    function registerAsset(address contractAddr, uint256 subAssetId, uint256 chainId) external returns (bytes32 assetId);

    /// @notice Marks an asset inactive while keeping its reference and claim history.
    /// @param assetId Asset registry key.
    function removeAsset(bytes32 assetId) external;

    /// @notice Checks whether the registry accepts new claim changes for an asset.
    /// @param assetId Asset registry key.
    /// @return True if the asset is active in this registry.
    function isAssetActive(bytes32 assetId) external view returns (bool);

    /// @notice Computes the asset id for an asset reference.
    /// @param contractAddr Asset contract address, or zero for off-chain assets.
    /// @param subAssetId Asset-specific sub-identifier.
    /// @param chainId Chain where the asset reference exists.
    /// @return Asset registry key.
    function getAssetId(address contractAddr, uint256 subAssetId, uint256 chainId) external pure returns (bytes32);

    /// @notice Resolves an asset id to its registered asset reference.
    /// @param assetId Asset registry key.
    /// @return contractAddr Asset contract address, or zero for off-chain assets.
    /// @return subAssetId Asset-specific sub-identifier.
    /// @return chainId Chain where the asset reference exists.
    function getAssetReference(bytes32 assetId)
        external
        view
        returns (address contractAddr, uint256 subAssetId, uint256 chainId);
}
