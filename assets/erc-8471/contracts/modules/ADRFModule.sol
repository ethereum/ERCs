// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "../libraries/ADRFStore.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFStorage — the one storage layout of the dispute registry, shared with its modules
/// @notice The registry and every module inherit this contract first, so that the record lives at the same
///         slots in all of them; a module's code runs on the registry's storage by delegatecall and never on
///         its own.
abstract contract ADRFStorage {
    S.Data internal _s;
}

/// @title  ADRFEvents — the events of IADRFDisputeRegistry, declared once for the registry and its modules
/// @notice A module emits under the registry's address (it runs by delegatecall), so the registry's log is
///         the one log of the record whichever module wrote the entry.
abstract contract ADRFEvents {
    event BindingRegistered(bytes32 indexed bindingId, address indexed source, bytes32 indexed policyId, T.AcceptanceMode mode, bytes32 scopeKey);
    event BindingRevoked(bytes32 indexed bindingId, address indexed source);

    event CaseFiled(bytes32 indexed caseId, bytes32 indexed policyId, bytes32 indexed bindingId, address claimant, address respondent, bytes32 proposition);
    event CaseAdmitted(bytes32 indexed caseId, T.EffectClass effectClass, uint64 admittedAt, uint64 decisionDeadline, uint64 hardDeadline);
    event CaseNotAdmitted(bytes32 indexed caseId, T.Reason reason);
    event CaseDowngraded(bytes32 indexed caseId, T.Reason reason);
    event CaseAccepted(bytes32 indexed caseId, address indexed respondent);
    event CaseWithdrawn(bytes32 indexed caseId);
    event CaseAnswered(bytes32 indexed caseId, address indexed respondent);

    event EvidenceSubmitted(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed party, bytes32 commitment, string uri);
    event JudgmentOpened(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed method, bytes32 handle);
    event FindingRecorded(bytes32 indexed caseId, uint32 indexed subQuestion, uint32 round, T.Value value, uint8 supportKinds, T.Reason reason, address acceptedBy);
    event RoundDecided(bytes32 indexed caseId, uint32 indexed round, T.SubstantiveResult result, T.Reason reason, bool bySilence, uint64 reviewOpenUntil);
    event ReviewRequested(bytes32 indexed caseId, uint32 indexed newRound, uint8 reviewType, address indexed by);
    event CaseFinalized(bytes32 indexed caseId, T.ProcedureState state, T.SubstantiveResult result, T.Reason reason, uint32 sourceRound, bool adoptedFromEarlierRound);

    event EnactmentReported(bytes32 indexed caseId, bytes32 indexed effectId, address indexed reporter, T.EnactmentStatus status, bytes32 ref);
    event LeadReported(bytes32 indexed objectKey, address indexed reporter, bytes32 commitment, string uri);
}

/// @title  ADRFModule — base of the dispute registry's modules
/// @notice A module holds one group of the registry's state-changing functions (the registry routes each
///         function of IADRFDisputeRegistry that it does not implement itself to one module by delegatecall,
///         with the original calldata and the original `msg.sender`). The split keeps every deployable unit
///         well within the per-transaction gas limits of current networks; it changes neither the interface
///         nor any identifier nor the record. Each module pins the policy registry it was built for, and the
///         registry refuses a module built for another; a module refuses to run on its own storage.
abstract contract ADRFModule is ADRFStorage, ADRFEvents {
    IADRFPolicyRegistry public immutable policies;
    address private immutable __self;

    constructor(IADRFPolicyRegistry policies_) {
        policies = policies_;
        __self = address(this);
    }

    /// Every entry point runs only under the registry's delegatecall, never directly on the module.
    modifier delegated() {
        if (address(this) == __self) revert E.ADRF_DirectCall();
        _;
    }

    // ------------------------------------------------------------------ shared internals

    function _admitted(bytes32 caseId) internal view returns (T.CaseHeader storage c) {
        c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted) revert E.ADRF_WrongState(caseId, uint8(c.state));
    }

    /// Opens the procedure: the clocks of the first round, the optimistic answer window when the track has
    /// one, the state Admitted.
    function _admit(bytes32 caseId, T.Track memory track) internal {
        T.CaseHeader storage c = _s.cases[caseId];
        T.CaseClock storage k = _s.clocks[caseId];
        uint64 t = S.now64();
        k.admittedAt = t;
        k.evidenceCloseAt = t + track.evidenceWindow;
        k.decisionDeadline = t + track.decisionWindow;
        k.hardDeadline = t + track.maxTotalDuration;
        k.roundCount = 1;
        if (track.optimistic) k.answerDeadline = t + track.answerWindow;
        c.state = T.ProcedureState.Admitted;
        emit CaseAdmitted(caseId, c.effectClass, t, k.decisionDeadline, k.hardDeadline);
    }

    function _releaseActive(T.CaseHeader storage c, bytes32 caseId) internal {
        if (c.exclusivityKey != bytes32(0) && _s.activeCase[c.exclusivityKey] == caseId) {
            delete _s.activeCase[c.exclusivityKey];
        }
    }

    /// Writes a finding: what was decided, by which method, with which support kinds, in which round.
    function _record(bytes32 caseId, uint32 sq, T.Value value, uint8 kinds, bytes32 resultHash, address acceptedBy, T.Reason reason)
        internal
    {
        T.Finding storage f = _s.findings[caseId][sq];
        f.resolved = true;
        f.value = value;
        f.supportKinds = kinds;
        f.resultHash = resultHash;
        f.acceptedBy = acceptedBy;
        f.reason = reason;
        f.round = _s.clocks[caseId].roundCount;
        f.at = S.now64();
        emit FindingRecorded(caseId, sq, f.round, value, kinds, reason, acceptedBy);
    }
}
