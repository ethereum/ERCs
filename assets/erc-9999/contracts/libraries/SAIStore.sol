// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import "../SAIErrors.sol";
import {IEligibility} from "../interfaces/IEligibility.sol";

/// @title  SAIStore — storage layout and shared helpers of the reference registry (v0.2)
/// @notice The registry keeps all of its state in one `Store` struct so that the lifecycle,
///         membership and resource logic can live in external libraries (DELEGATECALL) that
///         operate on it by reference. Helpers here are `internal` and inlined wherever used.
library SAIStore {
    struct Milestone { T.MilestoneStatus status; bytes32 resultHash; uint64 at; }
    struct Counts { uint32 active; uint32 suspended; uint32 candidates; }
    struct RoleCounts { uint32 active; uint32 suspended; }

    struct Store {
        mapping(bytes32 => T.Swarm) swarms;
        mapping(bytes32 => T.SwarmSpec) specs;
        mapping(bytes32 => T.Authority[16]) authorities;                 // current holders
        mapping(bytes32 => mapping(bytes32 => uint256)) roleIndex;       // roleId => index + 1
        mapping(bytes32 => T.Objective) objectives;
        mapping(bytes32 => mapping(uint32 => Milestone)) milestones;
        mapping(bytes32 => mapping(address => T.Member)) members;
        mapping(bytes32 => mapping(address => uint256)) seatEpochs;
        mapping(bytes32 => Counts) counts;
        mapping(bytes32 => mapping(bytes32 => RoleCounts)) roleCounts;
        mapping(bytes32 => bytes32[]) resourceIds;
        mapping(bytes32 => mapping(bytes32 => T.Resource)) resources;
        mapping(bytes32 => address) resourceAdapters;                    // kind => adapter (deployment-bound)
        mapping(bytes32 => mapping(bytes32 => bool)) terms;
        mapping(bytes32 => mapping(bytes32 => string)) termURIs;
        uint256 nonce;
    }

    bytes32 internal constant ROLE_INITIATOR = keccak256("sai.role.initiator");

    function live(Store storage st, bytes32 id) internal view returns (T.Swarm storage s) {
        s = st.swarms[id];
        if (s.state == T.LifecycleState.NONE) revert SAI_UnknownSwarm();
    }

    /// FORMING, ACTIVE or SUSPENDED: the states in which the ledger may change by judgment.
    function requireOpen(T.Swarm storage s) internal view {
        if (s.state != T.LifecycleState.FORMING && s.state != T.LifecycleState.ACTIVE
            && s.state != T.LifecycleState.SUSPENDED) revert SAI_WrongState();
    }

    function auth(Store storage st, bytes32 id, T.DecisionPoint dp) internal view {
        if (!isAuthorized(st, id, dp, msg.sender)) revert SAI_NotAuthorized();
    }

    function isAuthorized(Store storage st, bytes32 id, T.DecisionPoint dp, address account) internal view returns (bool) {
        T.Authority storage a = st.authorities[id][uint256(dp)];
        if (a.kind == T.AuthorityKind.ADDRESS) return account == a.target;
        if (a.kind == T.AuthorityKind.INITIATOR) return account == st.swarms[id].initiator;
        if (a.kind == T.AuthorityKind.ROLE || a.kind == T.AuthorityKind.ANY_MEMBER) {
            T.Member storage m = st.members[id][account];
            if (derived(st.swarms[id], m) != T.MemberStatus.ACTIVE) return false;
            return a.kind == T.AuthorityKind.ANY_MEMBER || m.roleId == a.roleId;
        }
        return false;
    }

    function derived(T.Swarm storage s, T.Member storage m) internal view returns (T.MemberStatus) {
        (T.MemberStatus stt,) = derivedPair(s, m);
        return stt;
    }

    /// Lazy roster-wide exits: a dissolved swarm exits every seat; a seat not carried into the
    /// phase the roster last re-formed in is exited NOT_CARRIED.
    function derivedPair(T.Swarm storage s, T.Member storage m) internal view returns (T.MemberStatus stt, T.ExitReason r) {
        stt = m.status;
        r = m.exitReason;
        if (stt == T.MemberStatus.NONE || stt == T.MemberStatus.EXITED) return (stt, r);
        if (s.state == T.LifecycleState.DISSOLVED) return (T.MemberStatus.EXITED, T.ExitReason.SWARM_DISSOLVED);
        if (m.carriedPhase < s.rosterPhase) return (T.MemberStatus.EXITED, T.ExitReason.NOT_CARRIED);
    }

    function rosterMet(Store storage st, bytes32 id) internal view returns (bool) {
        T.SwarmSpec storage spec = st.specs[id];
        if (st.counts[id].active < spec.minMembers) return false;
        for (uint256 i = 0; i < spec.roles.length; i++) {
            if (st.roleCounts[id][spec.roles[i].roleId].active < spec.roles[i].min) return false;
        }
        return true;
    }

    function hardDeadline(T.Swarm storage s, T.SwarmSpec storage spec) internal view returns (uint64) {
        if (spec.maxDuration == 0 || s.activatedAt == 0) return 0;
        return s.activatedAt + spec.maxDuration;
    }

    function inputOpen(T.Swarm storage s, T.PhaseSpec storage ph) internal view returns (bool) {
        if (s.state == T.LifecycleState.FORMING) return true;
        return ph.inputWindow == 0 || block.timestamp <= s.phaseStartedAt + ph.inputWindow;
    }

    function eligible(address module, bytes32 id, bytes32 roleId, address account) internal view returns (bool) {
        (bool ok, bytes memory ret) = module.staticcall(
            abi.encodeWithSelector(IEligibility.isEligible.selector, id, roleId, account));
        return ok && ret.length == 32 && abi.decode(ret, (bool));
    }

    function roleOf(Store storage st, bytes32 id, bytes32 roleId) internal view returns (T.RoleSpec storage) {
        uint256 ri = st.roleIndex[id][roleId];
        if (ri == 0) revert SAI_UnknownRole();
        return st.specs[id].roles[ri - 1];
    }

    /// Opens a candidate seat for `account`, overwriting any exited seat; history stays in events.
    function openSeat(Store storage st, bytes32 id, address account, bytes32 roleId) internal returns (T.Member storage m) {
        m = st.members[id][account];
        m.roleId = roleId;
        m.status = T.MemberStatus.CANDIDATE;
        m.suspension = T.SuspensionCause.NONE;
        m.exitReason = T.ExitReason.NONE;
        m.admitted = false;
        m.accepted = false;
        m.substituted = false;
        m.admittedPhase = 0;
        m.carriedPhase = st.swarms[id].phase;
        m.admittedAt = 0;
        m.suspendedAt = 0;
        m.exitedAt = 0;
        m.lastActivity = uint64(block.timestamp);
        m.acceptedCharter = bytes32(0);
        m.acceptedVersion = 0;
        m.acceptedCommitment = 0;
        st.counts[id].candidates += 1;
    }

    function conclude(T.Swarm storage s, bytes32 id, T.OutcomeType outcome, T.Reason reason, bytes32 resultHash) internal {
        s.state = T.LifecycleState.CONCLUDING;
        s.outcome = outcome;
        s.reason = reason;
        s.resultHash = resultHash;
        s.concludedAt = uint64(block.timestamp);
        emit ISwarmRegistryEvents.SwarmConcluded(id, outcome, reason, resultHash, msg.sender);
    }

    function suspend(T.Swarm storage s, bytes32 id, T.Reason reason) internal {
        s.state = T.LifecycleState.SUSPENDED;
        s.reason = reason;
        s.suspendedAt = uint64(block.timestamp);
        emit ISwarmRegistryEvents.SwarmSuspended(id, reason, msg.sender);
    }

    function dissolve(T.Swarm storage s, bytes32 id) internal {
        s.state = T.LifecycleState.DISSOLVED;
        s.dissolvedAt = uint64(block.timestamp);
        emit ISwarmRegistryEvents.SwarmDissolved(id, s.dissolvedAt, msg.sender);
    }
}

