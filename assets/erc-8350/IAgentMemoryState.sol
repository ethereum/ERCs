// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title Agent Memory State
/// @notice Minimal interface for authorized, privacy-preserving memory state transitions.
interface IAgentMemoryState {
    /// @dev The complete normative v1 claim. Field order is part of the standard.
    struct ExperienceDelta {
        bytes32 spaceId;
        uint64 sequence;
        bytes32 prevStateRoot;
        bytes32 deltaCommitment;
        bytes32 provenanceCommitment;
        bytes32 profileId;
        bytes32 locatorCommitment;
    }

    event SpaceRegistered(
        bytes32 indexed spaceId, address indexed controller, address indexed authorizer
    );

    event SpaceAuthorizationUpdated(
        bytes32 indexed spaceId,
        address indexed controller,
        address indexed authorizer,
        uint64 configNonce
    );

    event TransitionCommitted(
        bytes32 indexed spaceId,
        bytes32 indexed transitionId,
        uint64 indexed sequence,
        bytes32 prevStateRoot,
        bytes32 nextStateRoot,
        bytes32 deltaCommitment,
        bytes32 provenanceCommitment,
        bytes32 profileId,
        bytes32 locatorCommitment,
        address authorizer
    );

    /// @notice Register a new namespace. A relayer may submit a controller signature.
    /// @dev An empty signature is accepted only when `msg.sender == controller`.
    function registerSpace(
        bytes32 spaceId,
        address controller,
        address authorizer,
        bytes32 salt,
        bytes calldata controllerSignature
    ) external;

    /// @notice Rotate controller and/or transition authorizer.
    function updateSpaceAuthorization(
        bytes32 spaceId,
        address newController,
        address newAuthorizer,
        bytes calldata controllerSignature
    ) external;

    /// @notice Advance a registered space by exactly one valid state transition.
    function commitTransition(ExperienceDelta calldata delta, bytes calldata authorizerSignature)
        external
        returns (bytes32 transitionId, bytes32 nextStateRoot);

    function head(bytes32 spaceId)
        external
        view
        returns (bytes32 transitionId, bytes32 stateRoot, uint64 sequence);

    function spaceAuthorization(bytes32 spaceId)
        external
        view
        returns (address controller, address authorizer, uint64 configNonce);

    function transition(bytes32 transitionId)
        external
        view
        returns (bytes32 spaceId, bytes32 nextStateRoot, uint64 sequence, uint64 committedAt);

    function hashExperienceDelta(ExperienceDelta calldata delta)
        external
        pure
        returns (bytes32 transitionId);

    function computeNextStateRoot(bytes32 prevStateRoot, bytes32 transitionId)
        external
        pure
        returns (bytes32 nextStateRoot);

    function signingDigest(bytes32 structHash) external view returns (bytes32 digest);

    function deriveSpaceId(address initialController, bytes32 salt)
        external
        pure
        returns (bytes32 spaceId);
}
