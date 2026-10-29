// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "./ADRFStore.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";
import {IADRFVerifier} from "../interfaces/IADRFVerifier.sol";
import {IADRFEvidenceRule} from "../interfaces/IADRFEvidenceRule.sol";
import {IADRFJudgmentMethod} from "../interfaces/IADRFJudgmentMethod.sol";

/// @title  ADRFLifecycle — resolution, decision, review and finality (externally linked library of the dispute registry)
/// @notice Sub-questions are resolved by their bound methods in the order their dependency table allows; a
///         finding records what was decided, by which method, with which support kinds, and on which premises.
///         A round decision maps the decisive finding to the claim through the claim's own direction
///         (`supportsWhen`) and the method binding's burden rule; reviews open new rounds; finality adopts a
///         round under the policy's review mode and writes the ruling. Nothing here executes an effect.
library ADRFLifecycle {
    event CaseAnswered(bytes32 indexed caseId, address indexed respondent);
    event JudgmentOpened(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed method, bytes32 handle);
    event FindingRecorded(bytes32 indexed caseId, uint32 indexed subQuestion, uint32 round, T.Value value, uint8 supportKinds, T.Reason reason, address acceptedBy);
    event RoundDecided(bytes32 indexed caseId, uint32 indexed round, T.SubstantiveResult result, T.Reason reason, bool bySilence, uint64 reviewOpenUntil);
    event ReviewRequested(bytes32 indexed caseId, uint32 indexed newRound, uint8 reviewType, address indexed by);
    event CaseFinalized(bytes32 indexed caseId, T.ProcedureState state, T.SubstantiveResult result, T.Reason reason, uint32 sourceRound, bool adoptedFromEarlierRound);

    // ------------------------------------------------------------------ optimistic track

    function answer(S.Data storage s, bytes32 caseId, address sender) external {
        T.CaseHeader storage c = admitted(s, caseId);
        T.CaseClock storage k = s.clocks[caseId];
        if (k.answerDeadline == 0) revert E.ADRF_NotOptimistic(caseId);
        if (sender != c.respondent) revert E.ADRF_NotRespondent(sender);
        if (k.answered) revert E.ADRF_AlreadyAnswered(caseId);
        if (S.now64() > k.answerDeadline) revert E.ADRF_WindowClosed("answer");
        k.answered = true;
        emit CaseAnswered(caseId, sender);
    }

    /// Silence adopts the result the parties accepted in advance for silence; it proves nothing. The round
    /// record carries no support kinds and the reason SILENCE.
    function applySilence(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = admitted(s, caseId);
        T.CaseClock storage k = s.clocks[caseId];
        if (k.answerDeadline == 0 || k.roundCount != 1) revert E.ADRF_NotOptimistic(caseId);
        if (k.answered) revert E.ADRF_AlreadyAnswered(caseId);
        if (S.now64() <= k.answerDeadline) revert E.ADRF_WindowOpen("answer");
        if (s.findings[caseId][c.decisive].resolved) revert E.ADRF_AlreadyResolved(c.decisive);
        T.Track memory track = policies.trackOf(c.policyId);
        T.RoundRecord storage r = s.rounds[caseId][1];
        r.result = track.silenceRule == T.SilenceRule.SUSTAIN ? T.SubstantiveResult.Sustained : T.SubstantiveResult.NotSustained;
        r.reason = T.Reason.SILENCE;
        r.at = S.now64();
        r.bySilence = true;
        afterRound(s, caseId, c, track);
    }

    // ------------------------------------------------------------------ resolution

    function resolveFormal(S.Data storage s, bytes32 caseId, uint32 sq, bytes calldata inputs) external {
        T.SubQuestion storage q = resolvable(s, caseId, sq, T.QuestionType.FORMAL);
        if (premiseFailed(s, caseId, sq)) {
            record(s, caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        if (keccak256(inputs) != q.inputsHash) revert E.ADRF_InputsMismatch(sq);
        (T.Value value, bytes32 resultHash) = IADRFVerifier(q.method).verify(q.proposition, q.params, inputs);
        record(s, caseId, sq, value, T.SUPPORT_COMPUTED, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
    }

    function resolveEvidenced(S.Data storage s, bytes32 caseId, uint32 sq, bytes calldata bundle) external {
        T.SubQuestion storage q = resolvable(s, caseId, sq, T.QuestionType.EVIDENCED);
        if (premiseFailed(s, caseId, sq)) {
            record(s, caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        (T.Value value, bytes32 resultHash, uint8 kinds) =
            IADRFEvidenceRule(q.method).evaluate(caseId, sq, q.proposition, q.params, bundle);
        kinds &= ~T.SUPPORT_JUDGED; // an evidence rule does not form a judgment
        record(s, caseId, sq, value, kinds, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
    }

    function openJudgment(S.Data storage s, bytes32 caseId, uint32 sq) external {
        T.SubQuestion storage q = resolvable(s, caseId, sq, T.QuestionType.JUDGED);
        if (q.handle != bytes32(0)) revert E.ADRF_JudgmentAlreadyOpened(sq);
        if (premiseFailed(s, caseId, sq)) {
            record(s, caseId, sq, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.PREMISE_NOT_ESTABLISHED);
            return;
        }
        bytes32 handle = IADRFJudgmentMethod(q.method).open(caseId, sq, q.proposition, q.params, s.clocks[caseId].decisionDeadline);
        if (handle == bytes32(0)) revert E.ADRF_JudgmentNotOpened(sq);
        q.handle = handle;
        emit JudgmentOpened(caseId, sq, q.method, handle);
    }

    function recordJudgedFinding(S.Data storage s, bytes32 caseId, uint32 sq, T.Value value, bytes32 resultHash,
        T.JudgmentSource calldata source, address sender) external
    {
        T.SubQuestion storage q = resolvable(s, caseId, sq, T.QuestionType.JUDGED);
        if (sender != q.method) revert E.ADRF_NotMethod(sender);
        if (q.handle == bytes32(0)) revert E.ADRF_JudgmentNotOpened(sq);
        record(s, caseId, sq, value, T.SUPPORT_JUDGED, resultHash, q.method,
            value == T.Value.UNDETERMINED ? T.Reason.METHOD_UNDETERMINED : T.Reason.NONE);
        s.findings[caseId][sq].source = source;
    }

    // ------------------------------------------------------------------ decision, review and finality

    function decide(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = admitted(s, caseId);
        if (!s.findings[caseId][c.decisive].resolved) revert E.ADRF_DecisiveUnresolved(caseId);
        T.Track memory track = policies.trackOf(c.policyId);
        decideRound(s, caseId, c);
        afterRound(s, caseId, c, track);
    }

    function expireDecision(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = admitted(s, caseId);
        if (S.now64() <= s.clocks[caseId].decisionDeadline) revert E.ADRF_WindowOpen("decision");
        T.Track memory track = policies.trackOf(c.policyId);
        if (!s.findings[caseId][c.decisive].resolved) {
            record(s, caseId, c.decisive, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.TIMEOUT);
        }
        decideRound(s, caseId, c);
        afterRound(s, caseId, c, track);
    }

    function requestReview(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId, uint8 reviewType,
        uint32[] calldata targets, address sender) external
    {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        T.CaseClock storage k = s.clocks[caseId];
        if (sender != c.claimant && sender != c.respondent) revert E.ADRF_NotParty(sender);
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
        T.SubQuestion[] storage subs = s.subs[caseId];
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
            delete s.findings[caseId][uint32(i)];
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
        emit ReviewRequested(caseId, k.roundCount, reviewType, sender);
    }

    function finalize(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (S.now64() <= s.clocks[caseId].reviewOpenUntil) revert E.ADRF_WindowOpen("review");
        close(s, policies, caseId, c, T.Reason.REVIEW_LAPSED);
    }

    function enforceDeadline(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted && c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (S.now64() <= s.clocks[caseId].hardDeadline) revert E.ADRF_WindowOpen("hard deadline");
        if (c.state == T.ProcedureState.Admitted) {
            if (!s.findings[caseId][c.decisive].resolved) {
                record(s, caseId, c.decisive, T.Value.UNDETERMINED, 0, bytes32(0), address(0), T.Reason.TIMEOUT);
            }
            decideRound(s, caseId, c);
        }
        close(s, policies, caseId, c, T.Reason.TIMEOUT);
    }

    // ------------------------------------------------------------------ internals

    function admitted(S.Data storage s, bytes32 caseId) internal view returns (T.CaseHeader storage c) {
        c = s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted) revert E.ADRF_WrongState(caseId, uint8(c.state));
    }

    function resolvable(S.Data storage s, bytes32 caseId, uint32 sq, T.QuestionType qType)
        internal view returns (T.SubQuestion storage q)
    {
        T.CaseHeader storage c = admitted(s, caseId);
        if (sq >= c.subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        if (S.now64() > s.clocks[caseId].decisionDeadline) revert E.ADRF_WindowClosed("decision");
        q = s.subs[caseId][sq];
        if (q.qType != qType) revert E.ADRF_WrongQuestionType(sq);
        if (s.findings[caseId][sq].resolved) revert E.ADRF_AlreadyResolved(sq);
        for (uint256 d = 0; d < q.dependsOn.length; d++) {
            if (!s.findings[caseId][q.dependsOn[d]].resolved) revert E.ADRF_PremisePending(sq, q.dependsOn[d]);
        }
    }

    /// True when a resolved premise has a value other than the required one: the sub-question is recorded
    /// UNDETERMINED with PREMISE_NOT_ESTABLISHED and its method is never run.
    function premiseFailed(S.Data storage s, bytes32 caseId, uint32 sq) internal view returns (bool) {
        T.SubQuestion storage q = s.subs[caseId][sq];
        for (uint256 d = 0; d < q.dependsOn.length; d++) {
            if (s.findings[caseId][q.dependsOn[d]].value != q.requiredValues[d]) return true;
        }
        return false;
    }

    function record(S.Data storage s, bytes32 caseId, uint32 sq, T.Value value, uint8 kinds, bytes32 resultHash,
        address acceptedBy, T.Reason reason) internal
    {
        T.Finding storage f = s.findings[caseId][sq];
        f.resolved = true;
        f.value = value;
        f.supportKinds = kinds;
        f.resultHash = resultHash;
        f.acceptedBy = acceptedBy;
        f.reason = reason;
        f.round = s.clocks[caseId].roundCount;
        f.at = S.now64();
        emit FindingRecorded(caseId, sq, f.round, value, kinds, reason, acceptedBy);
    }

    /// Union of the support kinds of a finding and of its transitive premises. Provenance only: it names the
    /// sources the result cites and confers no proof on the derived result.
    function provenance(S.Data storage s, bytes32 caseId, uint32 sq, uint256 depth) internal view returns (uint8 kinds) {
        kinds = s.findings[caseId][sq].supportKinds;
        if (depth >= T.MAX_SUB_QUESTIONS) return kinds;
        uint32[] storage deps = s.subs[caseId][sq].dependsOn;
        for (uint256 d = 0; d < deps.length; d++) kinds |= provenance(s, caseId, deps[d], depth + 1);
    }

    /// The claim's direction: Sustained iff the decisive finding has the value the claim named; NotSustained
    /// for the other determined value; an UNDETERMINED decisive finding follows the burden rule of its method
    /// binding (NotSustained with BURDEN_NOT_MET, or NoDecision with the finding's reason).
    function decideRound(S.Data storage s, bytes32 caseId, T.CaseHeader storage c) internal {
        T.Finding storage f = s.findings[caseId][c.decisive];
        T.RoundRecord storage r = s.rounds[caseId][s.clocks[caseId].roundCount];
        if (f.value == c.supportsWhen) {
            r.result = T.SubstantiveResult.Sustained;
            r.reason = T.Reason.NONE;
        } else if (f.value != T.Value.UNDETERMINED) {
            r.result = T.SubstantiveResult.NotSustained;
            r.reason = T.Reason.NONE;
        } else if (s.subs[caseId][c.decisive].onUndetermined == T.OnUndetermined.NOT_SUSTAINED) {
            r.result = T.SubstantiveResult.NotSustained;
            r.reason = T.Reason.BURDEN_NOT_MET;
        } else {
            r.result = T.SubstantiveResult.NoDecision;
            r.reason = f.reason;
        }
        r.at = S.now64();
        r.bySilence = false;
        r.supportKinds = provenance(s, caseId, c.decisive, 0);
        r.decisiveValue = f.value;
        r.judgment = f.source;
    }

    function afterRound(S.Data storage s, bytes32 caseId, T.CaseHeader storage c, T.Track memory track) internal {
        T.CaseClock storage k = s.clocks[caseId];
        T.RoundRecord storage r = s.rounds[caseId][k.roundCount];
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
            closeWithTrack(s, caseId, c, track, T.Reason.NONE);
        }
    }

    function close(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId, T.CaseHeader storage c, T.Reason closure) internal {
        closeWithTrack(s, caseId, c, policies.trackOf(c.policyId), closure);
    }

    /// Adoption rule, then the terminal record. PRESERVE_UNLESS_OVERTURNED adopts the most recent round with a
    /// substantive result; REQUIRE_FRESH_DECISION adopts the last round only. A case that never produced a
    /// substantive result and closed by the hard deadline is Expired; every other closure is Final.
    function closeWithTrack(S.Data storage s, bytes32 caseId, T.CaseHeader storage c, T.Track memory track, T.Reason closure) internal {
        T.CaseClock storage k = s.clocks[caseId];
        uint32 last = k.roundCount;
        uint32 adopted = last;
        bool anySubstantive = false;
        if (track.reviewMode == T.ReviewMode.PRESERVE_UNLESS_OVERTURNED) {
            for (uint32 rr = last; rr >= 1; rr--) {
                T.SubstantiveResult res = s.rounds[caseId][rr].result;
                if (res == T.SubstantiveResult.Sustained || res == T.SubstantiveResult.NotSustained) {
                    adopted = rr;
                    anySubstantive = true;
                    break;
                }
            }
        } else {
            T.SubstantiveResult res = s.rounds[caseId][last].result;
            anySubstantive = res == T.SubstantiveResult.Sustained || res == T.SubstantiveResult.NotSustained;
        }
        T.RoundRecord storage a = s.rounds[caseId][adopted];
        T.Ruling storage u = s.rulings[caseId];
        u.result = anySubstantive ? a.result : T.SubstantiveResult.NoDecision;
        u.reason = anySubstantive ? a.reason : s.rounds[caseId][last].reason;
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
            s.finalCase[c.exclusivityKey] = caseId;
            if (s.activeCase[c.exclusivityKey] == caseId) delete s.activeCase[c.exclusivityKey];
        }
        emit CaseFinalized(caseId, c.state, u.result, u.reason, adopted, u.adoptedFromEarlierRound);
    }
}
