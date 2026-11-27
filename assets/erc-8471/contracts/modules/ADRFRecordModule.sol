// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFModule} from "./ADRFModule.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFRecordModule — the case reads, the evidence commitments, the enactment log and the leads (module of the dispute registry)
/// @notice The reads return the record as stored. The three informative entries open no case and move nothing:
///         an evidence commitment is a party's pointer to material, an enactment report is what an authorized
///         executor says it did with one effect, a lead is a report about an object that confers no standing,
///         no power and no presumption. The reads of bindings are in the binding module; the reads of
///         sub-questions, findings, rounds, rulings and enactment reports are in the outcome module.
contract ADRFRecordModule is ADRFModule {
    constructor(IADRFPolicyRegistry policies_) ADRFModule(policies_) {}

    // ------------------------------------------------------------------ evidence commitments

    function submitEvidence(bytes32 caseId, uint32 subQuestion, bytes32 commitment, string calldata uri) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Admitted && c.state != T.ProcedureState.Provisional) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (subQuestion >= c.subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        if (uint64(block.timestamp) > _s.clocks[caseId].evidenceCloseAt) revert E.ADRF_WindowClosed("evidence");
        emit EvidenceSubmitted(caseId, subQuestion, msg.sender, commitment, uri);
    }

    // ------------------------------------------------------------------ enactment log

    /// Informative log of what an authorized executor did with one effect. Only Final (or Expired) Binding
    /// cases; only the source or an executor named by the binding; only the effect the ruling allows, or a
    /// procedural/economic effect the binding authorized. Enacted is never overwritten; Unknown is not Failed.
    function reportEnactment(bytes32 caseId, bytes32 effectId, T.EnactmentStatus status, bytes32 ref) external delegated {
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

    // ------------------------------------------------------------------ leads

    /// A lead is a record that someone reported something about an object. It opens no case and confers no
    /// standing, no power and no presumption.
    function reportLead(T.ObjectRef calldata object, bytes32 commitment, string calldata uri) external delegated {
        emit LeadReported(keccak256(abi.encode(object)), msg.sender, commitment, uri);
    }

    // ------------------------------------------------------------------ reads

    function getCase(bytes32 caseId) external view delegated returns (T.CaseHeader memory) { return _s.cases[caseId]; }
    function getClock(bytes32 caseId) external view delegated returns (T.CaseClock memory) { return _s.clocks[caseId]; }
    function activeCaseOf(bytes32 exclusivityKey) external view delegated returns (bytes32) { return _s.activeCase[exclusivityKey]; }
    function finalCaseOf(bytes32 exclusivityKey) external view delegated returns (bytes32) { return _s.finalCase[exclusivityKey]; }

    function exclusivityKeyOf(address source, bytes32 obligationRef, bytes32 proposition) external pure returns (bytes32) {
        return keccak256(abi.encode(source, obligationRef, proposition));
    }

    function objectKeyOf(T.ObjectRef calldata object) external pure returns (bytes32) {
        return keccak256(abi.encode(object));
    }
}
