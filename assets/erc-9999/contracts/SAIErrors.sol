// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

// SAI — Swarm AI Framework: custom errors of the reference registry (v0.2).
// One error per refusal cause named in the specification, so relying contracts and tests can
// distinguish causes without parsing strings.

// specification validation
error SAI_RolesOutOfRange();
error SAI_ZeroRole();
error SAI_DuplicateRole();
error SAI_RoleBounds();
error SAI_ModuleNotContract();
error SAI_PhasesOutOfRange();
error SAI_Phase0MustRecruit();
error SAI_AuthoritiesLength();
error SAI_AuthorityShape();
error SAI_UnknownRoleAuthority();
error SAI_MinMembers();
error SAI_MaxMembers();
error SAI_ActivationAuthority();
error SAI_RecruitmentWindow();
error SAI_NoLivenessFallback();
error SAI_NoConclusionPath();
error SAI_AdvanceAuthority();
error SAI_InitiatorRoleMin();
error SAI_InitiatorRoleAuthority();
error SAI_RecruitAdmitter();
error SAI_DurationTooLong();
error SAI_UnknownTerm();

// objective
error SAI_ZeroObjective();
error SAI_MilestoneCount();
error SAI_MilestoneIndex();
error SAI_MilestoneStatus();
error SAI_MilestoneFinal();

// lifecycle
error SAI_UnknownSwarm();
error SAI_WrongState();
error SAI_NotAuthorized();
error SAI_RosterNotMet();
error SAI_RosterMet();
error SAI_WindowOpen();
error SAI_BeforeDeadline();
error SAI_NotInactive();
error SAI_LastPhase();
error SAI_CarriedShape();
error SAI_NotCarriedMember();
error SAI_BadOutcome();
error SAI_MilestonesIncomplete();
error SAI_ParentUnavailable();
error SAI_RosterCheckDeferred();

// charter and signatures
error SAI_StaleCharter();
error SAI_SameCharter();
error SAI_SignatureExpired();
error SAI_BadSignature();

// membership
error SAI_BoundaryClosed();
error SAI_Gated();
error SAI_InputClosed();
error SAI_UnknownRole();
error SAI_RoleFull();
error SAI_SwarmFull();
error SAI_SeatTaken();
error SAI_Ineligible();
error SAI_NotMember();
error SAI_NoSeat();
error SAI_NotCandidate();
error SAI_NotSuspended();
error SAI_NoModule();
error SAI_GraceRunning();
error SAI_Unevaluable();
error SAI_SuccessorHasSeat();
error SAI_InitiatorRoleSeated();
error SAI_RoleMismatch();
error SAI_ContributionsDisabled();

// resources and vocabulary
error SAI_ZeroKind();
error SAI_ZeroDigest();
error SAI_AnchorMissing();
error SAI_DigestMismatch();
error SAI_UnknownResource();
error SAI_Detached();
error SAI_UnknownDimension();
error SAI_ZeroTerm();
error SAI_TermExists();

// authority and account
error SAI_NotHolder();
error SAI_ZeroAuthority();
error SAI_NotTransferable();
error SAI_AccountSet();
error SAI_AccountMismatch();
