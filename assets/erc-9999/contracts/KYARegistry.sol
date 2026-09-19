// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IKYASchemeRegistry} from "./interfaces/IKYASchemeRegistry.sol";
import {IKYAVerifier} from "./interfaces/IKYAVerifier.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @title KYARegistry — reference implementation
/// @notice Stores assertion skeletons only; evidence lives off-chain (URI emitted, never stored).
contract KYARegistry is IKYARegistry, IERC165 {
    IKYASchemeRegistry public immutable schemeRegistry;

    mapping(bytes32 => Assertion) private _assertions;
    mapping(bytes32 => bool) private _exists;
    // subjectKey => schemeId => issuer => latest assertionId
    mapping(bytes32 => mapping(bytes32 => mapping(address => bytes32))) private _latest;
    mapping(address => uint256) private _issuerNonce;
    // schemeId => nullifier => used
    mapping(bytes32 => mapping(bytes32 => bool)) private _nullifiers;

    constructor(address schemeRegistry_) {
        schemeRegistry = IKYASchemeRegistry(schemeRegistry_);
    }

    // ------------------------------------------------------------------ views

    function getSchemeRegistry() external view returns (address) {
        return address(schemeRegistry);
    }

    function subjectKeyOf(Subject calldata subject) public pure returns (bytes32) {
        return keccak256(abi.encode(subject.subjectType, subject.subjectData));
    }

    function getAssertion(bytes32 assertionId) external view returns (Assertion memory) {
        if (!_exists[assertionId]) revert KYA_AssertionNotFound(assertionId);
        return _assertions[assertionId];
    }

    function latestAssertion(bytes32 subjectKey, bytes32 schemeId, address issuer) external view returns (bytes32) {
        return _latest[subjectKey][schemeId][issuer];
    }

    function isNullifierUsed(bytes32 schemeId, bytes32 nullifier) external view returns (bool) {
        return _nullifiers[schemeId][nullifier];
    }

    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        public
        view
        returns (uint8 level, uint64 expiresAt, bytes32 assertionId)
    {
        if (issuers.length == 0) revert KYA_EmptyIssuers();
        bytes32 subjectKey = subjectKeyOf(subject);
        uint64 bestIssuedAt = 0;
        for (uint256 i = 0; i < issuers.length; i++) {
            bytes32 id = _latest[subjectKey][schemeId][issuers[i]];
            if (id == bytes32(0)) continue;
            Assertion storage a = _assertions[id];
            if (a.status != uint8(AssertionStatus.ACTIVE)) continue;
            if (a.expiresAt != 0 && a.expiresAt <= block.timestamp) continue;
            if (assertionId == bytes32(0) || a.level > level || (a.level == level && a.issuedAt > bestIssuedAt)) {
                level = a.level;
                expiresAt = a.expiresAt;
                assertionId = id;
                bestIssuedAt = a.issuedAt;
            }
        }
    }

    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata issuers)
        external
        view
        returns (bool)
    {
        (uint8 level,, bytes32 id) = resolve(subject, schemeId, issuers);
        return id != bytes32(0) && level >= minLevel;
    }

    // ----------------------------------------------------------------- writes

    function attest(
        Subject calldata subject,
        bytes32 schemeId,
        uint8 level,
        bytes32 claimDigest,
        uint64 expiresAt,
        string calldata evidenceURI,
        bytes32 evidenceHash
    ) external returns (bytes32 assertionId) {
        Scheme memory s = _loadScheme(schemeId);
        if (s.mode != uint8(SchemeMode.ATTESTED)) revert KYA_ModeMismatch(schemeId, uint8(SchemeMode.ATTESTED), s.mode);
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert KYA_Expired(expiresAt);

        Assertion memory a;
        a.subjectKey = subjectKeyOf(subject);
        a.level = level;
        a.claimDigest = claimDigest;
        a.expiresAt = expiresAt;
        a.evidenceHash = evidenceHash;
        assertionId = _record(a, schemeId, msg.sender, evidenceURI);
    }

    function attestWithProof(
        Subject calldata subject,
        bytes32 schemeId,
        bytes calldata publicInputs,
        bytes calldata proof,
        string calldata evidenceURI
    ) external returns (bytes32 assertionId) {
        address verifier = _provedVerifier(schemeId);
        Assertion memory a = _verify(verifier, subjectKeyOf(subject), schemeId, publicInputs, proof);

        assertionId = _record(a, schemeId, verifier, evidenceURI);
    }

    function _provedVerifier(bytes32 schemeId) internal view returns (address verifier) {
        Scheme memory s = _loadScheme(schemeId);
        if (s.mode != uint8(SchemeMode.PROVED)) revert KYA_ModeMismatch(schemeId, uint8(SchemeMode.PROVED), s.mode);
        if (s.verifier == address(0)) revert KYA_VerifierRequired();
        verifier = s.verifier;
    }

    /// @dev Runs the verifier, enforces subject binding + nullifier, returns a partially filled Assertion.
    function _verify(address verifier, bytes32 subjectKey, bytes32 schemeId, bytes calldata publicInputs, bytes calldata proof)
        internal
        returns (Assertion memory a)
    {
        bool ok;
        bytes32 provedSubjectKey;
        bytes32 nullifier;
        (ok, provedSubjectKey, nullifier, a.level, a.claimDigest, a.expiresAt, a.anchor) =
            IKYAVerifier(verifier).verify(schemeId, publicInputs, proof);
        if (!ok) revert KYA_VerifierRejected();
        if (provedSubjectKey != subjectKey) revert KYA_SubjectMismatch(subjectKey, provedSubjectKey);
        if (_nullifiers[schemeId][nullifier]) revert KYA_NullifierUsed(schemeId, nullifier);
        _nullifiers[schemeId][nullifier] = true;
        if (a.expiresAt != 0 && a.expiresAt <= block.timestamp) revert KYA_Expired(a.expiresAt);

        a.subjectKey = subjectKey;
        a.evidenceHash = keccak256(publicInputs);
    }

    function revoke(bytes32 assertionId, uint16 reasonCode) external {
        if (!_exists[assertionId]) revert KYA_AssertionNotFound(assertionId);
        Assertion storage a = _assertions[assertionId];
        if (a.status != uint8(AssertionStatus.ACTIVE)) revert KYA_AssertionNotActive(assertionId);

        bool isIssuer = msg.sender == a.issuer;
        bool isController = schemeRegistry.getScheme(a.schemeId).controller == msg.sender;
        if (!isIssuer && !isController) revert KYA_NotIssuer(assertionId, msg.sender);

        a.status = uint8(AssertionStatus.REVOKED);
        emit Revoked(assertionId, a.subjectKey, msg.sender, reasonCode);
    }

    // --------------------------------------------------------------- internal

    function _loadScheme(bytes32 schemeId) internal view returns (Scheme memory s) {
        if (!schemeRegistry.schemeExists(schemeId)) revert KYA_SchemeNotFound(schemeId);
        s = schemeRegistry.getScheme(schemeId);
    }

    /// @dev `a` carries subjectKey, level, claimDigest, expiresAt, evidenceHash, anchor.
    function _record(Assertion memory a, bytes32 schemeId, address issuer, string calldata evidenceURI)
        internal
        returns (bytes32 assertionId)
    {
        uint256 nonce = _issuerNonce[issuer]++;
        assertionId = keccak256(abi.encode(a.subjectKey, schemeId, issuer, nonce));

        a.schemeId = schemeId;
        a.issuer = issuer;
        a.issuedAt = uint64(block.timestamp);
        a.status = uint8(AssertionStatus.ACTIVE);
        _assertions[assertionId] = a;
        _exists[assertionId] = true;

        bytes32 prev = _latest[a.subjectKey][schemeId][issuer];
        if (prev != bytes32(0) && _assertions[prev].status == uint8(AssertionStatus.ACTIVE)) {
            _assertions[prev].status = uint8(AssertionStatus.SUPERSEDED);
            emit Superseded(prev, assertionId);
        }
        _latest[a.subjectKey][schemeId][issuer] = assertionId;

        _emitAsserted(assertionId, a, evidenceURI);
    }

    function _emitAsserted(bytes32 assertionId, Assertion memory a, string calldata evidenceURI) internal {
        emit Asserted(
            assertionId, a.subjectKey, a.schemeId, a.issuer, a.level, a.claimDigest, a.expiresAt, evidenceURI, a.evidenceHash, a.anchor
        );
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IKYARegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
