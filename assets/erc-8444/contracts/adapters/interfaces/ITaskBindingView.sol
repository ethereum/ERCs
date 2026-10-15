// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  ITaskBindingView — the one binding view of the task tender draft the task adapter reads.
interface ITaskBindingView {
    struct TaskBinding {
        bytes32 tdHash;   // SHA-256 digest of the plaintext primary Markdown task document
        bytes32 taskHash; // SHA-256 digest of the encoded TaskRoot as published
        uint64  version;  // content version, starts at 1
    }

    function taskOf(uint256 tokenId) external view returns (TaskBinding memory);
}
