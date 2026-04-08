// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/OffchainScorerMock.sol";

/// @title Scenario 3 — Hybrid Off-chain Scoring + On-chain Assurance
/// @notice Demonstrates that an off-chain score (AHS-style) can serve as shared
///         evidence for both task rejection (Layer 1) and claim filing (Layer 3),
///         using the same reasoningCID.
contract Scenario3_HybridOffchainScoring is Test {
    AAPMockMinimal     aap;
    MockERC20          token;
    OffchainScorerMock scorer;

    address oracle       = makeAddr("oracle");
    address suspectAgent = makeAddr("suspectAgent");
    address taskManager  = makeAddr("taskManager");
    address claimant     = makeAddr("claimant");
    address reviewer     = makeAddr("reviewer");

    uint256 constant CLAIM_AMOUNT     = 300e18;
    uint8   constant CONFIDENCE_THRESHOLD = 70;

    // Simulated CID for the full off-chain reasoning
    bytes32 constant REASONING_CID = keccak256("ipfs://QmReasoningReport_SuspectAgent_v1");

    function setUp() public {
        token  = new MockERC20("Assurance Token", "ASR");
        aap    = new AAPMockMinimal(address(token), reviewer);
        scorer = new OffchainScorerMock();

        // Fund AAP
        token.mint(address(aap), 10_000e18);
    }

    function test_HybridOffchainScoring() public {
        // ── Step 1: Oracle posts a DENY score for the suspect agent ────
        vm.prank(oracle);
        vm.expectEmit(true, false, false, true, address(scorer));
        emit OffchainScorerMock.ScorePosted(
            suspectAgent,
            OffchainScorerMock.ScorerVerdict.DENY,
            87,
            REASONING_CID
        );
        scorer.postScore(
            suspectAgent,
            OffchainScorerMock.ScorerVerdict.DENY,
            87,              // confidence
            REASONING_CID
        );

        // ── Step 2: Task manager reads the score and rejects the task ──
        // (In a real ERC-8183 setup this would call reject() on the task
        //  contract. Here we just verify the score is readable and actionable.)
        (
            OffchainScorerMock.ScorerVerdict verdict,
            uint8 confidence,
            bytes32 reasoningCID
        ) = scorer.score(suspectAgent);

        assertEq(uint8(verdict), uint8(OffchainScorerMock.ScorerVerdict.DENY));
        assertTrue(confidence >= CONFIDENCE_THRESHOLD, "Confidence should exceed threshold");
        assertEq(reasoningCID, REASONING_CID, "CID should match posted value");

        // Task manager would call reject() here — simulated as a logged action
        emit log_named_string("Task Manager action", "Task rejected based on DENY score");

        // ── Step 3: Claimant files a claim using the SAME reasoningCID ─
        bytes32 upstreamRef = keccak256(abi.encode("OffchainScore", suspectAgent));

        vm.prank(claimant);
        uint256 claimId = aap.fileClaim(CLAIM_AMOUNT, REASONING_CID, upstreamRef);

        // The evidenceHash in the claim IS the reasoningCID — same artifact
        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.evidenceHash, REASONING_CID, "Claim evidence must be the same CID used for task rejection");

        // ── Step 4: Reviewer verifies score and approves claim ─────────
        // Reviewer reads the on-chain score to verify
        (
            OffchainScorerMock.ScorerVerdict reviewVerdict,
            uint8 reviewConfidence,
            bytes32 reviewCID
        ) = scorer.score(suspectAgent);

        // Verify the score matches the claim
        assertEq(uint8(reviewVerdict), uint8(OffchainScorerMock.ScorerVerdict.DENY), "Verdict must be DENY");
        assertTrue(reviewConfidence >= CONFIDENCE_THRESHOLD, "Confidence must exceed threshold");
        assertEq(reviewCID, c.evidenceHash, "Score CID must match claim evidence");

        bytes32 approvalReason = keccak256(
            abi.encode("score_verified", suspectAgent, reviewConfidence)
        );

        vm.prank(reviewer);
        aap.reviewClaim(claimId, IAAP.Verdict.Approve, approvalReason);

        // ── Step 5: Verify final state ─────────────────────────────────
        IAAP.Claim memory resolved = aap.getClaim(claimId);
        assertEq(uint8(resolved.status), uint8(IAAP.ClaimStatus.Approved));
        assertEq(token.balanceOf(claimant), CLAIM_AMOUNT, "Claimant should receive payout");

        // The key invariant: both the task rejection and the claim used
        // the same reasoningCID as their evidence, demonstrating that a
        // single off-chain evaluation serves both Layer 1 and Layer 3.
        assertEq(REASONING_CID, c.evidenceHash, "Shared evidence invariant holds");
    }
}
