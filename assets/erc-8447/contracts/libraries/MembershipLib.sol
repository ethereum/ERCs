// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import "../SAIErrors.sol";
import {SAIStore as S, ISwarmRegistryEvents as E} from "./SAIStore.sol";
import {SignatureChecker} from "./SignatureChecker.sol";
import {IEligibility} from "../interfaces/IEligibility.sol";

/// @title  MembershipLib — two-sided admission, departure, suspension, challenge, substitution,
///         contributions (v0.3)
/// @notice External library executed in the registry's context (DELEGATECALL).
library MembershipLib {
    using S for S.Store;

    bytes32 private constant JOIN_TYPEHASH = keccak256(
        "Join(bytes32 swarmId,address account,bytes32 roleId,bytes32 charterHash,uint256 seatEpoch,uint32 phase,uint256 deadline)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // ------------------------------------------------------------------ member side

    /// `viaJoin`: join (authority side implied in an OPEN phase for a selfJoin role); otherwise apply.
    function memberSide(S.Store storage st, bytes32 id, address account, bytes32 roleId, bytes32 charterHash,
                        bool viaJoin, bool signed) external
    {
        _memberSide(st, id, account, roleId, charterHash, viaJoin, signed);
    }

    function joinBySig(S.Store storage st, bytes32 id, address account, bytes32 roleId, bytes32 charterHash,
                       uint256 deadline, bytes calldata signature) external
    {
        if (block.timestamp > deadline) revert SAI_SignatureExpired();
        T.Swarm storage s = st.live(id);
        bytes32 digest = joinDigest(st, id, account, roleId, charterHash, deadline);
        if (!SignatureChecker.isValid(account, digest, signature)) revert SAI_BadSignature();
        T.RoleSpec storage r = st.roleOf(id, roleId);
        bool viaJoin = st.specs[id].phases[s.phase].boundary == T.Boundary.OPEN && r.selfJoin;
        _memberSide(st, id, account, roleId, charterHash, viaJoin, true);
    }

    function _memberSide(S.Store storage st, bytes32 id, address account, bytes32 roleId, bytes32 charterHash,
                         bool viaJoin, bool signed) private
    {
        T.Swarm storage s = st.live(id);
        if (charterHash != s.charterHash) revert SAI_StaleCharter();
        T.Member storage m = st.members[id][account];
        T.MemberStatus stt = S.derived(s, m);
        if (stt == T.MemberStatus.NONE || stt == T.MemberStatus.EXITED) {
            _admissionOpen(st, s, id, roleId, viaJoin);
            m = st.openSeat(id, account, roleId);
            if (!viaJoin) emit E.MemberApplied(id, account, roleId, charterHash);
        } else if (stt == T.MemberStatus.CANDIDATE) {
            if (m.roleId != roleId) revert SAI_RoleMismatch();
            if (viaJoin) _admissionOpen(st, s, id, roleId, true);
        } else {
            revert SAI_SeatTaken();
        }
        _recordAcceptance(s, id, account, m, signed);
        if (viaJoin) m.admitted = true;
        if (m.admitted) _complete(st, s, id, account, m);
    }

    function acceptCharter(S.Store storage st, bytes32 id, bytes32 charterHash) external {
        T.Swarm storage s = st.live(id);
        if (s.state == T.LifecycleState.DISSOLVED) revert SAI_WrongState();
        T.Member storage m = st.members[id][msg.sender];
        T.MemberStatus stt = S.derived(s, m);
        if (stt == T.MemberStatus.NONE || stt == T.MemberStatus.EXITED) revert SAI_NoSeat();
        if (charterHash != s.charterHash) revert SAI_StaleCharter();
        _recordAcceptance(s, id, msg.sender, m, false);
        if (stt == T.MemberStatus.CANDIDATE && m.admitted) _complete(st, s, id, msg.sender, m);
    }

    // ------------------------------------------------------------------ authority side

    function admit(S.Store storage st, bytes32 id, address account, bytes32 roleId) external {
        T.Swarm storage s = st.live(id);
        st.auth(id, T.DecisionPoint.ADMIT);
        _admissionOpen(st, s, id, roleId, false);
        T.Member storage m = st.members[id][account];
        T.MemberStatus stt = S.derived(s, m);
        if (stt == T.MemberStatus.NONE || stt == T.MemberStatus.EXITED) {
            m = st.openSeat(id, account, roleId);
        } else if (stt == T.MemberStatus.CANDIDATE) {
            if (m.roleId != roleId) revert SAI_RoleMismatch();
        } else {
            revert SAI_SeatTaken();
        }
        m.admitted = true;
        s.lastActivity = uint64(block.timestamp);
        emit E.MemberAdmitted(id, account, roleId, msg.sender);
        if (m.accepted && m.acceptedCommitment == s.commitmentVersion) _complete(st, s, id, account, m);
    }

    function leave(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state == T.LifecycleState.DISSOLVED) revert SAI_WrongState();
        T.Member storage m = st.members[id][msg.sender];
        T.MemberStatus stt = S.derived(s, m);
        if (stt == T.MemberStatus.NONE || stt == T.MemberStatus.EXITED) revert SAI_NoSeat();
        bool onAmendment = block.timestamp <= s.exitWindowUntil && m.acceptedCommitment < s.commitmentVersion;
        _exit(st, id, msg.sender, m, T.ExitReason.LEFT, onAmendment);
    }

    function suspendMember(S.Store storage st, bytes32 id, address account) external {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        st.auth(id, T.DecisionPoint.REMOVE);
        T.Member storage m = st.members[id][account];
        if (S.derived(s, m) != T.MemberStatus.ACTIVE) revert SAI_NotMember();
        _suspendMember(st, id, account, m, T.SuspensionCause.AUTHORITY);
    }

    /// Reinstatement on judgment: the REINSTATE authority lifts a suspension of either cause; for an
    /// INELIGIBLE suspension the module must agree. Reinstatement on evidence — anyone, through
    /// `challenge` or `expel`, once the module answers `true` again — needs no authority.
    function reinstate(S.Store storage st, bytes32 id, address account) external {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        st.auth(id, T.DecisionPoint.REINSTATE);
        T.Member storage m = st.members[id][account];
        if (S.derived(s, m) != T.MemberStatus.SUSPENDED) revert SAI_NotSuspended();
        if (m.suspension == T.SuspensionCause.INELIGIBLE) {
            address module = st.roleOf(id, m.roleId).eligibility;
            if (module != address(0) && !S.eligible(module, id, m.roleId, account)) revert SAI_Ineligible();
        }
        _reinstate(st, id, account, m);
    }

    function remove(S.Store storage st, bytes32 id, address account) external {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        T.Member storage m = st.members[id][account];
        T.MemberStatus stt = S.derived(s, m);
        if (stt == T.MemberStatus.CANDIDATE) {
            st.auth(id, T.DecisionPoint.ADMIT);
        } else if (stt == T.MemberStatus.ACTIVE || stt == T.MemberStatus.SUSPENDED) {
            st.auth(id, T.DecisionPoint.REMOVE);
        } else {
            revert SAI_NoSeat();
        }
        _exit(st, id, account, m, T.ExitReason.REMOVED, false);
    }

    /// A `false` answer returned with less than this fraction of the pre-call gas remaining is
    /// treated as unevaluable: under EIP-150 a call that ran out of gas inside the module leaves
    /// at most one sixty-fourth of the forwarded gas per catching layer, so a module that catches
    /// its own reads and answers `false` cannot be made to suspend an honest member by a caller
    /// that starves it. A challenger who means the question supplies ample gas.
    uint256 private constant GAS_RESERVE_DIVISOR = 8;

    /// Re-evaluation on evidence, by anyone. An ACTIVE member answered `false` is suspended
    /// INELIGIBLE; a member SUSPENDED(INELIGIBLE) answered `true` is reinstated; every other
    /// evaluated answer changes nothing; an unevaluable call changes nothing and does not revert.
    function challenge(S.Store storage st, bytes32 id, address account) external returns (bool evaluated, bool eligible) {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        T.Member storage m = st.members[id][account];
        T.MemberStatus stt = S.derived(s, m);
        bool suspendedIneligible = stt == T.MemberStatus.SUSPENDED && m.suspension == T.SuspensionCause.INELIGIBLE;
        if (stt != T.MemberStatus.ACTIVE && !suspendedIneligible) revert SAI_NotMember();
        address module = st.roleOf(id, m.roleId).eligibility;
        if (module == address(0)) revert SAI_NoModule();
        (evaluated, eligible) = _evaluate(module, id, m.roleId, account);
        if (!evaluated) return (false, false);
        emit E.Challenged(id, account, msg.sender, eligible);
        if (!eligible && stt == T.MemberStatus.ACTIVE) _suspendMember(st, id, account, m, T.SuspensionCause.INELIGIBLE);
        if (eligible && suspendedIneligible) _reinstate(st, id, account, m);
    }

    /// Expulsion after the grace period re-adjudicates on current evidence: `false` exits the
    /// member INELIGIBLE, `true` reinstates it instead, an unevaluable module leaves the
    /// suspension in place and reverts so that the caller knows nothing was decided.
    function expel(S.Store storage st, bytes32 id, address account) external {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        T.Member storage m = st.members[id][account];
        if (S.derived(s, m) != T.MemberStatus.SUSPENDED || m.suspension != T.SuspensionCause.INELIGIBLE) revert SAI_NotSuspended();
        if (block.timestamp <= m.suspendedAt + st.specs[id].ineligibleGrace) revert SAI_GraceRunning();
        address module = st.roleOf(id, m.roleId).eligibility;
        if (module != address(0)) {
            (bool evaluated, bool eligible) = _evaluate(module, id, m.roleId, account);
            if (!evaluated) revert SAI_Unevaluable();
            emit E.Challenged(id, account, msg.sender, eligible);
            if (eligible) { _reinstate(st, id, account, m); return; }
        }
        _exit(st, id, account, m, T.ExitReason.INELIGIBLE, false);
    }

    function substitute(S.Store storage st, bytes32 id, address previous, address next) external {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        st.auth(id, T.DecisionPoint.ADMIT);
        T.Member storage p = st.members[id][previous];
        T.MemberStatus stt = S.derived(s, p);
        if (stt != T.MemberStatus.ACTIVE && stt != T.MemberStatus.SUSPENDED) revert SAI_NotMember();
        T.MemberStatus nst = S.derived(s, st.members[id][next]);
        if (nst != T.MemberStatus.NONE && nst != T.MemberStatus.EXITED) revert SAI_SuccessorHasSeat();
        bytes32 role = p.roleId;
        address module = st.roleOf(id, role).eligibility;
        if (module != address(0) && !S.eligible(module, id, role, next)) revert SAI_Ineligible();
        _exit(st, id, previous, p, T.ExitReason.REPLACED, false);
        T.Member storage n = st.openSeat(id, next, role);
        n.admitted = true;
        n.substituted = true; // the seat already exists: completion is exempt from boundary, window and maximum checks
        emit E.MemberSubstituted(id, previous, next, role, msg.sender);
        emit E.MemberAdmitted(id, next, role, msg.sender);
    }

    // ------------------------------------------------------------------ contributions

    function recordContribution(S.Store storage st, bytes32 id, bytes32 contributionHash, string calldata uri) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        T.SwarmSpec storage spec = st.specs[id];
        if (spec.contributions == T.Contributions.DISABLED) revert SAI_ContributionsDisabled();
        if (!S.inputOpen(s, spec.phases[s.phase])) revert SAI_InputClosed();
        T.Member storage m = st.members[id][msg.sender];
        T.MemberStatus stt = S.derived(s, m);
        bool isMember = stt == T.MemberStatus.ACTIVE || stt == T.MemberStatus.SUSPENDED;
        if (!isMember && spec.contributions == T.Contributions.MEMBERS) revert SAI_NotMember();
        if (isMember) m.lastActivity = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        emit E.Contribution(id, msg.sender, s.phase, contributionHash, uri, s.charterVersion, isMember,
                            stt == T.MemberStatus.SUSPENDED);
    }

    // ------------------------------------------------------------------ digest

    function joinDigest(S.Store storage st, bytes32 id, address account, bytes32 roleId, bytes32 charterHash, uint256 deadline)
        public view returns (bytes32)
    {
        bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("SAI"), keccak256("1"), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(JOIN_TYPEHASH, id, account, roleId, charterHash,
                                                  st.seatEpochs[id][account], st.swarms[id].phase, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    // ------------------------------------------------------------------ internals

    function _recordAcceptance(T.Swarm storage s, bytes32 id, address account, T.Member storage m, bool signed) private {
        m.accepted = true;
        m.acceptedCharter = s.charterHash;
        m.acceptedVersion = s.charterVersion;
        m.acceptedCommitment = s.commitmentVersion;
        m.lastActivity = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        emit E.CharterAccepted(id, account, s.charterHash, s.charterVersion, s.commitmentVersion, signed);
    }

    /// Everything an admission depends on at the moment it is performed or completed.
    function _admissionOpen(S.Store storage st, T.Swarm storage s, bytes32 id, bytes32 roleId, bool viaJoin) private view {
        if (s.state != T.LifecycleState.FORMING && s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        T.SwarmSpec storage spec = st.specs[id];
        T.PhaseSpec storage ph = spec.phases[s.phase];
        if (ph.boundary == T.Boundary.CLOSED) revert SAI_BoundaryClosed();
        if (roleId == S.ROLE_INITIATOR) revert SAI_InitiatorRoleSeated();
        T.RoleSpec storage r = st.roleOf(id, roleId);
        if (viaJoin && (ph.boundary != T.Boundary.OPEN || !r.selfJoin)) revert SAI_Gated();
        if (!S.inputOpen(s, ph)) revert SAI_InputClosed();
        S.RoleCounts storage rc = st.roleCounts[id][roleId];
        if (r.max != 0 && rc.active + rc.suspended >= r.max) revert SAI_RoleFull();
        S.Counts storage c = st.counts[id];
        if (spec.maxMembers != 0 && c.active + c.suspended >= spec.maxMembers) revert SAI_SwarmFull();
    }

    /// Completes an admission once both sides are present for the current commitment version.
    function _complete(S.Store storage st, T.Swarm storage s, bytes32 id, address account, T.Member storage m) private {
        if (m.acceptedCommitment != s.commitmentVersion) return; // accepted an earlier version; wait for acceptCharter
        if (!m.substituted) _admissionOpen(st, s, id, m.roleId, false);
        T.RoleSpec storage r = st.roleOf(id, m.roleId);
        if (r.eligibility != address(0) && !S.eligible(r.eligibility, id, m.roleId, account)) revert SAI_Ineligible();
        m.status = T.MemberStatus.ACTIVE;
        m.admittedPhase = s.phase;
        m.carriedPhase = s.phase;
        m.admittedAt = uint64(block.timestamp);
        st.counts[id].candidates -= 1;
        st.counts[id].active += 1;
        st.roleCounts[id][m.roleId].active += 1;
        s.lastActivity = uint64(block.timestamp);
        emit E.MemberActivated(id, account, m.roleId, s.phase);
    }

    /// The module call of `challenge` and `expel`: a revert, a malformed return or a `false`
    /// returned with too little gas left are all "unevaluable".
    function _evaluate(address module, bytes32 id, bytes32 roleId, address account)
        private view returns (bool evaluated, bool eligible)
    {
        uint256 g0 = gasleft();
        (bool ok, bytes memory ret) = module.staticcall(
            abi.encodeWithSelector(IEligibility.isEligible.selector, id, roleId, account));
        if (!ok || ret.length != 32) return (false, false);
        uint256 answer = abi.decode(ret, (uint256));
        if (answer > 1) return (false, false); // not a boolean: malformed, hence unevaluable
        eligible = answer == 1;
        if (!eligible && gasleft() < g0 / GAS_RESERVE_DIVISOR) return (false, false);
        evaluated = true;
    }

    function _reinstate(S.Store storage st, bytes32 id, address account, T.Member storage m) private {
        m.status = T.MemberStatus.ACTIVE;
        m.suspension = T.SuspensionCause.NONE;
        m.suspendedAt = 0;
        m.lastActivity = uint64(block.timestamp);
        st.counts[id].suspended -= 1;
        st.counts[id].active += 1;
        S.RoleCounts storage rc = st.roleCounts[id][m.roleId];
        rc.suspended -= 1;
        rc.active += 1;
        emit E.MemberReinstated(id, account, msg.sender);
    }

    function _suspendMember(S.Store storage st, bytes32 id, address account, T.Member storage m, T.SuspensionCause cause) private {
        m.status = T.MemberStatus.SUSPENDED;
        m.suspension = cause;
        m.suspendedAt = uint64(block.timestamp);
        st.counts[id].active -= 1;
        st.counts[id].suspended += 1;
        S.RoleCounts storage rc = st.roleCounts[id][m.roleId];
        rc.active -= 1;
        rc.suspended += 1;
        emit E.MemberSuspended(id, account, cause, msg.sender);
    }

    function _exit(S.Store storage st, bytes32 id, address account, T.Member storage m, T.ExitReason reason, bool onAmendment) private {
        S.Counts storage c = st.counts[id];
        S.RoleCounts storage rc = st.roleCounts[id][m.roleId];
        if (m.status == T.MemberStatus.CANDIDATE) {
            c.candidates -= 1;
        } else if (m.status == T.MemberStatus.ACTIVE) {
            c.active -= 1;
            rc.active -= 1;
        } else if (m.status == T.MemberStatus.SUSPENDED) {
            c.suspended -= 1;
            rc.suspended -= 1;
        }
        m.status = T.MemberStatus.EXITED;
        m.exitReason = reason;
        m.exitedAt = uint64(block.timestamp);
        st.seatEpochs[id][account] += 1;
        emit E.MemberExited(id, account, reason, onAmendment, msg.sender);
    }
}
