// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-KYA Verifier (ZK-KYA profile adapter)
/// @notice Maps a proof + public inputs to framework fields. Any proving system enters the
///         framework by supplying one of these. MUST be side-effect free.
interface IKYAVerifier {
    /// @param schemeId     The scheme the proof is presented under.
    /// @param publicInputs ABI-encoded public inputs; layout is scheme-defined and documented
    ///                     in the Scheme Descriptor `circuit.publicInputLayout`.
    /// @param proof        Opaque proof bytes.
    /// @return ok          true iff the proof verifies.
    /// @return subjectKey  keccak256(abi.encode(subjectType, subjectData)) bound inside the proof.
    /// @return nullifier   Replay-protection value scoped at least to schemeId.
    /// @return level       Scheme-defined level.
    /// @return claimDigest Commitment to disclosed claims.
    /// @return expiresAt   Unix seconds; 0 = no expiry.
    function verify(bytes32 schemeId, bytes calldata publicInputs, bytes calldata proof)
        external
        view
        returns (
            bool ok,
            bytes32 subjectKey,
            bytes32 nullifier,
            uint8 level,
            bytes32 claimDigest,
            uint64 expiresAt
        );
}
