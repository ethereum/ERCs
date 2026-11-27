// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IConfidentialPolicyVerdict, Verdict, IPolicyGuarded} from "./IConfidentialPolicyVerdict.sol";
import {PolicyAction, PolicyActionLib} from "./PolicyAction.sol";

/// @notice Example guarded contract. Recomputes the canonical actionCommitment from the action
/// it is about to dispatch, requires it match the verdict, consumes the verdict, then executes.
/// @dev Action-binding lives here (not in the Guard): `consume` receives a `Verdict` but not the
/// action params, so this contract recomputes the commitment via the canonical `PolicyActionLib`
/// — the same preimage the proving program uses. The executor question is resolved cryptographically:
/// pass `executorAuth = ""` to consume on this contract's own behalf (v.executor == this), or pass a
/// signature by an end-user `v.executor` and this contract relays it. Because the action is committed
/// and the executor is bound by signature, front-running `execute()` is neutral.
contract GuardedExecutor is IPolicyGuarded {
    using PolicyActionLib for PolicyAction;

    IConfidentialPolicyVerdict public immutable guard;
    bytes32 public immutable domainId;

    mapping(uint256 => uint256) public actionNonce; // per ERC-8004 agentId, monotonic

    error ActionCommitmentMismatch(bytes32 expected, bytes32 got);
    error ActionFailed();

    constructor(IConfidentialPolicyVerdict _guard, bytes32 _domainId) {
        guard = _guard;
        domainId = _domainId;
    }

    function policyDomain() external view returns (bytes32) {
        return domainId;
    }

    /// @dev The canonical commitment: binds chainId + domainId (replay separation), agentId,
    /// the action, and a monotonic per-agent nonce.
    function actionCommitmentOf(uint256 agentId, address target, uint256 value, bytes calldata callData)
        public
        view
        returns (bytes32)
    {
        return PolicyAction({
            chainId: block.chainid,
            domainId: domainId,
            agentId: agentId,
            target: target,
            value: value,
            callDataHash: keccak256(callData),
            actionNonce: actionNonce[agentId]
        }).commit();
    }

    function execute(
        Verdict calldata v,
        bytes calldata proof,
        bytes calldata executorAuth,
        address target,
        uint256 value,
        bytes calldata callData
    ) external returns (bytes memory) {
        bytes32 expected = actionCommitmentOf(v.agentId, target, value, callData);
        if (expected != v.actionCommitment) revert ActionCommitmentMismatch(expected, v.actionCommitment);
        actionNonce[v.agentId] += 1;

        guard.consume(v, proof, executorAuth); // reverts the whole tx on any failure

        (bool ok, bytes memory ret) = target.call{value: value}(callData);
        if (!ok) revert ActionFailed();
        return ret;
    }
}
