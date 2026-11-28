// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERCXXXX} from "./IERCXXXX.sol";
interface IERC165 { function supportsInterface(bytes4 interfaceId) external view returns (bool); }

/// @title ProofRegistry — Reference implementation of ERC-XXXX (B-hybrid).
/// @notice Normative text is `EIP-XXXX.md`. A satellite IERCXXXX registry:
///         attach, flags, B-hybrid reads. Authorization is implementation-defined.
/// @dev Authorization model (implementation-defined, satisfies EIP-XXXX § Authorization):
///        - Anyone may call `attachProof`.
///        - `FLAG_VERIFIED` (bit 1) can only be set by an authorized verifier
///          registered for the proof's `assetId`. The original submitter is
///          NOT a verifier by default. Flags are not set at attach time.
///        - `FLAG_FLAGGED` (bit 0) can be set by anyone but only cleared by the owner.
///        - Custom flag bits (bits 2..255) can only be modified by the owner.
///        - No-op calls (`flags == oldFlags`) return early without emitting `ProofFlagsUpdated`.
///        - `proofId` uses the RECOMMENDED derivation with `attachNonce =
///          getProofCount(assetId)` **before** the current attach is committed
///          (first attach on an asset uses nonce `0`).
contract ProofRegistry is IERCXXXX, IERC165 {
    // ---------------------------------------------------------------------
    // Constants (EIP-XXXX § Constants)
    // ---------------------------------------------------------------------
    /// @dev Fixed by the ERC. Not part of IERCXXXX (uniform across implementations).
    uint256 public constant MAX_DEPENDENCIES = 16;
    uint256 public constant METADATA_HEAD_LEN = 96;
    uint256 public constant FLAG_FLAGGED = 1 << 0;
    uint256 public constant FLAG_VERIFIED = 1 << 1;

    /// @inheritdoc IERCXXXX
    uint256 public constant override MAX_METADATA_LEN = 16_384;

    /// @notice OPTIONAL EIP-XXXX page cap. `getAssetProofs` clamps `limit` to this.
    uint256 public constant MAX_PAGE_SIZE = 100;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    struct Proof {
        bytes32 assetId;
        address submitter;
        bytes32 proofHash;
        bytes32 metadataHash;
        bytes metadataHead; // word-aligned: 0 / 32 / 64 / 96 bytes
        uint16 metadataLen;
        uint64 timestamp;
        uint256 flags;
        bytes32[] dependencies;
        bool exists;
    }

    mapping(bytes32 => Proof) internal _proofs;
    mapping(bytes32 => bytes32[]) internal _byAsset;

    /// @dev Verifier registry: assetId => verifier => allowed.
    mapping(bytes32 => mapping(address => bool)) public isVerifier;

    address public owner;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error DepsExceedMax();
    error MetadataTooLong();
    error DependencyMissing(bytes32 dep);
    error SelfReference();
    error ProofNotFound();
    error ProofIdCollision();
    error NotOwner();
    error NotVerifier();
    error ZeroOwner();

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------
    event VerifierSet(bytes32 indexed assetId, address indexed verifier, bool allowed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setVerifier(bytes32 assetId, address verifier, bool allowed) external onlyOwner {
        isVerifier[assetId][verifier] = allowed;
        emit VerifierSet(assetId, verifier, allowed);
    }

    // ---------------------------------------------------------------------
    // IERCXXXX
    // ---------------------------------------------------------------------
    function attachProof(
        bytes32 assetId,
        bytes32 proofHash,
        bytes calldata metadata,
        bytes32[] calldata dependencies
    ) external virtual override returns (bytes32 proofId) {
        if (dependencies.length > MAX_DEPENDENCIES) revert DepsExceedMax();
        if (metadata.length > MAX_METADATA_LEN) revert MetadataTooLong();

        // RECOMMENDED derivation: nonce = getProofCount(assetId) before commit.
        uint256 nonce = _byAsset[assetId].length;
        proofId = keccak256(abi.encode(block.chainid, address(this), assetId, proofHash, msg.sender, nonce));
        if (_proofs[proofId].exists) revert ProofIdCollision();

        for (uint256 i; i < dependencies.length; ++i) {
            bytes32 dep = dependencies[i];
            if (dep == proofId) revert SelfReference();
            if (!_proofs[dep].exists) revert DependencyMissing(dep);
        }

        bytes32 metadataHash = keccak256(metadata);
        Proof storage p = _proofs[proofId];
        p.assetId = assetId;
        p.submitter = msg.sender;
        p.proofHash = proofHash;
        p.metadataHash = metadataHash;
        p.metadataHead = _wordAlignedHead(metadata);
        p.metadataLen = uint16(metadata.length);
        p.timestamp = uint64(block.timestamp);
        p.dependencies = dependencies;
        p.exists = true;

        _byAsset[assetId].push(proofId);

        emit ProofAttached(assetId, proofId, msg.sender, metadataHash, metadata, dependencies);
    }

    function setProofFlags(bytes32 proofId, uint256 flags) external virtual override {
        Proof storage p = _proofs[proofId];
        if (!p.exists) revert ProofNotFound();

        uint256 oldFlags = p.flags;
        if (flags == oldFlags) return;

        uint256 diff = oldFlags ^ flags;
        bool changingVerified = (diff & FLAG_VERIFIED) != 0;
        bool changingFlagged = (diff & FLAG_FLAGGED) != 0;
        bool changingCustom = (diff & ~(FLAG_FLAGGED | FLAG_VERIFIED)) != 0;

        if (changingVerified) {
            if (!isVerifier[p.assetId][msg.sender]) revert NotVerifier();
        }
        if (changingFlagged) {
            bool isSet = (flags & FLAG_FLAGGED) != 0;
            if (!isSet && msg.sender != owner) revert NotOwner();
        }
        if (changingCustom) {
            if (msg.sender != owner) revert NotOwner();
        }

        p.flags = flags;
        emit ProofFlagsUpdated(proofId, msg.sender, oldFlags, flags);
    }

    function getProof(bytes32 proofId)
        external
        view
        override
        returns (
            bytes32 assetId,
            address submitter,
            bytes32 proofHash,
            bytes32 metadataHash,
            bytes memory metadataHead,
            uint16 metadataLen,
            uint64 timestamp,
            bytes32[] memory dependencies,
            uint256 flags
        )
    {
        Proof storage p = _proofs[proofId];
        if (!p.exists) revert ProofNotFound();
        return (
            p.assetId,
            p.submitter,
            p.proofHash,
            p.metadataHash,
            p.metadataHead,
            p.metadataLen,
            p.timestamp,
            p.dependencies,
            p.flags
        );
    }

    function getAssetProofs(bytes32 assetId, uint256 offset, uint256 limit)
        external
        view
        override
        returns (bytes32[] memory proofIds, uint256 total)
    {
        bytes32[] storage all = _byAsset[assetId];
        total = all.length;
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        if (limit > MAX_PAGE_SIZE) limit = MAX_PAGE_SIZE;
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 n = end - offset;
        proofIds = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            proofIds[i] = all[offset + i];
        }
    }

    function proofExists(bytes32 proofId) external view override returns (bool) {
        return _proofs[proofId].exists;
    }

    function getProofCount(bytes32 assetId) external view override returns (uint256) {
        return _byAsset[assetId].length;
    }

    // ---------------------------------------------------------------------
    // ERC-165
    // ---------------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERCXXXX).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------
    /// @dev `32 * floor(min(METADATA_HEAD_LEN, n) / 32)` → 0, 32, 64, or 96.
    function _wordAlignedHead(bytes calldata metadata) internal pure returns (bytes memory) {
        uint256 n = metadata.length;
        uint256 take;
        if (n >= METADATA_HEAD_LEN) take = METADATA_HEAD_LEN;
        else if (n >= 64) take = 64;
        else if (n >= 32) take = 32;
        else return "";
        return metadata[0:take];
    }
}
