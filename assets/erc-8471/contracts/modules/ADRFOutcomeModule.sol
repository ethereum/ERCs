// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFModule} from "./ADRFModule.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFOutcomeModule — the reads of sub-questions, findings, round decisions, rulings and enactment reports (module of the dispute registry)
/// @notice The reads return the record as stored, with one convenience: `getRuling` of a case that has no ruling
///         yet reports the case's procedure state in the ruling's `state` field, so that the four dimensions of a
///         case (procedure state, substantive result, reason, enactment status per effect) can always be read
///         from the same place.
contract ADRFOutcomeModule is ADRFModule {
    constructor(IADRFPolicyRegistry policies_) ADRFModule(policies_) {}

    function getSubQuestion(bytes32 caseId, uint32 subQuestion) external view delegated returns (T.SubQuestion memory) {
        if (subQuestion >= _s.cases[caseId].subQuestionCount) revert E.ADRF_BadSubQuestions("index");
        return _s.subs[caseId][subQuestion];
    }
    function getFinding(bytes32 caseId, uint32 subQuestion) external view delegated returns (T.Finding memory) { return _s.findings[caseId][subQuestion]; }
    function getRound(bytes32 caseId, uint32 round) external view delegated returns (T.RoundRecord memory) { return _s.rounds[caseId][round]; }
    function getRuling(bytes32 caseId) external view delegated returns (T.Ruling memory u) {
        u = _s.rulings[caseId];
        if (u.state == T.ProcedureState.None) u.state = _s.cases[caseId].state;
    }
    function getEnactment(bytes32 caseId, bytes32 effectId) external view delegated returns (T.Enactment memory) { return _s.enactments[caseId][effectId]; }
}
