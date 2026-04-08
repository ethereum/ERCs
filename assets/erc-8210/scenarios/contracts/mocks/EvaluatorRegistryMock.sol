// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title EvaluatorRegistry mock — emits slash events consumed by Scenario 2.
/// @dev   Event signature agreed with Bakugo32 (Demsys) in the ERC-8183 thread.
contract EvaluatorRegistryMock {
    // ── Events ─────────────────────────────────────────────────────────
    event EvaluatorSlashed(
        address indexed evaluator,
        uint256 indexed jobId,
        uint256 slashedAmount,
        bytes32 reason
    );

    // ── State ──────────────────────────────────────────────────────────
    struct SlashRecord {
        address evaluator;
        uint256 jobId;
        uint256 slashedAmount;
        bytes32 reason;
        uint256 timestamp;
    }

    mapping(uint256 => SlashRecord) public slashRecords; // jobId => record
    uint256 public slashCount;

    // ── Functions ──────────────────────────────────────────────────────

    /// @notice Slash an evaluator for misconduct on a specific job.
    function slashEvaluator(
        address evaluator,
        uint256 jobId,
        uint256 slashedAmount,
        bytes32 reason
    ) external {
        slashRecords[jobId] = SlashRecord({
            evaluator:     evaluator,
            jobId:         jobId,
            slashedAmount: slashedAmount,
            reason:        reason,
            timestamp:     block.timestamp
        });
        slashCount++;
        emit EvaluatorSlashed(evaluator, jobId, slashedAmount, reason);
    }

    /// @notice Build an evidence hash from a slash record for AAP claim filing.
    function buildEvidenceHash(uint256 jobId) external view returns (bytes32) {
        SlashRecord memory r = slashRecords[jobId];
        return keccak256(abi.encode(r.evaluator, r.jobId, r.slashedAmount, r.reason, r.timestamp));
    }
}
