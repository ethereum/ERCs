// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title IUnclonableCredential
/// @notice Normative interface for ERC-XXXX. Issuance is mandatory and consumption is coupled to
///         execution, so the burn can never be separated from performing the issued action. See
///         ethereum-magicians.org/t/29274 posts 11 to 15 for why the separable `consume` primitive
///         was rejected.
interface IUnclonableCredential {
    /// @notice Emitted when the orchestrator authorizes a capability commitment.
    event CapabilityIssued(
        bytes32 indexed capabilityCommitment,
        uint256 indexed agentId,
        uint256 capabilityIndex
    );

    /// @notice Emitted on the first and only successful spend of a nullifier.
    /// @dev The rejecting path reverts and therefore cannot emit. Observability is this event on
    ///      the accepting path plus the named error below on the rejecting one.
    event NullifierBurned(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        uint256 capabilityIndex,
        bytes32 actionCommitment
    );

    /// @notice A second spend of a nullifier. This is the on-chain alarm for a contested count.
    /// @dev Classify against `highestIssuedIndex`. A collision at an index the orchestrator never
    ///      issued indicates a clone. One at an index it did issue indicates a reissue bug.
    error CredentialAlreadySpent(bytes32 nullifier);

    /// @notice The commitment was never issued, so no action bound to it may ever burn.
    error CommitmentNotIssued(bytes32 capabilityCommitment);

    /// @notice Capability metadata bound to a single agent action.
    /// @dev The salt is deliberately absent. It is a private witness of the circuit only, and
    ///      placing it in calldata would publish it in the mempool ahead of inclusion, handing any
    ///      observer the ability to grief burn the capability.
    struct Capability {
        bytes32 nullifier;            // public output, H(NULLIFIER_TAG, salt)
        bytes32 capabilityCommitment; // public input, binds salt to every field below
        uint256 agentId;              // ERC-8004 identity
        uint256 homeChainId;          // the one chain this capability spends on
        uint256 homeDomainId;         // issuing orchestrator domain
        uint256 capabilityIndex;      // monotonic per agentId and homeDomainId
        bytes32 actionCommitment;     // keccak256(abi.encode(target, callData))
        address executor;             // intended submitter
        uint256 expiry;               // unix seconds
    }

    /// @notice Authorize a capability commitment. Restricted to the issuing orchestrator.
    function issue(
        bytes32 capabilityCommitment,
        uint256 agentId,
        uint256 capabilityIndex
    ) external;

    /// @notice Burn the nullifier and perform the authorized action in one call.
    /// @dev Reverts unless keccak256(abi.encode(target, callData)) equals cap.actionCommitment.
    /// @return nullifier The burned nullifier.
    function execute(
        Capability calldata cap,
        bytes calldata proof,
        address target,
        bytes calldata callData
    ) external returns (bytes32 nullifier);

    /// @notice Query whether a nullifier has been burned.
    function isConsumed(bytes32 nullifier) external view returns (bool);

    /// @notice Highest capability index the orchestrator has issued for an agent.
    function highestIssuedIndex(uint256 agentId) external view returns (uint256);
}
