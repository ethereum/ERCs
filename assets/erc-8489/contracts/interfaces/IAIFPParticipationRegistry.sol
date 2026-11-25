// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPParticipationRegistry
/// @notice Role bindings: who holds which role bits, in which scope of which channel, on what basis, for
///         how long. Every grant creates a `bindingId`; suspension and revocation address a binding, never
///         a subject in general. Evaluation is a pure function of the registry state at a timepoint.
///         Every management event names the caller (`by`), on what grounds the caller was authorized
///         (`authorityKind`: 0 channel authority, 1 governance executor, 2 a holder of the management role,
///         3 the subject of the binding itself) and, for kind 2, the role binding relied on
///         (`authorizingBinding`), so that a reader of the log can check the action against the role history
///         in log order without a call trace. `RoleReinstated` is authorized by having imposed the
///         suspension, which the `RoleSuspended` log already shows.
interface IAIFPParticipationRegistry {
    // Stored states; Pending (re-admission required) and Expired are derived, not stored.
    enum BindingState {
        Granted,
        Suspended,
        Revoked
    }

    struct RoleBinding {
        bytes32 channelId;
        bytes32 subject;
        bytes32 onBehalfOf; // represented principal, 0 when the subject acts for itself
        uint16 roles;
        bytes32 scopeRef; // 0 = whole channel, otherwise a sub-context or object reference
        uint8 basisKind;
        bytes32 basisRef;
        uint8 outcomeAtGrant;
        bytes32 ruleVersion; // paradigmId in force when granted (or last re-admitted)
        uint48 validFrom;
        uint48 validUntil; // 0 = no end
        uint48 revokedAt; // 0 = not revoked
        uint48 suspendedAt; // start of the latest suspension; 0 if the binding was never suspended
        uint48 reinstatedAt; // end of the latest suspension (reinstated, or revoked while suspended); 0 while it is in force
        address suspendedBy;
        uint32 admittedEpoch; // readmission epoch at grant or last re-admission
        BindingState state;
    }

