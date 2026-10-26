// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "./ASFTypes.sol";
import {ASFErrors} from "./ASFErrors.sol";
import {ASFEvaluation} from "./libraries/ASFEvaluation.sol";
import {IASFBindingRegistry} from "./interfaces/IASFBindingRegistry.sol";
import {IASFSpecificationRegistry} from "./interfaces/IASFSpecificationRegistry.sol";

/// @title  ASFBindingRegistry — reference implementation of the Safety Binding registry
/// @notice Records adoption relations and their lifecycle, indexes them by (subject, adopter) and
///         (scope, adopter), and offers a registry-level `check` that consumers can call before acting.
///         What it deliberately does not do: decide whether the adopter may speak for the subject or the
///         resource (consumers verify that against the permission source named in `authorityRef`),
///         evaluate any policy, or enforce anything by itself.
///         The evaluation (`check`, `checkBinding`) lives in the externally linked `ASFEvaluation` library,
///         which runs on this contract's storage through DELEGATECALL; the split keeps the registry's deployed
///         code within the per-transaction gas cap of networks that meter code deposit heavily and changes
///         neither the ABI nor the behaviour.
contract ASFBindingRegistry is IASFBindingRegistry {
    uint256 private constant MAX_INTERVENERS = 16;

    T.Store private _s;
    mapping(bytes32 => mapping(address => bytes32[])) private _bySubject;
    mapping(bytes32 => mapping(address => bytes32[])) private _byScope;

    // ------------------------------------------------------------------------------ ERC-165

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IASFBindingRegistry).interfaceId;
    }

    // -------------------------------------------------------------------------------- adopt

    function adopt(T.BindingInput calldata input) external returns (bytes32 bindingId) {
        bindingId = computeBindingId(msg.sender, input);
        T.Binding storage b = _s.bindings[bindingId];
        if (b.state != T.BindingState.None) revert ASFErrors.BindingExists();

        // validity window: validUntil is exclusive; 0 = open-ended
        if (input.validUntil != 0) {
            if (input.validUntil <= block.timestamp) revert ASFErrors.InvalidValidity();
            if (input.validFrom != 0 && input.validUntil <= input.validFrom) revert ASFErrors.InvalidValidity();
        }

        // pinned specification version: registry must be queryable and the content hash must match
        if (!ASFEvaluation.supportsSpecRegistry(input.specRegistry)) revert ASFErrors.SpecRegistryNotSupported();
        T.SpecificationVersion memory v;
        try IASFSpecificationRegistry(input.specRegistry).versionOf(input.specId, input.version) returns (
            T.SpecificationVersion memory got
        ) {
            v = got;
        } catch {
            revert ASFErrors.UnknownVersion();
        }
        if (v.contentHash == bytes32(0) || v.contentHash != input.contentHash) revert ASFErrors.ContentHashMismatch();

        // derived binding: same pinned version, window inside the parent's, bounded depth
        uint8 depth;
        if (input.parentBindingId != bytes32(0)) {
            T.Binding storage p = _s.bindings[input.parentBindingId];
            if (p.state != T.BindingState.Active) revert ASFErrors.ParentNotActive();
            if (p.specRegistry != input.specRegistry || p.specId != input.specId || p.version != input.version) {
                revert ASFErrors.ParentMismatch();
            }
            if (p.validUntil != 0 && (input.validUntil == 0 || input.validUntil > p.validUntil)) {
                revert ASFErrors.ParentWindowExceeded();
            }
            if (p.depth >= T.MAX_DEPTH) revert ASFErrors.DepthExceeded();
            depth = p.depth + 1;
        }

        // interveners
        uint256 n = input.interveners.length;
        if (n > MAX_INTERVENERS) revert ASFErrors.TooManyInterveners();
        for (uint256 i = 0; i < n; i++) {
            T.Intervener calldata iv = input.interveners[i];
            if (iv.account == address(0)) revert ASFErrors.ZeroIntervener();
            if (iv.account == msg.sender) revert ASFErrors.DuplicateIntervener();
            if (iv.rights == 0 || iv.rights > T.RIGHT_ALL) revert ASFErrors.InvalidRights();
            if (_s.rights[bindingId][iv.account] != 0) revert ASFErrors.DuplicateIntervener();
            _s.rights[bindingId][iv.account] = iv.rights;
            _s.interveners[bindingId].push(iv);
        }

        b.adopter = msg.sender;
        b.subjectKey = input.subjectKey;
        b.scopeKey = input.scopeKey;
        b.specRegistry = input.specRegistry;
        b.specId = input.specId;
        b.version = input.version;
        b.contentHash = input.contentHash;
        b.paramsHash = input.paramsHash;
        b.paramsLocator = input.paramsLocator;
        b.authorityRef = input.authorityRef;
        b.enforcement = input.enforcement;
        b.validFrom = input.validFrom;
        b.validUntil = input.validUntil;
        b.parentBindingId = input.parentBindingId;
        b.depth = depth;
        b.createdAt = uint64(block.timestamp);
        b.stateChangedAt = uint64(block.timestamp);
        b.state = T.BindingState.Active;

        _bySubject[input.subjectKey][msg.sender].push(bindingId);
        _byScope[input.scopeKey][msg.sender].push(bindingId);

        emit BindingCreated(
            bindingId,
            msg.sender,
            input.subjectKey,
            input.scopeKey,
            input.specRegistry,
            input.specId,
            input.version,
            input.contentHash,
            input.parentBindingId
        );
        emit BindingStateChanged(
            bindingId, T.BindingState.None, T.BindingState.Active, 0, bytes32(0), msg.sender, bytes32(0)
        );
    }

    // ---------------------------------------------------------------------------- lifecycle

    function suspend(bytes32 bindingId, uint8 restrictions, bytes32 responseRef, bytes32 reasonRef) external {
        T.Binding storage b = _existing(bindingId);
        if (b.state != T.BindingState.Active) revert ASFErrors.InvalidState();
        if (restrictions == 0 || restrictions > T.RESTRICT_ALL) revert ASFErrors.InvalidRestriction();
        if (rightsOf(bindingId, msg.sender) & T.RIGHT_SUSPEND == 0) revert ASFErrors.NotAuthorized();
        b.state = T.BindingState.Suspended;
        b.restrictions = restrictions;
        b.responseRef = responseRef;
        b.suspendedBy = msg.sender;
        b.stateChangedAt = uint64(block.timestamp);
        emit BindingStateChanged(
            bindingId, T.BindingState.Active, T.BindingState.Suspended, restrictions, responseRef, msg.sender, reasonRef
        );
    }

    function resume(bytes32 bindingId, bytes32 reasonRef) external {
        T.Binding storage b = _existing(bindingId);
        if (b.state != T.BindingState.Suspended) revert ASFErrors.InvalidState();
        if (rightsOf(bindingId, msg.sender) & T.RIGHT_RESUME == 0) revert ASFErrors.NotAuthorized();
        // an intervener's suspension is not the adopter's to lift: only an intervener holding RIGHT_RESUME may
        if (b.suspendedBy != b.adopter && msg.sender == b.adopter) revert ASFErrors.NotAuthorized();
        b.state = T.BindingState.Active;
        b.restrictions = 0;
        b.responseRef = bytes32(0);
        b.suspendedBy = address(0);
        b.stateChangedAt = uint64(block.timestamp);
        emit BindingStateChanged(
            bindingId, T.BindingState.Suspended, T.BindingState.Active, 0, bytes32(0), msg.sender, reasonRef
        );
    }

    function terminate(bytes32 bindingId, bytes32 reasonRef) external {
        T.Binding storage b = _existing(bindingId);
        if (b.state == T.BindingState.Terminated) revert ASFErrors.InvalidState();
        if (rightsOf(bindingId, msg.sender) & T.RIGHT_TERMINATE == 0) revert ASFErrors.NotAuthorized();
        T.BindingState previous = b.state;
        b.state = T.BindingState.Terminated;
        b.restrictions = 0;
        b.responseRef = bytes32(0);
        b.suspendedBy = address(0);
        b.stateChangedAt = uint64(block.timestamp);
        emit BindingStateChanged(bindingId, previous, T.BindingState.Terminated, 0, bytes32(0), msg.sender, reasonRef);
    }

    function setParamsLocator(bytes32 bindingId, string calldata locator) external {
        T.Binding storage b = _existing(bindingId);
        if (b.adopter != msg.sender) revert ASFErrors.NotAdopter();
        if (b.state == T.BindingState.Terminated) revert ASFErrors.InvalidState();
        b.paramsLocator = locator;
        emit BindingParamsLocatorUpdated(bindingId, locator);
    }

    // -------------------------------------------------------------------------------- views

    function computeBindingId(address adopter, T.BindingInput calldata input) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                adopter,
                input.subjectKey,
                input.scopeKey,
                input.specRegistry,
                input.specId,
                input.version,
                input.salt
            )
        );
    }

    function bindingOf(bytes32 bindingId) external view returns (T.Binding memory) {
        return _existing(bindingId);
    }

    function intervenersOf(bytes32 bindingId) external view returns (T.Intervener[] memory) {
        _existing(bindingId);
        return _s.interveners[bindingId];
    }

    function rightsOf(bytes32 bindingId, address account) public view returns (uint8) {
        T.Binding storage b = _s.bindings[bindingId];
        if (b.state == T.BindingState.None) return 0;
        if (account == b.adopter) return T.RIGHT_ALL;
        return _s.rights[bindingId][account];
    }

    function countBySubject(bytes32 subjectKey, address adopter) external view returns (uint256) {
        return _bySubject[subjectKey][adopter].length;
    }

    function bindingsBySubject(bytes32 subjectKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        return _slice(_bySubject[subjectKey][adopter], offset, limit);
    }

    function countByScope(bytes32 scopeKey, address adopter) external view returns (uint256) {
        return _byScope[scopeKey][adopter].length;
    }

    function bindingsByScope(bytes32 scopeKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        return _slice(_byScope[scopeKey][adopter], offset, limit);
    }

    // -------------------------------------------------------------------------------- check

    /// @dev Both checks run in the externally linked evaluation library on this contract's storage; the calldata
    ///      after the selector is forwarded as is, so the registry carries no decoder of its own.
    function checkBinding(bytes32, T.Clause calldata)
        external view returns (T.Verdict verdict, T.Reason reason, uint8 restrictions)
    {
        return ASFEvaluation.checkBinding(_s, msg.data[4:]);
    }

    function check(T.RequirementSet calldata, bytes32[] calldata)
        external view returns (T.Verdict verdict, T.Reason[] memory reasons, uint8[] memory restrictions)
    {
        return ASFEvaluation.check(_s, msg.data[4:]);
    }

    function requirementId(T.RequirementSet calldata requirement) external pure returns (bytes32) {
        ASFEvaluation.validateRequirementCalldata(requirement);
        return keccak256(abi.encode(requirement));
    }

    // ----------------------------------------------------------------------------- internal

    function _existing(bytes32 bindingId) private view returns (T.Binding storage b) {
        b = _s.bindings[bindingId];
        if (b.state == T.BindingState.None) revert ASFErrors.UnknownBinding();
    }

    function _slice(bytes32[] storage list, uint256 offset, uint256 limit) private view returns (bytes32[] memory out) {
        uint256 len = list.length;
        if (offset >= len) return new bytes32[](0);
        uint256 end = offset + limit;
        if (limit == 0 || end > len) end = len;
        out = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) out[i - offset] = list[i];
    }
}
