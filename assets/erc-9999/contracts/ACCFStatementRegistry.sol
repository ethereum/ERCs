// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "./interfaces/ACCFTypes.sol";
import {IACCFUnits} from "./interfaces/IACCFUnits.sol";
import {IACCFProfiles} from "./interfaces/IACCFProfiles.sol";
import {IACCFStatements} from "./interfaces/IACCFStatements.sol";
import {IACCFEvidenceAdapter} from "./interfaces/IACCFEvidenceAdapter.sol";
import {ACCFErrors} from "./ACCFErrors.sol";

/// @title ACCFStatementRegistry
/// @notice Reference registry of Completeness Statements and evaluation policies, with the derived view.
/// @dev    Cell completeness is computed on every call from the statements, the unit's current record and
///         the consumer's policy. Nothing here stores a completeness result.
contract ACCFStatementRegistry is IACCFStatements, ACCFErrors {
    uint256 private constant MAX_REFERENCES = 8;
    uint256 private constant MAX_ASSESSORS = 16;
    uint256 private constant MAX_METHODS = 16;
    /// @dev Gas given to one adapter call, gas the evaluation keeps for itself, and the only answer size
    ///      accepted. A call that cannot be given its budget, fails, or answers otherwise is an adapter error.
    uint256 public constant ADAPTER_GAS = 200_000;
    uint256 public constant ADAPTER_RESERVE = 60_000;
    uint32 private constant SNAPSHOT_ONLY = T.FLAG_EVIDENCE_UNVERIFIED;
    uint8 private constant STATES_ALLOWED = 0x1e; // Active, Degraded, Suspended, Maintenance

    uint8 private constant R_UNDETERMINED = uint8(T.Result.Undetermined);
    uint8 private constant R_SATISFIED = uint8(T.Result.Satisfied);
    uint8 private constant R_NOT_SATISFIED = uint8(T.Result.NotSatisfied);
    uint8 private constant R_NOT_APPLICABLE = uint8(T.Result.NotApplicable);

    IACCFUnits private immutable _unitRegistry;
    IACCFProfiles private immutable _profileRegistry;

    mapping(bytes32 => T.Statement) private _statements;
    mapping(bytes32 => T.EvidenceRef[]) private _references;
    mapping(bytes32 => mapping(bytes32 => mapping(address => mapping(uint256 => bytes32)))) private _latest;
    mapping(bytes32 => T.Policy) private _policies;
    mapping(address => uint256) private _statementNonces;
    uint256 private _policyNonce;

    /// @dev What one evaluation reads repeatedly, with the classification of the last statement seen.
    struct Context {
        bytes32 unitId;
        bytes32 profileId;
        uint48 timepoint;
        uint48 maxAge;
        uint48 authorizationExpiry;
        bool liveEvidence;
        bytes32[] methods;
        bytes32 lastId;
        uint32 lastFlags;
        bytes32 receipt; // running commitment to every statement read and its classification
    }

    constructor(address unitRegistry, address profileRegistry) {
        _unitRegistry = IACCFUnits(unitRegistry);
        _profileRegistry = IACCFProfiles(profileRegistry);
    }

    // ---------------------------------------------------------------------
    // Clock and introspection
    // ---------------------------------------------------------------------

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACCFStatements).interfaceId || interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0xda287a1d; // ERC-6372
    }

    function units() external view returns (address) {
        return address(_unitRegistry);
    }

    function profiles() external view returns (address) {
        return address(_profileRegistry);
    }

    // ---------------------------------------------------------------------
    // Statements
    // ---------------------------------------------------------------------

    function issue(T.StatementInput calldata input) public returns (bytes32 statementId) {
        T.Unit memory u = _unitRegistry.unitOf(input.unitId);
        if (u.state == T.OperatingState.Retired) revert Retired(input.unitId);
        if (input.coverage == 0) revert EmptyCoverage();
        (uint256 required, bool allConditional) =
            _profileRegistry.resolveCoverage(input.profileId, input.axis, input.coverage);

        uint256 dependencies = input.dependencies;
        if (dependencies & ~T.DEPENDENCY_MASK != 0) revert InvalidDependencies(dependencies);
        // an assessor may depend on more than the requirements ask for, never on less
        if (dependencies & required != required) revert DependencyOmitted(required, dependencies);
        if (input.result == T.Result.NotApplicable && !allConditional) revert NotApplicableRefused();
        if (input.result == T.Result.Satisfied) {
            uint256 missing = _unitRegistry.dependencyClosure(input.unitId, dependencies) & T.ENTRY_MASK & ~u.entries;
            if (missing != 0) revert EntryMissing(missing);
        }
        // the statement is about the state the assessor assessed, or it is not recorded
        bytes32 digest = _unitRegistry.dependencyDigest(input.unitId, dependencies);
        if (digest != input.expectedDigest) revert StateChanged(input.expectedDigest, digest);

        uint48 timepoint = clock();
        if (input.observedFrom > input.observedTo || input.observedTo > timepoint) revert InvalidWindow();
        // a derived unit has no history before its derivation
        if (u.bornAt != 0 && input.observedFrom < u.bornAt) revert WindowPrecedesUnit(input.observedFrom, u.bornAt);
        if (input.validUntil <= timepoint) revert InvalidValidity();
        if (input.evidenceHash == bytes32(0)) revert DetailsRequired();
        if (input.refs.length > MAX_REFERENCES) revert TooManyReferences();
        if (input.supersedes != bytes32(0)) {
            T.Statement storage old = _statements[input.supersedes];
            if (old.assessor != msg.sender || old.unitId != input.unitId || old.profileId != input.profileId) {
                revert InvalidSupersedes(input.supersedes);
            }
        }

        statementId = keccak256(abi.encode(block.chainid, address(this), msg.sender, ++_statementNonces[msg.sender]));
        T.Statement storage s = _statements[statementId];
        s.unitId = input.unitId;
        s.profileId = input.profileId;
        s.assessor = msg.sender;
        s.axis = input.axis;
        s.result = input.result;
        s.issuedAt = timepoint;
        s.manifestVersion = u.manifestVersion;
        s.boundaryVersion = u.boundaryVersion;
        s.controlVersion = u.controlVersion;
        s.observedFrom = input.observedFrom;
        s.observedTo = input.observedTo;
        s.validUntil = input.validUntil;
        s.coverage = input.coverage;
        s.dependencies = dependencies;
        s.dependencyDigest = digest;
        s.manifestRoot = u.manifestRoot;
        s.methodId = input.methodId;
        s.evidenceHash = input.evidenceHash;
        s.supersedes = input.supersedes;

        // the statement becomes this assessor's latest word on every requirement it covers
        mapping(uint256 => bytes32) storage latest = _latest[input.unitId][input.profileId][msg.sender];
        for (uint256 i = 0; input.coverage >> i != 0; ++i) {
            if ((input.coverage >> i) & 1 == 1) latest[i] = statementId;
        }
        _emitIssued(statementId, input, s.dependencyDigest);
        for (uint256 i = 0; i < input.refs.length; ++i) {
            T.EvidenceRef calldata r = input.refs[i];
            _references[statementId].push(r);
            emit EvidenceReferenced(statementId, r.adapter, r.source, r.recordId, r.commitment, r.dynamic);
        }
    }

    function issueBatch(T.StatementInput[] calldata inputs) external returns (bytes32[] memory statementIds) {
        statementIds = new bytes32[](inputs.length);
        for (uint256 i = 0; i < inputs.length; ++i) {
            statementIds[i] = issue(inputs[i]);
        }
    }

    function revoke(bytes32 statementId, bytes32 reasonHash) external {
        T.Statement storage s = _statements[statementId];
        if (s.assessor == address(0)) revert UnknownStatement(statementId);
        if (s.assessor != msg.sender) revert NotAssessor(statementId, msg.sender);
        if (s.revokedAt != 0) revert AlreadyRevoked(statementId);
        s.revokedAt = clock();
        s.revocationReason = reasonHash;
        emit StatementRevoked(statementId, msg.sender, reasonHash);
    }

    // ---------------------------------------------------------------------
    // Policies
    // ---------------------------------------------------------------------

    function registerPolicy(T.PolicyInput calldata input) external returns (bytes32 policyId) {
        if (!_profileRegistry.profileExists(input.profileId)) revert UnknownProfile(input.profileId);
        uint256 count = input.assessors.length;
        if (count == 0 || count > MAX_ASSESSORS || input.methods.length > MAX_METHODS) revert InvalidPolicy();
        if (input.mixing > T.MIX_PER_REQUIREMENT || input.conflictRule > T.CONFLICT_UNANIMOUS) revert InvalidPolicy();
        if (input.acceptedStates == 0 || input.acceptedStates & ~STATES_ALLOWED != 0) revert InvalidPolicy();

        policyId = keccak256(abi.encode(block.chainid, address(this), "policy", msg.sender, ++_policyNonce));
        T.Policy storage p = _policies[policyId];
        p.owner = msg.sender;
        p.profileId = input.profileId;
        p.maxAge = input.maxAge;
        p.mixing = input.mixing;
        p.conflictRule = input.conflictRule;
        p.acceptedStates = input.acceptedStates;
        p.liveEvidence = input.liveEvidence;
        p.contentHash = input.contentHash;
        for (uint256 i = 0; i < count; ++i) {
            T.AssessorRule calldata rule = input.assessors[i];
            if (rule.assessor == address(0) || rule.axes == 0 || rule.axes > 7) revert InvalidPolicy();
            for (uint256 j = 0; j < i; ++j) {
                if (input.assessors[j].assessor == rule.assessor) revert InvalidPolicy();
            }
            p.assessors.push(rule);
        }
        for (uint256 i = 0; i < input.methods.length; ++i) {
            p.methods.push(input.methods[i]);
        }
        emit PolicyRegistered(policyId, msg.sender, input.profileId, input);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function statementOf(bytes32 statementId) external view returns (T.Statement memory) {
        if (_statements[statementId].assessor == address(0)) revert UnknownStatement(statementId);
        return _statements[statementId];
    }

    function evidenceOf(bytes32 statementId) external view returns (T.EvidenceRef[] memory) {
        return _references[statementId];
    }

    function latestOf(bytes32 unitId, bytes32 profileId, address assessor, uint256 index)
        external
        view
        returns (bytes32)
    {
        return _latest[unitId][profileId][assessor][index];
    }

    function policyOf(bytes32 policyId) external view returns (T.Policy memory) {
        if (_policies[policyId].owner == address(0)) revert UnknownPolicy(policyId);
        return _policies[policyId];
    }

    function applicability(bytes32 statementId, bool liveEvidence) external view returns (bool applicable, uint32 flags) {
        T.Statement storage s = _statements[statementId];
        if (s.assessor == address(0)) revert UnknownStatement(statementId);
        Context memory c;
        c.unitId = s.unitId;
        c.timepoint = clock();
        c.authorizationExpiry = _unitRegistry.unitOf(s.unitId).authorizationExpiry;
        c.liveEvidence = liveEvidence;
        flags = _classify(c, statementId, s);
        applicable = flags & ~SNAPSHOT_ONLY == 0;
    }

    function isCellComplete(bytes32 unitId, bytes32 policyId) external view returns (bool) {
        return evaluate(unitId, policyId).cellComplete;
    }

    function evaluate(bytes32 unitId, bytes32 policyId) public view returns (T.Evaluation memory ev) {
        T.Policy storage p = _policies[policyId];
        if (p.owner == address(0)) revert UnknownPolicy(policyId);
        T.Unit memory u = _unitRegistry.unitOf(unitId);
        T.Profile memory pf = _profileRegistry.profileOf(p.profileId);

        ev.timepoint = clock();
        ev.state = u.state;
        ev.baseline = pf.baseline;
        ev.stateAccepted = (p.acceptedStates >> uint8(u.state)) & 1 == 1;
        uint32 flags;
        if (!ev.stateAccepted) flags |= T.FLAG_STATE;
        if (!pf.baseline) flags |= T.FLAG_NOT_BASELINE;
        if (pf.deprecated) flags |= T.FLAG_PROFILE_DEPRECATED;

        Context memory c;
        c.unitId = unitId;
        c.profileId = p.profileId;
        c.timepoint = ev.timepoint;
        c.maxAge = p.maxAge;
        c.authorizationExpiry = u.authorizationExpiry;
        c.liveEvidence = p.liveEvidence;
        c.methods = p.methods;

        // results[k][i]: what assessor k's latest applicable statement says about requirement i
        uint256 assessors = p.assessors.length;
        uint8[][] memory results = new uint8[][](assessors);
        uint8[] memory accepted = new uint8[](assessors);
        uint256 supported;
        for (uint256 k = 0; k < assessors; ++k) {
            T.AssessorRule memory rule = p.assessors[k];
            accepted[k] = rule.axes;
            results[k] = new uint8[](pf.count);
            for (uint256 i = 0; i < pf.count; ++i) {
                if ((rule.axes >> _axisOf(pf.axisMasks, i)) & 1 == 0) continue;
                (uint8 r, uint32 f) = _resultOf(c, k, rule.assessor, i);
                flags |= f;
                results[k][i] = r;
                if (r == R_SATISFIED || r == R_NOT_APPLICABLE) supported |= uint256(1) << i;
            }
        }
        ev.open = (pf.axisMasks[0] | pf.axisMasks[1] | pf.axisMasks[2]) & ~supported;

        bool conflict;
        if (p.mixing == T.MIX_PER_REQUIREMENT) {
            for (uint8 axis = 0; axis < 3; ++axis) {
                (ev.axes[axis], conflict) = _axisPerRequirement(results, accepted, pf.axisMasks[axis], axis, p.conflictRule, conflict);
            }
            ev.overall = _fold3(ev.axes);
        } else {
            // folds[k][axis]: what assessor k's statements alone give for the axis
            uint8[3][] memory folds = new uint8[3][](assessors);
            for (uint256 k = 0; k < assessors; ++k) {
                for (uint8 axis = 0; axis < 3; ++axis) {
                    if ((accepted[k] >> axis) & 1 == 1) folds[k][axis] = _foldAxis(results[k], pf.axisMasks[axis]);
                }
            }
            uint8[] memory column = new uint8[](assessors);
            for (uint8 axis = 0; axis < 3; ++axis) {
                uint256 length;
                for (uint256 k = 0; k < assessors; ++k) {
                    if ((accepted[k] >> axis) & 1 == 1) column[length++] = folds[k][axis];
                }
                bool clash;
                uint8 r;
                (r, clash) = _combine(column, length, p.conflictRule);
                ev.axes[axis] = T.Result(r);
                if (p.mixing == T.MIX_PER_AXIS) conflict = conflict || clash;
            }
            if (p.mixing == T.MIX_PER_AXIS) {
                ev.overall = _fold3(ev.axes);
            } else {
                // one assessor has to support all three axes; the axes above are informative
                uint256 length;
                for (uint256 k = 0; k < assessors; ++k) {
                    if (accepted[k] == 7) column[length++] = _foldWhole(folds[k]);
                }
                uint8 r;
                (r, conflict) = _combine(column, length, p.conflictRule);
                ev.overall = T.Result(r);
            }
        }

        if (conflict) flags |= T.FLAG_CONFLICT;
        ev.flags = flags;
        // a snapshot whose dynamic evidence this evaluation did not verify is not reported as current
        ev.cellComplete = ev.overall == T.Result.Satisfied && ev.baseline && ev.stateAccepted
            && flags & T.FLAG_EVIDENCE_UNVERIFIED == 0;
        ev.receipt = keccak256(
            abi.encode(
                keccak256(
                    abi.encode(
                        unitId,
                        policyId,
                        p.profileId,
                        u.manifestRoot,
                        u.descriptorHash,
                        u.boundaryVersion,
                        u.controlVersion,
                        u.authorizationRevision,
                        u.manifestVersion,
                        u.state,
                        ev.timepoint
                    )
                ),
                c.receipt,
                ev.overall,
                ev.axes,
                flags
            )
        );
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _emitIssued(bytes32 statementId, T.StatementInput calldata input, bytes32 digest) private {
        emit StatementIssued(
            statementId,
            input.unitId,
            input.profileId,
            msg.sender,
            input.axis,
            input.result,
            input.coverage,
            input.dependencies,
            digest,
            input.methodId,
            input.observedFrom,
            input.observedTo,
            input.validUntil,
            input.evidenceHash,
            input.evidenceURI,
            input.supersedes
        );
    }

    /// @dev Result of the assessor at position `k` for requirement `index`: the result of its latest statement
    ///      when that statement is applicable, Undetermined otherwise, with the reason in the flags. A statement
    ///      that is applicable as a snapshot only keeps its result and reports that it is a snapshot.
    function _resultOf(Context memory c, uint256 k, address assessor, uint256 index)
        private
        view
        returns (uint8 result, uint32 flags)
    {
        bytes32 statementId = _latest[c.unitId][c.profileId][assessor][index];
        if (statementId != bytes32(0)) {
            T.Statement storage s = _statements[statementId];
            if (statementId == c.lastId) {
                flags = c.lastFlags;
            } else {
                flags = _classify(c, statementId, s);
                c.lastId = statementId;
                c.lastFlags = flags;
            }
            result = flags & ~SNAPSHOT_ONLY != 0 ? R_UNDETERMINED : uint8(s.result);
        }
        c.receipt = keccak256(abi.encode(c.receipt, k, index, statementId, flags, result));
    }

    /// @dev Zero when the statement can support a current judgment; otherwise the reasons it cannot.
    function _classify(Context memory c, bytes32 statementId, T.Statement storage s) private view returns (uint32 flags) {
        if (s.revokedAt != 0) flags |= T.FLAG_REVOKED;
        if (s.validUntil <= c.timepoint || (c.maxAge != 0 && uint256(s.issuedAt) + c.maxAge < c.timepoint)) {
            flags |= T.FLAG_STALE;
        }
        if (c.methods.length != 0) {
            bool found;
            for (uint256 i = 0; i < c.methods.length; ++i) {
                if (c.methods[i] == s.methodId) {
                    found = true;
                    break;
                }
            }
            if (!found) flags |= T.FLAG_METHOD;
        }
        if (_unitRegistry.dependencyDigest(c.unitId, s.dependencies) != s.dependencyDigest) flags |= T.FLAG_INAPPLICABLE;
        // a grant included in the authorization configuration has lapsed since it was granted
        if (
            s.dependencies & T.DEP_AUTHORIZATION != 0 && c.authorizationExpiry != 0
                && c.authorizationExpiry < c.timepoint
        ) flags |= T.FLAG_AUTHORIZATION_LAPSED;
        if (flags == 0) {
            if (c.liveEvidence) {
                flags = _probe(c, statementId);
            } else {
                T.EvidenceRef[] storage refs = _references[statementId];
                for (uint256 i = 0; i < refs.length; ++i) {
                    if (refs[i].dynamic) {
                        flags = T.FLAG_EVIDENCE_UNVERIFIED;
                        break;
                    }
                }
            }
        }
    }

    /// @dev Reads every referenced record through its adapter. A failed or malformed call is an adapter
    ///      error, which is neither support nor a finding against the unit.
    function _probe(Context memory c, bytes32 statementId) private view returns (uint32 flags) {
        T.EvidenceRef[] storage refs = _references[statementId];
        for (uint256 i = 0; i < refs.length; ++i) {
            T.EvidenceRef memory r = refs[i];
            (bool ok, uint256 status, uint256 validUntil) = _call(
                r.adapter,
                abi.encodeCall(
                    IACCFEvidenceAdapter.probe, (address(_unitRegistry), c.unitId, r.source, r.recordId, r.commitment)
                )
            );
            if (!ok || validUntil > type(uint48).max) {
                flags |= T.FLAG_ADAPTER_ERROR;
                continue;
            }
            if (status == uint256(T.ProbeStatus.Supported)) {
                if (validUntil != 0 && validUntil <= c.timepoint) flags |= T.FLAG_EVIDENCE_LAPSED;
            } else if (status == uint256(T.ProbeStatus.NotSupported)) {
                flags |= T.FLAG_EVIDENCE_LAPSED;
            } else if (status == uint256(T.ProbeStatus.Undetermined)) {
                flags |= T.FLAG_PROBE_UNDETERMINED;
            } else {
                flags |= T.FLAG_ADAPTER_ERROR;
            }
        }
    }

    /// @dev One adapter call with a fixed gas budget and a fixed answer size. Nothing beyond 64 bytes of the
    ///      answer is copied, and an adapter that uses up its budget cannot use up the evaluation's.
    function _call(address adapter, bytes memory payload)
        private
        view
        returns (bool ok, uint256 status, uint256 validUntil)
    {
        // The adapter gets its whole allowance or the evaluation stops: an adapter error never comes from the
        // caller's gas, so the result does not depend on how much gas the caller sent.
        if (gasleft() < ADAPTER_GAS + ADAPTER_GAS / 63 + ADAPTER_RESERVE) revert InsufficientGas();
        assembly ("memory-safe") {
            let out := mload(0x40)
            ok := staticcall(ADAPTER_GAS, adapter, add(payload, 32), mload(payload), out, 64)
            if iszero(eq(returndatasize(), 64)) { ok := 0 }
            status := mload(out)
            validUntil := mload(add(out, 32))
        }
    }

    function _axisOf(uint256[3] memory axisMasks, uint256 index) private pure returns (uint8) {
        uint256 bit = uint256(1) << index;
        if (axisMasks[0] & bit != 0) return 0;
        if (axisMasks[1] & bit != 0) return 1;
        return 2;
    }

    /// @dev One assessor's results over the requirements of an axis. An axis without requirements is
    ///      Undetermined: no profile can make an axis hold by leaving it empty.
    function _foldAxis(uint8[] memory results, uint256 mask) private pure returns (uint8) {
        if (mask == 0) return R_UNDETERMINED;
        bool undetermined;
        for (uint256 i = 0; mask >> i != 0; ++i) {
            if ((mask >> i) & 1 == 0) continue;
            uint8 r = results[i];
            if (r == R_NOT_SATISFIED) return R_NOT_SATISFIED;
            if (r == R_UNDETERMINED) undetermined = true;
        }
        return undetermined ? R_UNDETERMINED : R_SATISFIED;
    }

    function _axisPerRequirement(
        uint8[][] memory results,
        uint8[] memory accepted,
        uint256 mask,
        uint8 axis,
        uint8 rule,
        bool conflictSoFar
    ) private pure returns (T.Result, bool conflict) {
        conflict = conflictSoFar;
        if (mask == 0) return (T.Result.Undetermined, conflict);
        uint8[] memory column = new uint8[](accepted.length);
        bool undetermined;
        bool notSatisfied;
        for (uint256 i = 0; mask >> i != 0; ++i) {
            if ((mask >> i) & 1 == 0) continue;
            uint256 length;
            for (uint256 k = 0; k < accepted.length; ++k) {
                if ((accepted[k] >> axis) & 1 == 1) column[length++] = results[k][i];
            }
            (uint8 r, bool clash) = _combine(column, length, rule);
            conflict = conflict || clash;
            if (r == R_NOT_SATISFIED) notSatisfied = true;
            else if (r == R_UNDETERMINED) undetermined = true;
        }
        if (notSatisfied) return (T.Result.NotSatisfied, conflict);
        return (undetermined ? T.Result.Undetermined : T.Result.Satisfied, conflict);
    }

    /// @dev Combines what the accepted assessors say about one thing under the policy's conflict rule.
    function _combine(uint8[] memory values, uint256 length, uint8 rule) private pure returns (uint8, bool conflict) {
        bool positive;
        bool negative;
        bool undetermined;
        for (uint256 i = 0; i < length; ++i) {
            uint8 v = values[i];
            if (v == R_SATISFIED || v == R_NOT_APPLICABLE) {
                if (rule == T.CONFLICT_PRIORITY) return (R_SATISFIED, false);
                positive = true;
            } else if (v == R_NOT_SATISFIED) {
                if (rule == T.CONFLICT_PRIORITY) return (R_NOT_SATISFIED, false);
                negative = true;
            } else {
                undetermined = true;
            }
        }
        if (rule == T.CONFLICT_UNANIMOUS) {
            if (negative) return (R_NOT_SATISFIED, false);
            if (undetermined || !positive) return (R_UNDETERMINED, false);
            return (R_SATISFIED, false);
        }
        if (positive && negative) return (R_UNDETERMINED, true);
        if (negative) return (R_NOT_SATISFIED, false);
        if (positive) return (R_SATISFIED, false);
        return (R_UNDETERMINED, false);
    }

    function _foldWhole(uint8[3] memory axes) private pure returns (uint8) {
        if (axes[0] == R_NOT_SATISFIED || axes[1] == R_NOT_SATISFIED || axes[2] == R_NOT_SATISFIED) {
            return R_NOT_SATISFIED;
        }
        if (axes[0] == R_SATISFIED && axes[1] == R_SATISFIED && axes[2] == R_SATISFIED) return R_SATISFIED;
        return R_UNDETERMINED;
    }

    /// @dev The conjunction of the three axes. No axis offsets another.
    function _fold3(T.Result[3] memory axes) private pure returns (T.Result) {
        return T.Result(_foldWhole([uint8(axes[0]), uint8(axes[1]), uint8(axes[2])]));
    }
}
