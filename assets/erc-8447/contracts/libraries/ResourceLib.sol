// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import "../SAIErrors.sol";
import {SAIStore as S, ISwarmRegistryEvents as E} from "./SAIStore.sol";
import {IResourceAdapter} from "../interfaces/IResourceAdapter.sol";

/// @title  ResourceLib — resources, posture vocabulary and milestones (v0.2)
/// @notice External library executed in the registry's context (DELEGATECALL).
library ResourceLib {
    using S for S.Store;

    function attach(S.Store storage st, bytes32 id, T.ResourceInput calldata r) external returns (bytes32 resourceId) {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.FORMING && s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.ATTACH);
        if (r.kind == bytes32(0)) revert SAI_ZeroKind();
        if (r.digest == bytes32(0)) revert SAI_ZeroDigest();
        if (r.roleId != bytes32(0) && st.roleIndex[id][r.roleId] == 0) revert SAI_UnknownRole();
        address adapter = st.resourceAdapters[r.kind];
        if (adapter != address(0) && (r.chainId != 0 || r.target != address(0))) {
            IResourceAdapter ad = IResourceAdapter(adapter);
            if (!ad.exists(r.chainId, r.target, r.id)) revert SAI_AnchorMissing();
            (bytes32 d, bytes32 dk) = ad.digestOf(r.chainId, r.target, r.id);
            if (d != r.digest || dk != r.digestKind) revert SAI_DigestMismatch();
        }
        bytes32[] storage ids = st.resourceIds[id];
        resourceId = keccak256(abi.encode(id, ids.length));
        ids.push(resourceId);
        T.Resource storage res = st.resources[id][resourceId];
        res.kind = r.kind;
        res.chainId = r.chainId;
        res.target = r.target;
        res.id = r.id;
        res.digest = r.digest;
        res.digestKind = r.digestKind;
        res.uri = r.uri;
        res.roleId = r.roleId;
        res.provider = r.provider;
        res.attachedBy = msg.sender;
        res.attachedAt = uint64(block.timestamp);
        s.lastActivity = uint64(block.timestamp);
        emit E.ResourceAttached(id, resourceId, r.kind, r.chainId, r.target, r.id, r.digest, r.digestKind, r.uri,
                                r.roleId, r.provider, msg.sender);
    }

    function detach(S.Store storage st, bytes32 id, bytes32 resourceId) external {
        T.Swarm storage s = st.live(id);
        if (s.state == T.LifecycleState.DISSOLVED) revert SAI_WrongState();
        st.auth(id, T.DecisionPoint.DETACH);
        T.Resource storage res = st.resources[id][resourceId];
        if (res.kind == bytes32(0)) revert SAI_UnknownResource();
        if (res.detached) revert SAI_Detached();
        res.detached = true;
        emit E.ResourceDetached(id, resourceId, msg.sender);
    }

    function registerTerm(S.Store storage st, bytes32 dimension, bytes32 term, string calldata uri) external {
        if (dimension != T.DIM_PAYOFF && dimension != T.DIM_TOPOLOGY && dimension != T.DIM_COORDINATION) revert SAI_UnknownDimension();
        if (term == bytes32(0)) revert SAI_ZeroTerm();
        if (st.terms[dimension][term]) revert SAI_TermExists();
        st.terms[dimension][term] = true;
        st.termURIs[dimension][term] = uri;
        emit E.TermRegistered(dimension, term, uri, msg.sender);
    }

    function seedTerm(S.Store storage st, bytes32 dimension, string memory name) external {
        bytes32 term = keccak256(bytes(name));
        st.terms[dimension][term] = true;
        st.termURIs[dimension][term] = name;
        emit E.TermRegistered(dimension, term, name, address(0));
    }

    function recordMilestone(S.Store storage st, bytes32 id, uint32 index, T.MilestoneStatus status, bytes32 resultHash) external {
        T.Swarm storage s = st.live(id);
        if (s.state != T.LifecycleState.ACTIVE) revert SAI_WrongState();
        T.Objective storage o = st.objectives[id];
        if (msg.sender != o.acceptanceAuthority || msg.sender == address(0)) revert SAI_NotAuthorized();
        if (index >= o.milestoneCount) revert SAI_MilestoneIndex();
        if (status == T.MilestoneStatus.PENDING) revert SAI_MilestoneStatus();
        S.Milestone storage ms = st.milestones[id][index];
        if (ms.status == T.MilestoneStatus.ACCEPTED) revert SAI_MilestoneFinal();
        ms.status = status;
        ms.resultHash = resultHash;
        ms.at = uint64(block.timestamp);
        if (status == T.MilestoneStatus.ACCEPTED) o.milestonesAccepted += 1;
        s.lastActivity = uint64(block.timestamp);
        emit E.MilestoneRecorded(id, index, status, resultHash, msg.sender);
    }
}
