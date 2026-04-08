// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Off-chain scorer mock — simulates AHS-style scoring (Scenario 3).
/// @notice Inspired by the conceptual AHS (Agent Health Score) approach.
///         RNWY is a separate project with related but distinct multidimensional
///         scoring (soulbound identity, explicit sybil signal weights, live
///         ERC-8183 hook integration) and will be referenced separately in the
///         AAP v2 IRiskHook section once their methodology document is published.
/// @dev    In production the score would be posted via an oracle; here we allow
///         direct setting for test determinism.
contract OffchainScorerMock {
    // ── Enums ──────────────────────────────────────────────────────────
    enum ScorerVerdict { PENDING, APPROVE, DENY }

    // ── Events ─────────────────────────────────────────────────────────
    event ScorePosted(
        address indexed subject,
        ScorerVerdict verdict,
        uint8 confidence,
        bytes32 reasoningCID
    );

    // ── State ──────────────────────────────────────────────────────────
    struct Score {
        ScorerVerdict verdict;
        uint8         confidence; // 0-100
        bytes32       reasoningCID;
    }

    mapping(address => Score) public scores;

    // ── Functions ──────────────────────────────────────────────────────

    /// @notice Post a score for a subject (simulates oracle callback).
    function postScore(
        address subject,
        ScorerVerdict verdict,
        uint8 confidence,
        bytes32 reasoningCID
    ) external {
        scores[subject] = Score({
            verdict:      verdict,
            confidence:   confidence,
            reasoningCID: reasoningCID
        });
        emit ScorePosted(subject, verdict, confidence, reasoningCID);
    }

    /// @notice Read the latest score for a subject.
    function score(address subject)
        external
        view
        returns (ScorerVerdict verdict, uint8 confidence, bytes32 reasoningCID)
    {
        Score memory s = scores[subject];
        return (s.verdict, s.confidence, s.reasoningCID);
    }
}
