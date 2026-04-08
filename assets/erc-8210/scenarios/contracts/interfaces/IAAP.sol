// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Minimal IAAP interface – only the subset used by multi-hop scenarios.
/// @dev This is NOT the full ERC-8210 interface. It covers fileClaim,
///      reviewClaim, and the events/structs consumed by the three reference
///      scenarios in this folder.
interface IAAP {
    // ── Enums ──────────────────────────────────────────────────────────
    enum ClaimStatus { Filed, UnderReview, Approved, Rejected, Appealed, Resolved }
    enum Verdict     { Pending, Approve, Deny }

    // ── Structs ────────────────────────────────────────────────────────
    struct Claim {
        address claimant;
        uint256 amount;
        ClaimStatus status;
        bytes32 evidenceHash;
        bytes32 upstream;          // traceability to upstream cause
    }

    // ── Events ─────────────────────────────────────────────────────────
    event ClaimFiled(
        uint256 indexed claimId,
        address indexed claimant,
        uint256 amount,
        bytes32 evidenceHash
    );

    event ClaimReviewed(
        uint256 indexed claimId,
        Verdict verdict,
        bytes32 reason
    );

    // ── Functions ──────────────────────────────────────────────────────
    /// @notice File a new claim with evidence and optional upstream reference.
    function fileClaim(
        uint256 amount,
        bytes32 evidenceHash,
        bytes32 upstream
    ) external returns (uint256 claimId);

    /// @notice Review an existing claim and render a verdict.
    function reviewClaim(
        uint256 claimId,
        Verdict verdict,
        bytes32 reason
    ) external;

    /// @notice Read a claim by ID.
    function getClaim(uint256 claimId) external view returns (Claim memory);
}
