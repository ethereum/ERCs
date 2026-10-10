// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IUnclonableCredential} from "./IUnclonableCredential.sol";
import {IVerifier} from "./IVerifier.sol";
import {DomainRegistry} from "./DomainRegistry.sol";
import {CapabilityCommitment} from "./CapabilityCommitment.sol";

/// @title UnclonableCredentialGuard
/// @notice NOT NORMATIVE. The earlier separable form, where the burn is its own call. Retained
///         only because `test/adversarial/GriefBurn.t.sol` runs against it to exhibit the liveness
///         break that motivated coupling: `consume` requires no issuance and the nullifier is
///         action-independent, so anyone satisfying the executor check burns the capability on an
///         action of their choosing and the honest task can never run. Deploy
///         `CoupledCredentialGuard` instead.
contract UnclonableCredentialGuard {
    using CapabilityCommitment for bytes32;

    /// @dev Superseded by IUnclonableCredential.NullifierBurned in the normative Guard.
    event CapabilityConsumed(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        uint256 indexed capabilityIndex,
        address executor,
        uint256 timestamp
    );

    mapping(bytes32 => bool) public consumed;
    IVerifier public immutable verifier;
    DomainRegistry public immutable domainRegistry;

    constructor(address _verifier, address _domainRegistry) {
        verifier = IVerifier(_verifier);
        domainRegistry = DomainRegistry(_domainRegistry);
    }

    /// @notice Rebuild public inputs in the exact order expected by the circuit
    ///         and the HonkVerifierAdapter.
    /// @dev Order: [capabilityCommitment, agentId, homeChainId, homeDomainId,
    ///         capabilityIndex, actionCommitment, executor, expiry, nullifier]
    function _buildPublicInputs(
        IUnclonableCredential.Capability calldata cap
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory inputs = new bytes32[](9);
        inputs[0] = cap.capabilityCommitment;
        inputs[1] = bytes32(uint256(cap.agentId));
        inputs[2] = bytes32(uint256(cap.homeChainId));
        inputs[3] = bytes32(uint256(cap.homeDomainId));
        inputs[4] = bytes32(uint256(cap.capabilityIndex));
        inputs[5] = cap.actionCommitment;
        inputs[6] = bytes32(uint256(uint160(cap.executor)));
        inputs[7] = bytes32(uint256(cap.expiry));
        inputs[8] = cap.nullifier;
        return inputs;
    }

    /// @notice Consume a capability exactly once.
    /// @dev The six checks are executed in the order mandated by the spec.
    function consume(
        IUnclonableCredential.Capability calldata cap,
        bytes calldata proof
    ) external returns (bytes32) {
        // 1. homeChainId == block.chainid
        require(cap.homeChainId == block.chainid, "UAC: wrong chain");

        // 2. homeDomainId is registered and not revoked
        require(domainRegistry.isActiveDomain(cap.homeDomainId), "UAC: domain invalid");

        // 3. block.timestamp <= expiry
        require(block.timestamp <= cap.expiry, "UAC: expired");

        // 4. msg.sender == executor. Relayed submission is an optional extension and is
        //    deliberately absent here. A Guard that adds it must build a real EIP-712 domain
        //    separator over the Guard address and block.chainid, and must take the signature
        //    as an explicit argument rather than reconstructing one.
        require(msg.sender == cap.executor, "UAC: executor mismatch");

        // 5. !consumed[nullifier]
        require(!consumed[cap.nullifier], "UAC: already spent");

        // 6. verifier.verify(proof, publicInputs) passes
        bytes32[] memory publicInputs = _buildPublicInputs(cap);
        require(verifier.verify(proof, publicInputs), "UAC: invalid proof");

        // 7. Burn and emit
        consumed[cap.nullifier] = true;
        emit CapabilityConsumed(
            cap.nullifier,
            cap.agentId,
            cap.capabilityIndex,
            cap.executor,
            block.timestamp
        );
        return cap.nullifier;
    }

    /// @notice Query whether a nullifier has been burned.
    function isConsumed(bytes32 nullifier) external view returns (bool) {
        return consumed[nullifier];
    }
}