    event RoleGranted(
        bytes32 indexed channelId,
        bytes32 indexed subject,
        bytes32 indexed bindingId,
        uint16 roles,
        bytes32 scopeRef,
        uint8 basisKind,
        bytes32 basisRef,
        uint8 outcomeAtGrant,
        bytes32 ruleVersion,
        uint48 validFrom,
        uint48 validUntil,
        bytes32 onBehalfOf,
        address by,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event RoleSuspended(
        bytes32 indexed channelId,
        bytes32 indexed bindingId,
        address indexed suspendedBy,
        bytes32 reasonRef,
        uint48 at,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event RoleReinstated(bytes32 indexed channelId, bytes32 indexed bindingId, address indexed by, uint48 at);
    event RoleRevoked(
        bytes32 indexed channelId,
        bytes32 indexed bindingId,
        address indexed by,
        bytes32 reasonRef,
        uint48 at,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event RoleReadmitted(
        bytes32 indexed channelId,
        bytes32 indexed bindingId,
        uint32 epoch,
        bytes32 ruleVersion,
        uint8 outcome,
        address by,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event AdmissionEvaluated(bytes32 indexed channelId, bytes32 indexed subject, uint16 role, bytes32 scopeRef, uint8 outcome);

    error AIFP_NotAuthorized(bytes32 channelId, address caller);
    error AIFP_UnknownBinding(bytes32 bindingId);
    error AIFP_InvalidRole(uint16 roles);
    error AIFP_ChannelNotActive(bytes32 channelId);
    error AIFP_BindingNotActive(bytes32 bindingId);
    error AIFP_BindingNotSuspended(bytes32 bindingId);
    error AIFP_NotSuspender(bytes32 bindingId, address caller);
    error AIFP_NotPending(bytes32 bindingId);
    error AIFP_ValidFromInPast(uint48 validFrom, uint48 now_);
    error AIFP_InvalidInterval(uint48 validFrom, uint48 validUntil);
    error AIFP_NoPredicateForRole(bytes32 paradigmId, uint16 role);
    error AIFP_PredicateMismatch(bytes32 expected, bytes32 actual);
    error AIFP_SubjectMismatch(bytes32 subject, address caller);
    error AIFP_NotSatisfied();
    error AIFP_Undeterminable();
    error AIFP_VerifierError();
    /// @notice The composite verifier could not give a leaf call its full gas bound (same error as the
    ///         verifier's). There is no outcome: the evaluation needs more gas than it was given.
    error AIFP_InsufficientGas();
    /// @notice The composite verifier did not return an outcome for another reason: it reverted or returned
    ///         something that is not one outcome word. `reason` is the first four bytes of its revert data -
    ///         the selector of the verifier's own error, for example the one for a malformed predicate - and
    ///         zero when there are fewer than four: gas exhausted in the verifier itself, predicate bytes that
    ///         do not decode, or an answer that is not one outcome word. There is no outcome and nothing is
    ///         recorded.
    error AIFP_EvaluationFailed(bytes4 reason);
    error AIFP_TooManyBindings(bytes32 channelId, bytes32 subject);

    /// @notice Manager path: the channel authority, a holder of MANAGE_ADMISSION in the channel (or in the
    ///         same scope) or a governance executor with the participation effect grants roles directly.
    function grant(
        bytes32 channelId,
        bytes32 subject,
        bytes32 onBehalfOf,
        uint16 roles,
        bytes32 scopeRef,
        uint8 basisKind,
        bytes32 basisRef,
        uint48 validFrom,
        uint48 validUntil
    ) external returns (bytes32 bindingId);

    /// @notice Admission path: the subject itself acquires one role by satisfying the paradigm's
    ///         predicate for that role. Reverts with the outcome when the predicate is not satisfied,
    ///         so that no NOT_SATISFIED is recorded for an UNDETERMINABLE or VERIFIER_ERROR answer, and
    ///         with AIFP_InsufficientGas or AIFP_EvaluationFailed when the composite verifier returned no
    ///         outcome: a failed evaluation is never reported as an outcome, so the gas forwarded to the
    ///         evaluation never changes the answer.
    function admit(
        bytes32 channelId,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence,
        uint48 validUntil
    ) external returns (bytes32 bindingId);

    /// @notice The same checks and the same evaluation as `admit`, for any subject and without state change:
    ///         reverts where `admit` would reject the call (invalid role, channel not active, no predicate
    ///         for the role, predicate mismatch, an evaluation that did not complete) and returns the outcome
    ///         otherwise.
    function previewAdmission(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) external view returns (uint8 outcome);

    function suspend(bytes32 bindingId, bytes32 reasonRef) external;
    /// @notice Only the party that imposed the current suspension lifts it.
    function reinstate(bytes32 bindingId) external;
    function revoke(bytes32 bindingId, bytes32 reasonRef) external;

    /// @notice Re-admission after a rule change that required it: predicate bindings are re-evaluated
    ///         against the current paradigm; other bindings are confirmed by a manager. Both require the
    ///         channel to be Active, like `admit` and `grant`.
    function readmit(bytes32 bindingId, bytes calldata predicate, bytes[] calldata evidence) external;
    function confirmReadmission(bytes32 bindingId) external;

    /// @notice Outcome for `role` in `scopeRef` at `timepoint`, combining the subject's bindings with anyOf
    ///         semantics: a binding that is granted, within its interval, not revoked, not suspended and not
    ///         pending re-admission at the timepoint yields SATISFIED; a pending binding yields
    ///         UNDETERMINABLE; a suspended one yields NOT_SATISFIED; no binding yields NOT_SATISFIED.
    ///         The answer for a timepoint is final once the clock has passed it. While the clock still reads
    ///         the timepoint, every state change recorded at it applies from its position in the chain, so
    ///         the answer is the state after the changes recorded so far.
    function evaluate(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef, uint48 timepoint)
        external
        view
        returns (uint8 outcome);
    /// @notice Same evaluation, also naming a binding that satisfies it: for a SATISFIED outcome `bindingId`
    ///         is the earliest-created binding of the subject that is SATISFIED at the timepoint, otherwise
    ///         zero. It is a witness that the role is held; when several bindings satisfy the check it says
    ///         nothing about the capacity in which the subject acts. A contract that accepts an action on a
    ///         SATISFIED outcome at the current clock value records this identifier: it is the evidence of
    ///         the decision taken at that position in the chain, which a later `evaluate` for the same
    ///         timepoint does not reproduce when the binding is revoked or suspended later within it.
    function evaluateWithBinding(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef, uint48 timepoint)
        external
        view
        returns (uint8 outcome, bytes32 bindingId);
    function evaluateNow(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef) external view returns (uint8 outcome);
    /// @notice Informative summary: union of role bits SATISFIED at the timepoint. Never a basis for
    ///         authorizing an action on its own.
    function rolesOf(bytes32 channelId, bytes32 subject, bytes32 scopeRef, uint48 timepoint) external view returns (uint16 roles);
    function isPending(bytes32 bindingId, uint48 timepoint) external view returns (bool);

    function bindingOf(bytes32 bindingId) external view returns (RoleBinding memory);
    /// @notice The subject's bindings in the channel, in creation order.
    function bindingIdsOf(bytes32 channelId, bytes32 subject) external view returns (bytes32[] memory);
}
