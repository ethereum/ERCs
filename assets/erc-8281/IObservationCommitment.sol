// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IObservationCommitment {
    /// @notice Commit a digest on-chain.
    /// @param digest The hash of the observation bytes, produced using
    ///               a hash function from the allowed set defined in this ERC.
    function record(bytes32 digest) external;

    /// @notice Emitted on every successful record() call.
    /// @param digest    The committed digest (topics[1]).
    /// @param committer The address that called record() (topics[2]).
    event Recorded(
        bytes32 indexed digest,
        address indexed committer
    );
}
