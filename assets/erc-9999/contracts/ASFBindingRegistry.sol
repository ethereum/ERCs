// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "./ASFTypes.sol";
import {ASFErrors} from "./ASFErrors.sol";
import {IASFBindingRegistry} from "./interfaces/IASFBindingRegistry.sol";
import {IASFSpecificationRegistry} from "./interfaces/IASFSpecificationRegistry.sol";

interface IERC165Probe {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title  ASFBindingRegistry — reference implementation of the Safety Binding registry
/// @notice Records adoption relations and their lifecycle, indexes them by (subject, adopter) and
///         (scope, adopter), and offers a registry-level `check` that consumers can call before acting.
///         What it deliberately does not do: decide whether the adopter may speak for the subject or the
///         resource (consumers verify that against the permission source named in `authorityRef`),
///         evaluate any policy, or enforce anything by itself.
contract ASFBindingRegistry is IASFBindingRegistry {
    uint256 private constant MAX_INTERVENERS = 16;

    mapping(bytes32 => T.Binding) private _bindings;
    mapping(bytes32 => T.Intervener[]) private _interveners;
    mapping(bytes32 => mapping(address => uint8)) private _rights;
    mapping(bytes32 => mapping(address => bytes32[])) private _bySubject;
    mapping(bytes32 => mapping(address => bytes32[])) private _byScope;

    // ------------------------------------------------------------------------------ ERC-165

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IASFBindingRegistry).interfaceId;
    }

    // -------------------------------------------------------------------------------- adopt

    function adopt(T.BindingInput calldata input) external returns (bytes32 bindingId) {
        bindingId = computeBindingId(msg.sender, input);
        T.Binding storage b = _bindings[bindingId];
        if (b.state != T.BindingState.None) revert ASFErrors.BindingExists();

        // validity window: validUntil is exclusive; 0 = open-ended
        if (input.validUntil != 0) {
            if (input.validUntil <= block.timestamp) revert ASFErrors.InvalidValidity();
            if (input.validFrom != 0 && input.validUntil <= input.validFrom) revert ASFErrors.InvalidValidity();
        }

        // pinned specification version: registry must be queryable and the content hash must match
        _requireSpecRegistry(input.specRegistry);
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
            T.Binding storage p = _bindings[input.parentBindingId];
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
            if (_rights[bindingId][iv.account] != 0) revert ASFErrors.DuplicateIntervener();
            _rights[bindingId][iv.account] = iv.rights;
            _interveners[bindingId].push(iv);
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
        b.stateChangedAt = uint64(block.timestamp);
        emit BindingStateChanged(
            bindingId, T.BindingState.Active, T.BindingState.Suspended, restrictions, responseRef, msg.sender, reasonRef
        );
    }

    function resume(bytes32 bindingId, bytes32 reasonRef) external {
        T.Binding storage b = _existing(bindingId);
        if (b.state != T.BindingState.Suspended) revert ASFErrors.InvalidState();
        if (rightsOf(bindingId, msg.sender) & T.RIGHT_RESUME == 0) revert ASFErrors.NotAuthorized();
        b.state = T.BindingState.Active;
        b.restrictions = 0;
        b.responseRef = bytes32(0);
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
        return _interveners[bindingId];
    }

    function rightsOf(bytes32 bindingId, address account) public view returns (uint8) {
        T.Binding storage b = _bindings[bindingId];
        if (b.state == T.BindingState.None) return 0;
        if (account == b.adopter) return T.RIGHT_ALL;
        return _rights[bindingId][account];
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

    function checkBinding(bytes32 bindingId, T.Clause calldata clause)
        external view returns (T.Verdict verdict, T.Reason reason, uint8 restrictions)
    {
        _validateClause(clause);
        return _evaluate(bindingId, clause);
    }

    function check(T.RequirementSet calldata requirement, bytes32[] calldata bindingIds)
        external view returns (T.Verdict verdict, T.Reason[] memory reasons)
    {
        _validateRequirement(requirement);
        uint256 n = requirement.clauses.length;
        if (bindingIds.length != n) revert ASFErrors.LengthMismatch();
        reasons = new T.Reason[](n);
        uint256 satisfied;
        uint256 unknown;
        for (uint256 i = 0; i < n; i++) {
            (T.Verdict v, T.Reason r,) = _evaluate(bindingIds[i], requirement.clauses[i]);
            reasons[i] = r;
            if (v == T.Verdict.Satisfied) satisfied++;
            else if (v == T.Verdict.Unknown) unknown++;
        }
        if (requirement.combinator == T.Combinator.All) {
            if (satisfied == n) return (T.Verdict.Satisfied, reasons);
            if (satisfied + unknown == n) return (T.Verdict.Unknown, reasons);
            return (T.Verdict.NotSatisfied, reasons);
        }
        uint256 k = requirement.combinator == T.Combinator.Any ? 1 : requirement.k;
        if (satisfied >= k) return (T.Verdict.Satisfied, reasons);
        if (satisfied + unknown >= k) return (T.Verdict.Unknown, reasons);
        return (T.Verdict.NotSatisfied, reasons);
    }

    function requirementId(T.RequirementSet calldata requirement) external pure returns (bytes32) {
        _validateRequirement(requirement);
        return keccak256(abi.encode(requirement));
    }

    // ----------------------------------------------------------------------------- internal

    function _existing(bytes32 bindingId) private view returns (T.Binding storage b) {
        b = _bindings[bindingId];
        if (b.state == T.BindingState.None) revert ASFErrors.UnknownBinding();
    }

    function _requireSpecRegistry(address specRegistry) private view {
        if (!_supportsSpecRegistry(specRegistry)) revert ASFErrors.SpecRegistryNotSupported();
    }

    function _supportsSpecRegistry(address specRegistry) private view returns (bool) {
        if (specRegistry.code.length == 0) return false;
        try IERC165Probe(specRegistry).supportsInterface(type(IASFSpecificationRegistry).interfaceId) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _inWindow(T.Binding storage b) private view returns (bool notYet, bool expired) {
        uint64 from = b.validFrom > b.createdAt ? b.validFrom : b.createdAt;
        notYet = block.timestamp < from;
        expired = b.validUntil != 0 && block.timestamp >= b.validUntil;
    }

    function _evaluate(bytes32 bindingId, T.Clause calldata clause)
        private view returns (T.Verdict, T.Reason, uint8)
    {
        if (bindingId == bytes32(0)) return (T.Verdict.NotSatisfied, T.Reason.NoBinding, 0);
        T.Binding storage b = _bindings[bindingId];
        if (b.state == T.BindingState.None) return (T.Verdict.NotSatisfied, T.Reason.NoBinding, 0);
        if (b.state == T.BindingState.Terminated) return (T.Verdict.NotSatisfied, T.Reason.Terminated, 0);
        if (b.state == T.BindingState.Suspended) return (T.Verdict.NotSatisfied, T.Reason.Suspended, b.restrictions);
        (bool notYet, bool expired) = _inWindow(b);
        if (notYet) return (T.Verdict.NotSatisfied, T.Reason.NotYetValid, 0);
        if (expired) return (T.Verdict.NotSatisfied, T.Reason.Expired, 0);
        if (clause.specRegistry != b.specRegistry || clause.specId != b.specId) {
            return (T.Verdict.NotSatisfied, T.Reason.SpecMismatch, 0);
        }
        if (clause.versions.length != 0) {
            bool found;
            for (uint256 i = 0; i < clause.versions.length; i++) {
                if (clause.versions[i] == b.version) { found = true; break; }
            }
            if (!found) return (T.Verdict.NotSatisfied, T.Reason.VersionMismatch, 0);
        }
        if (clause.adopter != address(0) && clause.adopter != b.adopter) {
            return (T.Verdict.NotSatisfied, T.Reason.AdopterMismatch, 0);
        }
        if (clause.subjectKey != bytes32(0) && clause.subjectKey != b.subjectKey) {
            return (T.Verdict.NotSatisfied, T.Reason.SubjectMismatch, 0);
        }
        if (clause.scopeKey != bytes32(0) && clause.scopeKey != b.scopeKey) {
            return (T.Verdict.NotSatisfied, T.Reason.ScopeMismatch, 0);
        }
        if (clause.enforcement & b.enforcement != clause.enforcement) {
            return (T.Verdict.NotSatisfied, T.Reason.EnforcementMismatch, 0);
        }
        // ancestors: every binding this one is derived from must itself be satisfied now
        bytes32 pid = b.parentBindingId;
        while (pid != bytes32(0)) {
            T.Binding storage p = _bindings[pid];
            if (p.state != T.BindingState.Active) {
                return (T.Verdict.NotSatisfied, T.Reason.ParentNotSatisfied, p.restrictions);
            }
            (bool pNotYet, bool pExpired) = _inWindow(p);
            if (pNotYet || pExpired) return (T.Verdict.NotSatisfied, T.Reason.ParentNotSatisfied, 0);
            pid = p.parentBindingId;
        }
        // the pinned specification registry must still be queryable; a dependency failure is Unknown, never a pass
        if (!_supportsSpecRegistry(b.specRegistry)) {
            return (T.Verdict.Unknown, T.Reason.SpecRegistryUnavailable, 0);
        }
        return (T.Verdict.Satisfied, T.Reason.None, 0);
    }

    function _validateClause(T.Clause calldata clause) private pure {
        if (clause.specRegistry == address(0) || clause.specId == bytes32(0)) revert ASFErrors.InvalidRequirement();
    }

    function _validateRequirement(T.RequirementSet calldata requirement) private pure {
        uint256 n = requirement.clauses.length;
        if (n == 0) revert ASFErrors.InvalidRequirement();
        if (requirement.combinator == T.Combinator.KOf) {
            if (requirement.k == 0 || requirement.k > n) revert ASFErrors.InvalidRequirement();
        } else if (requirement.k != 0) {
            revert ASFErrors.InvalidRequirement();
        }
        for (uint256 i = 0; i < n; i++) _validateClause(requirement.clauses[i]);
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
