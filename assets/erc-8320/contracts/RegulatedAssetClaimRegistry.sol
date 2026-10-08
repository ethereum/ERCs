// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {
    IRegulatedAssetClaimRegistry,
    RegulatedAssetClaim,
    ClaimType,
    ClaimState,
    RoleKind
} from "./interfaces/IRegulatedAssetClaimRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title RegulatedAssetClaimRegistry
/// @notice Reference ERC-8320 registry. Holds signed, versioned, role-gated claims about assets, keyed by
///         assetId. Claims move through a maker-checker lifecycle (propose -> validate -> activate, with
///         suspend/revoke) where every state change is authorized by an EIP-712 signature from the party
///         holding the matching role. The registry admin (DEFAULT_ADMIN_ROLE) registers assets and grants roles.
contract RegulatedAssetClaimRegistry is IRegulatedAssetClaimRegistry, AccessControl, EIP712 {
    bytes32 private constant PROPOSE_TYPEHASH = keccak256(
        "Propose(bytes32 assetId,uint8 claimType,bytes32 schemaId,bytes32 schemaHash,uint64 version,"
        "uint64 validFrom,uint64 validUntil,uint8 claimState,bytes32[] tags,bytes32 contentHash,"
        "address author,string uri,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant VALIDATE_TYPEHASH = keccak256(
        "Validate(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant ACTIVATE_TYPEHASH = keccak256(
        "Activate(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant SUSPEND_TYPEHASH = keccak256(
        "Suspend(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 private constant REVOKE_TYPEHASH = keccak256(
        "Revoke(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );

    struct AssetRef {
        address contractAddr;
        bool active;
        uint256 subAssetId;
        uint256 chainId;
    }

    /// @dev Role grants keyed by (assetId, claimType, roleKind) => account => granted.
    mapping(bytes32 assetId => mapping(ClaimType => mapping(RoleKind => mapping(address => bool)))) private _roles;
    /// @dev Registered asset references by assetId; existence is inferred from contractAddr != 0.
    mapping(bytes32 assetId => AssetRef) private _assets;
    /// @dev Append-only claim log per (assetId, claimType); the array itself is the enumeration.
    mapping(bytes32 assetId => mapping(ClaimType => RegulatedAssetClaim[])) private _claims;
    /// @dev Per-signer nonce for EIP-712 replay protection.
    mapping(address signer => uint256) public nonces;

    error AssetAlreadyRegistered();
    error AssetNotFound();
    error AssetNotActive();
    error NotAuthorized();
    error InvalidClaimState();
    error VersionNotIncreasing();
    error ClaimNotFound();
    error AuthorCannotValidate();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSignature();

    constructor(address admin) EIP712("RegulatedAssetClaimRegistry", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function grantRoleToClaimType(bytes32 assetId, ClaimType claimType, RoleKind kind, address who)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _roles[assetId][claimType][kind][who] = true;
        emit RoleGrantedToClaimType(assetId, claimType, kind, who);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function revokeRoleToClaimType(bytes32 assetId, ClaimType claimType, RoleKind kind, address who)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _roles[assetId][claimType][kind][who] = false;
        emit RoleRevokedFromClaimType(assetId, claimType, kind, who);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function isAuthorized(bytes32 assetId, ClaimType claimType, RoleKind kind, address who)
        external
        view
        returns (bool)
    {
        return _roles[assetId][claimType][kind][who];
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function proposeClaim(RegulatedAssetClaim calldata claim, uint256 nonce, uint64 deadline, bytes calldata signature)
        external
    {
        require(isAssetActive(claim.assetId), AssetNotActive());
        require(_roles[claim.assetId][claim.claimType][RoleKind.AUTHOR][claim.author], NotAuthorized());
        require(claim.claimState == ClaimState.PROPOSED, InvalidClaimState());

        RegulatedAssetClaim[] storage claims = _claims[claim.assetId][claim.claimType];
        uint64 prior = claims.length == 0 ? 0 : claims[claims.length - 1].version;
        require(claim.version > prior, VersionNotIncreasing());

        _verifySig(claim.author, _proposeStructHash(claim, nonce, deadline), nonce, deadline, signature);

        claims.push(claim);

        emit ClaimProposed(claim.assetId, claim.claimType, claim.version, claim.author);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function validateClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external {
        require(isAssetActive(assetId), AssetNotActive());
        RegulatedAssetClaim storage stored = _claimRef(assetId, claimType, version);
        require(_roles[assetId][claimType][RoleKind.VALIDATOR][signer], NotAuthorized());
        require(signer != stored.author, AuthorCannotValidate());
        require(_effectiveState(stored) == ClaimState.PROPOSED, InvalidClaimState());

        bytes32 structHash = keccak256(
            abi.encode(VALIDATE_TYPEHASH, assetId, uint8(claimType), version, uint8(ClaimState.VALID), nonce, deadline)
        );
        _verifySig(signer, structHash, nonce, deadline, signature);

        stored.claimState = ClaimState.VALID;
        emit ClaimValidated(assetId, claimType, version, signer);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function activateClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external {
        require(isAssetActive(assetId), AssetNotActive());
        RegulatedAssetClaim storage stored = _claimRef(assetId, claimType, version);
        require(_roles[assetId][claimType][RoleKind.ACTIVATOR][signer], NotAuthorized());
        require(_effectiveState(stored) == ClaimState.VALID, InvalidClaimState());

        bytes32 structHash = keccak256(
            abi.encode(ACTIVATE_TYPEHASH, assetId, uint8(claimType), version, uint8(ClaimState.ACTIVE), nonce, deadline)
        );
        _verifySig(signer, structHash, nonce, deadline, signature);

        stored.claimState = ClaimState.ACTIVE;
        emit ClaimActivated(assetId, claimType, version, signer);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function suspendClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external {
        RegulatedAssetClaim storage stored = _claimRef(assetId, claimType, version);
        require(_roles[assetId][claimType][RoleKind.ACTIVATOR][signer], NotAuthorized());
        require(_effectiveState(stored) == ClaimState.ACTIVE, InvalidClaimState());

        bytes32 structHash = keccak256(
            abi.encode(SUSPEND_TYPEHASH, assetId, uint8(claimType), version, uint8(ClaimState.VALID), nonce, deadline)
        );
        _verifySig(signer, structHash, nonce, deadline, signature);

        stored.claimState = ClaimState.VALID;
        emit ClaimSuspended(assetId, claimType, version, signer);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function revokeClaim(
        bytes32 assetId,
        ClaimType claimType,
        uint64 version,
        address signer,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external {
        RegulatedAssetClaim storage stored = _claimRef(assetId, claimType, version);
        require(_roles[assetId][claimType][RoleKind.VALIDATOR][signer], NotAuthorized());
        ClaimState state = _effectiveState(stored);
        require(
            state == ClaimState.PROPOSED || state == ClaimState.VALID || state == ClaimState.ACTIVE, InvalidClaimState()
        );

        bytes32 structHash = keccak256(
            abi.encode(REVOKE_TYPEHASH, assetId, uint8(claimType), version, uint8(ClaimState.REVOKED), nonce, deadline)
        );
        _verifySig(signer, structHash, nonce, deadline, signature);

        stored.claimState = ClaimState.REVOKED;
        emit ClaimRevoked(assetId, claimType, version, signer);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function getActiveClaims(bytes32 assetId, ClaimType claimType)
        external
        view
        returns (RegulatedAssetClaim[] memory activeClaims)
    {
        RegulatedAssetClaim[] storage claims = _claims[assetId][claimType];
        uint256 total = claims.length;

        uint256 count;
        for (uint256 i = 0; i < total; i++) {
            if (_isLiveActive(claims[i])) count++;
        }

        activeClaims = new RegulatedAssetClaim[](count);
        uint256 j;
        for (uint256 i = 0; i < total; i++) {
            if (_isLiveActive(claims[i])) {
                activeClaims[j] = claims[i];
                j++;
            }
        }
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function getClaim(bytes32 assetId, ClaimType claimType, uint64 version)
        external
        view
        returns (RegulatedAssetClaim memory claim)
    {
        RegulatedAssetClaim storage stored = _claimRef(assetId, claimType, version);
        claim = stored;
        claim.claimState = _effectiveState(stored);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function registerAsset(address contractAddr, uint256 subAssetId, uint256 chainId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bytes32 assetId)
    {
        assetId = _assetId(contractAddr, subAssetId, chainId);
        require(_assets[assetId].contractAddr == address(0), AssetAlreadyRegistered());

        _assets[assetId] =
            AssetRef({contractAddr: contractAddr, active: true, subAssetId: subAssetId, chainId: chainId});

        emit AssetRegistered(assetId, contractAddr, subAssetId, chainId, msg.sender);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function removeAsset(bytes32 assetId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_assets[assetId].contractAddr != address(0), AssetNotFound());
        _assets[assetId].active = false;
        emit AssetRemoved(assetId, msg.sender);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function isAssetActive(bytes32 assetId) public view returns (bool) {
        return _assets[assetId].active;
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function getAssetId(address contractAddr, uint256 subAssetId, uint256 chainId) external pure returns (bytes32) {
        return _assetId(contractAddr, subAssetId, chainId);
    }

    /// @inheritdoc IRegulatedAssetClaimRegistry
    function getAssetReference(bytes32 assetId)
        external
        view
        returns (address contractAddr, uint256 subAssetId, uint256 chainId)
    {
        AssetRef storage asset = _assets[assetId];
        require(asset.contractAddr != address(0), AssetNotFound());
        return (asset.contractAddr, asset.subAssetId, asset.chainId);
    }

    /// @notice Returns the EIP-712 domain separator. Exposed for integrators and off-chain signers.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IRegulatedAssetClaimRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev keccak256(chainId, contract, subAssetId) per the spec's asset-id derivation.
    function _assetId(address contractAddr, uint256 subAssetId, uint256 chainId) private pure returns (bytes32) {
        return keccak256(abi.encode(chainId, contractAddr, subAssetId));
    }

    /// @dev Finds a claim by version within its (assetId, claimType) log. Scans newest-first, since lifecycle
    ///      calls typically target a recently proposed claim. Reverts if the version was never proposed.
    function _claimRef(bytes32 assetId, ClaimType claimType, uint64 version)
        private
        view
        returns (RegulatedAssetClaim storage)
    {
        RegulatedAssetClaim[] storage claims = _claims[assetId][claimType];
        for (uint256 i = claims.length; i > 0; i--) {
            if (claims[i - 1].version == version) return claims[i - 1];
        }
        revert ClaimNotFound();
    }

    /// @dev deadline -> nonce -> EIP-712 digest -> signature; bumps the signer nonce on success.
    function _verifySig(address signer, bytes32 structHash, uint256 nonce, uint64 deadline, bytes calldata signature)
        private
    {
        require(block.timestamp <= deadline, SignatureExpired());
        require(nonce == nonces[signer], InvalidNonce());
        bytes32 digest = _hashTypedDataV4(structHash);
        require(SignatureChecker.isValidSignatureNow(signer, digest, signature), InvalidSignature());
        unchecked {
            nonces[signer]++;
        }
    }

    /// @dev EIP-712 struct hash for Propose. Split into two encodes so the 15 static words never sit on the
    ///      stack at once; the concatenation equals a single abi.encode.
    function _proposeStructHash(RegulatedAssetClaim calldata claim, uint256 nonce, uint64 deadline)
        private
        pure
        returns (bytes32)
    {
        bytes memory head = abi.encode(
            PROPOSE_TYPEHASH,
            claim.assetId,
            uint8(claim.claimType),
            claim.schemaId,
            claim.schemaHash,
            claim.version,
            claim.validFrom
        );
        bytes memory tail = abi.encode(
            claim.validUntil,
            uint8(claim.claimState),
            keccak256(abi.encodePacked(claim.tags)),
            claim.contentHash,
            claim.author,
            keccak256(bytes(claim.uri)),
            nonce,
            deadline
        );
        return keccak256(bytes.concat(head, tail));
    }

    /// @dev A stored VALID/ACTIVE claim past its validUntil reads as EXPIRED without a state-changing tx.
    function _effectiveState(RegulatedAssetClaim storage claim) private view returns (ClaimState) {
        if (
            (claim.claimState == ClaimState.VALID || claim.claimState == ClaimState.ACTIVE) && claim.validUntil != 0
                && block.timestamp >= claim.validUntil
        ) {
            return ClaimState.EXPIRED;
        }
        return claim.claimState;
    }

    /// @dev True when a claim is ACTIVE and within its live window (used by getActiveClaims).
    function _isLiveActive(RegulatedAssetClaim storage claim) private view returns (bool) {
        return claim.claimState == ClaimState.ACTIVE && block.timestamp >= claim.validFrom
            && (claim.validUntil == 0 || block.timestamp < claim.validUntil);
    }
}
