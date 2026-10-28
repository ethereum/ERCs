// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "./ADRFStore.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";
import {IADRFObligationSource} from "../interfaces/IADRFObligationSource.sol";

/// @title  ADRFAdmission — bindings, filing and admission (externally linked library of the dispute registry)
/// @notice Admission is the algorithmic check of the five criteria against the obligation source's
///         attestations: identifiable object and event, accountable respondent, pre-declared norm, available
///         method for every sub-question, open window; plus standing, authorized effects, clock compatibility
///         and exclusivity. It never pre-judges the merits.
library ADRFAdmission {
    event BindingRegistered(bytes32 indexed bindingId, address indexed source, bytes32 indexed policyId, T.AcceptanceMode mode, bytes32 scopeKey);
    event BindingRevoked(bytes32 indexed bindingId, address indexed source);
    event CaseFiled(bytes32 indexed caseId, bytes32 indexed policyId, bytes32 indexed bindingId, address claimant, address respondent, bytes32 proposition);
    event CaseAdmitted(bytes32 indexed caseId, T.EffectClass effectClass, uint64 admittedAt, uint64 decisionDeadline, uint64 hardDeadline);
    event CaseNotAdmitted(bytes32 indexed caseId, T.Reason reason);
    event CaseDowngraded(bytes32 indexed caseId, T.Reason reason);
    event CaseAccepted(bytes32 indexed caseId, address indexed respondent);
    event CaseWithdrawn(bytes32 indexed caseId);

    // ------------------------------------------------------------------ bindings

    function bind(S.Data storage s, IADRFPolicyRegistry policies, T.BindingInput calldata input, address sender)
        external returns (bytes32 bindingId)
    {
        if (!policies.policyExists(input.policyId)) revert E.ADRF_UnknownPolicy(input.policyId);
        if (!S.supportsIface(sender, type(IADRFObligationSource).interfaceId)) revert E.ADRF_InvalidBinding("source interface");
        (, , , , , T.StandingMode standing, , , ) = policies.policyHeader(input.policyId);
        T.Track memory track = policies.trackOf(input.policyId);
        if (input.openChallenge && standing != T.StandingMode.OPEN) revert E.ADRF_InvalidBinding("open challenge not allowed by policy");
        if (input.beneficiaries.length > 0 && standing == T.StandingMode.PARTIES) revert E.ADRF_InvalidBinding("beneficiaries not allowed by policy");
        if (input.mode == T.AcceptanceMode.POST_DISPUTE && track.acceptanceWindow == 0) revert E.ADRF_InvalidBinding("policy has no acceptance window");
        if (input.validUntil != 0 && input.validUntil <= S.now64()) revert E.ADRF_InvalidBinding("validUntil in the past");

        bindingId = S.newId(s);
        T.Binding storage b = s.bindings[bindingId];
        b.source = sender;
        b.policyId = input.policyId;
        b.scopeKey = input.scopeKey;
        b.mode = input.mode;
        b.openChallenge = input.openChallenge;
        b.hasBeneficiaries = input.beneficiaries.length > 0;
        b.downgradeOnClock = input.downgradeOnClock;
        b.validUntil = input.validUntil;
        b.createdAt = S.now64();
        b.termsHash = input.termsHash;

        for (uint256 i = 0; i < input.authorizedEffects.length; i++) {
            (bool declared, ) = policies.effectCategory(input.policyId, input.authorizedEffects[i]);
            if (!declared) revert E.ADRF_InvalidBinding("effect not declared by policy");
            s.authorizedEffect[bindingId][input.authorizedEffects[i]] = true;
        }
        for (uint256 i = 0; i < input.executors.length; i++) {
            if (input.executors[i] == address(0)) revert E.ADRF_InvalidBinding("zero executor");
            s.executor[bindingId][input.executors[i]] = true;
        }
        for (uint256 i = 0; i < input.beneficiaries.length; i++) {
            if (input.beneficiaries[i] == address(0)) revert E.ADRF_InvalidBinding("zero beneficiary");
            s.beneficiary[bindingId][input.beneficiaries[i]] = true;
        }
        emit BindingRegistered(bindingId, sender, input.policyId, input.mode, input.scopeKey);
    }

    function revokeBinding(S.Data storage s, bytes32 bindingId, address sender) external {
        T.Binding storage b = s.bindings[bindingId];
        if (b.source == address(0)) revert E.ADRF_UnknownBinding(bindingId);
        if (sender != b.source) revert E.ADRF_NotSource(bindingId);
        b.revoked = true;
        emit BindingRevoked(bindingId, sender);
    }

    // ------------------------------------------------------------------ filing

    function file(S.Data storage s, IADRFPolicyRegistry policies, bytes32 bindingId, T.ClaimInput calldata claim, address sender)
        external returns (bytes32 caseId)
    {
        T.Binding storage b = s.bindings[bindingId];
        if (b.source == address(0)) revert E.ADRF_UnknownBinding(bindingId);
        if (b.revoked || (b.validUntil != 0 && S.now64() > b.validUntil)) revert E.ADRF_BindingInactive(bindingId);
        if (b.scopeKey != bytes32(0) && b.scopeKey != S.objectKey(claim.object)) revert E.ADRF_NoStanding(sender);
        checkShape(claim);
        if (claim.respondent == sender) revert E.ADRF_NotAccountable(claim.respondent);

        T.Track memory track = policies.trackOf(b.policyId);
        IADRFObligationSource src = IADRFObligationSource(b.source);
        T.EventInfo memory info = src.eventInfo(claim.object, claim.eventRef);

        if (!info.known || info.eventAt == 0 || info.eventAt > S.now64()) revert E.ADRF_NotIdentifiable("event");
        if (info.obligationRef == bytes32(0)) revert E.ADRF_MissingElement("obligation");
        if (info.normRef == bytes32(0) || info.normDeclaredAt == 0) revert E.ADRF_MissingElement("norm");
        if (info.normRef != claim.normRef) revert E.ADRF_NormNotApplicable("norm not recognised by source");
        if (info.normDeclaredAt > info.eventAt) revert E.ADRF_NormNotApplicable("norm declared after event");
        if (info.obligationKind != 0 && info.obligationKind != claim.obligationKind) revert E.ADRF_NormNotApplicable("obligation kind");
        if (S.now64() > info.eventAt + track.filingWindow) revert E.ADRF_OutsideWindow("filing");
        if (claim.respondent != b.source && !src.isParty(claim.object, claim.eventRef, claim.respondent)) {
            revert E.ADRF_NotAccountable(claim.respondent);
        }
        if (!hasStanding(s, b, bindingId, src, claim, sender)) revert E.ADRF_NoStanding(sender);
        for (uint256 i = 0; i < claim.requestedEffects.length; i++) {
            bytes32 eff = claim.requestedEffects[i];
            if (!s.authorizedEffect[bindingId][eff]) revert E.ADRF_EffectNotAuthorized(eff);
            (, T.EffectCategory cat) = policies.effectCategory(b.policyId, eff);
            if (cat != T.EffectCategory.SUBSTANTIVE) revert E.ADRF_EffectNotAuthorized(eff);
        }

        T.EffectClass effectClass = T.EffectClass.Binding;
        uint64 required = S.now64() + track.maxTotalDuration + track.enactmentMargin;
        if (info.adoptionDeadline != 0 && info.adoptionDeadline < required) {
            if (!b.downgradeOnClock) revert E.ADRF_ClockIncompatible(info.adoptionDeadline, required);
            effectClass = T.EffectClass.Advisory;
        }

        caseId = S.newId(s);
        T.CaseHeader storage c = s.cases[caseId];
        initCase(s, policies, c, caseId, claim, b.policyId, sender);
        c.bindingId = bindingId;
        c.source = b.source;
        c.effectClass = effectClass;
        c.obligationRef = info.obligationRef;
        s.clocks[caseId].eventAt = info.eventAt;
        s.clocks[caseId].filedAt = S.now64();

        if (effectClass == T.EffectClass.Binding) {
            bytes32 key = S.exclusivityKey(b.source, info.obligationRef, claim.proposition);
            if (s.finalCase[key] != bytes32(0)) revert E.ADRF_Duplicate(key, s.finalCase[key]);
            bytes32 active = s.activeCase[key];
            if (active != bytes32(0)) {
                T.ProcedureState st = s.cases[active].state;
                if (st != T.ProcedureState.NotAdmitted && st != T.ProcedureState.Withdrawn) revert E.ADRF_Duplicate(key, active);
            }
            c.exclusivityKey = key;
            s.activeCase[key] = caseId;
        }
        emit CaseFiled(caseId, b.policyId, bindingId, sender, claim.respondent, claim.proposition);

        if (effectClass == T.EffectClass.Advisory) {
            emit CaseDowngraded(caseId, T.Reason.CLOCK_INCOMPATIBLE);
            admit(s, caseId, track);
        } else if (b.mode == T.AcceptanceMode.PRE_COMMIT) {
            admit(s, caseId, track);
        } else {
            c.state = T.ProcedureState.Filed;
        }
    }

    function fileAdvisory(S.Data storage s, IADRFPolicyRegistry policies, bytes32 policyId, T.ClaimInput calldata claim,
        uint64 eventAt, uint64 normDeclaredAt, address sender) external returns (bytes32 caseId)
    {
        if (!policies.policyExists(policyId)) revert E.ADRF_UnknownPolicy(policyId);
        checkShape(claim);
        if (claim.respondent == sender) revert E.ADRF_NotAccountable(claim.respondent);
        if (eventAt == 0 || eventAt > S.now64()) revert E.ADRF_NotIdentifiable("event");
        if (normDeclaredAt == 0) revert E.ADRF_MissingElement("norm");
        if (normDeclaredAt > eventAt) revert E.ADRF_NormNotApplicable("norm declared after event");
        T.Track memory track = policies.trackOf(policyId);
        if (S.now64() > eventAt + track.filingWindow) revert E.ADRF_OutsideWindow("filing");

        caseId = S.newId(s);
        T.CaseHeader storage c = s.cases[caseId];
        initCase(s, policies, c, caseId, claim, policyId, sender);
        c.effectClass = T.EffectClass.Advisory;
        s.clocks[caseId].eventAt = eventAt;
        s.clocks[caseId].filedAt = S.now64();
        emit CaseFiled(caseId, policyId, bytes32(0), sender, claim.respondent, claim.proposition);
        admit(s, caseId, track);
    }

    function accept(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId, address sender) external {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (sender != c.respondent) revert E.ADRF_NotRespondent(sender);
        T.Track memory track = policies.trackOf(c.policyId);
        if (S.now64() > s.clocks[caseId].filedAt + track.acceptanceWindow) revert E.ADRF_WindowClosed("acceptance");
        emit CaseAccepted(caseId, sender);
        admit(s, caseId, track);
    }

    function expireAcceptance(S.Data storage s, IADRFPolicyRegistry policies, bytes32 caseId) external {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        T.Track memory track = policies.trackOf(c.policyId);
        if (S.now64() <= s.clocks[caseId].filedAt + track.acceptanceWindow) revert E.ADRF_WindowOpen("acceptance");
        c.state = T.ProcedureState.NotAdmitted;
        releaseActive(s, c, caseId);
        emit CaseNotAdmitted(caseId, T.Reason.ACCEPTANCE_LAPSED);
    }

    function withdraw(S.Data storage s, bytes32 caseId, address sender) external {
        T.CaseHeader storage c = s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (sender != c.claimant) revert E.ADRF_NotClaimant(sender);
        c.state = T.ProcedureState.Withdrawn;
        releaseActive(s, c, caseId);
        emit CaseWithdrawn(caseId);
    }

    // ------------------------------------------------------------------ internals

    function checkShape(T.ClaimInput calldata claim) internal pure {
        if (claim.object.target == address(0) || claim.object.chainId == 0) revert E.ADRF_NotIdentifiable("object");
        if (claim.eventRef == bytes32(0)) revert E.ADRF_NotIdentifiable("event");
        if (claim.proposition == bytes32(0)) revert E.ADRF_MissingElement("claim");
        if (claim.normRef == bytes32(0)) revert E.ADRF_MissingElement("norm");
        if (claim.respondent == address(0)) revert E.ADRF_MissingElement("respondent");
        if (claim.documentHash == bytes32(0)) revert E.ADRF_MissingElement("document");
        uint256 n = claim.subQuestions.length;
        if (n == 0 || n > T.MAX_SUB_QUESTIONS) revert E.ADRF_BadSubQuestions("count");
        if (claim.decisive >= n) revert E.ADRF_BadSubQuestions("decisive");
        if (claim.supportsWhen == T.Value.UNDETERMINED) revert E.ADRF_BadSubQuestions("supportsWhen");
        for (uint256 i = 0; i < n; i++) {
            T.SubQuestionInput calldata q = claim.subQuestions[i];
            if (q.proposition == bytes32(0)) revert E.ADRF_BadSubQuestions("proposition");
            if (q.dependsOn.length != q.requiredValues.length) revert E.ADRF_BadSubQuestions("premises");
            for (uint256 d = 0; d < q.dependsOn.length; d++) {
                if (q.dependsOn[d] >= n || q.dependsOn[d] == i) revert E.ADRF_BadSubQuestions("premise index");
                if (q.requiredValues[d] == T.Value.UNDETERMINED) revert E.ADRF_BadSubQuestions("premise value");
                for (uint256 e = d + 1; e < q.dependsOn.length; e++) {
                    if (q.dependsOn[e] == q.dependsOn[d]) revert E.ADRF_BadSubQuestions("duplicate premise");
                }
            }
        }
        if (claim.effectOnSustained != bytes32(0) && !contains(claim.requestedEffects, claim.effectOnSustained)) revert E.ADRF_BadSubQuestions("effectOnSustained");
        if (claim.effectOnNotSustained != bytes32(0) && !contains(claim.requestedEffects, claim.effectOnNotSustained)) revert E.ADRF_BadSubQuestions("effectOnNotSustained");
    }

    function contains(bytes32[] calldata xs, bytes32 x) internal pure returns (bool) {
        for (uint256 i = 0; i < xs.length; i++) if (xs[i] == x) return true;
        return false;
    }

    function hasStanding(S.Data storage s, T.Binding storage b, bytes32 bindingId, IADRFObligationSource src,
        T.ClaimInput calldata claim, address who) internal view returns (bool)
    {
        if (b.openChallenge) return true;
        if (src.isParty(claim.object, claim.eventRef, who)) return true;
        if (b.hasBeneficiaries && s.beneficiary[bindingId][who]) return true;
        return false;
    }

    /// Stores the claim and pins each sub-question to the method the policy binds for it (fourth criterion:
    /// a method and a procedure exist). The dependency table must be acyclic.
    function initCase(S.Data storage s, IADRFPolicyRegistry policies, T.CaseHeader storage c, bytes32 caseId,
        T.ClaimInput calldata claim, bytes32 policyId, address sender) internal
    {
        c.policyId = policyId;
        c.claimant = sender;
        c.respondent = claim.respondent;
        c.object = claim.object;
        c.eventRef = claim.eventRef;
        c.proposition = claim.proposition;
        c.normRef = claim.normRef;
        c.clause = claim.clause;
        c.obligationKind = claim.obligationKind;
        c.effectOnSustained = claim.effectOnSustained;
        c.effectOnNotSustained = claim.effectOnNotSustained;
        c.fallbackRef = claim.fallbackRef;
        c.evidenceScopeHash = claim.evidenceScopeHash;
        c.documentHash = claim.documentHash;
        c.decisive = claim.decisive;
        c.supportsWhen = claim.supportsWhen;
        c.subQuestionCount = uint32(claim.subQuestions.length);
        T.SubQuestion[] storage subs = s.subs[caseId];
        for (uint256 i = 0; i < claim.subQuestions.length; i++) {
            T.SubQuestionInput calldata q = claim.subQuestions[i];
            (bool found, T.MethodBinding memory m) = policies.findMethod(policyId, q.obligationKind, q.qType);
            if (!found) revert E.ADRF_NotDecidable(uint32(i));
            subs.push();
            T.SubQuestion storage sq = subs[i];
            sq.proposition = q.proposition;
            sq.qType = q.qType;
            sq.obligationKind = q.obligationKind;
            sq.inputsHash = q.inputsHash;
            sq.method = m.method;
            sq.params = m.params;
            sq.onUndetermined = m.onUndetermined;
            for (uint256 d = 0; d < q.dependsOn.length; d++) {
                sq.dependsOn.push(q.dependsOn[d]);
                sq.requiredValues.push(q.requiredValues[d]);
            }
        }
        checkAcyclic(subs);
    }

    function checkAcyclic(T.SubQuestion[] storage subs) internal view {
        uint256 n = subs.length;
        bool[] memory done = new bool[](n);
        uint256 settled = 0;
        for (uint256 pass = 0; pass < n; pass++) {
            for (uint256 i = 0; i < n; i++) {
                if (done[i]) continue;
                uint32[] storage deps = subs[i].dependsOn;
                bool ready = true;
                for (uint256 d = 0; d < deps.length; d++) if (!done[deps[d]]) { ready = false; break; }
                if (ready) { done[i] = true; settled++; }
            }
            if (settled == n) break;
        }
        if (settled != n) revert E.ADRF_BadSubQuestions("cycle");
    }

    function admit(S.Data storage s, bytes32 caseId, T.Track memory track) internal {
        T.CaseHeader storage c = s.cases[caseId];
        T.CaseClock storage k = s.clocks[caseId];
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

    function releaseActive(S.Data storage s, T.CaseHeader storage c, bytes32 caseId) internal {
        if (c.exclusivityKey != bytes32(0) && s.activeCase[c.exclusivityKey] == caseId) {
            delete s.activeCase[c.exclusivityKey];
        }
    }
}
