// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "../libraries/ADRFStore.sol";
import {ADRFModule} from "./ADRFModule.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";
import {IADRFVerifier} from "../interfaces/IADRFVerifier.sol";
import {IADRFEvidenceRule} from "../interfaces/IADRFEvidenceRule.sol";
import {IADRFJudgmentMethod} from "../interfaces/IADRFJudgmentMethod.sol";

/// @title  ADRFResolutionModule — the answer, the resolution of sub-questions and reviews (module of the dispute registry)
/// @notice Sub-questions are resolved by their bound methods in the order their dependency table allows; a
///         finding records what was decided, by which method, with which support kinds, and on which premises.
///         A formal question runs a verifier over inputs pinned at filing (support `computed`); a question of
///         fact runs an evidence rule (support as the rule declares, never `judged`); a question of judgment is
///         opened with a judgment method, which records the finding it imports (support `judged`). A review
///         resets the targeted sub-questions and their dependents and opens a new round.
contract ADRFResolutionModule is ADRFModule {
    constructor(IADRFPolicyRegistry policies_) ADRFModule(policies_) {}

    // ------------------------------------------------------------------ optimistic track

    function answer(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _admitted(caseId);
        T.CaseClock storage k = _s.clocks[caseId];
        if (k.answerDeadline == 0) revert E.ADRF_NotOptimistic(caseId);
        if (msg.sender != c.respondent) revert E.ADRF_NotRespondent(msg.sender);
        if (k.answered) revert E.ADRF_AlreadyAnswered(caseId);
        if (S.now64() > k.answerDeadline) revert E.ADRF_WindowClosed("answer");
        k.answered = true;
        emit CaseAnswered(caseId, msg.sender);
    }

    // ------------------------------------------------------------------ resolution

    function resolveFormal(bytes32 caseId, uint32 sq, bytes calldata inputs) external delegated {
        T.SubQuestion storage q = resolvable(caseId, sq, T.QuestionType.FORMAL);
        if (premiseFailed(caseId, sq)) {
            _record(caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        if (keccak256(inputs) != q.inputsHash) revert E.ADRF_InputsMismatch(sq);
        (T.Value value, bytes32 resultHash) = IADRFVerifier(q.method).verify(q.proposition, q.params, inputs);
        _record(caseId, sq, value, T.SUPPORT_COMPUTED, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
    }

    function resolveEvidenced(bytes32 caseId, uint32 sq, bytes calldata bundle) external delegated {
        T.SubQuestion storage q = resolvable(caseId, sq, T.QuestionType.EVIDENCED);
        if (premiseFailed(caseId, sq)) {
            _record(caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        (T.Value value, bytes32 resultHash, uint8 kinds) =
            IADRFEvidenceRule(q.method).evaluate(caseId, sq, q.proposition, q.params, bundle);
        kinds &= ~T.SUPPORT_JUDGED; // an evidence rule does not form a judgment
        _record(caseId, sq, value, kinds, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
    }

    function openJudgment(bytes32 caseId, uint32 sq) external delegated {
        T.SubQuestion storage q = resolvable(caseId, sq, T.QuestionType.JUDGED);
        if (q.handle != bytes32(0)) revert E.ADRF_JudgmentAlreadyOpened(sq);
        if (premiseFailed(caseId, sq)) {
            _record(caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        bytes32 handle = IADRFJudgmentMethod(q.method).open(caseId, sq, q.proposition, q.params, _s.clocks[caseId].decisionDeadline);
        if (handle == bytes32(0)) revert E.ADRF_JudgmentNotOpened(sq);
        q.handle = handle;
        emit JudgmentOpened(caseId, sq, q.method, handle);
    }

    function recordJudgedFinding(bytes32 caseId, uint32 sq, T.Value value, bytes32 resultHash, T.JudgmentSource calldata source)
        external delegated
    {
        T.SubQuestion storage q = resolvable(caseId, sq, T.QuestionType.JUDGED);
        if (msg.sender != q.method) revert E.ADRF_NotMethod(msg.sender);
        if (q.handle == bytes32(0)) revert E.ADRF_JudgmentNotOpened(sq);
        _record(caseId, sq, value, T.SUPPORT_JUDGED, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
        _s.findings[caseId][sq].source = source;
    }

    // ------------------------------------------------------------------ review

    function requestReview(bytes32 caseId, uint8 reviewType, uint32[] calldata targets) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        T.CaseClock storage k = _s.clocks[caseId];
        if (msg.sender != c.claimant && msg.sender != c.respondent) revert E.ADRF_NotParty(msg.sender);
        if (S.now64() > k.reviewOpenUntil) revert E.ADRF_WindowClosed("review");
        T.Track memory track = policies.trackOf(c.policyId);
        if (reviewType == 0 || (reviewType & (reviewType - 1)) != 0 || (track.reviewTypes & reviewType) == 0) revert E.ADRF_ReviewNotAllowed("type");
        if (k.reviewsUsed >= track.maxReviews) revert E.ADRF_ReviewNotAllowed("reviews exhausted");
        if (targets.length == 0) revert E.ADRF_ReviewNotAllowed("no target");
        uint256 n = c.subQuestionCount;

        bool[] memory reset = new bool[](n);
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] >= n) revert E.ADRF_BadSubQuestions("index");
            reset[targets[i]] = true;
        }
        T.SubQuestion[] storage subs = _s.subs[caseId];
        for (uint256 pass = 0; pass < n; pass++) {
            bool changed = false;
            for (uint256 i = 0; i < n; i++) {
                if (reset[i]) continue;
                uint32[] storage deps = subs[i].dependsOn;
                for (uint256 d = 0; d < deps.length; d++) {
                    if (reset[deps[d]]) { reset[i] = true; changed = true; break; }
                }
            }
            if (!changed) break;
        }
        if (!reset[c.decisive]) revert E.ADRF_ReviewNotAllowed("decisive not targeted");

        for (uint256 i = 0; i < n; i++) {
            if (!reset[i]) continue;
            if (subs[i].qType == T.QuestionType.JUDGED && subs[i].handle != bytes32(0)) {
                IADRFJudgmentMethod(subs[i].method).review(caseId, uint32(i));
            }
            delete _s.findings[caseId][uint32(i)];
        }

        k.reviewsUsed += 1;
        k.roundCount += 1;
        uint64 deadline = S.now64() + track.decisionWindow;
        if (deadline > k.hardDeadline) deadline = k.hardDeadline;
        k.decisionDeadline = deadline;
        uint64 evidenceClose = S.now64() + track.evidenceWindow;
        k.evidenceCloseAt = evidenceClose > deadline ? deadline : evidenceClose;
        k.reviewOpenUntil = 0;
        c.state = T.ProcedureState.Admitted;
        emit ReviewRequested(caseId, k.roundCount, reviewType, msg.sender);
    }

    // ------------------------------------------------------------------ internals

    function resolvable(bytes32 caseId, uint32 sq, T.QuestionType qType) internal view returns (T.SubQuestion storage q) {
        T.CaseHeader storage c = _admitted(caseId);
        if (sq >= c.subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        if (S.now64() > _s.clocks[caseId].decisionDeadline) revert E.ADRF_WindowClosed("decision");
        q = _s.subs[caseId][sq];
        if (q.qType != qType) revert E.ADRF_WrongQuestionType(sq);
        if (_s.findings[caseId][sq].resolved) revert E.ADRF_AlreadyResolved(sq);
        for (uint256 d = 0; d < q.dependsOn.length; d++) {
            if (!_s.findings[caseId][q.dependsOn[d]].resolved) revert E.ADRF_PremisePending(sq, q.dependsOn[d]);
        }
    }

    /// True when a resolved premise has a value other than the required one: the sub-question is recorded
    /// UNDETERMINED with PREMISE_NOT_ESTABLISHED and its method is never run.
    function premiseFailed(bytes32 caseId, uint32 sq) internal view returns (bool) {
        T.SubQuestion storage q = _s.subs[caseId][sq];
        for (uint256 d = 0; d < q.dependsOn.length; d++) {
            if (_s.findings[caseId][q.dependsOn[d]].value != q.requiredValues[d]) return true;
        }
        return false;
    }
}
