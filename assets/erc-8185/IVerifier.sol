// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IVerifier
/// @notice Per-namespace ownership verifier. Implementations may use oracle
///         signatures, ZK proofs, DNSSEC, or any other mechanism.
interface IVerifier {
    /// @param id       Identifier being claimed.
    /// @param claimant Address asserting ownership.
    /// @param proof    Verifier-specific encoded proof data.
    /// @return True if the proof is valid and the claimant owns the identifier.
    function verify(bytes32 id, address claimant, bytes calldata proof) external returns (bool);
}
