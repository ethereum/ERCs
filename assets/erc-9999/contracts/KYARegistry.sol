// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IKYASchemeRegistry} from "./interfaces/IKYASchemeRegistry.sol";
import {IKYAVerifier} from "./interfaces/IKYAVerifier.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {IERC8004IdentityRegistry} from "./interfaces/IERC8004Validation.sol";

/// @title KYARegistry — reference implementation
/// @notice Stores assertion skeletons only; evidence lives off-chain (URI emitted, never stored).
contract KYARegistry is IKYARegistry, IERC165 {
    bytes32 public constant SUBJECT_TYPE_ERC8004 = keccak256("erc8004");

    IKYASchemeRegistry public immutable schemeRegistry;
    // assertionId => subject bytes (needed to re-evaluate the binding predicate later)
    mapping(bytes32 => bytes) private _subjectData;
    mapping(bytes32 => bytes32) private _subjectType;

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
        return _resolve(subject, schemeId, issuers, true);
    }

    function resolveLocal(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        public
        view
        returns (uint8 level, uint64 expiresAt, bytes32 assertionId)
    {
        return _resolve(subject, schemeId, issuers, false);
    }

    function _resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers, bool complete)
        internal
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
            if (complete) {
                uint8 bs = _bindingStatus(id, a);
                if (bs == uint8(BindingStatus.VIOLATED) || bs == uint8(BindingStatus.UNEVALUABLE)) continue;
            }
            if (assertionId == bytes32(0) || a.level > level || (a.level == level && a.issuedAt > bestIssuedAt)) {
                level = a.level;
                expiresAt = a.expiresAt;
                assertionId = id;
                bestIssuedAt = a.issuedAt;
            }
        }
    }

    // ------------------------------------------------------------ binding

    function bindingStatus(bytes32 assertionId) external view returns (uint8) {
        if (!_exists[assertionId]) revert KYA_AssertionNotFound(assertionId);
        return _bindingStatus(assertionId, _assertions[assertionId]);
    }

    /// @dev Evaluates the scheme's binding predicate for a recorded assertion against CURRENT state.
    function _bindingStatus(bytes32 assertionId, Assertion storage a) internal view returns (uint8) {
        uint8 binding = schemeRegistry.getScheme(a.schemeId).binding;
        if (binding == uint8(BindingKind.IDENTITY)) return uint8(BindingStatus.NOT_APPLICABLE);
        if (binding == uint8(BindingKind.INSTANCE)) {
            // the instance commitment is the claimDigest itself; relying parties compare it to the
            // instance they interact with. From the registry's view it is satisfied by construction.
            return uint8(BindingStatus.SATISFIED);
        }
        // CONTROLLER
        if (a.bindingWitness == bytes32(0)) return uint8(BindingStatus.UNEVALUABLE);
        (bytes32 w, bool ok) = _controllerWitness(_subjectType[assertionId], _subjectData[assertionId]);
        if (!ok) return uint8(BindingStatus.UNEVALUABLE);
        return w == a.bindingWitness ? uint8(BindingStatus.SATISFIED) : uint8(BindingStatus.VIOLATED);
    }

    /// @dev Native controller witness: supported for `erc8004` subjects on this chain.
    ///      witness = keccak256(abi.encode(ownerOf(agentId))). Returns ok=false when it cannot be
    ///      evaluated here (foreign chain, unknown subject type, ownerOf reverting).
    function _controllerWitness(bytes32 subjectType, bytes memory subjectData) internal view returns (bytes32 w, bool ok) {
        if (subjectType != SUBJECT_TYPE_ERC8004 || subjectData.length != 96) return (bytes32(0), false);
        (uint256 chainId, address identityRegistry, uint256 agentId) = abi.decode(subjectData, (uint256, address, uint256));
        if (chainId != block.chainid || identityRegistry.code.length == 0) return (bytes32(0), false);
        try IERC8004IdentityRegistry(identityRegistry).ownerOf(agentId) returns (address owner) {
            if (owner == address(0)) return (bytes32(0), false);
            return (keccak256(abi.encode(owner)), true);
        } catch {
            return (bytes32(0), false);
        }
    }

    /// @dev Witness captured at issuance according to the scheme's binding kind.
    function _witnessAtIssuance(Subject calldata subject, uint8 binding, bytes32 claimDigest) internal view returns (bytes32) {
        if (binding == uint8(BindingKind.IDENTITY)) return bytes32(0);
        if (binding == uint8(BindingKind.INSTANCE)) return claimDigest;
        (bytes32 w, bool ok) = _controllerWitness(subject.subjectType, subject.subjectData);
        if (!ok) revert KYA_BindingUnevaluable(subjectKeyOf(subject), binding);
        return w;
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
        a.bindingWitness = _witnessAtIssuance(subject, s.binding, claimDigest);
        assertionId = _record(a, schemeId, msg.sender, evidenceURI);
        _storeSubject(assertionId, subject);
    }

    function attestWithProof(
        Subject calldata subject,
        bytes32 schemeId,
        bytes calldata publicInputs,
        bytes calldata proof,
        string calldata evidenceURI
    ) external returns (bytes32 assertionId) {
        (address verifier, uint8 binding) = _provedVerifier(schemeId);
        Assertion memory a = _verify(verifier, subjectKeyOf(subject), schemeId, publicInputs, proof);
        a.bindingWitness = _witnessAtIssuance(subject, binding, a.claimDigest);

        assertionId = _record(a, schemeId, verifier, evidenceURI);
        _storeSubject(assertionId, subject);
    }

    function _provedVerifier(bytes32 schemeId) internal view returns (address verifier, uint8 binding) {
        Scheme memory s = _loadScheme(schemeId);
        if (s.mode != uint8(SchemeMode.PROVED)) revert KYA_ModeMismatch(schemeId, uint8(SchemeMode.PROVED), s.mode);
        if (s.verifier == address(0)) revert KYA_VerifierRequired();
        // semantic immutability: the verifier's code must be the code that was registered
        bytes32 ch = s.verifier.codehash;
        if (ch != s.verifierCodehash) revert KYA_VerifierCodeChanged(schemeId, s.verifierCodehash, ch);
        verifier = s.verifier;
        binding = s.binding;
    }

    function _storeSubject(bytes32 assertionId, Subject calldata subject) internal {
        _subjectType[assertionId] = subject.subjectType;
        _subjectData[assertionId] = subject.subjectData;
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
            assertionId, a.subjectKey, a.schemeId, a.issuer, a.level, a.claimDigest, a.expiresAt, evidenceURI, a.evidenceHash, a.anchor, a.bindingWitness
        );
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IKYARegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
