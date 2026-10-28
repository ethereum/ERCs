// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "./ADRFTypes.sol";
import {ADRFErrors as E} from "./ADRFErrors.sol";
import {ADRFStore as S} from "./libraries/ADRFStore.sol";
import {ADRFAdmission} from "./libraries/ADRFAdmission.sol";
import {ADRFLifecycle} from "./libraries/ADRFLifecycle.sol";
import {IADRFDisputeRegistry} from "./interfaces/IADRFDisputeRegistry.sol";
import {IADRFPolicyRegistry} from "./interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFDisputeRegistry — AI Dispute Resolution Framework, dispute registry (reference kernel v0.1)
/// @notice Non-upgradeable. Holds the normative record of bindings, cases, findings, round decisions,
///         rulings, enactment reports and leads. Admission is an algorithmic check of the five criteria
///         (identifiable object and event, accountable respondent, pre-declared norm, available method,
///         open window) against what the obligation source attests; effect authority comes only from the
///         binding; the registry never moves funds and never executes an effect. The admission and
///         lifecycle logic lives in two externally linked libraries that share this contract's storage.
contract ADRFDisputeRegistry is IADRFDisputeRegistry {
    IADRFPolicyRegistry public immutable override policies;

    S.Data private _s;

    constructor(IADRFPolicyRegistry policies_) {
        policies = policies_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFDisputeRegistry).interfaceId;
    }

    // ------------------------------------------------------------------ clock (ERC-6372)

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    // ------------------------------------------------------------------ bindings

    function bind(T.BindingInput calldata input) external returns (bytes32 bindingId) {
        return ADRFAdmission.bind(_s, policies, input, msg.sender);
    }

    function revokeBinding(bytes32 bindingId) external {
        ADRFAdmission.revokeBinding(_s, bindingId, msg.sender);
    }

    // ------------------------------------------------------------------ filing and admission

    function file(bytes32 bindingId, T.ClaimInput calldata claim) external returns (bytes32 caseId) {
        return ADRFAdmission.file(_s, policies, bindingId, claim, msg.sender);
    }

    function fileAdvisory(bytes32 policyId, T.ClaimInput calldata claim, uint64 eventAt, uint64 normDeclaredAt)
        external returns (bytes32 caseId)
    {
        return ADRFAdmission.fileAdvisory(_s, policies, policyId, claim, eventAt, normDeclaredAt, msg.sender);
    }

    function accept(bytes32 caseId) external {
        ADRFAdmission.accept(_s, policies, caseId, msg.sender);
    }

    function expireAcceptance(bytes32 caseId) external {
        ADRFAdmission.expireAcceptance(_s, policies, caseId);
    }

    function withdraw(bytes32 caseId) external {
        ADRFAdmission.withdraw(_s, caseId, msg.sender);
    }

    // ------------------------------------------------------------------ evidence and resolution

    function submitEvidence(bytes32 caseId, uint32 subQuestion, bytes32 commitment, string calldata uri) external {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted && c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (subQuestion >= c.subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        if (uint64(block.timestamp) > _s.clocks[caseId].evidenceCloseAt) revert E.ADRF_WindowClosed("evidence");
        emit EvidenceSubmitted(caseId, subQuestion, msg.sender, commitment, uri);
    }

    function answer(bytes32 caseId) external {
        ADRFLifecycle.answer(_s, caseId, msg.sender);
    }

    function applySilence(bytes32 caseId) external {
        ADRFLifecycle.applySilence(_s, policies, caseId);
    }

    function resolveFormal(bytes32 caseId, uint32 subQuestion, bytes calldata inputs) external {
        ADRFLifecycle.resolveFormal(_s, caseId, subQuestion, inputs);
    }

    function resolveEvidenced(bytes32 caseId, uint32 subQuestion, bytes calldata bundle) external {
        ADRFLifecycle.resolveEvidenced(_s, caseId, subQuestion, bundle);
    }

    function openJudgment(bytes32 caseId, uint32 subQuestion) external {
        ADRFLifecycle.openJudgment(_s, caseId, subQuestion);
    }

    function recordJudgedFinding(bytes32 caseId, uint32 subQuestion, T.Value value, bytes32 resultHash, T.JudgmentSource calldata source) external {
        ADRFLifecycle.recordJudgedFinding(_s, caseId, subQuestion, value, resultHash, source, msg.sender);
    }

    // ------------------------------------------------------------------ decision, review and finality

    function decide(bytes32 caseId) external {
        ADRFLifecycle.decide(_s, policies, caseId);
    }

    function expireDecision(bytes32 caseId) external {
        ADRFLifecycle.expireDecision(_s, policies, caseId);
    }

    function requestReview(bytes32 caseId, uint8 reviewType, uint32[] calldata subQuestions) external {
        ADRFLifecycle.requestReview(_s, policies, caseId, reviewType, subQuestions, msg.sender);
    }

    function finalize(bytes32 caseId) external {
        ADRFLifecycle.finalize(_s, policies, caseId);
    }

    function enforceDeadline(bytes32 caseId) external {
        ADRFLifecycle.enforceDeadline(_s, policies, caseId);
    }

    // ------------------------------------------------------------------ enactment log and leads

    /// Informative log of what an authorized executor did with one effect. Only Final (or Expired) Binding
    /// cases; only the source or an executor named by the binding; only the effect the ruling allows, or a
    /// procedural/economic effect the binding authorized. Enacted is never overwritten; Unknown is not Failed.
    function reportEnactment(bytes32 caseId, bytes32 effectId, T.EnactmentStatus status, bytes32 ref) external {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Final && c.state != T.ProcedureState.Expired) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (c.effectClass != T.EffectClass.Binding) revert E.ADRF_AdvisoryNoEffect(caseId);
        if (msg.sender != c.source && !_s.executor[c.bindingId][msg.sender]) revert E.ADRF_NotExecutor(msg.sender);
        if (status == T.EnactmentStatus.NotRequested) revert E.ADRF_BadStatus();
        if (effectId == bytes32(0)) revert E.ADRF_EffectNotAllowed(effectId);
        if (effectId != _s.rulings[caseId].allowedEffect) {
            (bool declared, T.EffectCategory cat) = policies.effectCategory(c.policyId, effectId);
            if (!declared || cat != T.EffectCategory.PROCEDURAL_ECONOMIC || !_s.authorizedEffect[c.bindingId][effectId]) {
                revert E.ADRF_EffectNotAllowed(effectId);
            }
        }
        T.Enactment storage en = _s.enactments[caseId][effectId];
        if (en.status == T.EnactmentStatus.Enacted) revert E.ADRF_EnactmentLocked(effectId);
        en.status = status;
        en.reporter = msg.sender;
        en.ref = ref;
        en.at = uint64(block.timestamp);
        emit EnactmentReported(caseId, effectId, msg.sender, status, ref);
    }

    /// A lead is a record that someone reported something about an object. It opens no case and confers no
    /// standing, no power and no presumption.
    function reportLead(T.ObjectRef calldata object, bytes32 commitment, string calldata uri) external {
        emit LeadReported(keccak256(abi.encode(object)), msg.sender, commitment, uri);
    }

    // ------------------------------------------------------------------ reads

    function getBinding(bytes32 bindingId) external view returns (T.Binding memory) { return _s.bindings[bindingId]; }
    function isAuthorizedEffect(bytes32 bindingId, bytes32 effectId) external view returns (bool) { return _s.authorizedEffect[bindingId][effectId]; }
    function isExecutor(bytes32 bindingId, address account) external view returns (bool) {
        return _s.executor[bindingId][account] || _s.bindings[bindingId].source == account;
    }
    function isBeneficiary(bytes32 bindingId, address account) external view returns (bool) { return _s.beneficiary[bindingId][account]; }
    function getCase(bytes32 caseId) external view returns (T.CaseHeader memory) { return _s.cases[caseId]; }
    function getClock(bytes32 caseId) external view returns (T.CaseClock memory) { return _s.clocks[caseId]; }
    function getSubQuestion(bytes32 caseId, uint32 subQuestion) external view returns (T.SubQuestion memory) {
        if (subQuestion >= _s.cases[caseId].subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        return _s.subs[caseId][subQuestion];
    }
    function getFinding(bytes32 caseId, uint32 subQuestion) external view returns (T.Finding memory) { return _s.findings[caseId][subQuestion]; }
    function getRound(bytes32 caseId, uint32 round) external view returns (T.RoundRecord memory) { return _s.rounds[caseId][round]; }
    function getRuling(bytes32 caseId) external view returns (T.Ruling memory u) {
        u = _s.rulings[caseId];
        if (u.state == T.ProcedureState.None) u.state = _s.cases[caseId].state;
    }
    function getEnactment(bytes32 caseId, bytes32 effectId) external view returns (T.Enactment memory) { return _s.enactments[caseId][effectId]; }
    function activeCaseOf(bytes32 exclusivityKey) external view returns (bytes32) { return _s.activeCase[exclusivityKey]; }
    function finalCaseOf(bytes32 exclusivityKey) external view returns (bytes32) { return _s.finalCase[exclusivityKey]; }

    function exclusivityKeyOf(address source, bytes32 obligationRef, bytes32 proposition) external pure returns (bytes32) {
        return keccak256(abi.encode(source, obligationRef, proposition));
    }

    function objectKeyOf(T.ObjectRef calldata object) external pure returns (bytes32) {
        return keccak256(abi.encode(object));
    }
}
