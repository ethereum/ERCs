// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ADRFErrors — custom errors of the reference implementation
library ADRFErrors {
    // policy registry
    error ADRF_InvalidPolicy(string what);
    error ADRF_PolicyExists(bytes32 policyId);
    error ADRF_UnknownPolicy(bytes32 policyId);
    error ADRF_NotFamilyAuthority(bytes32 family);
    error ADRF_BadFamilyLink(string what);

    // bindings
    error ADRF_InvalidBinding(string what);
    error ADRF_UnknownBinding(bytes32 bindingId);
    error ADRF_NotSource(bytes32 bindingId);
    error ADRF_BindingInactive(bytes32 bindingId);

    // admission (five criteria and standing)
    error ADRF_MissingElement(string which);
    error ADRF_NotIdentifiable(string which);
    error ADRF_NotAccountable(address respondent);
    error ADRF_NormNotApplicable(string what);
    error ADRF_NotDecidable(uint32 subQuestion);
    error ADRF_OutsideWindow(string which);
    error ADRF_ClockIncompatible(uint64 adoptionDeadline, uint64 required);
    error ADRF_NoStanding(address account);
    error ADRF_EffectNotAuthorized(bytes32 effectId);
    error ADRF_Duplicate(bytes32 exclusivityKey, bytes32 existingCase);
    error ADRF_BadSubQuestions(string what);

    // procedure
    error ADRF_WrongState(bytes32 caseId, uint8 state);
    error ADRF_NotParty(address account);
    error ADRF_NotRespondent(address account);
    error ADRF_NotClaimant(address account);
    error ADRF_AlreadyResolved(uint32 subQuestion);
    error ADRF_PremisePending(uint32 subQuestion, uint32 premise);
    error ADRF_WrongQuestionType(uint32 subQuestion);
    error ADRF_InputsMismatch(uint32 subQuestion);
    error ADRF_NotMethod(address caller);
    error ADRF_JudgmentNotOpened(uint32 subQuestion);
    error ADRF_JudgmentAlreadyOpened(uint32 subQuestion);
    error ADRF_DecisiveUnresolved(bytes32 caseId);
    error ADRF_WindowOpen(string which);
    error ADRF_WindowClosed(string which);
    error ADRF_ReviewNotAllowed(string why);
    error ADRF_NotOptimistic(bytes32 caseId);
    error ADRF_AlreadyAnswered(bytes32 caseId);

    // enactment log
    error ADRF_NotExecutor(address account);
    error ADRF_AdvisoryNoEffect(bytes32 caseId);
    error ADRF_EffectNotAllowed(bytes32 effectId);
    error ADRF_EnactmentLocked(bytes32 effectId);
    error ADRF_BadStatus();

    // registry modules
    error ADRF_InvalidModule(address module);
    error ADRF_UnknownFunction(bytes4 selector);
    error ADRF_DirectCall();
}
