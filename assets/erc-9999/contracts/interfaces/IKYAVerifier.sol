// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-KYA Verifier (ZK-KYA profile adapter)
/// @notice Maps a proof + public inputs to framework fields. Any proving system enters the
///         framework by supplying one of these. MUST be side-effect free.
///         A verifier MUST enforce the scheme's time-window rule for the nullifier scope it
///         implements (e.g. epoch == floor(block.timestamp / epochLength), optionally minus a grace
///         window) so that provers cannot mint fresh nullifiers by choosing arbitrary epochs.
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
    /// @return anchor      Verifier-defined trust anchor the proof was checked against (for the
    ///                     reference circuit: the issuer-set Merkle root). Recorded on the assertion
    ///                     so relying parties can pin (verifier, anchor) rather than trusting the
    ///                     verifier address alone. 0x0 if not applicable.
    function verify(bytes32 schemeId, bytes calldata publicInputs, bytes calldata proof)
        external
        view
        returns (
            bool ok,
            bytes32 subjectKey,
            bytes32 nullifier,
            uint8 level,
            bytes32 claimDigest,
            uint64 expiresAt,
            bytes32 anchor
        );
}
