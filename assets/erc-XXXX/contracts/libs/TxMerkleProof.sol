// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice A library for verifying transaction inclusion in Bitcoin block.
 * Provides functions for processing and verifying Merkle tree proofs
 */
library TxMerkleProof {
    /**
     * @notice Possible directions for hashing:
     * Left: computed hash is on the left, sibling hash is on the right.
     * Right: computed hash is on the right, sibling hash is on the left.
     * Self: node has no sibling and is hashed with itself
     * */
    enum HashDirection {
        Left,
        Right,
        Self
    }

    /**
     * @notice Emitted when the proof and directions array are of different length.
     * This error ensures that only correctly sized proofs are processed
     */
    error InvalidLengths();

    /**
     * @notice Returns true if `leaf` can be proven to be part of a Merkle tree
     * defined by `root`. Requires a `proof` containing the sibling hashes along
     * the path from the leaf to the root. Each element of `directions` indicates
     * the hashing order for each pair. Uses double SHA-256 hashing
     */
    function verify(
        bytes32[] calldata proof,
        HashDirection[] calldata directions,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        require(directions.length == proof.length, InvalidLengths());

        return processProof(proof, directions, leaf) == root;
    }

    /**
     * @notice Returns the rebuilt hash obtained by traversing the Merkle tree
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the given tree root. The pre-images are hashed in the order
     * specified by the `directions` elements. Uses double SHA-256 hashing
     */
    function processProof(
        bytes32[] calldata proof,
        HashDirection[] calldata directions,
        bytes32 leaf
    ) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        uint256 proofLength = proof.length;

        for (uint256 i = 0; i < proofLength; ++i) {
            if (directions[i] == HashDirection.Left) {
                computedHash = _doubleSHA256(computedHash, proof[i]);
            } else if (directions[i] == HashDirection.Right) {
                computedHash = _doubleSHA256(proof[i], computedHash);
            } else {
                computedHash = _doubleSHA256(computedHash, computedHash);
            }
        }

        return computedHash;
    }

    function _doubleSHA256(bytes32 left, bytes32 right) private pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(abi.encodePacked(left, right))));
    }
}
