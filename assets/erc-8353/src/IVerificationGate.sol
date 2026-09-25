// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title Staked Weighted Verification Gate (interface per draft/erc-draft.md)
/// @notice A claim carries no trusted status until verified by third parties;
///         verification is weighted by the verifier's own verified depth.
interface IVerificationGate {
    enum Status { None, Offered, Verified, Settled, Revoked }

    /// @notice A claim was registered and entered the Offered state.
    event ClaimOffered(bytes32 indexed claimId, address indexed subject,
                       address indexed offerer, bytes32 claimHash, uint256 stake);

    /// @notice A third party verified the claim, contributing `weight`.
    event ClaimVerified(bytes32 indexed claimId, address indexed verifier,
                        uint256 weight, bytes32 evidenceHash);

    /// @notice A Verified claim was finalized. Settled is terminal.
    event ClaimSettled(bytes32 indexed claimId);

    /// @notice The claim was revoked. The record persists.
    event ClaimRevoked(bytes32 indexed claimId, address indexed revoker,
                       bytes32 reasonHash);

    /// @notice Register a claim about `subject`. Binds msg.value as stake, if any.
    /// @dev MUST emit ClaimOffered. MUST revert if a required stake is missing.
    function offer(address subject, bytes32 claimHash, bytes calldata data)
        external payable returns (bytes32 claimId);

    /// @notice Endorse a claim as a third party.
    /// @dev MUST emit ClaimVerified with the weight actually credited.
    ///      Calls from the claim's subject or offerer MUST NOT contribute
    ///      weight (this implementation reverts). A verifier MUST NOT
    ///      contribute weight to the same claim more than once (this
    ///      implementation reverts on repeat calls). MUST revert unless the
    ///      claim is Offered or Verified.
    function verify(bytes32 claimId, bytes32 evidenceHash) external;

    /// @notice Finalize a Verified claim. MUST revert unless Verified.
    function settle(bytes32 claimId) external;

    /// @notice Revoke a claim. MUST revert unless Offered or Verified —
    ///         Settled is terminal and cannot be revoked.
    function revoke(bytes32 claimId, bytes32 reasonHash) external;

    /// @notice The gate: consumers MUST check this before relying on a claim.
    function statusOf(bytes32 claimId)
        external view returns (Status status, uint256 weight);

    /// @notice The verifier's own verified depth, as computed by this implementation.
    function weightOf(address verifier) external view returns (uint256);
}
