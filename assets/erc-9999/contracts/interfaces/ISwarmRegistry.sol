// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";

/// @title  ISwarmRegistry — Swarm AI Framework registry (reference v0.2)
/// @notice The registry is the normative record of swarms: their specification and charter
///         commitments, lifecycle state, phases, membership ledger, objective binding,
///         attached resources, decision-point authorities and the posture vocabulary. It
///         executes only the transitions this interface names, each gated by the authority
///         the swarm's specification assigns to the decision point. It never moves value;
///         the only contracts it calls are the eligibility modules and resource adapters a
///         spec or deployment names, the swarm account it is asked to bind, and ERC-1271
///         signers.
interface ISwarmRegistry /* is IERC165, IERC6372 */ {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // ------------------------------------------------------------------ lifecycle events

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
    /// Emitted by every state-changing call after its own event(s): the swarm's organizational
    /// change log. `revision` is strictly increasing per swarm; `selector` names the function.
    event Changed(bytes32 indexed swarmId, uint64 indexed revision, bytes4 selector, address by);

    // ------------------------------------------------------------------ membership events

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

    // ------------------------------------------------------------------ process events

    event Contribution(bytes32 indexed swarmId, address indexed contributor, uint32 indexed phase,
                       bytes32 contributionHash, string uri, uint32 charterVersion, bool isMember, bool whileSuspended);
    event MilestoneRecorded(bytes32 indexed swarmId, uint32 indexed index, T.MilestoneStatus status,
                            bytes32 resultHash, address by);
    event ResourceAttached(bytes32 indexed swarmId, bytes32 indexed resourceId, bytes32 indexed kind,
                           uint256 chainId, address target, uint256 id, bytes32 digest, bytes32 digestKind,
                           string uri, bytes32 roleId, address provider, address by);
    event ResourceDetached(bytes32 indexed swarmId, bytes32 indexed resourceId, address by);
    event TermRegistered(bytes32 indexed dimension, bytes32 indexed term, string uri, address by);

    // ------------------------------------------------------------------ formation and lifecycle

    function specHashOf(T.SwarmSpec calldata spec) external pure returns (bytes32);

    /// Forms a swarm in state FORMING. `msg.sender` is recorded as the initiator for ever.
    function form(T.SwarmSpec calldata spec, bytes32 charterHash, string calldata charterURI,
                  bytes32 parentId, T.Origin calldata origin, T.ObjectiveInput calldata objective)
        external returns (bytes32 swarmId);

    function activate(bytes32 swarmId) external;          // ACTIVATE authority and/or roster thresholds
    function abort(bytes32 swarmId) external;             // ABORT authority, or anyone after the recruitment window
    function suspend(bytes32 swarmId) external;           // SUSPEND authority
    function resume(bytes32 swarmId) external;            // RESUME authority; anyone when the cause was ROSTER_LOST and the roster holds again
    function enforceRoster(bytes32 swarmId) external;     // anyone: ACTIVE -> SUSPENDED(ROSTER_LOST) when thresholds fail
    function enforceInactivity(bytes32 swarmId) external; // anyone: ACTIVE -> SUSPENDED(INACTIVITY); SUSPENDED -> CONCLUDING(ABANDONED)
    function enforceDeadline(bytes32 swarmId) external;   // anyone after the hard deadline: -> CONCLUDING(ABANDONED, TIMEOUT)
    function advance(bytes32 swarmId, address[] calldata carried, bytes32[] calldata roles) external; // ADVANCE authority
    function conclude(bytes32 swarmId, T.OutcomeType outcome, bytes32 resultHash) external; // CONCLUDE authority or the acceptance authority
    function dissolve(bytes32 swarmId) external;          // DISSOLVE authority, or anyone after the settlement window

    /// Forms a successor swarm, carrying the listed members as admitted candidates of the
    /// successor, and concludes this swarm SUPERSEDED.
    function succeed(bytes32 swarmId, T.SwarmSpec calldata newSpec, bytes32 charterHash, string calldata charterURI,
                     T.ObjectiveInput calldata objective, address[] calldata carried, bytes32[] calldata roles)
        external returns (bytes32 successorId);

    // ------------------------------------------------------------------ charter, authority, account

    function amend(bytes32 swarmId, bytes32 charterHash, string calldata charterURI, bytes32 objectiveHash,
                   bool material) external;                                                                      // AMEND authority
    function setCharterURI(bytes32 swarmId, string calldata charterURI) external;                                // AMEND authority
    function transferAuthority(bytes32 swarmId, T.DecisionPoint decisionPoint, address newAuthority) external;  // the current ADDRESS holder
    function setAccount(bytes32 swarmId, address account) external;                                              // SET_ACCOUNT authority

