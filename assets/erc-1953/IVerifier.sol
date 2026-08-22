// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title IVerifier — Backend-Agnostic Proof Verifier Interface
/// @notice Abstracts the cryptographic proof verification so the Guard
///         never depends on a specific proving system.
interface IVerifier {
    /// @notice Verify a proof against public inputs.
    /// @param proof      The serialized proof bytes.
    /// @param publicInputs Ordered public inputs as expected by the circuit.
    /// @return valid True if the proof is cryptographically valid.
    function verify(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external view returns (bool valid);
}
