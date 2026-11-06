// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAUFAssertionRegistry} from "./interfaces/IAUFAssertionRegistry.sol";
import {IAUFUnitRegistry} from "./interfaces/IAUFUnitRegistry.sol";
import {
    AssertionInput,
    Assertion,
    AssertionKind,
    AssertionStatus,
    ValuationCore,
    ObservationCore,
    AUFResultKind
} from "./AUFTypes.sol";
import "./AUFErrors.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

/// @title AIFi Assertion Registry (reference implementation)
/// @notice Records characterizations, observations, valuation receipts and extension assertions about
///         Unit versions of one Unit Registry, plus content-addressed descriptors.
contract AUFAssertionRegistry is IAUFAssertionRegistry, IERC165 {
    using AUFResultKind for uint8;

    struct Descriptor {
        address publisher;
        bytes32 kind;
        uint64 registeredAt;
        string uri;
    }

    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("AUFAssertionRegistry");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 public constant ASSERTION_TYPEHASH = keccak256(
        "Assertion(uint8 kind,uint256 unitId,uint32 version,bytes32 profileId,bytes32 contentHash,string contentURI,uint64 validFrom,uint64 validUntil,bytes32 supersedes,bytes32 payloadHash,uint256 nonce,uint256 deadline)"
    );
    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

    IAUFUnitRegistry private immutable _unitRegistry;
    uint256 private immutable _cachedChainId;
    bytes32 private immutable _cachedDomainSeparator;

    mapping(bytes32 => Assertion) private _assertions;
    mapping(bytes32 => ValuationCore) private _valuations;
    mapping(bytes32 => ObservationCore) private _observations;
    mapping(uint256 => mapping(uint32 => bytes32[])) private _byVersion;
    mapping(address => uint256) private _nonces;
    mapping(bytes32 => Descriptor) private _descriptors;

    constructor(IAUFUnitRegistry unitRegistry_) {
        _unitRegistry = unitRegistry_;
        _cachedChainId = block.chainid;
        _cachedDomainSeparator = _buildDomainSeparator();
    }

    // ---------------------------------------------------------------- descriptors

    /// @inheritdoc IAUFAssertionRegistry
    function registerDescriptor(bytes32 descriptorHash, bytes32 descriptorKind, string calldata uri) external {
        if (descriptorHash == bytes32(0)) revert AUF_ZeroHash();
        if (_descriptors[descriptorHash].registeredAt != 0) revert AUF_DescriptorExists(descriptorHash);
        _descriptors[descriptorHash] =
            Descriptor({publisher: msg.sender, kind: descriptorKind, registeredAt: uint64(block.timestamp), uri: uri});
        emit DescriptorRegistered(descriptorHash, descriptorKind, msg.sender, uri);
    }

    /// @inheritdoc IAUFAssertionRegistry
    function descriptorOf(bytes32 descriptorHash)
        external
        view
        returns (address publisher, bytes32 descriptorKind, uint64 registeredAt, string memory uri)
    {
        Descriptor storage d = _descriptors[descriptorHash];
        if (d.registeredAt == 0) revert AUF_DescriptorNotFound(descriptorHash);
        return (d.publisher, d.kind, d.registeredAt, d.uri);
    }

    // ---------------------------------------------------------------- assertions

    /// @inheritdoc IAUFAssertionRegistry
    function assertStatement(AssertionInput calldata input) external returns (bytes32 assertionId) {
        return _record(input, msg.sender);
    }

    /// @inheritdoc IAUFAssertionRegistry
    function assertStatementBySig(
        AssertionInput calldata input,
        address asserter,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bytes32 assertionId) {
        if (block.timestamp > deadline) revert AUF_Expired(deadline);
        bytes32 digest = hashAssertion(input, _nonces[asserter], deadline);
        if (!_isValidSignature(asserter, digest, signature)) revert AUF_InvalidSignature();
        return _record(input, asserter);
    }

    /// @inheritdoc IAUFAssertionRegistry
    function revoke(bytes32 assertionId) external {
        Assertion storage a = _assertions[assertionId];
        if (a.status == AssertionStatus.None) revert AUF_AssertionNotFound(assertionId);
        if (a.asserter != msg.sender) revert AUF_NotAsserter(assertionId, msg.sender);
        if (a.status != AssertionStatus.Active) revert AUF_NotActive(assertionId);
        a.status = AssertionStatus.Revoked;
        emit Revoked(assertionId, msg.sender);
    }

    // ---------------------------------------------------------------- views

    /// @inheritdoc IAUFAssertionRegistry
    function unitRegistry() external view returns (address) {
        return address(_unitRegistry);
    }

    /// @inheritdoc IAUFAssertionRegistry
    function assertionOf(bytes32 assertionId) external view returns (Assertion memory) {
        Assertion memory a = _assertions[assertionId];
        if (a.status == AssertionStatus.None) revert AUF_AssertionNotFound(assertionId);
        return a;
    }

    /// @inheritdoc IAUFAssertionRegistry
    function valuationCoreOf(bytes32 assertionId) external view returns (ValuationCore memory) {
        if (_assertions[assertionId].kind != AssertionKind.Valuation) revert AUF_AssertionNotFound(assertionId);
        return _valuations[assertionId];
    }

    /// @inheritdoc IAUFAssertionRegistry
    function observationCoreOf(bytes32 assertionId) external view returns (ObservationCore memory) {
        if (_assertions[assertionId].kind != AssertionKind.Observation) revert AUF_AssertionNotFound(assertionId);
        return _observations[assertionId];
    }

    /// @inheritdoc IAUFAssertionRegistry
    function assertionCount(uint256 unitId, uint32 version) external view returns (uint256) {
        return _byVersion[unitId][version].length;
    }

    /// @inheritdoc IAUFAssertionRegistry
    function assertionAt(uint256 unitId, uint32 version, uint256 index) external view returns (bytes32) {
        return _byVersion[unitId][version][index];
    }

    /// @inheritdoc IAUFAssertionRegistry
    function nonces(address asserter) external view returns (uint256) {
        return _nonces[asserter];
    }

    /// @inheritdoc IAUFAssertionRegistry
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _cachedChainId ? _cachedDomainSeparator : _buildDomainSeparator();
    }

    /// @notice EIP-712 struct hash of an assertion input for a given nonce and deadline (Section 12).
    function structHashOf(AssertionInput calldata input, uint256 nonce, uint256 deadline) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ASSERTION_TYPEHASH,
                uint8(input.kind),
                input.unitId,
                input.version,
                input.profileId,
                input.contentHash,
                keccak256(bytes(input.contentURI)),
                input.validFrom,
                input.validUntil,
                input.supersedes,
                keccak256(input.payload),
                nonce,
                deadline
            )
        );
    }

    /// @notice EIP-712 digest of an assertion input for a given nonce and deadline (Section 12).
    function hashAssertion(AssertionInput calldata input, uint256 nonce, uint256 deadline) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHashOf(input, nonce, deadline)));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAUFAssertionRegistry).interfaceId;
    }

    // ---------------------------------------------------------------- internals

    function _record(AssertionInput calldata input, address asserter) internal returns (bytes32 assertionId) {
        if (input.kind == AssertionKind.None || uint8(input.kind) > uint8(AssertionKind.Extension)) revert AUF_InvalidKind();
        if (input.contentHash == bytes32(0)) revert AUF_ZeroHash();
        if (input.validUntil != 0 && input.validUntil <= input.validFrom) revert AUF_InvalidValidity();
        // Subject must exist in the bound Unit Registry (reverts otherwise).
        uint32 latest = _unitRegistry.latestVersion(input.unitId);
        if (input.version == 0 || input.version > latest) revert AUF_VersionNotFound(input.unitId, input.version);

        uint256 nonce = _nonces[asserter]++;
        assertionId = keccak256(abi.encode(address(this), asserter, nonce));

        bool byController = _unitRegistry.controllerOf(input.unitId) == asserter;

        Assertion storage a = _assertions[assertionId];
        a.kind = input.kind;
        a.status = AssertionStatus.Active;
        a.byController = byController;
        a.version = input.version;
        a.assertedAt = uint64(block.timestamp);
        a.validFrom = input.validFrom;
        a.validUntil = input.validUntil;
        a.asserter = asserter;
        a.unitId = input.unitId;
        a.profileId = input.profileId;
        a.contentHash = input.contentHash;
        a.supersedes = input.supersedes;
        a.contentURI = input.contentURI;
        _byVersion[input.unitId][input.version].push(assertionId);

        if (input.kind == AssertionKind.Valuation) {
            if (input.payload.length != 320) revert AUF_InvalidPayload();
            ValuationCore memory core = abi.decode(input.payload, (ValuationCore));
            if (core.resultKind == 0 || core.resultKind > AUFResultKind.MAX) revert AUF_InvalidResultKind(core.resultKind);
            if (core.methodId != input.profileId) revert AUF_MethodMismatch(input.profileId, core.methodId);
            if (!core.resultKind.carriesValue() && core.value != 0) revert AUF_ValueNotAllowed(core.resultKind);
            _valuations[assertionId] = core;
            emit ValuationAsserted(
                assertionId,
                input.unitId,
                core.methodId,
                core.interestId,
                core.resultKind,
                core.value,
                core.denominationId,
                core.asOf
            );
        } else if (input.kind == AssertionKind.Observation) {
            if (input.payload.length != 96) revert AUF_InvalidPayload();
            ObservationCore memory core = abi.decode(input.payload, (ObservationCore));
            if (core.windowEnd < core.windowStart) revert AUF_InvalidWindow();
            _observations[assertionId] = core;
            emit ObservationAsserted(assertionId, input.unitId, core.snapshotHash, core.windowStart, core.windowEnd);
        } else if (input.payload.length != 0) {
            revert AUF_InvalidPayload();
        }

        if (input.supersedes != bytes32(0)) {
            Assertion storage prev = _assertions[input.supersedes];
            if (prev.status == AssertionStatus.None) revert AUF_AssertionNotFound(input.supersedes);
            if (prev.status != AssertionStatus.Active) revert AUF_NotActive(input.supersedes);
            if (prev.kind != input.kind || prev.unitId != input.unitId || prev.asserter != asserter) {
                revert AUF_SupersedeMismatch(input.supersedes);
            }
            prev.status = AssertionStatus.Superseded;
            prev.supersededBy = assertionId;
            emit Superseded(input.supersedes, assertionId);
        }

        emit Asserted(
            assertionId, input.unitId, input.version, input.kind, asserter, input.profileId, input.contentHash, byController
        );
    }

    function _isValidSignature(address signer, bytes32 digest, bytes calldata signature) internal view returns (bool) {
        if (signer.code.length == 0) {
            if (signature.length != 65) return false;
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 32))
                v := byte(0, calldataload(add(signature.offset, 64)))
            }
            if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) return false;
            if (v != 27 && v != 28) return false;
            address recovered = ecrecover(digest, v, r, s);
            return recovered != address(0) && recovered == signer;
        }
        (bool ok, bytes memory ret) =
            signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, digest, signature));
        return ok && ret.length == 32 && abi.decode(ret, (bytes4)) == _ERC1271_MAGIC;
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(_EIP712_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }
}
