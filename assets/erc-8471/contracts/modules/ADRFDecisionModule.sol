// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "../libraries/ADRFStore.sol";
import {ADRFModule} from "./ADRFModule.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFDecisionModule — round decisions and finality (module of the dispute registry)
/// @notice A round decision maps the decisive finding to the claim through the claim's own direction
///         (`supportsWhen`) and the method binding's burden rule; silence under the optimistic track adopts the
///         pre-accepted result and proves nothing; finality adopts a round under the policy's review mode and
///         writes the ruling (a review, which opens a new round, is in the resolution module). Nothing here
///         executes an effect.
contract ADRFDecisionModule is ADRFModule {
    constructor(IADRFPolicyRegistry policies_) ADRFModule(policies_) {}

    // ------------------------------------------------------------------ optimistic track

    /// Silence adopts the result the parties accepted in advance for silence; it proves nothing. The round
    /// record carries no support kinds and the reason SILENCE.
    function applySilence(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _admitted(caseId);
        T.CaseClock storage k = _s.clocks[caseId];
        if (k.answerDeadline == 0 || k.roundCount != 1) revert E.ADRF_NotOptimistic(caseId);
        if (k.answered) revert E.ADRF_AlreadyAnswered(caseId);
        if (S.now64() <= k.answerDeadline) revert E.ADRF_WindowOpen("answer");
        if (_s.findings[caseId][c.decisive].resolved) revert E.ADRF_AlreadyResolved(c.decisive);
        T.Track memory track = policies.trackOf(c.policyId);
        T.RoundRecord storage r = _s.rounds[caseId][1];
        r.result = track.silenceRule == T.SilenceRule.SUSTAIN ? T.SubstantiveResult.Sustained : T.SubstantiveResult.NotSustained;
        r.reason = T.Reason.SILENCE;
        r.at = S.now64();
        r.bySilence = true;
        afterRound(caseId, c, track);
    }

    // ------------------------------------------------------------------ decision and finality

    function decide(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _admitted(caseId);
        if (!_s.findings[caseId][c.decisive].resolved) revert E.ADRF_DecisiveUnresolved(caseId);
        T.Track memory track = policies.trackOf(c.policyId);
        decideRound(caseId, c);
        afterRound(caseId, c, track);
    }

    function expireDecision(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _admitted(caseId);
        if (S.now64() <= _s.clocks[caseId].decisionDeadline) revert E.ADRF_WindowOpen("decision");
        T.Track memory track = policies.trackOf(c.policyId);
        if (!_s.findings[caseId][c.decisive].resolved) {
            _record(caseId, c.decisive, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.TIMEOUT);
        }
        decideRound(caseId, c);
        afterRound(caseId, c, track);
    }

    function finalize(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (S.now64() <= _s.clocks[caseId].reviewOpenUntil) revert E.ADRF_WindowOpen("review");
        closeWithTrack(caseId, c, policies.trackOf(c.policyId), T.Reason.REVIEW_LAPSED);
    }

    function enforceDeadline(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted && c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (S.now64() <= _s.clocks[caseId].hardDeadline) revert E.ADRF_WindowOpen("hard deadline");
        if (c.state == T.ProcedureState.Admitted) {
            if (!_s.findings[caseId][c.decisive].resolved) {
                _record(caseId, c.decisive, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.TIMEOUT);
            }
            decideRound(caseId, c);
        }
        closeWithTrack(caseId, c, policies.trackOf(c.policyId), T.Reason.TIMEOUT);
    }

    // ------------------------------------------------------------------ internals

    /// Union of the support kinds of a finding and of its transitive premises. Provenance only: it names the
    /// sources the result cites and confers no proof on the derived result.
    function provenance(bytes32 caseId, uint32 sq, uint256 depth) internal view returns (uint8 kinds) {
        kinds = _s.findings[caseId][sq].supportKinds;
        if (depth >= T.MAX_SUB_QUESTIONS) return kinds;
        uint32[] storage deps = _s.subs[caseId][sq].dependsOn;
        for (uint256 d = 0; d < deps.length; d++) kinds |= provenance(caseId, deps[d], depth + 1);
    }

    /// The claim's direction: Sustained iff the decisive finding has the value the claim named; NotSustained
    /// for the other determined value; an UNDETERMINED decisive finding follows the burden rule of its method
    /// binding (NotSustained with BURDEN_NOT_MET, or NoDecision with the finding's reason).
    function decideRound(bytes32 caseId, T.CaseHeader storage c) internal {
        T.Finding storage f = _s.findings[caseId][c.decisive];
        T.RoundRecord storage r = _s.rounds[caseId][_s.clocks[caseId].roundCount];
        if (f.value == c.supportsWhen) {
            r.result = T.SubstantiveResult.Sustained;
            r.reason = T.Reason.NONE;
        } else if (f.value != T.Value.UNDETERMINED) {
            r.result = T.SubstantiveResult.NotSustained;
            r.reason = T.Reason.NONE;
        } else if (_s.subs[caseId][c.decisive].onUndetermined == T.OnUndetermined.NOT_SUSTAINED) {
            r.result = T.SubstantiveResult.NotSustained;
            r.reason = T.Reason.BURDEN_NOT_MET;
        } else {
            r.result = T.SubstantiveResult.NoDecision;
            r.reason = f.reason;
        }
        r.at = S.now64();
        r.bySilence = false;
        r.supportKinds = provenance(caseId, c.decisive, 0);
        r.decisiveValue = f.value;
        r.judgment = f.source;
    }

    function afterRound(bytes32 caseId, T.CaseHeader storage c, T.Track memory track) internal {
        T.CaseClock storage k = _s.clocks[caseId];
        T.RoundRecord storage r = _s.rounds[caseId][k.roundCount];
        uint64 until = 0;
        if (k.reviewsUsed < track.maxReviews) {
            until = S.now64() + track.reviewWindow;
            if (until > k.hardDeadline) until = k.hardDeadline;
        }
        emit RoundDecided(caseId, k.roundCount, r.result, r.reason, r.bySilence, until);
        if (until > S.now64()) {
            k.reviewOpenUntil = until;
            c.state = T.ProcedureState.Provisional;
        } else {
            closeWithTrack(caseId, c, track, T.Reason.NONE);
        }
    }

    /// Adoption rule, then the terminal record. PRESERVE_UNLESS_OVERTURNED adopts the most recent round with a
    /// substantive result; REQUIRE_FRESH_DECISION adopts the last round only. A case that never produced a
    /// substantive result and closed by the hard deadline is Expired; every other closure is Final.
    function closeWithTrack(bytes32 caseId, T.CaseHeader storage c, T.Track memory track, T.Reason closure) internal {
        T.CaseClock storage k = _s.clocks[caseId];
        uint32 last = k.roundCount;
        uint32 adopted = last;
        bool anySubstantive = false;
        if (track.reviewMode == T.ReviewMode.PRESERVE_UNLESS_OVERTURNED) {
            for (uint32 rr = last; rr >= 1; rr--) {
                T.SubstantiveResult res = _s.rounds[caseId][rr].result;
                if (res == T.SubstantiveResult.Sustained || res == T.SubstantiveResult.NotSustained) {
                    adopted = rr;
                    anySubstantive = true;
                    break;
                }
            }
        } else {
            T.SubstantiveResult res = _s.rounds[caseId][last].result;
            anySubstantive = res == T.SubstantiveResult.Sustained || res == T.SubstantiveResult.NotSustained;
        }
        T.RoundRecord storage a = _s.rounds[caseId][adopted];
        T.Ruling storage u = _s.rulings[caseId];
        u.result = anySubstantive ? a.result : T.SubstantiveResult.NoDecision;
        u.reason = anySubstantive ? a.reason : _s.rounds[caseId][last].reason;
        u.closure = closure;
        u.effectClass = c.effectClass;
        u.decidedAt = a.at;
        u.finalAt = S.now64();
        u.roundCount = last;
        u.sourceRound = adopted;
        u.adoptedFromEarlierRound = anySubstantive && adopted < last;
        u.bySilence = anySubstantive && a.bySilence;
        u.supportKinds = anySubstantive ? a.supportKinds : 0;
        u.policyId = c.policyId;
        u.bindingId = c.bindingId;
        u.source = c.source;
        u.proposition = c.proposition;
        u.judgment = a.judgment;
        if (c.effectClass == T.EffectClass.Binding) {
            if (u.result == T.SubstantiveResult.Sustained) u.allowedEffect = c.effectOnSustained;
            else if (u.result == T.SubstantiveResult.NotSustained) u.allowedEffect = c.effectOnNotSustained;
        }
        if (u.result == T.SubstantiveResult.NoDecision) u.fallbackRef = c.fallbackRef;

        bool expired = !anySubstantive && closure == T.Reason.TIMEOUT;
        c.state = expired ? T.ProcedureState.Expired : T.ProcedureState.Final;
        u.state = c.state;
        k.reviewOpenUntil = 0;
        if (c.exclusivityKey != bytes32(0)) {
            _s.finalCase[c.exclusivityKey] = caseId;
            if (_s.activeCase[c.exclusivityKey] == caseId) delete _s.activeCase[c.exclusivityKey];
        }
        emit CaseFinalized(caseId, c.state, u.result, u.reason, adopted, u.adoptedFromEarlierRound);
    }
}
