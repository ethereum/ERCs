// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IFHEIFAuthorizer} from "../interfaces/IFHEIFAuthorizer.sol";
import {IFHEIFRegistry} from "../interfaces/IFHEIFRegistry.sol";

/// @title Example authorizer: a table of grants
/// @notice One way to answer the questions the ledger asks. The controller of a scope writes
/// grants, a grant can be passed on in a narrower form, and a scope can be frozen so that nothing
/// is granted any more. It is an example module and is not part of the interfaces of the framework.
///
/// A grant names a subject, a capability, a class of objects (zero for any) and a resource (zero
/// for any), with a validity window. A grant that was passed on holds only while the grant it was
/// passed on from holds.
contract FHEIFGrantAuthorizer is IFHEIFAuthorizer {
    struct GrantTerms {
        address subject;
        bytes32 capability;
        bytes32 classId;
        bytes32 resource;
        uint64 validAfter;
        uint64 validUntil;
        bool delegable;
    }

    struct Grant {
        bytes32 scopeId;
        GrantTerms terms;
        address grantor;
        bytes32 parent;
        bool revoked;
    }

    event Granted(
        bytes32 indexed grantId,
        bytes32 indexed scopeId,
        address indexed subject,
        bytes32 capability,
        bytes32 classId,
        bytes32 resource,
        uint64 validAfter,
        uint64 validUntil,
        bool delegable,
        address grantor,
        bytes32 parent
    );
    event Revoked(bytes32 indexed grantId, address indexed revokedBy);
    event ApprovalsRequired(bytes32 indexed scopeId, bytes32 classId, bytes32 indexed viewId, uint256 count);
    event Frozen(bytes32 indexed scopeId);

    error NotController(address caller);
    error NotGrantor(address caller);
    error ScopeFrozen(bytes32 scopeId);
    error InvalidTerms();
    error UnknownGrant(bytes32 grantId);
    error NotDelegable(bytes32 grantId);
    error NotNarrower(bytes32 grantId);
    error GrantExists(bytes32 grantId);
    error InvalidSignature();
    error TooDeep();

    bytes32 public constant GRANT_TYPEHASH = keccak256(
        "Grant(bytes32 scopeId,address subject,bytes32 capability,bytes32 classId,bytes32 resource,uint64 validAfter,uint64 validUntil,bool delegable,uint256 nonce)"
    );
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant _HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
    uint256 private constant _MAX_DEPTH = 4;

    IFHEIFRegistry public immutable registry;

    mapping(bytes32 => Grant) private _grants;
    mapping(bytes32 => bytes32[]) private _index;
    mapping(bytes32 => uint256) private _approvals;
    mapping(bytes32 => bool) public frozen;
    uint256 private _counter;

    constructor(address registry_) {
        registry = IFHEIFRegistry(registry_);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFHEIFAuthorizer).interfaceId || interfaceId == 0x01ffc9a7;
    }

    // Questions of the ledger

    function isAuthorized(
        bytes32 scopeId,
        uint64,
        address subject,
        bytes32 capability,
        bytes32 classId,
        bytes32 resource
    ) external view returns (bool) {
        return _any(scopeId, subject, capability, classId, resource) || _any(scopeId, subject, capability, classId, 0)
            || _any(scopeId, subject, capability, 0, resource) || _any(scopeId, subject, capability, 0, 0);
    }

    function requiredApprovals(bytes32 scopeId, uint64, bytes32 classId, bytes32 viewId, address)
        external
        view
        returns (uint256 required)
    {
        required = _approvals[keccak256(abi.encode(scopeId, classId, viewId))];
        uint256 forAnyClass = _approvals[keccak256(abi.encode(scopeId, bytes32(0), viewId))];
        if (forAnyClass > required) required = forAnyClass;
    }

    // Grants

    /// @notice Writes a grant. Only the controller of the scope.
    function grant(bytes32 scopeId, GrantTerms calldata terms) external returns (bytes32 grantId) {
        _requireController(scopeId, msg.sender);
        grantId = _write(scopeId, terms, msg.sender, bytes32(0));
    }

    /// @notice Writes a grant that the controller of the scope signed. Anybody may submit it.
    /// The signature is checked now. Once written, the grant holds by this record and ends by its
    /// window or by revocation, whatever the signer would answer later.
    function grantWithSignature(bytes32 scopeId, GrantTerms calldata terms, uint256 nonce, bytes calldata signature)
        external
        returns (bytes32 grantId)
    {
        address controller = registry.scopeOf(scopeId).controller;
        bytes32 digest = hashGrant(scopeId, terms, nonce);
        if (_grants[digest].grantor != address(0)) revert GrantExists(digest);
        _checkSignature(controller, digest, signature);
        grantId = _store(digest, scopeId, terms, controller, bytes32(0));
    }

    /// @notice Passes a grant on in a form that is the same or narrower. Only its subject.
    function delegate(bytes32 parentId, GrantTerms calldata terms) external returns (bytes32 grantId) {
        Grant storage parent = _grants[parentId];
        if (parent.grantor == address(0)) revert UnknownGrant(parentId);
        if (parent.terms.subject != msg.sender || !parent.terms.delegable || !_holds(parentId, 0)) {
            revert NotDelegable(parentId);
        }
        // Narrower is decided only where it can be decided: same capability, the same class and
        // resource or a named one under "any", and a window inside the window. Anything else is refused.
        if (
            terms.capability != parent.terms.capability
                || (parent.terms.classId != bytes32(0) && terms.classId != parent.terms.classId)
                || (parent.terms.resource != bytes32(0) && terms.resource != parent.terms.resource)
                || terms.validAfter < parent.terms.validAfter || terms.validUntil > parent.terms.validUntil
        ) revert NotNarrower(parentId);
        grantId = _write(parent.scopeId, terms, msg.sender, parentId);
    }

    /// @notice Revokes a grant. Its grantor or the controller of the scope.
    function revoke(bytes32 grantId) external {
        Grant storage record = _grants[grantId];
        if (record.grantor == address(0)) revert UnknownGrant(grantId);
        if (record.grantor != msg.sender && registry.scopeOf(record.scopeId).controller != msg.sender) {
            revert NotGrantor(msg.sender);
        }
        record.revoked = true;
        emit Revoked(grantId, msg.sender);
    }

    /// @notice Sets how many approvals a release under `viewId` over objects of `classId` needs.
    /// A frozen scope can raise the number and cannot lower it.
    function setRequiredApprovals(bytes32 scopeId, bytes32 classId, bytes32 viewId, uint256 count) external {
        _requireController(scopeId, msg.sender);
        bytes32 key = keccak256(abi.encode(scopeId, classId, viewId));
        if (frozen[scopeId] && count < _approvals[key]) revert ScopeFrozen(scopeId);
        _approvals[key] = count;
        emit ApprovalsRequired(scopeId, classId, viewId, count);
    }

    /// @notice Ends granting in a scope. Grants can still be revoked. It cannot be undone.
    function freeze(bytes32 scopeId) external {
        _requireController(scopeId, msg.sender);
        frozen[scopeId] = true;
        emit Frozen(scopeId);
    }

    function grantOf(bytes32 grantId) external view returns (Grant memory record) {
        record = _grants[grantId];
        if (record.grantor == address(0)) revert UnknownGrant(grantId);
    }

    /// @notice Whether a grant holds now: written, in its window, not revoked, and so for every
    /// grant it was passed on from.
    function holds(bytes32 grantId) external view returns (bool) {
        return _holds(grantId, 0);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _DOMAIN_TYPEHASH, keccak256("FHEIF Grant Authorizer"), keccak256("1"), block.chainid, address(this)
            )
        );
    }

    function hashGrant(bytes32 scopeId, GrantTerms calldata terms, uint256 nonce) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                GRANT_TYPEHASH,
                scopeId,
                terms.subject,
                terms.capability,
                terms.classId,
                terms.resource,
                terms.validAfter,
                terms.validUntil,
                terms.delegable,
                nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
    }

    // Internal

    function _requireController(bytes32 scopeId, address caller) private view {
        if (registry.scopeOf(scopeId).controller != caller) revert NotController(caller);
    }

    function _write(bytes32 scopeId, GrantTerms calldata terms, address grantor, bytes32 parent)
        private
        returns (bytes32 grantId)
    {
        grantId = keccak256(abi.encode(address(this), scopeId, grantor, parent, ++_counter));
        return _store(grantId, scopeId, terms, grantor, parent);
    }

    function _store(bytes32 grantId, bytes32 scopeId, GrantTerms calldata terms, address grantor, bytes32 parent)
        private
        returns (bytes32)
    {
        if (frozen[scopeId]) revert ScopeFrozen(scopeId);
        if (terms.subject == address(0) || terms.capability == bytes32(0) || terms.validAfter > terms.validUntil) {
            revert InvalidTerms();
        }
        _grants[grantId] = Grant(scopeId, terms, grantor, parent, false);
        _index[_key(scopeId, terms.subject, terms.capability, terms.classId, terms.resource)].push(grantId);
        emit Granted(
            grantId,
            scopeId,
            terms.subject,
            terms.capability,
            terms.classId,
            terms.resource,
            terms.validAfter,
            terms.validUntil,
            terms.delegable,
            grantor,
            parent
        );
        return grantId;
    }

    function _key(bytes32 scopeId, address subject, bytes32 capability, bytes32 classId, bytes32 resource)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(scopeId, subject, capability, classId, resource));
    }

    function _any(bytes32 scopeId, address subject, bytes32 capability, bytes32 classId, bytes32 resource)
        private
        view
        returns (bool)
    {
        bytes32[] storage ids = _index[_key(scopeId, subject, capability, classId, resource)];
        uint256 count = ids.length;
        for (uint256 i = 0; i < count; ++i) {
            if (_holds(ids[i], 0)) return true;
        }
        return false;
    }

    function _holds(bytes32 grantId, uint256 depth) private view returns (bool) {
        if (depth > _MAX_DEPTH) revert TooDeep();
        Grant storage record = _grants[grantId];
        if (
            record.grantor == address(0) || record.revoked || block.timestamp < record.terms.validAfter
                || block.timestamp > record.terms.validUntil
        ) return false;
        return record.parent == bytes32(0) || _holds(record.parent, depth + 1);
    }

    function _checkSignature(address signer, bytes32 digest, bytes calldata signature) private view {
        if (signature.length == 65) {
            bytes32 r = bytes32(signature[0:32]);
            bytes32 s = bytes32(signature[32:64]);
            uint8 v = uint8(signature[64]);
            if (uint256(s) <= _HALF_ORDER && (v == 27 || v == 28)) {
                address recovered = ecrecover(digest, v, r, s);
                if (recovered != address(0) && recovered == signer) return;
            }
        }
        if (signer.code.length != 0) {
            (bool success, bytes memory result) =
                signer.staticcall(abi.encodeWithSelector(_ERC1271_MAGIC, digest, signature));
            if (success && result.length >= 32 && abi.decode(result, (bytes32)) == bytes32(_ERC1271_MAGIC)) return;
        }
        revert InvalidSignature();
    }
}
