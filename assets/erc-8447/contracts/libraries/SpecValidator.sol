// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import "../SAIErrors.sol";

/// @title  SpecValidator — the structural rules of a SwarmSpec (reference v0.2)
/// @notice Deployed as an external library so that the registry stays within the contract
///         size limit; it executes in the registry's context and reads the registry's term
///         table. Every rule corresponds to one error in SAIErrors.
library SpecValidator {
    uint256 private constant MAX_ROLES = 32;
    uint256 private constant MAX_PHASES = 32;
    uint64 private constant MAX_DURATION = type(uint64).max >> 1; // 2^63 - 1
    bytes32 private constant ROLE_INITIATOR = keccak256("sai.role.initiator");

    function validate(T.SwarmSpec calldata spec, mapping(bytes32 => mapping(bytes32 => bool)) storage terms) external view {
        uint256 nr = spec.roles.length;
        if (nr < 1 || nr > MAX_ROLES) revert SAI_RolesOutOfRange();
        for (uint256 i = 0; i < nr; i++) {
            T.RoleSpec calldata r = spec.roles[i];
            if (r.roleId == bytes32(0)) revert SAI_ZeroRole();
            for (uint256 j = 0; j < i; j++) {
                if (spec.roles[j].roleId == r.roleId) revert SAI_DuplicateRole();
            }
            if (r.max != 0 && r.min > r.max) revert SAI_RoleBounds();
            if (r.eligibility != address(0) && r.eligibility.code.length == 0) revert SAI_ModuleNotContract();
            if (r.roleId == ROLE_INITIATOR && r.min != 0) revert SAI_InitiatorRoleMin();
        }

        uint256 np = spec.phases.length;
        if (np < 1 || np > MAX_PHASES) revert SAI_PhasesOutOfRange();
        if (spec.phases[0].admission != T.Admission.RECRUIT) revert SAI_Phase0MustRecruit();
        for (uint256 i = 0; i < np; i++) {
            T.PhaseSpec calldata ph = spec.phases[i];
            if (!terms[T.DIM_PAYOFF][ph.payoff] || !terms[T.DIM_TOPOLOGY][ph.topology]
                || !terms[T.DIM_COORDINATION][ph.coordination]) revert SAI_UnknownTerm();
            if (ph.inputWindow > MAX_DURATION) revert SAI_DurationTooLong();
        }

        if (spec.authorities.length != T.DECISION_POINTS) revert SAI_AuthoritiesLength();
        for (uint256 i = 0; i < T.DECISION_POINTS; i++) {
            T.Authority calldata a = spec.authorities[i];
            if (a.kind == T.AuthorityKind.ADDRESS) {
                if (a.target == address(0) || a.roleId != bytes32(0)) revert SAI_AuthorityShape();
            } else if (a.kind == T.AuthorityKind.ROLE) {
                if (a.target != address(0) || a.roleId == bytes32(0)) revert SAI_AuthorityShape();
                if (a.roleId == ROLE_INITIATOR) revert SAI_InitiatorRoleAuthority();
                bool found;
                for (uint256 j = 0; j < nr; j++) {
                    if (spec.roles[j].roleId == a.roleId) { found = true; break; }
                }
                if (!found) revert SAI_UnknownRoleAuthority();
            } else {
                if (a.target != address(0) || a.roleId != bytes32(0)) revert SAI_AuthorityShape();
            }
        }

        if (spec.minMembers < 1) revert SAI_MinMembers();
        if (spec.maxMembers != 0 && spec.maxMembers < spec.minMembers) revert SAI_MaxMembers();
        if (spec.activation != T.Activation.ROSTER_MET
            && spec.authorities[uint256(T.DecisionPoint.ACTIVATE)].kind == T.AuthorityKind.NONE) revert SAI_ActivationAuthority();
        if (spec.recruitmentWindow == 0) revert SAI_RecruitmentWindow();
        if (spec.maxDuration == 0 && spec.inactivityTimeout == 0) revert SAI_NoLivenessFallback();
        if (np > 1 && spec.authorities[uint256(T.DecisionPoint.ADVANCE)].kind == T.AuthorityKind.NONE) revert SAI_AdvanceAuthority();
        for (uint256 i = 1; i < np; i++) {
            if (spec.phases[i].admission == T.Admission.RECRUIT && spec.phases[i].boundary == T.Boundary.GATED) {
                T.AuthorityKind k = spec.authorities[uint256(T.DecisionPoint.ADMIT)].kind;
                if (k != T.AuthorityKind.ADDRESS && k != T.AuthorityKind.INITIATOR) revert SAI_RecruitAdmitter();
            }
        }
        if (spec.recruitmentWindow > MAX_DURATION || spec.maxDuration > MAX_DURATION
            || spec.inactivityTimeout > MAX_DURATION || spec.ineligibleGrace > MAX_DURATION
            || spec.settlementWindow > MAX_DURATION || spec.amendmentExitWindow > MAX_DURATION) revert SAI_DurationTooLong();
    }
}
