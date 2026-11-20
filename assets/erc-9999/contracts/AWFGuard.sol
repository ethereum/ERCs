// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC165} from "./Introspection.sol";
import {IAWFGuard} from "./interfaces/IAWFGuard.sol";
import {IAWFRegistry} from "./interfaces/IAWFRegistry.sol";
import {IAWFSubjectResolver} from "./interfaces/IAWFSubjectResolver.sol";
import "./interfaces/AWFTypes.sol";

/// @title Reference guard of the Agent Whitelist Framework
/// @notice Stores bindings and applies them. No owner, no upgrade path and no privileged account:
/// a binding is written by the consumer it governs or by the adopter that consumer named.
contract AWFGuard is IAWFGuard, IERC165 {
    uint256 public constant MAX_LISTS = 8;
    uint256 public constant MAX_ACTIONS = 16;
    /// @dev Gas a call to a resolver or to the subject's namespace may use.
    uint256 public constant CALL_GAS = 500_000;

    mapping(bytes32 => BindingInfo) private _info;
    mapping(bytes32 => BindingConfig) private _config;
    mapping(address => address) private _adopters;
    mapping(bytes32 => mapping(bytes32 => Admission)) private _admissions;

    // ------------------------------------------------------------ adoption

    function setAdopter(address adopter) external {
        _adopters[msg.sender] = adopter;
        emit AdopterSet(msg.sender, adopter);
    }

    function adopterOf(address consumer) external view returns (address) {
        return _adopters[consumer];
    }

    function adopt(BindingConfig calldata config, bytes32 salt, string calldata uri) external returns (bytes32 bindingId) {
        address consumer = config.scope.anchor;
        _authorize(consumer);
        _validate(config);
        bytes32 scopeId = _scopeId(config.scope);
        bindingId = bindingIdOf(consumer, scopeId, salt);
        BindingInfo storage info = _info[bindingId];
        if (info.consumer != address(0)) revert BindingExists();
        info.consumer = consumer;
        info.adoptedBy = msg.sender;
        info.version = 1;
        info.scopeId = scopeId;
        info.configHash = keccak256(abi.encode(config));
        _store(bindingId, config);
        emit BindingAdopted(bindingId, consumer, scopeId, info.configHash, msg.sender, uri);
    }

    function amend(bytes32 bindingId, BindingConfig calldata config, string calldata uri) external {
        BindingInfo storage info = _live(bindingId);
        _authorize(info.consumer);
        _validate(config);
        // The scope identifies the binding. Another scope is another binding.
        if (_scopeId(config.scope) != info.scopeId) revert InvalidBinding();
        info.version += 1;
        info.configHash = keccak256(abi.encode(config));
        _store(bindingId, config);
        emit BindingAmended(bindingId, info.version, info.configHash, msg.sender, uri);
    }

    function retire(bytes32 bindingId) external {
        BindingInfo storage info = _live(bindingId);
        _authorize(info.consumer);
        info.retired = true;
        emit BindingRetired(bindingId, msg.sender);
    }

    function bindingIdOf(address consumer, bytes32 scopeId, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encode(BINDING_TAG, block.chainid, address(this), consumer, scopeId, salt));
    }

    function bindingOf(bytes32 bindingId) external view returns (BindingInfo memory info, BindingConfig memory config) {
        return (_info[bindingId], _config[bindingId]);
    }

    // ------------------------------------------------------------ assessment

    function assess(
        bytes32 bindingId,
        SubjectRef calldata subject,
        address presenter,
        bytes32 action,
        bytes32 context,
        bytes[] calldata evidence
    ) external view returns (Assessment memory a) {
        bool live;
        (a,, live) = _open(bindingId, subject, presenter, action, context);
        if (live) _decide(a, subject, evidence);
    }

    function enforce(
        bytes32 bindingId,
        SubjectRef calldata subject,
        address presenter,
        bytes32 action,
        bytes32 context,
        bytes[] calldata evidence
    ) external returns (Disposition, Outcome, bytes32) {
        BindingInfo storage info = _info[bindingId];
        if (info.consumer == address(0)) revert UnknownBinding();
        if (msg.sender != info.consumer) revert NotAuthorized();

        (Assessment memory a, bool once, bool live) = _open(bindingId, subject, presenter, action, context);
        if (live) {
            Admission storage admission = _admissions[bindingId][_slot(context, a.subjectKey, action)];
            bool entitled = _config[bindingId].role == Role.OBJECT || a.standing == Match.MATCH;
            if (once && admission.at != 0 && entitled) {
                // An admission already given for this context is honoured. Only standing was checked again.
                a.outcome = admission.outcome;
                a.disposition = admission.disposition;
                a.reason = R_ADMISSION_HONOURED;
                a.stateDigest = stateDigestOf(bindingId);
            } else {
                _decide(a, subject, evidence);
                bool proceeds = a.disposition == Disposition.PROCEED || a.disposition == Disposition.PROCEED_RESTRICTED;
                if (once && proceeds && admission.at == 0) {
                    admission.at = uint64(block.timestamp);
                    admission.bindingVersion = a.bindingVersion;
                    admission.outcome = a.outcome;
                    admission.disposition = a.disposition;
                    emit AdmissionRecorded(bindingId, a.subjectKey, action, context, a.outcome);
                }
            }
        }
        emit Assessed(
            bindingId,
            a.subjectKey,
            action,
            context,
            presenter,
            a.outcome,
            a.disposition,
            a.reason,
            a.bindingVersion,
            a.stateDigest,
            a.validUntil
        );
        return (a.disposition, a.outcome, a.reason);
    }

    function stateDigestOf(bytes32 bindingId) public view returns (bytes32) {
        BindingConfig storage c = _config[bindingId];
        uint256 allowed = c.allow.length;
        bytes32[] memory states = new bytes32[](allowed + c.deny.length);
        for (uint256 i; i < states.length; ++i) {
            ListRef storage ref = i < allowed ? c.allow[i] : c.deny[i - allowed];
            try IAWFRegistry(ref.registry).stateOf(ref.listId) returns (uint64, bytes32 state) {
                states[i] = state;
            } catch {}
        }
        return _digest(bindingId, _info[bindingId].version, states);
    }

    function isCurrent(bytes32 bindingId, bytes32 stateDigest, uint64 validUntil) external view returns (bool) {
        BindingInfo storage info = _info[bindingId];
        return info.consumer != address(0) && !info.retired && block.timestamp <= validUntil
            && stateDigest == stateDigestOf(bindingId);
    }

    function admissionOf(bytes32 bindingId, bytes32 context, bytes32 subjectKey, bytes32 action)
        external
        view
        returns (Admission memory)
    {
        return _admissions[bindingId][_slot(context, subjectKey, action)];
    }

    function withdrawAdmission(bytes32 bindingId, bytes32 context, bytes32 subjectKey, bytes32 action) external {
        BindingInfo storage info = _info[bindingId];
        if (info.consumer == address(0)) revert UnknownBinding();
        _authorize(info.consumer);
        delete _admissions[bindingId][_slot(context, subjectKey, action)];
        emit AdmissionWithdrawn(bindingId, subjectKey, action, context);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAWFGuard).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------------------------------------ evaluation

    /// @dev Identifies the request, checks that the binding covers it and establishes standing.
    /// `live` is false when the assessment is already concluded.
    function _open(bytes32 bindingId, SubjectRef calldata subject, address presenter, bytes32 action, bytes32 context)
        private
        view
        returns (Assessment memory a, bool once, bool live)
    {
        BindingInfo storage info = _info[bindingId];
        BindingConfig storage c = _config[bindingId];
        a.bindingId = bindingId;
        a.bindingVersion = info.version;
        a.subjectKey = keccak256(abi.encode(subject.kind, subject.chainId, subject.namespace, subject.id));
        a.presenter = presenter;
        a.action = action;
        a.context = context;
        a.assessedAt = uint64(block.timestamp);

        if (info.consumer == address(0)) {
            _conclude(a, c, Outcome.NOT_APPLICABLE, R_BINDING_UNKNOWN);
            return (a, false, false);
        }
        if (info.retired) {
            _conclude(a, c, Outcome.NOT_APPLICABLE, R_BINDING_RETIRED);
            return (a, false, false);
        }
        bool covered;
        for (uint256 i; i < c.actions.length; ++i) {
            if (c.actions[i].action == action) {
                covered = true;
                once = c.actions[i].once;
                break;
            }
        }
        if (!covered) {
            _conclude(a, c, Outcome.NOT_APPLICABLE, R_ACTION_NOT_COVERED);
            return (a, false, false);
        }
        if (c.scope.context != bytes32(0) && c.scope.context != context) {
            _conclude(a, c, Outcome.NOT_APPLICABLE, R_CONTEXT_NOT_COVERED);
            return (a, false, false);
        }
        if (c.role == Role.ACTOR) (a.standing, a.controller) = _standing(c.resolver, subject, presenter);
        live = true;
    }

    /// @dev Asks every list, combines the two sides and applies the declared rules.
    function _decide(Assessment memory a, SubjectRef calldata subject, bytes[] calldata evidence) private view {
        BindingConfig storage c = _config[a.bindingId];
        Request memory request = Request({
            consumer: c.scope.anchor,
            action: a.action,
            context: a.context,
            presenter: a.presenter,
            controller: a.controller
        });
        uint256 allowed = c.allow.length;
        uint256 n = allowed + c.deny.length;
        a.findings = new Finding[](n);
        bytes32[] memory states = new bytes32[](n);
        uint64 validUntil = type(uint64).max;
        for (uint256 i; i < n; ++i) {
            bool allowSide = i < allowed;
            ListRef storage ref = allowSide ? c.allow[i] : c.deny[i - allowed];
            Finding memory f = _finding(
                ref, allowSide ? Polarity.ALLOW : Polarity.DENY, subject, request, i < evidence.length ? evidence[i] : bytes("")
            );
            a.findings[i] = f;
            states[i] = f.stateHash;
            if (f.validUntil < validUntil) validUntil = f.validUntil;
        }
        a.validUntil = validUntil;
        a.stateDigest = _digest(a.bindingId, a.bindingVersion, states);
        a.allowSide = _side(a.findings, 0, allowed, c.allowThreshold);
        a.denySide = _side(a.findings, allowed, n, c.denyThreshold);

        Outcome outcome = _combine(a.allowSide, a.denySide, c.onConflict, c.onNoMatch);
        bytes32 reason;
        if (a.allowSide == Match.MATCH && a.denySide == Match.MATCH) reason = R_CONFLICT;
        else if (outcome == Outcome.INDETERMINATE) reason = R_UNDETERMINED_INPUT;
        else if (outcome == Outcome.DENY && a.denySide == Match.MATCH) reason = R_DENY_MATCH;
        else if (outcome == Outcome.ALLOW && a.allowSide == Match.MATCH) reason = R_ALLOW_MATCH;
        else reason = R_DEFAULT;

        // A list result gives nothing to a caller who may not act for the subject.
        if (c.role == Role.ACTOR) {
            if (a.standing == Match.NO_MATCH) {
                outcome = Outcome.DENY;
                reason = R_PRESENTER_NOT_AUTHORIZED;
            } else if (a.standing == Match.UNDETERMINED && outcome == Outcome.ALLOW) {
                outcome = Outcome.INDETERMINATE;
                reason = R_STANDING_UNVERIFIED;
            }
        }
        _conclude(a, c, outcome, reason);
    }

    function _finding(
        ListRef storage ref,
        Polarity expected,
        SubjectRef calldata subject,
        Request memory request,
        bytes memory evidence
    ) private view returns (Finding memory f) {
        f.listId = ref.listId;
        f.polarity = expected;
        try IAWFRegistry(ref.registry).stateOf(ref.listId) returns (uint64 revision, bytes32 state) {
            f.revision = revision;
            f.stateHash = state;
            if (ref.pin != bytes32(0) && state != ref.pin) {
                // The adopter holds to a state the list has left. Until it adopts the new one, the list says nothing.
                f.reason = R_LIST_STATE_CHANGED;
                return f;
            }
        } catch {
            f.reason = R_REGISTRY_UNAVAILABLE;
            return f;
        }
        try IAWFRegistry(ref.registry).matchOf(ref.listId, subject, request, evidence) returns (Finding memory g) {
            if (g.polarity != expected) {
                f.reason = R_POLARITY_MISMATCH;
                return f;
            }
            g.listId = ref.listId;
            return g;
        } catch {
            f.reason = R_REGISTRY_UNAVAILABLE;
        }
    }

    /// @dev Threshold over three-valued results. An empty side matches nothing.
    function _side(Finding[] memory findings, uint256 from, uint256 to, uint256 threshold) private pure returns (Match) {
        uint256 matched;
        uint256 undetermined;
        for (uint256 i = from; i < to; ++i) {
            if (findings[i].result == Match.MATCH) ++matched;
            else if (findings[i].result == Match.UNDETERMINED) ++undetermined;
        }
        if (to == from) return Match.NO_MATCH;
        if (matched >= threshold) return Match.MATCH;
        if (matched + undetermined < threshold) return Match.NO_MATCH;
        return Match.UNDETERMINED;
    }

    /// @dev The outcome is determined only if it is the same whichever way every undetermined side
    /// would resolve.
    function _combine(Match allowSide, Match denySide, Outcome onConflict, Outcome onNoMatch)
        private
        pure
        returns (Outcome result)
    {
        bool first = true;
        for (uint256 i; i < 4; ++i) {
            bool allowMatches = i & 1 == 1;
            bool denyMatches = i & 2 == 2;
            if (allowSide != Match.UNDETERMINED && allowMatches != (allowSide == Match.MATCH)) continue;
            if (denySide != Match.UNDETERMINED && denyMatches != (denySide == Match.MATCH)) continue;
            Outcome o = allowMatches
                ? (denyMatches ? onConflict : Outcome.ALLOW)
                : (denyMatches ? Outcome.DENY : onNoMatch);
            if (o == Outcome.INDETERMINATE) return Outcome.INDETERMINATE;
            if (first) {
                result = o;
                first = false;
            } else if (o != result) {
                return Outcome.INDETERMINATE;
            }
        }
    }

    function _conclude(Assessment memory a, BindingConfig storage c, Outcome outcome, bytes32 reason) private view {
        a.outcome = outcome;
        a.reason = reason;
        if (outcome == Outcome.ALLOW) a.disposition = Disposition.PROCEED;
        else if (outcome == Outcome.DENY) a.disposition = Disposition.REFUSE;
        else if (outcome == Outcome.INDETERMINATE) a.disposition = c.onIndeterminate;
        else a.disposition = c.onNotApplicable;
    }

    // ------------------------------------------------------------ standing

    function _standing(address resolver, SubjectRef calldata subject, address presenter)
        private
        view
        returns (Match authorized, address controller)
    {
        if (resolver != address(0)) {
            (bool ok, uint256 a, uint256 b) =
                _query(resolver, abi.encodeCall(IAWFSubjectResolver.standingOf, (subject, presenter)), 64);
            if (!ok || a > uint256(Match.NO_MATCH) || b > type(uint160).max) return (Match.UNDETERMINED, address(0));
            return (Match(uint8(a)), address(uint160(b)));
        }
        // Built-in rules: accounts and registry entries on this chain. Anything else needs a resolver.
        // Without a presenter nobody invokes the subject's standing, and it stays unverified.
        if (subject.chainId != block.chainid) return (Match.UNDETERMINED, address(0));
        if (subject.kind == KIND_ACCOUNT) {
            if (subject.namespace != address(0) || uint256(subject.id) > type(uint160).max) {
                return (Match.UNDETERMINED, address(0));
            }
            controller = address(uint160(uint256(subject.id)));
            if (presenter == address(0)) return (Match.UNDETERMINED, controller);
            return (presenter == controller ? Match.MATCH : Match.NO_MATCH, controller);
        }
        if (subject.kind == KIND_ENTRY) {
            uint256 id = uint256(subject.id);
            (bool ok, uint256 owner,) = _query(subject.namespace, abi.encodeWithSignature("ownerOf(uint256)", id), 32);
            if (!ok || owner == 0 || owner > type(uint160).max) return (Match.UNDETERMINED, address(0));
            controller = address(uint160(owner));
            if (presenter == address(0)) return (Match.UNDETERMINED, controller);
            if (presenter == controller) return (Match.MATCH, controller);
            uint256 approved;
            (ok, approved,) = _query(subject.namespace, abi.encodeWithSignature("getApproved(uint256)", id), 32);
            if (ok && approved == uint256(uint160(presenter))) return (Match.MATCH, controller);
            (ok, approved,) = _query(
                subject.namespace, abi.encodeWithSignature("isApprovedForAll(address,address)", controller, presenter), 32
            );
            if (ok && approved == 1) return (Match.MATCH, controller);
            return (Match.NO_MATCH, controller);
        }
        return (Match.UNDETERMINED, address(0));
    }

    /// @dev Static call with bounded gas that succeeds only if exactly `size` bytes come back.
    function _query(address target, bytes memory data, uint256 size) private view returns (bool ok, uint256 a, uint256 b) {
        uint256 gasLimit = CALL_GAS;
        assembly ("memory-safe") {
            let out := mload(0x40)
            ok := staticcall(gasLimit, target, add(data, 32), mload(data), out, size)
            if iszero(eq(returndatasize(), size)) { ok := 0 }
            a := mload(out)
            if gt(size, 32) { b := mload(add(out, 32)) }
        }
    }

    // ------------------------------------------------------------ internals

    function _authorize(address consumer) private view {
        if (consumer == address(0) || (msg.sender != consumer && msg.sender != _adopters[consumer])) revert NotAuthorized();
    }

    function _live(bytes32 bindingId) private view returns (BindingInfo storage info) {
        info = _info[bindingId];
        if (info.consumer == address(0)) revert UnknownBinding();
        if (info.retired) revert BindingIsRetired();
    }

    function _validate(BindingConfig calldata c) private view {
        uint256 allowed = c.allow.length;
        uint256 denied = c.deny.length;
        if (c.actions.length == 0 || c.actions.length > MAX_ACTIONS) revert InvalidBinding();
        if (allowed + denied == 0 || allowed > MAX_LISTS || denied > MAX_LISTS) revert InvalidBinding();
        if (allowed == 0 ? c.allowThreshold != 0 : (c.allowThreshold == 0 || c.allowThreshold > allowed)) {
            revert InvalidBinding();
        }
        if (denied == 0 ? c.denyThreshold != 0 : (c.denyThreshold == 0 || c.denyThreshold > denied)) {
            revert InvalidBinding();
        }
        if (c.onConflict == Outcome.NOT_APPLICABLE || c.onNoMatch == Outcome.INDETERMINATE) revert InvalidBinding();
        for (uint256 i; i < allowed; ++i) _requirePolarity(c.allow[i], Polarity.ALLOW);
        for (uint256 i; i < denied; ++i) _requirePolarity(c.deny[i], Polarity.DENY);
    }

    function _requirePolarity(ListRef calldata ref, Polarity expected) private view {
        if (ref.registry.code.length == 0) revert InvalidBinding();
        try IAWFRegistry(ref.registry).listOf(ref.listId) returns (ListInfo memory l) {
            if (l.polarity != expected) revert InvalidBinding();
        } catch {
            revert InvalidBinding();
        }
    }

    function _store(bytes32 bindingId, BindingConfig calldata config) private {
        BindingConfig storage c = _config[bindingId];
        c.scope = config.scope;
        c.role = config.role;
        c.allowThreshold = config.allowThreshold;
        c.denyThreshold = config.denyThreshold;
        c.onConflict = config.onConflict;
        c.onNoMatch = config.onNoMatch;
        c.onIndeterminate = config.onIndeterminate;
        c.onNotApplicable = config.onNotApplicable;
        c.resolver = config.resolver;
        c.documentHash = config.documentHash;
        delete c.actions;
        delete c.allow;
        delete c.deny;
        for (uint256 i; i < config.actions.length; ++i) c.actions.push(config.actions[i]);
        for (uint256 i; i < config.allow.length; ++i) c.allow.push(config.allow[i]);
        for (uint256 i; i < config.deny.length; ++i) c.deny.push(config.deny[i]);
    }

    function _scopeId(Scope calldata scope) private view returns (bytes32) {
        return keccak256(abi.encode(SCOPE_TAG, block.chainid, scope.anchor, scope.context, scope.documentHash));
    }

    function _slot(bytes32 context, bytes32 subjectKey, bytes32 action) private pure returns (bytes32) {
        return keccak256(abi.encode(context, subjectKey, action));
    }

    function _digest(bytes32 bindingId, uint64 version, bytes32[] memory states) private pure returns (bytes32) {
        return keccak256(abi.encode(DIGEST_TAG, bindingId, version, states));
    }
}
