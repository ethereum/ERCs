// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  Machine-settlement verifier interface (TASK-KERNEL v3.0) — own ERC-165 id.
/// @notice Verifier contracts implement this (and declare it via ERC-165). A task
///         whose acceptance authority is such a contract is machine-settled: anyone
///         may call settleFulfillment on the task contract, which consults the
///         verifier. Fully quantifiable tasks (solve an equation, reveal a preimage,
///         oracle-confirmed outcomes) thereby settle with no one in the loop.
interface ITaskVerifier {
    /// @notice Decide a submission mechanically. MAY be stateful (streaks, rate limits,
    ///         provider continuity for standing tenders).
    /// @dev Called by the task contract during settleFulfillment. A false return or a
    ///      revert means the proof does not establish fulfillment; the submission
    ///      stays Pending — it is NOT a rejection.
    function verifyFulfillment(
        address taskContract,
        uint256 tokenId,
        uint256 submissionId,
        address fulfiller,
        bytes32 resultHash,
        bytes calldata proof
    ) external returns (bool);
}
