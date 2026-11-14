// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title IAgentMeditationStart
/// @notice Optional extension of the Agent Meditation Mechanism: a recorded start. The subject, or an operator
///         holding PERM_REPORT, registers the start of its next cycle before the cycle runs. A cycle record whose
///         `reportedStartedAt` equals the open start and whose submitter recorded that start is pinned: it is
///         governed by the policy version in effect at the recorded start and is exempt from the current-version
///         check that applies to records under a superseded policy version.
/// @dev    A subject has at most one open start. Timepoints are in the registry's clock domain (ERC-6372).
///         An accepted cycle record that is pinned to the open start, or whose reported end is after it, closes
///         the open start; a policy change voids an open start unless the subject or the changing account
///         recorded it.
interface IAgentMeditationStart {
    /// @notice A start was recorded. `replacedStartedAt` is the open start it replaced, 0 if none.
    event CycleBegun(address indexed subject, uint48 startedAt, uint48 replacedStartedAt, address by);

    /// @notice An open start was cleared without a cycle record pinned to it. `by` is the account whose call
    ///         cleared it (a cancellation, a policy change, or an accepted record of a later cycle).
    event StartVoided(address indexed subject, uint48 startedAt, address by);

    /// @notice Record `clock()` as the open start of `subject`'s next cycle; callable by the subject or an operator
    ///         holding PERM_REPORT. The caller may replace an open start it recorded itself; the subject may replace
    ///         any open start.
    function begin(address subject) external returns (uint48 startedAt);

    /// @notice Void the open start of `subject`; callable by the subject or by the account that recorded it.
    function cancelStart(address subject) external;

    /// @notice The open start of `subject`: its timepoint (0 = none) and the account that recorded it.
    function openStartOf(address subject) external view returns (uint48 startedAt, address recordedBy);
}