    // ------------------------------------------------------------------ membership

    function applyToJoin(bytes32 swarmId, bytes32 roleId, bytes32 charterHash) external;           // candidate: wherever join is refused for boundary or selfJoin
    function join(bytes32 swarmId, bytes32 roleId, bytes32 charterHash) external;                  // candidate: OPEN phases, selfJoin roles
    function joinBySig(bytes32 swarmId, address account, bytes32 roleId, bytes32 charterHash,
                       uint256 deadline, bytes calldata signature) external;                       // anyone relays an EIP-712 acceptance (digest binds seat epoch and phase)
    function acceptCharter(bytes32 swarmId, bytes32 charterHash) external;                         // an account with a seat (candidate, active or suspended)
    function admit(bytes32 swarmId, address account, bytes32 roleId) external;                     // ADMIT authority
    function leave(bytes32 swarmId) external;                                                      // the member; always available until DISSOLVED
    function suspendMember(bytes32 swarmId, address account) external;                             // REMOVE authority
    function reinstate(bytes32 swarmId, address account) external;                                 // REINSTATE authority
    function remove(bytes32 swarmId, address account) external;                                    // REMOVE authority; ADMIT authority for a candidate
    function challenge(bytes32 swarmId, address account) external returns (bool evaluated, bool eligible); // anyone: re-evaluates eligibility
    function expel(bytes32 swarmId, address account) external;                                     // anyone after the ineligible grace
    function substitute(bytes32 swarmId, address previous, address next) external;                 // ADMIT authority

    // ------------------------------------------------------------------ objective and process

    function recordContribution(bytes32 swarmId, bytes32 contributionHash, string calldata uri) external; // per the spec's contribution mode
    function recordMilestone(bytes32 swarmId, uint32 index, T.MilestoneStatus status, bytes32 resultHash) external; // acceptance authority

    // ------------------------------------------------------------------ resources and vocabulary

    function attach(bytes32 swarmId, T.ResourceInput calldata resource) external returns (bytes32 resourceId); // ATTACH authority
    function detach(bytes32 swarmId, bytes32 resourceId) external;                                             // DETACH authority
    function registerTerm(bytes32 dimension, bytes32 term, string calldata uri) external;                    // anyone, write-once

    // ------------------------------------------------------------------ views

    function getSwarm(bytes32 swarmId) external view returns (T.Swarm memory);
    function specOf(bytes32 swarmId) external view returns (T.SwarmSpec memory);
    function phaseSpecOf(bytes32 swarmId, uint32 phase) external view returns (T.PhaseSpec memory);
    function roleSpecOf(bytes32 swarmId, bytes32 roleId) external view returns (T.RoleSpec memory);
    function authorityOf(bytes32 swarmId, T.DecisionPoint decisionPoint) external view returns (T.Authority memory);
    function isAuthorized(bytes32 swarmId, T.DecisionPoint decisionPoint, address account) external view returns (bool);
    function objectiveOf(bytes32 swarmId) external view returns (T.Objective memory);
    function milestoneOf(bytes32 swarmId, uint32 index) external view returns (T.MilestoneStatus status, bytes32 resultHash, uint64 at);
    function getMember(bytes32 swarmId, address account) external view returns (T.Member memory);
    function memberStatus(bytes32 swarmId, address account) external view returns (T.MemberStatus status, T.ExitReason exitReason);
    function memberCount(bytes32 swarmId) external view returns (uint32 active, uint32 suspended, uint32 candidates);
    function roleCount(bytes32 swarmId, bytes32 roleId) external view returns (uint32 active, uint32 suspended);
    function rosterMet(bytes32 swarmId) external view returns (bool);
    function acceptedCharterOf(bytes32 swarmId, address account) external view
        returns (bytes32 charterHash, uint32 charterVersion, uint32 commitmentVersion);
    function seatEpochOf(bytes32 swarmId, address account) external view returns (uint256);
    function getResource(bytes32 swarmId, bytes32 resourceId) external view returns (T.Resource memory);
    function resourceCount(bytes32 swarmId) external view returns (uint256);
    function resourceAt(bytes32 swarmId, uint256 index) external view returns (bytes32 resourceId);
    function resourceAdapterOf(bytes32 kind) external view returns (address);
    function termURI(bytes32 dimension, bytes32 term) external view returns (string memory);
    function isTerm(bytes32 dimension, bytes32 term) external view returns (bool);
    function hardDeadlineOf(bytes32 swarmId) external view returns (uint64);
    function inputOpen(bytes32 swarmId) external view returns (bool);
    function joinDigest(bytes32 swarmId, address account, bytes32 roleId, bytes32 charterHash, uint256 deadline)
        external view returns (bytes32);

    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