/// Events of ISwarmRegistry, declared once so that the libraries and the registry emit the
/// same signatures (qualified event access).
interface ISwarmRegistryEvents {
    event SwarmFormed(bytes32 indexed swarmId, address indexed initiator, bytes32 indexed parentId,
                      bytes32 specHash, bytes32 charterHash, string charterURI, bytes32 originKind, bytes32 originRef,
                      bytes32 predecessorId);
    event SwarmActivated(bytes32 indexed swarmId, uint64 at, uint64 hardDeadline, address by);
    event SwarmSuspended(bytes32 indexed swarmId, T.Reason reason, address by);
    event SwarmResumed(bytes32 indexed swarmId, address by);
    event PhaseAdvanced(bytes32 indexed swarmId, uint32 indexed phase, uint32 carried, address by);
    event SwarmConcluded(bytes32 indexed swarmId, T.OutcomeType outcome, T.Reason reason, bytes32 resultHash, address by);
    event SwarmDissolved(bytes32 indexed swarmId, uint64 at, address by);
    event SwarmSucceeded(bytes32 indexed swarmId, bytes32 indexed successorId, address by);
    event CharterAmended(bytes32 indexed swarmId, uint32 indexed charterVersion, uint32 commitmentVersion, bool material,
                         bytes32 charterHash, bytes32 objectiveHash, string charterURI, uint64 exitUntil, address by);
    event CharterURIUpdated(bytes32 indexed swarmId, string charterURI);
    event AuthorityTransferred(bytes32 indexed swarmId, T.DecisionPoint indexed decisionPoint,
                               address indexed previous, address next);
    event AccountSet(bytes32 indexed swarmId, address account, address by);
    event Changed(bytes32 indexed swarmId, uint64 indexed revision, bytes4 selector, address by);
    event MemberApplied(bytes32 indexed swarmId, address indexed account, bytes32 indexed roleId, bytes32 charterHash);
    event MemberAdmitted(bytes32 indexed swarmId, address indexed account, bytes32 indexed roleId, address by);
    event CharterAccepted(bytes32 indexed swarmId, address indexed account, bytes32 charterHash,
                          uint32 charterVersion, uint32 commitmentVersion, bool signed);
    event MemberActivated(bytes32 indexed swarmId, address indexed account, bytes32 indexed roleId, uint32 phase);
    event MemberSuspended(bytes32 indexed swarmId, address indexed account, T.SuspensionCause cause, address by);
    event MemberReinstated(bytes32 indexed swarmId, address indexed account, address by);
    event MemberExited(bytes32 indexed swarmId, address indexed account, T.ExitReason reason, bool onAmendment, address by);
    event MemberSubstituted(bytes32 indexed swarmId, address indexed previous, address indexed next, bytes32 roleId, address by);
    event MemberCarried(bytes32 indexed swarmId, address indexed account, bytes32 indexed roleId, uint32 phase);
    event Challenged(bytes32 indexed swarmId, address indexed account, address indexed by, bool eligible);
    event Contribution(bytes32 indexed swarmId, address indexed contributor, uint32 indexed phase,
                       bytes32 contributionHash, string uri, uint32 charterVersion, bool isMember, bool whileSuspended);
    event MilestoneRecorded(bytes32 indexed swarmId, uint32 indexed index, T.MilestoneStatus status,
                            bytes32 resultHash, address by);
    event ResourceAttached(bytes32 indexed swarmId, bytes32 indexed resourceId, bytes32 indexed kind,
                           uint256 chainId, address target, uint256 id, bytes32 digest, bytes32 digestKind,
                           string uri, bytes32 roleId, address provider, address by);
    event ResourceDetached(bytes32 indexed swarmId, bytes32 indexed resourceId, address by);
    event TermRegistered(bytes32 indexed dimension, bytes32 indexed term, string uri, address by);
}
