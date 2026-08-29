// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IUnclonableCredential} from "./IUnclonableCredential.sol";
import {IVerifier} from "./IVerifier.sol";
import {DomainRegistry} from "./DomainRegistry.sol";

/// @title CoupledCredentialGuard
/// @notice The normative core. Answers the adversarial vectors on
///         ethereum-magicians.org/t/29274 with two properties that the separable `consume`
///         primitive could not provide.
///           1. Issuance is mandatory. Since `capabilityCommitment` binds the action, an unissued
///              action can never be consumed, which closes the arbitrary grief burn.
///           2. Consumption and execution are one call. The burn only happens as part of performing
///              the exact issued action, so a consumed nullifier always means the action ran.
///         The residual is a clone holding both the salt and the executor key triggering the
///         authorized action early. That is a key-management boundary, not something the Guard can
///         close. Coupling turns it from "task dead" into "task done early".
contract CoupledCredentialGuard is IUnclonableCredential {
    error ActionMismatch(bytes32 expected, bytes32 actual);
    error WrongChain();
    error DomainInvalid();
    error Expired();
    error ExecutorMismatch();
    error BadProof();
    error NotOrchestrator();
    error ActionReverted();

    IVerifier public immutable verifier;
    DomainRegistry public immutable domainRegistry;
    address public immutable orchestrator;

    mapping(bytes32 => bool) public consumed;
    mapping(bytes32 => bool) public issued;
    /// @dev agentId => highest issued index, so a collision can be classified: an index the
    ///      orchestrator never issued is a clone, one it did issue is its own reissue bug.
    mapping(uint256 => uint256) public override highestIssuedIndex;

    constructor(address _verifier, address _domainRegistry, address _orchestrator) {
        verifier = IVerifier(_verifier);
        domainRegistry = DomainRegistry(_domainRegistry);
        orchestrator = _orchestrator;
    }

    /// @inheritdoc IUnclonableCredential
    function issue(bytes32 capabilityCommitment, uint256 agentId, uint256 capabilityIndex)
        external
        override
    {
        if (msg.sender != orchestrator) revert NotOrchestrator();
        issued[capabilityCommitment] = true;
        if (capabilityIndex > highestIssuedIndex[agentId]) highestIssuedIndex[agentId] = capabilityIndex;
        emit CapabilityIssued(capabilityCommitment, agentId, capabilityIndex);
    }

    /// @dev Order: [capabilityCommitment, agentId, homeChainId, homeDomainId, capabilityIndex,
    ///      actionCommitment, executor, expiry, nullifier]. The circuit recomputes the commitment
    ///      from the private salt and these inputs, so the salt never reaches calldata, and it
    ///      must prove its own H(NULLIFIER_TAG, salt) output equals the nullifier input, so
    ///      cap.nullifier is checked against a value the circuit actually derived.
    function _buildPublicInputs(IUnclonableCredential.Capability calldata cap)
        internal
        pure
        returns (bytes32[] memory inputs)
    {
        inputs = new bytes32[](9);
        inputs[0] = cap.capabilityCommitment;
        inputs[1] = bytes32(cap.agentId);
        inputs[2] = bytes32(cap.homeChainId);
        inputs[3] = bytes32(cap.homeDomainId);
        inputs[4] = bytes32(cap.capabilityIndex);
        inputs[5] = cap.actionCommitment;
        inputs[6] = bytes32(uint256(uint160(cap.executor)));
        inputs[7] = bytes32(cap.expiry);
        inputs[8] = cap.nullifier;
    }

    /// @inheritdoc IUnclonableCredential
    function execute(
        IUnclonableCredential.Capability calldata cap,
        bytes calldata proof,
        address target,
        bytes calldata callData
    ) external override returns (bytes32) {
        // Public checks first, so a caller cannot force an expensive verification with a
        // capability that already fails on a public field.
        if (cap.homeChainId != block.chainid) revert WrongChain();
        if (!domainRegistry.isActiveDomain(cap.homeDomainId)) revert DomainInvalid();
        if (block.timestamp > cap.expiry) revert Expired();
        if (msg.sender != cap.executor) revert ExecutorMismatch();
        if (consumed[cap.nullifier]) revert CredentialAlreadySpent(cap.nullifier);

        // Mandatory issuance. The commitment binds the action, so an unissued action never consumes.
        if (!issued[cap.capabilityCommitment]) revert CommitmentNotIssued(cap.capabilityCommitment);

        // The action performed must be the one the proof is bound to.
        bytes32 action = keccak256(abi.encode(target, callData));
        if (action != cap.actionCommitment) revert ActionMismatch(cap.actionCommitment, action);

        bytes32[] memory publicInputs = _buildPublicInputs(cap);
        if (!verifier.verify(proof, publicInputs)) revert BadProof();

        // Burn and act atomically: a consumed nullifier always means the action ran.
        consumed[cap.nullifier] = true;
        emit NullifierBurned(cap.nullifier, cap.agentId, cap.capabilityIndex, cap.actionCommitment);

        (bool ok,) = target.call(callData);
        if (!ok) revert ActionReverted();
        return cap.nullifier;
    }

    /// @inheritdoc IUnclonableCredential
    function isConsumed(bytes32 nullifier) external view override returns (bool) {
        return consumed[nullifier];
    }
}
