// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ECDSA} from "./ECDSA.sol";
import {IAgentMemoryState} from "./IAgentMemoryState.sol";
import {IERC1271} from "./IERC1271.sol";

/// @title AgentMemoryStateRegistry
/// @notice Reference implementation of ExperienceDelta v1 and its linear state machine.
contract AgentMemoryStateRegistry is IAgentMemoryState {
    error ZeroSpaceId();
    error ZeroAddress();
    error InvalidSpaceId(bytes32 expected, bytes32 received);
    error SpaceAlreadyRegistered();
    error UnknownSpace();
    error InvalidAuthorization();
    error BadSequence(uint64 expected, uint64 received);
    error BadPreviousState(bytes32 expected, bytes32 received);
    error TransitionAlreadyExists();
    error ZeroDeltaCommitment();
    error ZeroProfileId();

    string public constant EIP712_NAME = "AgentMemoryState";
    string public constant EIP712_VERSION = "1";

    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant EXPERIENCE_DELTA_TYPEHASH = keccak256(
        "ExperienceDelta(bytes32 spaceId,uint64 sequence,bytes32 prevStateRoot,bytes32 deltaCommitment,bytes32 provenanceCommitment,bytes32 profileId,bytes32 locatorCommitment)"
    );
    bytes32 public constant MEMORY_STATE_TYPEHASH =
        keccak256("MemoryState(bytes32 prevStateRoot,bytes32 transitionId)");
    bytes32 public constant SPACE_REGISTRATION_TYPEHASH =
        keccak256("SpaceRegistration(bytes32 spaceId,address controller,address authorizer)");
    bytes32 public constant MEMORY_SPACE_TYPEHASH =
        keccak256("MemorySpace(address initialController,bytes32 salt)");
    bytes32 public constant SPACE_AUTHORIZATION_TYPEHASH = keccak256(
        "SpaceAuthorization(bytes32 spaceId,address newController,address newAuthorizer,uint64 nonce)"
    );

    bytes4 private constant _ERC1271_MAGIC_VALUE = IERC1271.isValidSignature.selector;

    struct SpaceRecord {
        address controller;
        address authorizer;
        bytes32 transitionId;
        bytes32 stateRoot;
        uint64 sequence;
        uint64 configNonce;
    }

    struct StoredTransition {
        bytes32 spaceId;
        bytes32 nextStateRoot;
        uint64 sequence;
        uint64 committedAt;
    }

    mapping(bytes32 spaceId => SpaceRecord) private _spaces;
    mapping(bytes32 transitionId => StoredTransition) private _transitions;

    uint256 private immutable _cachedChainId;
    bytes32 private immutable _cachedDomainSeparator;

    constructor() {
        _cachedChainId = block.chainid;
        _cachedDomainSeparator = _buildDomainSeparator();
    }

    function registerSpace(
        bytes32 spaceId,
        address controller,
        address authorizer,
        bytes32 salt,
        bytes calldata controllerSignature
    ) external {
        if (spaceId == bytes32(0)) revert ZeroSpaceId();
        if (controller == address(0) || authorizer == address(0)) revert ZeroAddress();
        bytes32 expectedSpaceId = deriveSpaceId(controller, salt);
        if (spaceId != expectedSpaceId) revert InvalidSpaceId(expectedSpaceId, spaceId);
        if (_spaces[spaceId].controller != address(0)) revert SpaceAlreadyRegistered();

        bytes32 registrationId =
            keccak256(abi.encode(SPACE_REGISTRATION_TYPEHASH, spaceId, controller, authorizer));
        _requireAuthorization(controller, _digest(registrationId), controllerSignature, true);

        _spaces[spaceId] = SpaceRecord({
            controller: controller,
            authorizer: authorizer,
            transitionId: bytes32(0),
            stateRoot: bytes32(0),
            sequence: 0,
            configNonce: 0
        });
        emit SpaceRegistered(spaceId, controller, authorizer);
    }

    function updateSpaceAuthorization(
        bytes32 spaceId,
        address newController,
        address newAuthorizer,
        bytes calldata controllerSignature
    ) external {
        if (newController == address(0) || newAuthorizer == address(0)) {
            revert ZeroAddress();
        }
        SpaceRecord storage space = _space(spaceId);
        uint64 nextNonce = space.configNonce + 1;
        bytes32 authorizationId = keccak256(
            abi.encode(
                SPACE_AUTHORIZATION_TYPEHASH, spaceId, newController, newAuthorizer, nextNonce
            )
        );
        _requireAuthorization(space.controller, _digest(authorizationId), controllerSignature, true);

        space.controller = newController;
        space.authorizer = newAuthorizer;
        space.configNonce = nextNonce;
        emit SpaceAuthorizationUpdated(spaceId, newController, newAuthorizer, nextNonce);
    }

    function commitTransition(ExperienceDelta calldata delta, bytes calldata authorizerSignature)
        external
        returns (bytes32 transitionId, bytes32 nextStateRoot)
    {
        SpaceRecord storage space = _space(delta.spaceId);
        if (delta.deltaCommitment == bytes32(0)) revert ZeroDeltaCommitment();
        if (delta.profileId == bytes32(0)) revert ZeroProfileId();
        uint64 expectedSequence = space.sequence + 1;
        if (delta.sequence != expectedSequence) {
            revert BadSequence(expectedSequence, delta.sequence);
        }
        if (delta.prevStateRoot != space.stateRoot) {
            revert BadPreviousState(space.stateRoot, delta.prevStateRoot);
        }

        transitionId = hashExperienceDelta(delta);
        if (_transitions[transitionId].spaceId != bytes32(0)) revert TransitionAlreadyExists();
        _requireAuthorization(space.authorizer, _digest(transitionId), authorizerSignature, true);

        nextStateRoot = computeNextStateRoot(delta.prevStateRoot, transitionId);
        _transitions[transitionId] = StoredTransition({
            spaceId: delta.spaceId,
            nextStateRoot: nextStateRoot,
            sequence: delta.sequence,
            committedAt: uint64(block.timestamp)
        });
        space.transitionId = transitionId;
        space.stateRoot = nextStateRoot;
        space.sequence = delta.sequence;

        emit TransitionCommitted(
            delta.spaceId,
            transitionId,
            delta.sequence,
            delta.prevStateRoot,
            nextStateRoot,
            delta.deltaCommitment,
            delta.provenanceCommitment,
            delta.profileId,
            delta.locatorCommitment,
            space.authorizer
        );
    }

    function head(bytes32 spaceId)
        external
        view
        returns (bytes32 transitionId, bytes32 stateRoot, uint64 sequence)
    {
        SpaceRecord storage space = _space(spaceId);
        return (space.transitionId, space.stateRoot, space.sequence);
    }

    function spaceAuthorization(bytes32 spaceId)
        external
        view
        returns (address controller, address authorizer, uint64 configNonce)
    {
        SpaceRecord storage space = _space(spaceId);
        return (space.controller, space.authorizer, space.configNonce);
    }

    function transition(bytes32 transitionId)
        external
        view
        returns (bytes32 spaceId, bytes32 nextStateRoot, uint64 sequence, uint64 committedAt)
    {
        StoredTransition storage record = _transitions[transitionId];
        return (record.spaceId, record.nextStateRoot, record.sequence, record.committedAt);
    }

    function hashExperienceDelta(ExperienceDelta calldata delta)
        public
        pure
        returns (bytes32 transitionId)
    {
        return keccak256(
            abi.encode(
                EXPERIENCE_DELTA_TYPEHASH,
                delta.spaceId,
                delta.sequence,
                delta.prevStateRoot,
                delta.deltaCommitment,
                delta.provenanceCommitment,
                delta.profileId,
                delta.locatorCommitment
            )
        );
    }

    function computeNextStateRoot(bytes32 prevStateRoot, bytes32 transitionId)
        public
        pure
        returns (bytes32 nextStateRoot)
    {
        return keccak256(abi.encode(MEMORY_STATE_TYPEHASH, prevStateRoot, transitionId));
    }

    function hashSpaceRegistration(bytes32 spaceId, address controller, address authorizer)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(SPACE_REGISTRATION_TYPEHASH, spaceId, controller, authorizer));
    }

    function deriveSpaceId(address initialController, bytes32 salt)
        public
        pure
        returns (bytes32 spaceId)
    {
        if (initialController == address(0)) revert ZeroAddress();
        return keccak256(abi.encode(MEMORY_SPACE_TYPEHASH, initialController, salt));
    }

    function hashSpaceAuthorization(
        bytes32 spaceId,
        address newController,
        address newAuthorizer,
        uint64 nonce
    ) external pure returns (bytes32) {
        return keccak256(
            abi.encode(SPACE_AUTHORIZATION_TYPEHASH, spaceId, newController, newAuthorizer, nonce)
        );
    }

    function signingDigest(bytes32 structHash) external view returns (bytes32 digest) {
        return _digest(structHash);
    }

    function computeDomainSeparator(uint256 chainId, address verifyingContract)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(EIP712_NAME)),
                keccak256(bytes(EIP712_VERSION)),
                chainId,
                verifyingContract
            )
        );
    }

    function computeSigningDigest(bytes32 structHash, uint256 chainId, address verifyingContract)
        external
        pure
        returns (bytes32 digest)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01", computeDomainSeparator(chainId, verifyingContract), structHash
            )
        );
    }

    function domainSeparator() public view returns (bytes32) {
        return block.chainid == _cachedChainId ? _cachedDomainSeparator : _buildDomainSeparator();
    }

    function _space(bytes32 spaceId) private view returns (SpaceRecord storage space) {
        space = _spaces[spaceId];
        if (space.controller == address(0)) revert UnknownSpace();
    }

    /// @dev Authorization accepts, in order: a direct call by the signer, an ERC-1271
    ///      signature, then a canonical ECDSA signature.
    ///
    ///      Code presence is deliberately NOT used to pick exactly one branch. An EOA
    ///      delegated under EIP-7702 has non-empty code (`0xef0100 || delegate`), so
    ///      branching on `code.length` alone would route every 7702 account into
    ///      ERC-1271 and revert for the many delegates that implement no signature
    ///      policy. Trying ERC-1271 first still lets a delegate that *does* implement a
    ///      policy enforce it; the ECDSA fallback then covers plain EOAs and 7702
    ///      accounts whose delegate is signature-agnostic.
    ///
    ///      Security note: delegation does not revoke the underlying key, so for a 7702
    ///      account a valid ECDSA signature authorizes even when the delegate's policy
    ///      would have rejected it. That is a property of EIP-7702 itself, not of this
    ///      registry, but deployments relying on a delegate policy must account for it.
    function _requireAuthorization(
        address signer,
        bytes32 digest,
        bytes calldata signature,
        bool allowDirectCall
    ) private view {
        if (allowDirectCall && msg.sender == signer && signature.length == 0) return;

        if (signer.code.length != 0 && _isValidERC1271Signature(signer, digest, signature)) {
            return;
        }

        // Guard the length before recovering: `ECDSA.recover` reverts on any size other
        // than 65, which would otherwise abort the transaction instead of falling back.
        if (signature.length != 65) revert InvalidAuthorization();
        if (ECDSA.recover(digest, signature) != signer) revert InvalidAuthorization();
    }

    function _isValidERC1271Signature(address signer, bytes32 digest, bytes calldata signature)
        private
        view
        returns (bool)
    {
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (digest, signature)));
        return success && result.length >= 32
            && abi.decode(result, (bytes4)) == _ERC1271_MAGIC_VALUE;
    }

    function _digest(bytes32 structHash) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return computeDomainSeparator(block.chainid, address(this));
    }
}
