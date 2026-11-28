// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC165} from "./Introspection.sol";
import {IAAFRegistry} from "./interfaces/IAAFRegistry.sol";
import {IAAFEvaluator} from "./interfaces/IAAFEvaluator.sol";
import {IAAFRelationSource} from "./interfaces/IAAFRelationSource.sol";
import "./interfaces/AAFTypes.sol";

/// @title Reference registry of the Agent Allowlist Framework
/// @notice No owner, no upgrade path and no privileged account. Every list is managed by the
/// account that created it or that it was handed to.
contract AAFRegistry is IAAFRegistry, IERC165 {
    /// @dev Longest chain of sources below a derived list.
    uint8 public constant MAX_DEPTH = 4;
    /// @dev Most origins a relation may contribute for one subject.
    uint8 public constant MAX_FANOUT = 8;
    /// @dev Gas a module call may use. A call that needs more fails and yields an undetermined result.
    uint256 public constant MODULE_GAS = 1_500_000;
    /// @dev keccak256 of the empty byte string: the code hash of an account without code.
    bytes32 private constant EMPTY_CODE_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    mapping(bytes32 => Scope) private _scopes;
    mapping(bytes32 => Criteria) private _criteria;
    mapping(bytes32 => bool) private _criteriaKnown;
    mapping(bytes32 => ListInfo) private _lists;
    mapping(bytes32 => address) private _candidates;
    mapping(bytes32 => mapping(bytes32 => Entry)) private _entries;

    modifier onlyManager(bytes32 listId) {
        ListInfo storage l = _lists[listId];
        if (l.mode == Mode.NONE) revert UnknownList();
        if (l.manager != msg.sender) revert NotManager();
        if (l.closed) revert ListIsClosed();
        _;
    }

    // ------------------------------------------------------------ identifiers

    function subjectKeyOf(SubjectRef calldata subject) external pure returns (bytes32) {
        return _key(subject);
    }

    function scopeIdOf(Scope calldata scope) public view returns (bytes32) {
        return keccak256(abi.encode(SCOPE_TAG, block.chainid, scope.anchor, scope.context, scope.documentHash));
    }

    function criteriaIdOf(Criteria calldata c) external view returns (bytes32) {
        return _criteriaId(c);
    }

    function listIdOf(address creator, ListConfig calldata config) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                LIST_TAG, block.chainid, address(this), creator, config.polarity, config.mode, config.source, config.salt
            )
        );
    }

    // ------------------------------------------------------------ scopes and criteria

    function declareScope(Scope calldata scope, string calldata uri) external returns (bytes32 scopeId) {
        scopeId = scopeIdOf(scope);
        _scopes[scopeId] = scope;
        emit ScopeDeclared(scopeId, scope.anchor, scope.context, scope.documentHash, uri, msg.sender);
    }

    function registerCriteria(bytes32 documentHash, address module, bytes32 rule, uint8 fanout, string calldata uri)
        external
        returns (bytes32 criteriaId)
    {
        Criteria memory c;
        c.documentHash = documentHash;
        c.module = module;
        c.rule = rule;
        c.fanout = fanout;
        if (module != address(0)) {
            if (module.code.length == 0) revert InvalidConfig();
            (bool ok, bytes32 config) = _configOf(module);
            if (!ok) revert InvalidConfig();
            c.moduleCodeHash = module.codehash;
            c.moduleConfig = config;
        } else if (rule != bytes32(0) || fanout != 0) {
            revert InvalidConfig();
        }
        if (fanout > MAX_FANOUT) revert InvalidConfig();
        criteriaId = _criteriaId(c);
        _criteria[criteriaId] = c;
        _criteriaKnown[criteriaId] = true;
        emit CriteriaRegistered(criteriaId, module, documentHash, c.moduleCodeHash, c.moduleConfig, rule, fanout, uri);
    }

    function scopeOf(bytes32 scopeId) external view returns (Scope memory) {
        return _scopes[scopeId];
    }

    function criteriaOf(bytes32 criteriaId) external view returns (Criteria memory) {
        return _criteria[criteriaId];
    }

    // ------------------------------------------------------------ lists

    function createList(ListConfig calldata config, string calldata uri) external returns (bytes32 listId) {
        if (config.polarity == Polarity.NONE || config.mode == Mode.NONE) revert InvalidConfig();
        listId = listIdOf(msg.sender, config);
        ListInfo storage l = _lists[listId];
        if (l.mode != Mode.NONE) revert ListExists();
        _requireCriteriaFit(config.mode, config.criteriaId);

        if (config.mode == Mode.DERIVED) {
            ListInfo storage s = _lists[config.source];
            if (s.mode == Mode.NONE) revert UnknownList();
            // A derived list keeps the polarity of its source: no entry is turned into its opposite.
            if (s.polarity != config.polarity || s.depth >= MAX_DEPTH) revert InvalidConfig();
            l.depth = s.depth + 1;
            l.source = config.source;
            l.sourcePin = config.sourcePin;
        } else if (config.source != bytes32(0) || config.sourcePin != bytes32(0)) {
            revert InvalidConfig();
        }
        if (config.noticePeriod != 0 && config.mode != Mode.ENUMERATED) revert InvalidConfig();

        l.manager = msg.sender;
        l.polarity = config.polarity;
        l.mode = config.mode;
        l.noticePeriod = config.noticePeriod;
        l.scopeId = config.scopeId;
        l.criteriaId = config.criteriaId;
        emit ListCreated(
            listId, msg.sender, config.polarity, config.mode, config.scopeId, config.source, config.noticePeriod, uri
        );
        _revise(listId, l);
    }

    function setCriteria(bytes32 listId, bytes32 criteriaId) external onlyManager(listId) {
        ListInfo storage l = _lists[listId];
        _requireCriteriaFit(l.mode, criteriaId);
        l.criteriaId = criteriaId;
        emit CriteriaSet(listId, criteriaId);
        _revise(listId, l);
    }

    function setSourcePin(bytes32 listId, bytes32 sourcePin) external onlyManager(listId) {
        ListInfo storage l = _lists[listId];
        if (l.mode != Mode.DERIVED) revert WrongMode();
        l.sourcePin = sourcePin;
        emit SourcePinSet(listId, sourcePin);
        _revise(listId, l);
    }

    function offerManager(bytes32 listId, address candidate) external onlyManager(listId) {
        _candidates[listId] = candidate;
        emit ManagerOffered(listId, candidate);
    }

    function acceptManager(bytes32 listId) external {
        ListInfo storage l = _lists[listId];
        if (l.mode == Mode.NONE) revert UnknownList();
        if (l.closed) revert ListIsClosed();
        if (_candidates[listId] != msg.sender || msg.sender == address(0)) revert NotCandidate();
        emit ManagerChanged(listId, l.manager, msg.sender);
        l.manager = msg.sender;
        delete _candidates[listId];
        _revise(listId, l);
    }

    function closeList(bytes32 listId) external onlyManager(listId) {
        ListInfo storage l = _lists[listId];
        l.closed = true;
        emit ListClosed(listId);
        _revise(listId, l);
    }

    function listOf(bytes32 listId) external view returns (ListInfo memory) {
        return _lists[listId];
    }

    function stateOf(bytes32 listId) external view returns (uint64 revision, bytes32 stateHash) {
        return (_lists[listId].revision, _state(listId));
    }

    // ------------------------------------------------------------ entries

    function addEntry(bytes32 listId, SubjectRef calldata subject, EntryInput calldata input, string calldata basisURI)
        external
        onlyManager(listId)
        returns (bytes32 subjectKey)
    {
        ListInfo storage l = _lists[listId];
        if (l.mode != Mode.ENUMERATED) revert WrongMode();
        subjectKey = _key(subject);
        Entry storage e = _entries[listId][subjectKey];
        // A subject has one live entry at a time. A revoked or expired one may be replaced.
        if (e.status == EntryStatus.SUSPENDED) revert EntryExists();
        if (e.status == EntryStatus.ACTIVE && (e.validUntil == 0 || block.timestamp < e.validUntil)) {
            revert EntryExists();
        }

        uint64 earliest = uint64(block.timestamp) + l.noticePeriod;
        uint64 validFrom = input.validFrom == 0 ? earliest : input.validFrom;
        if (validFrom < earliest) revert InvalidWindow();
        if (input.validUntil != 0 && input.validUntil <= validFrom) revert InvalidWindow();
        if (input.basis == Basis.EVIDENCED && input.basisHash == bytes32(0)) revert BasisRequired();
        // The code of a subject can be read only where the subject is an account on this chain.
        if (input.codeHash != bytes32(0) && !_isLocalAccount(subject)) revert CodePinNotSupported();

        e.status = EntryStatus.ACTIVE;
        e.basis = input.basis;
        e.serial += 1;
        e.listedAt = uint64(block.timestamp);
        e.validFrom = validFrom;
        e.validUntil = input.validUntil;
        e.changedAt = uint64(block.timestamp);
        e.controller = input.controller;
        e.basisHash = input.basisHash;
        e.reason = input.reason;
        e.codeHash = input.codeHash;
        emit EntryAdded(
            listId,
            subjectKey,
            subject,
            e.serial,
            validFrom,
            input.validUntil,
            input.basis,
            input.basisHash,
            input.reason,
            input.controller,
            input.codeHash,
            basisURI
        );
        _revise(listId, l);
    }

    function suspendEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external onlyManager(listId) {
        _setStatus(listId, subjectKey, EntryStatus.ACTIVE, EntryStatus.SUSPENDED, reason);
    }

    function resumeEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external onlyManager(listId) {
        _setStatus(listId, subjectKey, EntryStatus.SUSPENDED, EntryStatus.ACTIVE, reason);
    }

    function revokeEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external onlyManager(listId) {
        Entry storage e = _entries[listId][subjectKey];
        if (e.status != EntryStatus.ACTIVE && e.status != EntryStatus.SUSPENDED) revert EntryNotFound();
        _setStatus(listId, subjectKey, e.status, EntryStatus.REVOKED, reason);
    }

    function fileObjection(bytes32 listId, bytes32 subjectKey, bytes32 objectionHash, string calldata uri) external {
        if (_entries[listId][subjectKey].status == EntryStatus.NONE) revert EntryNotFound();
        emit ObjectionFiled(listId, subjectKey, msg.sender, objectionHash, uri);
    }

    function entryOf(bytes32 listId, bytes32 subjectKey) external view returns (Entry memory) {
        return _entries[listId][subjectKey];
    }

    // ------------------------------------------------------------ committed sets

    function commitSet(bytes32 listId, bytes32 root, SetKind kind, uint64 size, string calldata uri)
        external
        onlyManager(listId)
    {
        ListInfo storage l = _lists[listId];
        if (l.mode != Mode.COMMITTED) revert WrongMode();
        if (kind == SetKind.NONE || root == bytes32(0) || size == 0) revert InvalidConfig();
        l.setRoot = root;
        l.setKind = kind;
        l.setSize = size;
        emit SetCommitted(listId, root, kind, size, uri);
        _revise(listId, l);
    }

    function verifySetProof(bytes32 root, SetKind kind, uint64 size, bytes32 subjectKey, bytes calldata evidence)
        external
        pure
        returns (Match result, bytes32 reason)
    {
        SetProof memory p = abi.decode(evidence, (SetProof));
        uint256 depth = _depthOf(size);
        if (p.index >= size || p.path.length != depth) return (Match.UNDETERMINED, R_PROOF_INVALID);
        if (p.member) {
            if (_rootOf(_leaf(p.index, subjectKey), p.index, p.path) != root) {
                return (Match.UNDETERMINED, R_PROOF_INVALID);
            }
            return (Match.MATCH, R_SET_MEMBER);
        }
        // Only a sorted and complete set can show that a key is absent.
        if (kind != SetKind.SORTED) return (Match.UNDETERMINED, R_NEGATIVE_UNSUPPORTED);
        if (p.index + 1 >= size || p.highPath.length != depth) return (Match.UNDETERMINED, R_PROOF_INVALID);
        if (!(p.lowKey < subjectKey && subjectKey < p.highKey)) return (Match.UNDETERMINED, R_PROOF_INVALID);
        if (
            _rootOf(_leaf(p.index, p.lowKey), p.index, p.path) != root
                || _rootOf(_leaf(p.index + 1, p.highKey), p.index + 1, p.highPath) != root
        ) return (Match.UNDETERMINED, R_PROOF_INVALID);
        return (Match.NO_MATCH, R_SET_NON_MEMBER);
    }

    // ------------------------------------------------------------ results

    function check(bytes32 listId, SubjectRef calldata subject) external view returns (Match result, bytes32 reason) {
        Request memory none;
        Finding memory f = _match(listId, subject, none, "", 0);
        return (f.result, f.reason);
    }

    function matchOf(bytes32 listId, SubjectRef calldata subject, Request calldata request, bytes calldata evidence)
        external
        view
        returns (Finding memory)
    {
        return _match(listId, subject, request, evidence, 0);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAAFRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------------------------------------ matching

    /// @param relationHops relation hops already taken on the way to this list
    function _match(
        bytes32 listId,
        SubjectRef memory subject,
        Request memory request,
        bytes memory evidence,
        uint8 relationHops
    ) internal view returns (Finding memory f) {
        ListInfo storage l = _lists[listId];
        f.listId = listId;
        f.polarity = l.polarity;
        f.revision = l.revision;
        f.criteriaId = l.criteriaId;
        if (l.mode == Mode.NONE) {
            f.reason = R_LIST_UNKNOWN;
            return f;
        }
        f.stateHash = _state(listId);
        if (l.closed) {
            f.reason = R_LIST_CLOSED;
            return f;
        }
        if (l.mode == Mode.ENUMERATED) {
            _matchEntry(_entries[listId][_key(subject)], subject, request, f);
        } else if (l.mode == Mode.COMMITTED) {
            _matchSet(l, _key(subject), evidence, f);
        } else if (l.mode == Mode.PREDICATE) {
            _matchPredicate(listId, l, subject, request, evidence, f);
        } else {
            _matchDerived(l, subject, request, evidence, relationHops, f);
        }
    }

    function _matchEntry(Entry storage e, SubjectRef memory subject, Request memory request, Finding memory f)
        private
        view
    {
        f.result = Match.NO_MATCH;
        f.validUntil = type(uint64).max;
        f.basis = e.basisHash;
        if (e.status == EntryStatus.NONE) {
            f.reason = R_NOT_LISTED;
        } else if (e.status == EntryStatus.REVOKED) {
            f.reason = R_ENTRY_REVOKED;
        } else if (e.status == EntryStatus.SUSPENDED) {
            f.reason = R_ENTRY_SUSPENDED;
        } else if (block.timestamp < e.validFrom) {
            f.reason = R_ENTRY_PENDING;
            f.validUntil = e.validFrom - 1;
        } else if (e.validUntil != 0 && block.timestamp >= e.validUntil) {
            f.reason = R_ENTRY_EXPIRED;
        } else {
            if (e.validUntil != 0) f.validUntil = e.validUntil - 1;
            // Code can change at any time without the list changing: a result that depends on it is
            // for this call only.
            if (e.codeHash != bytes32(0)) f.validUntil = 0;
            if (e.codeHash != bytes32(0) && _codeHash(subject) != e.codeHash) {
                // The entry was made for other code than the account has now. The list cannot say.
                f.result = Match.UNDETERMINED;
                f.reason = R_CODE_CHANGED;
            } else if (e.controller == address(0) || e.controller == request.controller) {
                f.result = Match.MATCH;
                f.reason = R_LISTED;
            } else if (request.controller == address(0)) {
                // The entry is tied to a controller and the caller did not establish one.
                f.result = Match.UNDETERMINED;
                f.reason = R_CONTROLLER_UNKNOWN;
            } else {
                f.reason = R_CONTROLLER_CHANGED;
            }
        }
    }

    function _matchSet(ListInfo storage l, bytes32 key, bytes memory evidence, Finding memory f) private view {
        f.basis = l.setRoot;
        if (l.setKind == SetKind.NONE) {
            f.reason = R_SET_MISSING;
        } else if (evidence.length == 0) {
            f.reason = R_PROOF_MISSING;
        } else {
            // Decoding is done in a call of its own so that malformed evidence cannot revert the query.
            try this.verifySetProof(l.setRoot, l.setKind, l.setSize, key, evidence) returns (Match m, bytes32 r) {
                f.result = m;
                f.reason = r;
                if (m != Match.UNDETERMINED) f.validUntil = type(uint64).max;
            } catch {
                f.reason = R_PROOF_INVALID;
            }
        }
    }

    function _matchPredicate(
        bytes32 listId,
        ListInfo storage l,
        SubjectRef memory subject,
        Request memory request,
        bytes memory evidence,
        Finding memory f
    ) private view {
        Criteria storage c = _criteria[l.criteriaId];
        if (!_pinned(c)) {
            f.reason = R_MODULE_CHANGED;
            return;
        }
        (bool ok, bytes memory out) = _query(
            c.module, abi.encodeCall(IAAFEvaluator.evaluate, (listId, c.rule, subject, request, evidence)), 128
        );
        if (ok) {
            (uint256 result, bytes32 reason, uint256 validUntil, bytes32 basis) =
                abi.decode(out, (uint256, bytes32, uint256, bytes32));
            if (result <= uint256(Match.NO_MATCH) && validUntil <= type(uint64).max) {
                f.result = Match(uint8(result));
                f.reason = reason;
                f.validUntil = uint64(validUntil);
                f.basis = basis;
                return;
            }
        }
        f.reason = R_MODULE_FAILED;
    }

    function _matchDerived(
        ListInfo storage l,
        SubjectRef memory subject,
        Request memory request,
        bytes memory evidence,
        uint8 relationHops,
        Finding memory f
    ) private view {
        if (l.sourcePin != bytes32(0) && _state(l.source) != l.sourcePin) {
            f.reason = R_SOURCE_STATE_CHANGED;
            return;
        }
        Criteria storage c = _criteria[l.criteriaId];
        if (c.module == address(0)) {
            // Plain reference: the members of the source.
            Finding memory s = _match(l.source, subject, request, evidence, relationHops);
            f.result = s.result;
            f.reason = s.reason;
            f.validUntil = s.validUntil;
            f.basis = s.basis;
            f.derivedFrom = s.derivedFrom;
            return;
        }
        // Extension is not transitive: one relation hop between a listed object and the subject.
        if (relationHops != 0) {
            f.reason = R_EXTENSION_LIMIT;
            return;
        }
        if (!_pinned(c)) {
            f.reason = R_MODULE_CHANGED;
            return;
        }
        // The controller in the request is that of the subject, not of an origin.
        Request memory forOrigin = request;
        forOrigin.controller = address(0);
        bool complete;
        bool undetermined;
        // One query beyond the fan-out tells whether the origins looked at were all there are.
        for (uint256 i; i <= c.fanout; ++i) {
            (bool ok, bytes memory out) =
                _query(c.module, abi.encodeCall(IAAFRelationSource.originOf, (c.rule, subject, evidence, i)), 192);
            if (!ok) break;
            (uint256 status, SubjectRef memory origin,) = abi.decode(out, (uint256, SubjectRef, uint256));
            if (status == 2) {
                complete = true;
                break;
            }
            if (status != 1 || i == c.fanout) break;
            Finding memory s = _match(l.source, origin, forOrigin, evidence, 1);
            if (s.result == Match.MATCH) {
                f.result = Match.MATCH;
                f.reason = R_RELATED;
                f.basis = s.basis;
                f.derivedFrom = _key(origin);
                // The relation is read now and may end at any time: the result is for this call.
                return;
            }
            if (s.result == Match.UNDETERMINED) undetermined = true;
        }
        if (complete && !undetermined) {
            f.result = Match.NO_MATCH;
            f.reason = R_NOT_RELATED;
        } else {
            f.reason = R_RELATION_INCOMPLETE;
        }
    }

    // ------------------------------------------------------------ internals

    function _key(SubjectRef memory s) private pure returns (bytes32) {
        return keccak256(abi.encode(s.kind, s.chainId, s.namespace, s.id));
    }

    function _isLocalAccount(SubjectRef memory s) private view returns (bool) {
        return s.kind == KIND_ACCOUNT && s.chainId == block.chainid && s.namespace == address(0)
            && uint256(s.id) <= type(uint160).max;
    }

    /// @dev Code hash of an account subject. An account without code, whether or not it exists yet,
    /// has the hash of the empty byte string.
    function _codeHash(SubjectRef memory s) private view returns (bytes32 h) {
        h = address(uint160(uint256(s.id))).codehash;
        if (h == bytes32(0)) h = EMPTY_CODE_HASH;
    }

    function _criteriaId(Criteria memory c) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                CRITERIA_TAG, block.chainid, c.documentHash, c.module, c.moduleCodeHash, c.moduleConfig, c.rule, c.fanout
            )
        );
    }

    function _state(bytes32 listId) private view returns (bytes32) {
        ListInfo storage l = _lists[listId];
        if (l.mode == Mode.NONE) return bytes32(0);
        bytes32 sourceState = l.mode == Mode.DERIVED ? _state(l.source) : bytes32(0);
        return keccak256(
            abi.encode(
                STATE_TAG, listId, l.revision, l.manager, l.closed, l.criteriaId, l.setRoot, l.sourcePin, sourceState
            )
        );
    }

    function _revise(bytes32 listId, ListInfo storage l) private {
        l.revision += 1;
        emit ListRevised(listId, l.revision, _state(listId));
    }

    function _setStatus(bytes32 listId, bytes32 subjectKey, EntryStatus from, EntryStatus to, bytes32 reason) private {
        ListInfo storage l = _lists[listId];
        Entry storage e = _entries[listId][subjectKey];
        if (e.status != from || from == EntryStatus.NONE) revert EntryNotFound();
        e.status = to;
        e.changedAt = uint64(block.timestamp);
        emit EntryStatusChanged(listId, subjectKey, e.serial, to, reason);
        _revise(listId, l);
    }

    function _requireCriteriaFit(Mode mode, bytes32 criteriaId) private view {
        if (criteriaId == bytes32(0)) {
            if (mode == Mode.PREDICATE) revert InvalidConfig();
            return;
        }
        if (!_criteriaKnown[criteriaId]) revert UnknownCriteria();
        Criteria storage c = _criteria[criteriaId];
        bool hasModule = c.module != address(0);
        if (mode == Mode.PREDICATE) {
            if (!hasModule || c.fanout != 0) revert InvalidConfig();
        } else if (mode == Mode.DERIVED) {
            if (hasModule != (c.fanout != 0)) revert InvalidConfig();
        } else if (hasModule) {
            revert InvalidConfig();
        }
    }

    /// @dev Whether the module is still the code and configuration the criteria were registered with.
    function _pinned(Criteria storage c) private view returns (bool) {
        address module = c.module;
        if (module.codehash != c.moduleCodeHash) return false;
        (bool ok, bytes32 config) = _configOf(module);
        return ok && config == c.moduleConfig;
    }

    function _configOf(address module) private view returns (bool ok, bytes32 config) {
        bytes memory out;
        (ok, out) = _query(module, abi.encodeCall(IAAFEvaluator.configHash, ()), 32);
        if (ok) config = abi.decode(out, (bytes32));
    }

    /// @dev Static call with bounded gas that succeeds only if exactly `size` bytes come back.
    function _query(address target, bytes memory data, uint256 size) private view returns (bool ok, bytes memory out) {
        out = new bytes(size);
        uint256 gasLimit = MODULE_GAS;
        assembly ("memory-safe") {
            ok := staticcall(gasLimit, target, add(data, 32), mload(data), add(out, 32), size)
            if iszero(eq(returndatasize(), size)) { ok := 0 }
        }
    }

    function _depthOf(uint64 size) private pure returns (uint256 depth) {
        while ((uint256(1) << depth) < size) ++depth;
    }

    function _leaf(uint256 index, bytes32 key) private pure returns (bytes32) {
        return keccak256(abi.encode(SET_LEAF_TAG, index, key));
    }

    function _rootOf(bytes32 node, uint256 index, bytes32[] memory path) private pure returns (bytes32) {
        for (uint256 i; i < path.length; ++i) {
            node = index & 1 == 0 ? keccak256(abi.encode(node, path[i])) : keccak256(abi.encode(path[i], node));
            index >>= 1;
        }
        return node;
    }
}
