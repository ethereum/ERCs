// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVerifier
 * @notice Generic interface for zk-SNARK proof verifiers
 * @dev Different verifier implementations may require different public signal lengths
 */
interface IVerifier {
    /**
     * @dev Verifies a ZK-SNARK proof.
     * @param _pA The A point of the proof.
     * @param _pB The B point of the proof.
     * @param _pC The C point of the proof.
     * @param _pubSignals An array of public signals. The length and order
     *                    must match what the specific verifier expects.
     * @return bool True if the proof is valid.
     */
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title IMintVerifier
 * @notice Verifier for regular mint operations
 * @dev Public signals: [newActiveRoot, oldActiveRoot, newCommitment, mintAmount]
 */
interface IMintVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title IMintRolloverVerifier
 * @notice Verifier for mint operations that trigger subtree rollover
 * @dev Public signals: [newActiveRoot, newFinalizedRoot, oldActiveRoot, oldFinalizedRoot, newCommitment, mintAmount, subtreeIndex]
 */
interface IMintRolloverVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[7] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title IActiveTransferVerifier
 * @notice Verifier for transfers within the active subtree
 * @dev Fastest proof generation - most common transfer type
 */
interface IActiveTransferVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[12] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title IFinalizedTransferVerifier
 * @notice Verifier for transfers spending from finalized (historical) subtrees
 */
interface IFinalizedTransferVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[13] calldata _pubSignals
    ) external view returns (bool);
}

/**
 * @title ITransferRolloverVerifier
 * @notice Verifier for transfers that trigger subtree rollover
 */
interface ITransferRolloverVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[12] calldata _pubSignals
    ) external view returns (bool);
}
