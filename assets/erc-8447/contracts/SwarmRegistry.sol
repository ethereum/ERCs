// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "./SAITypes.sol";
import "./SAIErrors.sol";
import {ISwarmRegistry} from "./interfaces/ISwarmRegistry.sol";
import {IResourceAdapter} from "./interfaces/IResourceAdapter.sol";
import {SAIStore as S} from "./libraries/SAIStore.sol";
import {LifecycleLib} from "./libraries/LifecycleLib.sol";
import {MembershipLib} from "./libraries/MembershipLib.sol";
import {ResourceLib} from "./libraries/ResourceLib.sol";

/// @title  SwarmRegistry — Swarm AI Framework reference registry (v0.3)
/// @notice Non-upgradeable, permissionless. One instance, one clock (block timestamps). The
///         registry holds the normative record of swarms and executes only the transitions of
///         ISwarmRegistry, each gated by the authority the swarm's hashed specification assigns.
///         Logic lives in three external libraries linked at deployment (LifecycleLib,
///         MembershipLib, ResourceLib) plus the spec validator; they run in this contract's
///         context and never hold state. Roster-wide exits (SWARM_DISSOLVED, NOT_CARRIED) are
///         derived lazily by memberStatus, so no fallback ever loops over an unbounded roster.
contract SwarmRegistry is ISwarmRegistry {
    using S for S.Store;

    S.Store private st;

    // ------------------------------------------------------------------ construction

    /// @param kinds    resource kinds with a verifying adapter in this deployment (write-once)
    /// @param adapters the adapters, one per kind
    constructor(bytes32[] memory kinds, address[] memory adapters) {
        require(kinds.length == adapters.length);
        for (uint256 i = 0; i < kinds.length; i++) {
            require(adapters[i].code.length > 0 && IResourceAdapter(adapters[i]).kind() == kinds[i]);
            st.resourceAdapters[kinds[i]] = adapters[i];
        }
        ResourceLib.seedTerm(st, T.DIM_PAYOFF, "sai.payoff.shared");
        ResourceLib.seedTerm(st, T.DIM_PAYOFF, "sai.payoff.exclusive");
        ResourceLib.seedTerm(st, T.DIM_PAYOFF, "sai.payoff.mixed");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.redundant");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.partitioned");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.sequential");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.hierarchical");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.iterative");
        ResourceLib.seedTerm(st, T.DIM_TOPOLOGY, "sai.topology.free");
        ResourceLib.seedTerm(st, T.DIM_COORDINATION, "sai.coordination.leader");
        ResourceLib.seedTerm(st, T.DIM_COORDINATION, "sai.coordination.collective");
        ResourceLib.seedTerm(st, T.DIM_COORDINATION, "sai.coordination.market");
        ResourceLib.seedTerm(st, T.DIM_COORDINATION, "sai.coordination.automated");
        ResourceLib.seedTerm(st, T.DIM_COORDINATION, "sai.coordination.none");
    }

    // ------------------------------------------------------------------ ERC-165 / ERC-6372

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISwarmRegistry).interfaceId || interfaceId == 0x01ffc9a7;
    }

    function clock() external view returns (uint48) { return uint48(block.timestamp); }
    function CLOCK_MODE() external pure returns (string memory) { return "mode=timestamp"; }

    // ------------------------------------------------------------------ formation and lifecycle

    function specHashOf(T.SwarmSpec calldata spec) external pure returns (bytes32) { return keccak256(abi.encode(spec)); }

    function form(T.SwarmSpec calldata spec, bytes32 charterHash, bytes32 commitmentHash, string calldata charterURI,
                  bytes32 parentId, T.Origin calldata origin, T.ObjectiveInput calldata objective)
        external returns (bytes32 swarmId)
    {
        swarmId = LifecycleLib.form(st, spec, charterHash, commitmentHash, charterURI, parentId, origin, objective, bytes32(0));
        _bump(swarmId);
    }

    function activate(bytes32 swarmId) external { LifecycleLib.activate(st, swarmId); _bump(swarmId); }
    function abort(bytes32 swarmId) external { LifecycleLib.abort(st, swarmId); _bump(swarmId); }
    function suspend(bytes32 swarmId) external { LifecycleLib.suspend(st, swarmId); _bump(swarmId); }
    function resume(bytes32 swarmId) external { LifecycleLib.resume(st, swarmId); _bump(swarmId); }
    function enforceRoster(bytes32 swarmId) external { LifecycleLib.enforceRoster(st, swarmId); _bump(swarmId); }
    function enforceInactivity(bytes32 swarmId) external { LifecycleLib.enforceInactivity(st, swarmId); _bump(swarmId); }
    function enforceDeadline(bytes32 swarmId) external { LifecycleLib.enforceDeadline(st, swarmId); _bump(swarmId); }

    function advance(bytes32 swarmId, address[] calldata carried, bytes32[] calldata roles) external {
        LifecycleLib.advance(st, swarmId, carried, roles);
        _bump(swarmId);
    }

    function conclude(bytes32 swarmId, T.OutcomeType outcome, bytes32 resultHash) external {
        LifecycleLib.conclude(st, swarmId, outcome, resultHash);
        _bump(swarmId);
    }

    function dissolve(bytes32 swarmId) external { LifecycleLib.dissolve(st, swarmId); _bump(swarmId); }

    function succeed(bytes32 swarmId, T.SwarmSpec calldata newSpec, bytes32 charterHash, bytes32 commitmentHash,
                     string calldata charterURI, T.ObjectiveInput calldata objective,
                     address[] calldata carried, bytes32[] calldata roles)
        external returns (bytes32 successorId)
    {
        successorId = LifecycleLib.succeed(st, swarmId, newSpec, charterHash, commitmentHash, charterURI, objective, carried, roles);
        _bump(swarmId);
        _bump(successorId);
    }

    // ------------------------------------------------------------------ charter, authority, account

    function amend(bytes32 swarmId, bytes32 charterHash, string calldata charterURI, bytes32 objectiveHash,
                   bytes32 commitmentHash, bool material) external
    {
        LifecycleLib.amend(st, swarmId, charterHash, charterURI, objectiveHash, commitmentHash, material);
        _bump(swarmId);
    }

    function setCharterURI(bytes32 swarmId, string calldata charterURI) external {
        LifecycleLib.setCharterURI(st, swarmId, charterURI);
        _bump(swarmId);
    }

    function transferAuthority(bytes32 swarmId, T.DecisionPoint decisionPoint, address newAuthority) external {
        LifecycleLib.transferAuthority(st, swarmId, decisionPoint, newAuthority);
        _bump(swarmId);
    }

    function setAccount(bytes32 swarmId, address account) external {
        LifecycleLib.setAccount(st, swarmId, account);
        _bump(swarmId);
    }

    // ------------------------------------------------------------------ membership

    function applyToJoin(bytes32 swarmId, bytes32 roleId, bytes32 charterHash) external {
        MembershipLib.memberSide(st, swarmId, msg.sender, roleId, charterHash, false, false);
        _bump(swarmId);
    }

    function join(bytes32 swarmId, bytes32 roleId, bytes32 charterHash) external {
        MembershipLib.memberSide(st, swarmId, msg.sender, roleId, charterHash, true, false);
        _bump(swarmId);
    }

    function joinBySig(bytes32 swarmId, address account, bytes32 roleId, bytes32 charterHash,
                       uint256 deadline, bytes calldata signature) external
    {
        MembershipLib.joinBySig(st, swarmId, account, roleId, charterHash, deadline, signature);
        _bump(swarmId);
    }

    function acceptCharter(bytes32 swarmId, bytes32 charterHash) external {
        MembershipLib.acceptCharter(st, swarmId, charterHash);
        _bump(swarmId);
    }

    function admit(bytes32 swarmId, address account, bytes32 roleId) external {
        MembershipLib.admit(st, swarmId, account, roleId);
        _bump(swarmId);
    }

    function leave(bytes32 swarmId) external { MembershipLib.leave(st, swarmId); _bump(swarmId); }
    function suspendMember(bytes32 swarmId, address account) external { MembershipLib.suspendMember(st, swarmId, account); _bump(swarmId); }
    function reinstate(bytes32 swarmId, address account) external { MembershipLib.reinstate(st, swarmId, account); _bump(swarmId); }
    function remove(bytes32 swarmId, address account) external { MembershipLib.remove(st, swarmId, account); _bump(swarmId); }

    function challenge(bytes32 swarmId, address account) external returns (bool evaluated, bool eligible) {
        (evaluated, eligible) = MembershipLib.challenge(st, swarmId, account);
        if (evaluated) _bump(swarmId);
    }

    function expel(bytes32 swarmId, address account) external { MembershipLib.expel(st, swarmId, account); _bump(swarmId); }

    function substitute(bytes32 swarmId, address previous, address next) external {
        MembershipLib.substitute(st, swarmId, previous, next);
        _bump(swarmId);
    }

    // ------------------------------------------------------------------ objective and process

    function recordContribution(bytes32 swarmId, bytes32 contributionHash, string calldata uri) external {
        MembershipLib.recordContribution(st, swarmId, contributionHash, uri);
        _bump(swarmId);
    }

    function recordMilestone(bytes32 swarmId, uint32 index, T.MilestoneStatus status, bytes32 resultHash) external {
        ResourceLib.recordMilestone(st, swarmId, index, status, resultHash);
        _bump(swarmId);
    }

    // ------------------------------------------------------------------ resources and vocabulary

    function attach(bytes32 swarmId, T.ResourceInput calldata resource) external returns (bytes32 resourceId) {
        resourceId = ResourceLib.attach(st, swarmId, resource);
        _bump(swarmId);
    }

    function detach(bytes32 swarmId, bytes32 resourceId) external { ResourceLib.detach(st, swarmId, resourceId); _bump(swarmId); }

    function registerTerm(bytes32 dimension, bytes32 term, string calldata uri) external {
        ResourceLib.registerTerm(st, dimension, term, uri);
    }

    // ------------------------------------------------------------------ views

    function getSwarm(bytes32 swarmId) external view returns (T.Swarm memory) { return st.swarms[swarmId]; }
    function specOf(bytes32 swarmId) external view returns (T.SwarmSpec memory) { return st.specs[swarmId]; }
    function phaseSpecOf(bytes32 swarmId, uint32 phase) external view returns (T.PhaseSpec memory) { return st.specs[swarmId].phases[phase]; }
    function roleSpecOf(bytes32 swarmId, bytes32 roleId) external view returns (T.RoleSpec memory) { return st.roleOf(swarmId, roleId); }
    function authorityOf(bytes32 swarmId, T.DecisionPoint decisionPoint) external view returns (T.Authority memory) {
        return st.authorities[swarmId][uint256(decisionPoint)];
    }
    function isAuthorized(bytes32 swarmId, T.DecisionPoint decisionPoint, address account) external view returns (bool) {
        return st.isAuthorized(swarmId, decisionPoint, account);
    }
    function objectiveOf(bytes32 swarmId) external view returns (T.Objective memory) { return st.objectives[swarmId]; }
    function milestoneOf(bytes32 swarmId, uint32 index) external view returns (T.MilestoneStatus status, bytes32 resultHash, uint64 at) {
        S.Milestone storage ms = st.milestones[swarmId][index];
        return (ms.status, ms.resultHash, ms.at);
    }
    function getMember(bytes32 swarmId, address account) external view returns (T.Member memory m) {
        m = st.members[swarmId][account];
        (m.status, m.exitReason) = S.derivedPair(st.swarms[swarmId], st.members[swarmId][account]);
    }
    function memberStatus(bytes32 swarmId, address account) external view returns (T.MemberStatus status, T.ExitReason exitReason) {
        return S.derivedPair(st.swarms[swarmId], st.members[swarmId][account]);
    }
    function memberCount(bytes32 swarmId) external view returns (uint32 active, uint32 suspended, uint32 candidates) {
        if (st.swarms[swarmId].state == T.LifecycleState.DISSOLVED) return (0, 0, 0);
        S.Counts storage c = st.counts[swarmId];
        return (c.active, c.suspended, c.candidates);
    }
    function roleCount(bytes32 swarmId, bytes32 roleId) external view returns (uint32 active, uint32 suspended) {
        if (st.swarms[swarmId].state == T.LifecycleState.DISSOLVED) return (0, 0);
        S.RoleCounts storage rc = st.roleCounts[swarmId][roleId];
        return (rc.active, rc.suspended);
    }
    function rosterMet(bytes32 swarmId) external view returns (bool) { return st.rosterMet(swarmId); }
    function acceptedCharterOf(bytes32 swarmId, address account) external view
        returns (bytes32 charterHash, uint32 charterVersion, uint32 commitmentVersion)
    {
        T.Member storage m = st.members[swarmId][account];
        return (m.acceptedCharter, m.acceptedVersion, m.acceptedCommitment);
    }
    function seatEpochOf(bytes32 swarmId, address account) external view returns (uint256) { return st.seatEpochs[swarmId][account]; }
    function getResource(bytes32 swarmId, bytes32 resourceId) external view returns (T.Resource memory) { return st.resources[swarmId][resourceId]; }
    function resourceCount(bytes32 swarmId) external view returns (uint256) { return st.resourceIds[swarmId].length; }
    function resourceAt(bytes32 swarmId, uint256 index) external view returns (bytes32) { return st.resourceIds[swarmId][index]; }
    function resourceAdapterOf(bytes32 kind) external view returns (address) { return st.resourceAdapters[kind]; }
    function termURI(bytes32 dimension, bytes32 term) external view returns (string memory) { return st.termURIs[dimension][term]; }
    function isTerm(bytes32 dimension, bytes32 term) external view returns (bool) { return st.terms[dimension][term]; }
    function hardDeadlineOf(bytes32 swarmId) external view returns (uint64) { return S.hardDeadline(st.swarms[swarmId], st.specs[swarmId]); }
    function inputOpen(bytes32 swarmId) external view returns (bool) {
        T.Swarm storage s = st.swarms[swarmId];
        if (s.state == T.LifecycleState.FORMING) return true;
        if (s.state != T.LifecycleState.ACTIVE) return false;
        return S.inputOpen(s, st.specs[swarmId].phases[s.phase]);
    }
    function joinDigest(bytes32 swarmId, address account, bytes32 roleId, bytes32 charterHash, uint256 deadline)
        external view returns (bytes32)
    {
        return MembershipLib.joinDigest(st, swarmId, account, roleId, charterHash, deadline);
    }

    // ------------------------------------------------------------------ internals

    function _bump(bytes32 id) private {
        T.Swarm storage s = st.swarms[id];
        s.revision += 1;
        emit Changed(id, s.revision, msg.sig, msg.sender);
    }
}
