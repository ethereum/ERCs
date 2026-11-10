// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";
import {IAIFPParticipationRegistry} from "./interfaces/IAIFPParticipationRegistry.sol";
import {IAIFPChannelRegistry} from "./interfaces/IAIFPChannelRegistry.sol";
import {IAIFPParadigmRegistry} from "./interfaces/IAIFPParadigmRegistry.sol";
import {IAIFPCompositeVerifier} from "./interfaces/IAIFPPredicateVerifier.sol";
import {AIFPRoles} from "./libraries/AIFPRoles.sol";
import {AIFPBasis} from "./libraries/AIFPBasis.sol";
import {AIFPBindings} from "./libraries/AIFPBindings.sol";
import {AIFPOutcomes} from "./libraries/AIFPOutcomes.sol";
import {AIFPSubject} from "./libraries/AIFPSubject.sol";
import {AIFPCalls} from "./libraries/AIFPCalls.sol";

/// @title AIFPParticipationRegistry
/// @notice Reference implementation of IAIFPParticipationRegistry. Each grant is a separately addressable
///         role binding; evaluation at a timepoint is a pure function of the registry state, with
///         suspension intervals and re-admission epochs kept as history so that a timepoint the clock has
///         passed evaluates the same way ever after. While the clock still reads a timepoint, each state
///         change recorded at it applies from its position in transaction order; `evaluateWithBinding`
///         names the binding a check relied on, so that a contract recording an accepted action can keep
///         it as evidence of the decision it took at that position.
contract AIFPParticipationRegistry is IAIFPParticipationRegistry, IERC165, IERC6372 {
    struct Suspension {
        uint48 from;
        uint48 to; // 0 while the suspension is in force
        address by;
    }

    struct Admission {
        uint32 epoch;
        uint48 at;
    }

    uint256 public constant MAX_BINDINGS_PER_SUBJECT = 64;

    IAIFPChannelRegistry public immutable channelRegistry;
    IAIFPParadigmRegistry public immutable paradigmRegistry;
    IAIFPCompositeVerifier public immutable verifier;

    uint256 private _nonce;
    mapping(bytes32 => RoleBinding) private _bindings;
    mapping(bytes32 => bool) private _exists;
    mapping(bytes32 => Suspension[]) private _suspensions;
    mapping(bytes32 => Admission[]) private _admissions;
    mapping(bytes32 => mapping(bytes32 => bytes32[])) private _idsOf; // channelId => subject => bindingIds

    constructor(IAIFPChannelRegistry channelRegistry_, IAIFPParadigmRegistry paradigmRegistry_, IAIFPCompositeVerifier verifier_) {
        channelRegistry = channelRegistry_;
        paradigmRegistry = paradigmRegistry_;
        verifier = verifier_;
    }

    // ---------------------------------------------------------------- ERC-165 / ERC-6372

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6372).interfaceId
            || interfaceId == type(IAIFPParticipationRegistry).interfaceId;
    }

    /// @dev One clock domain per deployment: the channel registry's clock.
    function clock() public view virtual returns (uint48) {
        return IERC6372(address(channelRegistry)).clock();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        return IERC6372(address(channelRegistry)).CLOCK_MODE();
    }

    // ---------------------------------------------------------------- manager path

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
    ) external returns (bytes32 bindingId) {
        if (!AIFPRoles.isDefined(roles)) revert AIFP_InvalidRole(roles);
        if (basisKind > AIFPBasis.MAX_KIND || basisKind == AIFPBasis.PREDICATE) revert AIFP_InvalidRole(roles);
        _requireActive(channelId);
        Authority memory auth = _managerAuthority(channelId, msg.sender, scopeRef);
        uint48 now_ = clock();
        if (validFrom == 0) validFrom = now_;
        if (validFrom < now_) revert AIFP_ValidFromInPast(validFrom, now_);
        if (validUntil != 0 && validUntil <= validFrom) revert AIFP_InvalidInterval(validFrom, validUntil);
        bindingId = _create(
            NewBinding({
                channelId: channelId,
                subject: subject,
                onBehalfOf: onBehalfOf,
                roles: roles,
                scopeRef: scopeRef,
                basisKind: basisKind,
                basisRef: basisRef,
                outcome: AIFPOutcomes.SATISFIED,
                validFrom: validFrom,
                validUntil: validUntil
            }),
            auth
        );
    }

    // ---------------------------------------------------------------- admission path

    function admit(
        bytes32 channelId,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence,
        uint48 validUntil
    ) external returns (bytes32 bindingId) {
        if (!AIFPRoles.isSingle(role)) revert AIFP_InvalidRole(role);
        _requireActive(channelId);
        bytes32 subject = AIFPSubject.self(msg.sender);
        uint48 now_ = clock();
        bytes32 expected = _expectedPredicate(channelId, role, now_, predicate);
        uint8 outcome = _evaluatePredicate(channelId, subject, role, scopeRef, predicate, evidence);
        if (outcome != AIFPOutcomes.SATISFIED) _revertWith(outcome);
        if (validUntil != 0 && validUntil <= now_) revert AIFP_InvalidInterval(now_, validUntil);
        emit AdmissionEvaluated(channelId, subject, role, scopeRef, outcome);
        bindingId = _create(
            NewBinding({
                channelId: channelId,
                subject: subject,
                onBehalfOf: bytes32(0),
                roles: role,
                scopeRef: scopeRef,
                basisKind: AIFPBasis.PREDICATE,
                basisRef: expected,
                outcome: outcome,
                validFrom: now_,
                validUntil: validUntil
            }),
            Authority({by: msg.sender, kind: AIFPBasis.AUTHORITY_SUBJECT, bindingId: bytes32(0)})
        );
    }

    function previewAdmission(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) external view returns (uint8 outcome) {
        // The same checks as `admit`, in the same order: a preview reverts where an admission would be
        // rejected, and reports an outcome only when the composite verifier returned one.
        if (!AIFPRoles.isSingle(role)) revert AIFP_InvalidRole(role);
        _requireActive(channelId);
        _expectedPredicate(channelId, role, clock(), predicate);
        return _evaluatePredicate(channelId, subject, role, scopeRef, predicate, evidence);
    }

    // ---------------------------------------------------------------- state changes on a binding

    function suspend(bytes32 bindingId, bytes32 reasonRef) external {
        RoleBinding storage b = _binding(bindingId);
        if (b.state != BindingState.Granted) revert AIFP_BindingNotActive(bindingId);
        Authority memory auth = _managerAuthority(b.channelId, msg.sender, b.scopeRef);
        uint48 now_ = clock();
        _suspensions[bindingId].push(Suspension({from: now_, to: 0, by: msg.sender}));
        b.suspendedAt = now_;
        b.reinstatedAt = 0;
        b.suspendedBy = msg.sender;
        b.state = BindingState.Suspended;
        emit RoleSuspended(b.channelId, bindingId, msg.sender, reasonRef, now_, auth.kind, auth.bindingId);
    }

    function reinstate(bytes32 bindingId) external {
        RoleBinding storage b = _binding(bindingId);
        if (b.state != BindingState.Suspended) revert AIFP_BindingNotSuspended(bindingId);
        Suspension storage s = _suspensions[bindingId][_suspensions[bindingId].length - 1];
        if (s.by != msg.sender) revert AIFP_NotSuspender(bindingId, msg.sender);
        uint48 now_ = clock();
        s.to = now_;
        b.reinstatedAt = now_;
        b.state = BindingState.Granted;
        emit RoleReinstated(b.channelId, bindingId, msg.sender, now_);
    }

    function revoke(bytes32 bindingId, bytes32 reasonRef) external {
        RoleBinding storage b = _binding(bindingId);
        if (b.state == BindingState.Revoked) revert AIFP_BindingNotActive(bindingId);
        Authority memory auth = _managerAuthority(b.channelId, msg.sender, b.scopeRef);
        uint48 now_ = clock();
        if (b.state == BindingState.Suspended) {
            Suspension storage s = _suspensions[bindingId][_suspensions[bindingId].length - 1];
            s.to = now_;
            b.reinstatedAt = now_;
        }
        b.revokedAt = now_;
        b.state = BindingState.Revoked;
        emit RoleRevoked(b.channelId, bindingId, msg.sender, reasonRef, now_, auth.kind, auth.bindingId);
    }

    function readmit(bytes32 bindingId, bytes calldata predicate, bytes[] calldata evidence) external {
        RoleBinding storage b = _binding(bindingId);
        _requireActive(b.channelId); // re-admission is an admission: not accepted in a frozen or closed channel
        if (b.state == BindingState.Revoked) revert AIFP_BindingNotActive(bindingId);
        if (b.basisKind != AIFPBasis.PREDICATE) revert AIFP_NotAuthorized(b.channelId, msg.sender);
        if (AIFPSubject.self(msg.sender) != b.subject) revert AIFP_SubjectMismatch(b.subject, msg.sender);
        uint48 now_ = clock();
        if (!_isPendingAt(bindingId, now_)) revert AIFP_NotPending(bindingId);
        bytes32 expected = _expectedPredicate(b.channelId, b.roles, now_, predicate);
        uint8 outcome = _evaluatePredicate(b.channelId, b.subject, b.roles, b.scopeRef, predicate, evidence);
        if (outcome != AIFPOutcomes.SATISFIED) _revertWith(outcome);
        b.basisRef = expected;
        _recordAdmission(bindingId, b, now_, outcome, Authority({by: msg.sender, kind: AIFPBasis.AUTHORITY_SUBJECT, bindingId: bytes32(0)}));
    }

    function confirmReadmission(bytes32 bindingId) external {
        RoleBinding storage b = _binding(bindingId);
        _requireActive(b.channelId); // like a grant: not accepted in a frozen or closed channel
        if (b.state == BindingState.Revoked) revert AIFP_BindingNotActive(bindingId);
        if (b.basisKind == AIFPBasis.PREDICATE) revert AIFP_NotAuthorized(b.channelId, msg.sender);
        Authority memory auth = _managerAuthority(b.channelId, msg.sender, b.scopeRef);
        uint48 now_ = clock();
        if (!_isPendingAt(bindingId, now_)) revert AIFP_NotPending(bindingId);
        _recordAdmission(bindingId, b, now_, AIFPOutcomes.SATISFIED, auth);
    }

    // ---------------------------------------------------------------- evaluation

    function evaluate(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef, uint48 timepoint)
        public
        view
        returns (uint8 outcome)
    {
        (outcome,) = evaluateWithBinding(channelId, subject, role, scopeRef, timepoint);
    }

    /// @dev Bindings are examined in creation order, so the binding named for a SATISFIED outcome is the
    ///      earliest-created one that is SATISFIED at the timepoint.
    function evaluateWithBinding(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef, uint48 timepoint)
        public
        view
        returns (uint8 outcome, bytes32 bindingId)
    {
        if (!AIFPRoles.isSingle(role)) revert AIFP_InvalidRole(role);
        uint32 epoch = channelRegistry.readmissionEpochAt(channelId, timepoint);
        bytes32[] storage ids = _idsOf[channelId][subject];
        bool pending;
        for (uint256 i = 0; i < ids.length; i++) {
            uint8 status = _statusAt(ids[i], role, scopeRef, timepoint, epoch);
            if (status == AIFPOutcomes.SATISFIED) return (AIFPOutcomes.SATISFIED, ids[i]);
            if (status == AIFPOutcomes.UNDETERMINABLE) pending = true;
        }
        return (pending ? AIFPOutcomes.UNDETERMINABLE : AIFPOutcomes.NOT_SATISFIED, bytes32(0));
    }

    function evaluateNow(bytes32 channelId, bytes32 subject, uint16 role, bytes32 scopeRef) external view returns (uint8) {
        return evaluate(channelId, subject, role, scopeRef, clock());
    }

    function rolesOf(bytes32 channelId, bytes32 subject, bytes32 scopeRef, uint48 timepoint) external view returns (uint16 roles) {
        uint32 epoch = channelRegistry.readmissionEpochAt(channelId, timepoint);
        bytes32[] storage ids = _idsOf[channelId][subject];
        for (uint256 i = 0; i < ids.length; i++) {
            RoleBinding storage b = _bindings[ids[i]];
            if (_statusAt(ids[i], b.roles, scopeRef, timepoint, epoch) == AIFPOutcomes.SATISFIED) roles |= b.roles;
        }
    }

    function isPending(bytes32 bindingId, uint48 timepoint) external view returns (bool) {
        _binding(bindingId);
        return _isPendingAt(bindingId, timepoint);
    }

    function bindingOf(bytes32 bindingId) external view returns (RoleBinding memory) {
        return _binding(bindingId);
    }

    function bindingIdsOf(bytes32 channelId, bytes32 subject) external view returns (bytes32[] memory) {
        return _idsOf[channelId][subject];
    }

    function suspensionsOf(bytes32 bindingId) external view returns (Suspension[] memory) {
        return _suspensions[bindingId];
    }

    function admissionsOf(bytes32 bindingId) external view returns (Admission[] memory) {
        return _admissions[bindingId];
    }

    // ---------------------------------------------------------------- internals

    /// @dev Status of one binding for `role` in `scopeRef` at `timepoint`:
    ///      SATISFIED, UNDETERMINABLE (pending re-admission), NOT_SATISFIED (suspended), or 0xff (not applicable).
    function _statusAt(bytes32 bindingId, uint16 role, bytes32 scopeRef, uint48 timepoint, uint32 epoch)
        internal
        view
        returns (uint8)
    {
        RoleBinding storage b = _bindings[bindingId];
        if ((b.roles & role) == 0) return 0xff;
        if (b.scopeRef != bytes32(0) && b.scopeRef != scopeRef) return 0xff;
        if (timepoint < b.validFrom) return 0xff;
        if (b.validUntil != 0 && timepoint >= b.validUntil) return 0xff;
        if (b.revokedAt != 0 && timepoint >= b.revokedAt) return 0xff;
        if (_suspendedAt(bindingId, timepoint)) return AIFPOutcomes.NOT_SATISFIED;
        if (epoch > _admittedEpochAt(bindingId, timepoint)) return AIFPOutcomes.UNDETERMINABLE;
        return AIFPOutcomes.SATISFIED;
    }

    function _suspendedAt(bytes32 bindingId, uint48 timepoint) internal view returns (bool) {
        Suspension[] storage list = _suspensions[bindingId];
        for (uint256 i = 0; i < list.length; i++) {
            if (timepoint >= list[i].from && (list[i].to == 0 || timepoint < list[i].to)) return true;
        }
        return false;
    }

    function _admittedEpochAt(bytes32 bindingId, uint48 timepoint) internal view returns (uint32 epoch) {
        Admission[] storage list = _admissions[bindingId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].at <= timepoint && list[i].epoch > epoch) epoch = list[i].epoch;
        }
    }

    function _isPendingAt(bytes32 bindingId, uint48 timepoint) internal view returns (bool) {
        RoleBinding storage b = _bindings[bindingId];
        return channelRegistry.readmissionEpochAt(b.channelId, timepoint) > _admittedEpochAt(bindingId, timepoint);
    }

    struct NewBinding {
        bytes32 channelId;
        bytes32 subject;
        bytes32 onBehalfOf;
        uint16 roles;
        bytes32 scopeRef;
        uint8 basisKind;
        bytes32 basisRef;
        uint8 outcome;
        uint48 validFrom;
        uint48 validUntil;
    }

    /// @dev Who called a management function and on what grounds (AIFPBasis.AUTHORITY_*); `bindingId` is the
    ///      role binding relied on when the grounds are a management role, zero otherwise.
    struct Authority {
        address by;
        uint8 kind;
        bytes32 bindingId;
    }

    function _create(NewBinding memory n, Authority memory auth) internal returns (bytes32 bindingId) {
        bytes32[] storage ids = _idsOf[n.channelId][n.subject];
        if (ids.length >= MAX_BINDINGS_PER_SUBJECT) revert AIFP_TooManyBindings(n.channelId, n.subject);
        bindingId = keccak256(abi.encode(address(this), ++_nonce));
        uint48 now_ = clock();
        RoleBinding storage b = _bindings[bindingId];
        b.channelId = n.channelId;
        b.subject = n.subject;
        b.onBehalfOf = n.onBehalfOf;
        b.roles = n.roles;
        b.scopeRef = n.scopeRef;
        b.basisKind = n.basisKind;
        b.basisRef = n.basisRef;
        b.outcomeAtGrant = n.outcome;
        b.ruleVersion = channelRegistry.paradigmAt(n.channelId, now_);
        b.validFrom = n.validFrom;
        b.validUntil = n.validUntil;
        b.state = BindingState.Granted;
        uint32 epoch = channelRegistry.readmissionEpochAt(n.channelId, now_);
        b.admittedEpoch = epoch;
        _admissions[bindingId].push(Admission({epoch: epoch, at: now_}));
        _exists[bindingId] = true;
        ids.push(bindingId);
        _emitGranted(bindingId, b, auth);
    }

    function _emitGranted(bytes32 bindingId, RoleBinding storage b, Authority memory auth) internal {
        emit RoleGranted(
            b.channelId,
            b.subject,
            bindingId,
            b.roles,
            b.scopeRef,
            b.basisKind,
            b.basisRef,
            b.outcomeAtGrant,
            b.ruleVersion,
            b.validFrom,
            b.validUntil,
            b.onBehalfOf,
            auth.by,
            auth.kind,
            auth.bindingId
        );
    }

    function _recordAdmission(bytes32 bindingId, RoleBinding storage b, uint48 now_, uint8 outcome, Authority memory auth) internal {
        uint32 epoch = channelRegistry.readmissionEpochAt(b.channelId, now_);
        b.admittedEpoch = epoch;
        b.ruleVersion = channelRegistry.paradigmAt(b.channelId, now_);
        b.outcomeAtGrant = outcome;
        _admissions[bindingId].push(Admission({epoch: epoch, at: now_}));
        emit RoleReadmitted(b.channelId, bindingId, epoch, b.ruleVersion, outcome, auth.by, auth.kind, auth.bindingId);
    }

    function _expectedPredicate(bytes32 channelId, uint16 role, uint48 now_, bytes calldata predicate)
        internal
        view
        returns (bytes32 expected)
    {
        bytes32 paradigmId = channelRegistry.paradigmAt(channelId, now_);
        expected = paradigmRegistry.rolePredicateHash(paradigmId, role);
        if (expected == bytes32(0)) revert AIFP_NoPredicateForRole(paradigmId, role);
        bytes32 actual = keccak256(predicate);
        if (actual != expected) revert AIFP_PredicateMismatch(expected, actual);
    }

    /// @dev Evaluation through the deployment's composite verifier. An outcome is what a completed evaluation
    ///      returns and nothing else: the call has to succeed and return exactly one word with a value of at
    ///      most 3 (at most 32 bytes of what the verifier returns are ever copied). Every other result - a
    ///      revert of any kind, gas exhausted in the verifier, a malformed answer - means that there is no
    ///      outcome, and this function reverts instead of reporting VERIFIER_ERROR. `admit` in a transaction
    ///      with a tight gas limit and `previewAdmission` over `eth_call` therefore do not disagree because of
    ///      the gas forwarded to the evaluation: with too little there is a failed call, never a different
    ///      answer. (What a transaction has already touched, and the gas charge on its sender's balance, can
    ///      still reach a leaf verifier: see IAIFPPredicateVerifier.)
    function _evaluatePredicate(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) internal view returns (uint8) {
        bytes memory data =
            abi.encodeCall(IAIFPCompositeVerifier.evaluate, (channelId, subject, role, scopeRef, predicate, evidence));
        (bool success, uint256 size, bytes32 word) = AIFPCalls.staticcallWord(address(verifier), data, gasleft());
        if (success) {
            if (size != 32 || uint256(word) > AIFPOutcomes.VERIFIER_ERROR) revert AIFP_EvaluationFailed(bytes4(0));
            // The cast cannot truncate: the word is at most VERIFIER_ERROR (3).
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint8(uint256(word));
        }
        // The first four bytes of the revert data, zero-padded when it is shorter.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 reason = bytes4(word);
        if (size == 4 && reason == IAIFPCompositeVerifier.AIFP_InsufficientGas.selector) revert AIFP_InsufficientGas();
        revert AIFP_EvaluationFailed(reason);
    }

    function _revertWith(uint8 outcome) internal pure {
        if (outcome == AIFPOutcomes.NOT_SATISFIED) revert AIFP_NotSatisfied();
        if (outcome == AIFPOutcomes.UNDETERMINABLE) revert AIFP_Undeterminable();
        revert AIFP_VerifierError();
    }

    /// @dev The grounds on which `caller` may manage bindings in `scopeRef`, in the order of Section 9.2:
    ///      the channel authority, a governance executor with the participation effect, a MANAGE_ADMISSION
    ///      binding covering the scope (named in the result). Reverts with AIFP_NotAuthorized otherwise.
    function _managerAuthority(bytes32 channelId, address caller, bytes32 scopeRef) internal view returns (Authority memory auth) {
        auth.by = caller;
        if (caller == channelRegistry.channel(channelId).authority) return auth; // AUTHORITY_CHANNEL
        if (channelRegistry.isGovernanceExecutor(channelId, caller, AIFPBindings.EFFECT_PARTICIPATION)) {
            auth.kind = AIFPBasis.AUTHORITY_EXECUTOR;
            return auth;
        }
        (uint8 outcome, bytes32 managerBinding) =
            evaluateWithBinding(channelId, AIFPSubject.self(caller), AIFPRoles.MANAGE_ADMISSION, scopeRef, clock());
        if (outcome != AIFPOutcomes.SATISFIED) revert AIFP_NotAuthorized(channelId, caller);
        auth.kind = AIFPBasis.AUTHORITY_ROLE;
        auth.bindingId = managerBinding;
    }

    function _requireActive(bytes32 channelId) internal view {
        if (channelRegistry.channel(channelId).state != IAIFPChannelRegistry.ChannelState.Active) {
            revert AIFP_ChannelNotActive(channelId);
        }
    }

    function _binding(bytes32 bindingId) internal view returns (RoleBinding storage b) {
        if (!_exists[bindingId]) revert AIFP_UnknownBinding(bindingId);
        b = _bindings[bindingId];
    }
}
