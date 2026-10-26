// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice ZK verifier for a domain's interpreter program.
/// @dev `programKey` identifies the program (e.g. an SP1 vkey / Groth16 vk commitment).
///      `publicInputs` is the ABI-encoded Verdict — the proof's public inputs.
interface IVerifier {
    function verifyProof(bytes32 programKey, bytes calldata publicInputs, bytes calldata proof)
        external
        view
        returns (bool);
}
