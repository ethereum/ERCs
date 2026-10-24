// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import "../SAIErrors.sol";
import {SAIStore as S, ISwarmRegistryEvents as E} from "./SAIStore.sol";
import {SpecValidator} from "./SpecValidator.sol";
import {ISwarmAccount} from "../interfaces/ISwarmAccount.sol";

/// @title  LifecycleLib — formation, lifecycle, phases, charter, authorities, account (v0.2)
/// @notice External library executed in the registry's context (DELEGATECALL). Every function
///         corresponds to one entry point of ISwarmRegistry; the registry adds the revision bump.
library LifecycleLib {
    using S for S.Store;

    bytes32 private constant ORIGIN_SUCCESSION = keccak256("sai.origin.succession");

    // ------------------------------------------------------------------ formation

    function form(S.Store storage st, T.SwarmSpec calldata spec, bytes32 charterHash, bytes32 commitmentHash,
                  string calldata charterURI, bytes32 parentId, T.Origin memory origin,
                  T.ObjectiveInput calldata objective, bytes32 predecessorId)
        public returns (bytes32 id)
    {
        SpecValidator.validate(spec, st.terms);
        if (objective.objectiveHash == bytes32(0)) revert SAI_ZeroObjective();
        if ((objective.kind == T.ObjectiveKind.MILESTONED) != (objective.milestoneCount > 0)) revert SAI_MilestoneCount();
        if (spec.authorities[uint256(T.DecisionPoint.CONCLUDE)].kind == T.AuthorityKind.NONE
            && objective.acceptanceAuthority == address(0)) revert SAI_NoConclusionPath();
        if (parentId != bytes32(0)) {
            T.LifecycleState ps = st.swarms[parentId].state;
            if (ps != T.LifecycleState.FORMING && ps != T.LifecycleState.ACTIVE) revert SAI_ParentUnavailable();
        }

        id = keccak256(abi.encode(block.chainid, address(this), ++st.nonce));
        T.Swarm storage s = st.swarms[id];
        s.specHash = keccak256(abi.encode(spec));
        s.charterHash = charterHash;
        s.commitmentHash = commitmentHash;
        s.charterVersion = 1;
        s.commitmentVersion = 1;
        s.charterURI = charterURI;
        s.initiator = msg.sender;
        s.origin = origin;
        s.parentId = parentId;
        s.predecessorId = predecessorId;
        s.state = T.LifecycleState.FORMING;
        s.formedAt = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);

        _storeSpec(st, id, spec);

        // the initiator role is checked but never seated
        uint256 ri = st.roleIndex[id][S.ROLE_INITIATOR];
        if (ri != 0) {
            address module = spec.roles[ri - 1].eligibility;
            if (module != address(0) && !S.eligible(module, id, S.ROLE_INITIATOR, msg.sender)) revert SAI_Ineligible();
        }

        T.Objective storage o = st.objectives[id];
        o.objectiveHash = objective.objectiveHash;
        o.version = 1;
        o.kind = objective.kind;
        o.acceptanceAuthority = objective.acceptanceAuthority;
        o.obligation = objective.obligation;
        o.milestoneCount = objective.milestoneCount;

        emit E.SwarmFormed(id, msg.sender, parentId, s.specHash, charterHash, commitmentHash, charterURI,
                           origin.kind, origin.ref, predecessorId);
    }

    function _storeSpec(S.Store storage st, bytes32 id, T.SwarmSpec calldata spec) private {
        T.SwarmSpec storage p = st.specs[id];
        p.activation = spec.activation;
        p.contributions = spec.contributions;
        p.minMembers = spec.minMembers;
        p.maxMembers = spec.maxMembers;
        p.recruitmentWindow = spec.recruitmentWindow;
        p.maxDuration = spec.maxDuration;
        p.inactivityTimeout = spec.inactivityTimeout;
        p.ineligibleGrace = spec.ineligibleGrace;
        p.settlementWindow = spec.settlementWindow;
        p.amendmentExitWindow = spec.amendmentExitWindow;
        p.descriptorHash = spec.descriptorHash;
        for (uint256 i = 0; i < spec.roles.length; i++) {
            p.roles.push(spec.roles[i]);
            st.roleIndex[id][spec.roles[i].roleId] = i + 1;
        }
        for (uint256 i = 0; i < spec.phases.length; i++) {
            p.phases.push(spec.phases[i]);
        }
        T.Authority[16] storage a = st.authorities[id];
        for (uint256 i = 0; i < T.DECISION_POINTS; i++) {
            p.authorities.push(spec.authorities[i]);
            a[i] = spec.authorities[i];
        }
    }

    // ------------------------------------------------------------------ lifecycle

    function activate(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.FORMING) revert SAI_WrongState();
        T.Activation mode = st.specs[id].activation;
        if (mode != T.Activation.ROSTER_MET) st.auth(id, T.DecisionPoint.ACTIVATE);
        if (mode != T.Activation.AUTHORITY && !st.rosterMet(id)) revert SAI_RosterNotMet();
        s.state = T.LifecycleState.ACTIVE;
        s.activatedAt = uint64(block.timestamp);
        s.phaseStartedAt = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        emit E.SwarmActivated(id, s.activatedAt, S.hardDeadline(s, st.specs[id]), msg.sender);
    }

    function abort(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.FORMING) revert SAI_WrongState();
        T.Reason reason;
        if (st.isAuthorized(id, T.DecisionPoint.ABORT, msg.sender)) {
            reason = T.Reason.AUTHORITY;
        } else {
            if (block.timestamp <= s.formedAt + st.specs[id].recruitmentWindow) revert SAI_WindowOpen();
            reason = T.Reason.RECRUITMENT_EXPIRED;
        }
        s.outcome = T.OutcomeType.ABANDONED;
        s.reason = reason;
        s.concludedAt = uint64(block.timestamp);
        emit E.SwarmConcluded(id, T.OutcomeType.ABANDONED, reason, bytes32(0), msg.sender);
        S.dissolve(s, id);
    }

    function suspend(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.SUSPEND);
        S.suspend(s, id, T.Reason.AUTHORITY);
    }

    function enforceRoster(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        if (st.rosterMet(id)) revert SAI_RosterMet();
        // a roster that re-forms after a SELECT or RECRUIT advance gets the recruitment window first
        if (s.phase > 0 && s.rosterPhase == s.phase
            && block.timestamp < s.phaseStartedAt + st.specs[id].recruitmentWindow) revert SAI_RosterCheckDeferred();
        S.suspend(s, id, T.Reason.ROSTER_LOST);
    }

    function enforceInactivity(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        uint64 timeout = st.specs[id].inactivityTimeout;
        if (timeout == 0) revert SAI_NotInactive();
        if (s.state == T.LifecycleState.ACTIVE) {
            if (block.timestamp <= s.lastActivity + timeout) revert SAI_NotInactive();
            S.suspend(s, id, T.Reason.INACTIVITY);
        } else if (s.state == T.LifecycleState.SUSPENDED) {
            if (block.timestamp <= s.suspendedAt + timeout) revert SAI_NotInactive();
            S.conclude(s, id, T.OutcomeType.ABANDONED, T.Reason.INACTIVITY, bytes32(0));
        } else {
            revert SAI_WrongState();
        }
    }

    function enforceDeadline(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE && s.state != T.LifecycleState.SUSPENDED) revert SAI_WrongState();
        uint64 deadline = S.hardDeadline(s, st.specs[id]);
        if (deadline == 0 || block.timestamp <= deadline) revert SAI_BeforeDeadline();
        S.conclude(s, id, T.OutcomeType.ABANDONED, T.Reason.TIMEOUT, bytes32(0));
    }

    function resume(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.SUSPENDED) revert SAI_WrongState();
        if (!st.isAuthorized(id, T.DecisionPoint.RESUME, msg.sender)) {
            if (s.reason != T.Reason.ROSTER_LOST || !st.rosterMet(id)) revert SAI_NotAuthorized();
        }
        s.state = T.LifecycleState.ACTIVE;
        s.reason = T.Reason.NONE;
        s.lastActivity = uint64(block.timestamp);
        emit E.SwarmResumed(id, msg.sender);
    }

    function advance(S.Store storage st, bytes32 id, address[] calldata carried, bytes32[] calldata roles) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.ADVANCE);
        T.SwarmSpec storage spec = st.specs[id];
        uint32 next = s.phase + 1;
        if (next >= spec.phases.length) revert SAI_LastPhase();
        T.Admission adm = spec.phases[next].admission;
        uint32 carriedCount;
        if (adm == T.Admission.INHERIT) {
            if (carried.length != 0 || roles.length != 0) revert SAI_CarriedShape();
            S.Counts storage c = st.counts[id];
            carriedCount = c.active + c.suspended;
        } else {
            if (adm == T.Admission.RECRUIT && (carried.length != 0 || roles.length != 0)) revert SAI_CarriedShape();
            if (roles.length != 0 && roles.length != carried.length) revert SAI_CarriedShape();
            // the previous roster exits lazily; counters restart from the carried list
            delete st.counts[id];
            for (uint256 i = 0; i < spec.roles.length; i++) delete st.roleCounts[id][spec.roles[i].roleId];
            for (uint256 i = 0; i < carried.length; i++) {
                T.Member storage m = st.members[id][carried[i]];
                if (S.derived(s, m) != T.MemberStatus.ACTIVE || m.carriedPhase == next) revert SAI_NotCarriedMember();
                bytes32 role = roles.length == 0 ? m.roleId : roles[i];
                T.RoleSpec storage r = st.roleOf(id, role);
                if (r.eligibility != address(0) && !S.eligible(r.eligibility, id, role, carried[i])) revert SAI_Ineligible();
                S.RoleCounts storage rc = st.roleCounts[id][role];
                if (r.max != 0 && rc.active + rc.suspended >= r.max) revert SAI_RoleFull();
                if (spec.maxMembers != 0 && st.counts[id].active >= spec.maxMembers) revert SAI_SwarmFull();
                m.roleId = role;
                m.carriedPhase = next;
                rc.active += 1;
                st.counts[id].active += 1;
                emit E.MemberCarried(id, carried[i], role, next);
            }
            s.rosterPhase = next;
            carriedCount = uint32(carried.length);
        }
        s.phase = next;
        s.phaseStartedAt = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        emit E.PhaseAdvanced(id, next, carriedCount, msg.sender);
    }

    function conclude(S.Store storage st, bytes32 id, T.OutcomeType outcome, bytes32 resultHash) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE && s.state != T.LifecycleState.SUSPENDED) revert SAI_WrongState();
        T.Objective storage o = st.objectives[id];
        T.Reason reason;
        if (msg.sender == o.acceptanceAuthority && msg.sender != address(0)) {
            reason = T.Reason.ACCEPTANCE;
        } else {
            st.auth(id, T.DecisionPoint.CONCLUDE);
            reason = T.Reason.AUTHORITY;
        }
        if (outcome == T.OutcomeType.NONE || outcome == T.OutcomeType.SUPERSEDED) revert SAI_BadOutcome();
        if (o.kind == T.ObjectiveKind.MILESTONED) {
            if (outcome == T.OutcomeType.ACHIEVED && o.milestonesAccepted != o.milestoneCount) revert SAI_MilestonesIncomplete();
            if (outcome == T.OutcomeType.PARTIAL && o.milestonesAccepted == 0) revert SAI_MilestonesIncomplete();
        }
        S.conclude(s, id, outcome, reason, resultHash);
    }

    function dissolve(S.Store storage st, bytes32 id) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.CONCLUDING) revert SAI_WrongState();
        if (!st.isAuthorized(id, T.DecisionPoint.DISSOLVE, msg.sender)) {
            if (block.timestamp <= s.concludedAt + st.specs[id].settlementWindow) revert SAI_WindowOpen();
        }
        S.dissolve(s, id);
    }

    function succeed(S.Store storage st, bytes32 id, T.SwarmSpec calldata newSpec, bytes32 charterHash,
                     bytes32 commitmentHash, string calldata charterURI, T.ObjectiveInput calldata objective,
                     address[] calldata carried, bytes32[] calldata roles)
        external returns (bytes32 successorId)
    {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE && s.state != T.LifecycleState.SUSPENDED) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.SUCCEED);
        if (roles.length != carried.length) revert SAI_CarriedShape();

        successorId = form(st, newSpec, charterHash, commitmentHash, charterURI, s.parentId,
                           T.Origin({kind: ORIGIN_SUCCESSION, ref: id}), objective, id);
        for (uint256 i = 0; i < carried.length; i++) {
            if (S.derived(s, st.members[id][carried[i]]) != T.MemberStatus.ACTIVE) revert SAI_NotCarriedMember();
            if (st.roleIndex[successorId][roles[i]] == 0) revert SAI_UnknownRole();
            if (roles[i] == S.ROLE_INITIATOR) revert SAI_InitiatorRoleSeated();
            T.Member storage n = st.openSeat(successorId, carried[i], roles[i]);
            n.admitted = true;
            emit E.MemberAdmitted(successorId, carried[i], roles[i], msg.sender);
        }
        s.successorId = successorId;
        S.conclude(s, id, T.OutcomeType.SUPERSEDED, T.Reason.SUCCESSION, bytes32(0));
        emit E.SwarmSucceeded(id, successorId, msg.sender);
    }

    // ------------------------------------------------------------------ charter, authority, account

    /// An amendment is material by construction when it changes the objective hash or the
    /// commitment hash; the `material` flag can only add to that (a textual change the authority
    /// declares material), never subtract from it. Zero hashes mean "unchanged".
    function amend(S.Store storage st, bytes32 id, bytes32 charterHash, string calldata charterURI,
                   bytes32 objectiveHash, bytes32 commitmentHash, bool material) external
    {
        T.Swarm storage s = st.live(id);
        S.requireOpen(s);
        st.auth(id, T.DecisionPoint.AMEND);
        if (charterHash == s.charterHash || charterHash == bytes32(0)) revert SAI_SameCharter();
        s.charterHash = charterHash;
        s.charterURI = charterURI;
        s.charterVersion += 1;
        s.lastAmendedAt = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        T.Objective storage o = st.objectives[id];
        if (objectiveHash != bytes32(0) && objectiveHash != o.objectiveHash) {
            o.objectiveHash = objectiveHash;
            o.version = s.charterVersion;
            material = true;
        }
        if (commitmentHash != bytes32(0) && commitmentHash != s.commitmentHash) {
            s.commitmentHash = commitmentHash;
            material = true;
        }
        uint64 exitUntil;
        if (material) {
            s.commitmentVersion += 1;
            exitUntil = uint64(block.timestamp) + st.specs[id].amendmentExitWindow;
            s.exitWindowUntil = exitUntil;
        }
        emit E.CharterAmended(id, s.charterVersion, s.commitmentVersion, material, charterHash, o.objectiveHash,
                              s.commitmentHash, charterURI, exitUntil, msg.sender);
    }

    function setCharterURI(S.Store storage st, bytes32 id, string calldata charterURI) external {
        T.Swarm storage s = st.live(id);
        if (s.state == T.LifecycleState.DISSOLVED) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.AMEND);
        s.charterURI = charterURI;
        emit E.CharterURIUpdated(id, charterURI);
    }

    function transferAuthority(S.Store storage st, bytes32 id, T.DecisionPoint dp, address newAuthority) external {
        T.Swarm storage s = st.live(id);
        if (s.state == T.LifecycleState.DISSOLVED) revert SAI_WrongState();
        T.Authority storage a = st.authorities[id][uint256(dp)];
        if (a.kind != T.AuthorityKind.ADDRESS) revert SAI_NotTransferable();
        if (a.target != msg.sender) revert SAI_NotHolder();
        if (newAuthority == address(0)) revert SAI_ZeroAuthority();
        a.target = newAuthority;
        emit E.AuthorityTransferred(id, dp, msg.sender, newAuthority);
    }

    function setAccount(S.Store storage st, bytes32 id, address account) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.FORMING && s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.SET_ACCOUNT);
        if (s.account != address(0)) revert SAI_AccountSet();
        if (account.code.length == 0 || ISwarmAccount(account).swarmId() != id
            || ISwarmAccount(account).registry() != address(this)) revert SAI_AccountMismatch();
        s.account = account;
        emit E.AccountSet(id, account, msg.sender);
    }
}
