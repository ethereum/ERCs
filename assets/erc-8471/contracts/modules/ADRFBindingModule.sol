// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {ADRFErrors as E} from "../ADRFErrors.sol";
import {ADRFStore as S} from "../libraries/ADRFStore.sol";
import {ADRFModule} from "./ADRFModule.sol";
import {IADRFPolicyRegistry} from "../interfaces/IADRFPolicyRegistry.sol";
import {IADRFObligationSource} from "../interfaces/IADRFObligationSource.sol";

/// @title  ADRFBindingModule — bindings and their reads, acceptance and withdrawal (module of the dispute registry)
/// @notice A binding is the obligation source's own statement of which policy it accepts for its objects and
///         which effects a ruling may authorize: the only source of a ruling's authority. Acceptance opens a
///         POST_DISPUTE case; withdrawal and a lapsed acceptance window close it before admission.
contract ADRFBindingModule is ADRFModule {
    constructor(IADRFPolicyRegistry policies_) ADRFModule(policies_) {}

    // ------------------------------------------------------------------ bindings

    function bind(T.BindingInput calldata input) external delegated returns (bytes32 bindingId) {
        address sender = msg.sender;
        if (!policies.policyExists(input.policyId)) revert E.ADRF_UnknownPolicy(input.policyId);
        if (!S.supportsIface(sender, type(IADRFObligationSource).interfaceId)) revert E.ADRF_InvalidBinding("source interface");
        (, , , , , T.StandingMode standing, , , ) = policies.policyHeader(input.policyId);
        T.Track memory track = policies.trackOf(input.policyId);
        if (input.openChallenge && standing != T.StandingMode.OPEN) revert E.ADRF_InvalidBinding("open challenge not allowed by policy");
        if (input.beneficiaries.length > 0 && standing == T.StandingMode.PARTIES) revert E.ADRF_InvalidBinding("beneficiaries not allowed by policy");
        if (input.mode == T.AcceptanceMode.POST_DISPUTE && track.acceptanceWindow == 0) revert E.ADRF_InvalidBinding("policy has no acceptance window");
        if (input.validUntil != 0 && input.validUntil <= S.now64()) revert E.ADRF_InvalidBinding("validUntil in the past");

        bindingId = S.newId(_s);
        T.Binding storage b = _s.bindings[bindingId];
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
            _s.authorizedEffect[bindingId][input.authorizedEffects[i]] = true;
        }
        for (uint256 i = 0; i < input.executors.length; i++) {
            if (input.executors[i] == address(0)) revert E.ADRF_InvalidBinding("zero executor");
            _s.executor[bindingId][input.executors[i]] = true;
        }
        for (uint256 i = 0; i < input.beneficiaries.length; i++) {
            if (input.beneficiaries[i] == address(0)) revert E.ADRF_InvalidBinding("zero beneficiary");
            _s.beneficiary[bindingId][input.beneficiaries[i]] = true;
        }
        emit BindingRegistered(bindingId, sender, input.policyId, input.mode, input.scopeKey);
    }

    function revokeBinding(bytes32 bindingId) external delegated {
        T.Binding storage b = _s.bindings[bindingId];
        if (b.source == address(0)) revert E.ADRF_UnknownBinding(bindingId);
        if (msg.sender != b.source) revert E.ADRF_NotSource(bindingId);
        b.revoked = true;
        emit BindingRevoked(bindingId, msg.sender);
    }

    // ------------------------------------------------------------------ acceptance and withdrawal

    function accept(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (msg.sender != c.respondent) revert E.ADRF_NotRespondent(msg.sender);
        T.Track memory track = policies.trackOf(c.policyId);
        if (S.now64() > _s.clocks[caseId].filedAt + track.acceptanceWindow) revert E.ADRF_WindowClosed("acceptance");
        emit CaseAccepted(caseId, msg.sender);
        _admit(caseId, track);
    }

    function expireAcceptance(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        T.Track memory track = policies.trackOf(c.policyId);
        if (S.now64() <= _s.clocks[caseId].filedAt + track.acceptanceWindow) revert E.ADRF_WindowOpen("acceptance");
        c.state = T.ProcedureState.NotAdmitted;
        _releaseActive(c, caseId);
        emit CaseNotAdmitted(caseId, T.Reason.ACCEPTANCE_LAPSED);
    }

    function withdraw(bytes32 caseId) external delegated {
        T.CaseHeader storage c = _s.cases[caseId];
        if (c.state != T.ProcedureState.Filed) revert E.ADRF_WrongState(caseId, uint8(c.state));
        if (msg.sender != c.claimant) revert E.ADRF_NotClaimant(msg.sender);
        c.state = T.ProcedureState.Withdrawn;
        _releaseActive(c, caseId);
        emit CaseWithdrawn(caseId);
    }

    // ------------------------------------------------------------------ reads

    function getBinding(bytes32 bindingId) external view delegated returns (T.Binding memory) { return _s.bindings[bindingId]; }
    function isAuthorizedEffect(bytes32 bindingId, bytes32 effectId) external view delegated returns (bool) { return _s.authorizedEffect[bindingId][effectId]; }
    function isExecutor(bytes32 bindingId, address account) external view delegated returns (bool) {
        return _s.executor[bindingId][account] || _s.bindings[bindingId].source == account;
    }
    function isBeneficiary(bytes32 bindingId, address account) external view delegated returns (bool) { return _s.beneficiary[bindingId][account]; }
}
