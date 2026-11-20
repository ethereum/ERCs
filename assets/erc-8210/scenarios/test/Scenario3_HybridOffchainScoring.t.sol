// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/OffchainScorerMock.sol";
import "../contracts/interfaces/IAAP.sol";

/// @title Scenario 3 — Hybrid Off-chain Scoring + On-chain Assurance
/// @notice Demonstrates the "evidence-first composability" principle: a single
///         off-chain scoring artifact (referenced by `reasoningCID`) is used as
///         shared evidence by both the task rejection path (Layer 2 prevention)
///         and the AAP claim filing path (Layer 3 recovery), without requiring
///         re-attestation or additional oracles.
///
///         The same `reasoningCID` is encoded into the AAP evidence payload,
///         giving the resolver a direct lookup path back to the off-chain score
///         that drove the rejection decision in the first place.
contract Scenario3_HybridOffchainScoring is Test {
    AAPMockMinimal     aap;
    MockERC20          token;
    OffchainScorerMock scorer;

    address oracle           = makeAddr("oracle");
    address suspectAgent     = makeAddr("suspectAgent");
    address assuredAgent     = makeAddr("assuredAgent");
    address beneficiary      = makeAddr("beneficiary");
    address resolver         = makeAddr("resolver");

    uint256 constant DEPOSIT      = 1000e18;
    uint256 constant COMMIT       = 300e18;
    uint64  constant FAR_FUTURE   = type(uint64).max;
    uint256 constant CLAIM_AMOUNT = 300e18;
    uint8   constant CONFIDENCE_THRESHOLD = 70;
    uint256 constant SUSPECT_JOB_ID = 99;

    bytes32 constant REASONING_CID = keccak256("ipfs://QmReasoningReport_SuspectAgent_v1");

    function setUp() public {
        token  = new MockERC20("Assurance Token", "ASR");
        aap    = new AAPMockMinimal(address(token), resolver);
        scorer = new OffchainScorerMock();

        token.mint(assuredAgent, DEPOSIT * 10);
        vm.prank(assuredAgent);
        token.approve(address(aap), type(uint256).max);
    }

    function test_HybridOffchainScoring() public {
        // ── Step 1: AssuredAgent commits to the suspect job ────────────
        vm.startPrank(assuredAgent);
        aap.depositAssurance(DEPOSIT);
        bytes32 assuranceId = aap.commitToJob(
            bytes32(SUSPECT_JOB_ID),
            IAAP.CoverageType.JobFailure,
            beneficiary,
            COMMIT,
            FAR_FUTURE
        );
        vm.stopPrank();

        // ── Step 2: Oracle posts a DENY score for the suspect agent ────
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
            87,
            REASONING_CID
        );

        // ── Step 3: A downstream task manager reads the score and acts on it ──
        // This is the Layer 2 (Behavior) consumption: the same score is used
        // here as a prevention signal. In a real ERC-8183 deployment this would
        // trigger a reject() call. Here we simply verify the score is readable.
        (
            OffchainScorerMock.ScorerVerdict verdict,
            uint8 confidence,
            bytes32 reasoningCID
        ) = scorer.score(suspectAgent);
        assertEq(uint8(verdict), uint8(OffchainScorerMock.ScorerVerdict.DENY));
        assertTrue(confidence >= CONFIDENCE_THRESHOLD, "confidence must exceed threshold");
        assertEq(reasoningCID, REASONING_CID);

        emit log_named_string("Layer 2 action", "Task rejected based on DENY score");

        // ── Step 4: Beneficiary files a claim, encoding the SAME reasoningCID
        //           into the evidence payload ──────────────────────────
        // This is the key invariant of the scenario: the off-chain reasoning
        // artifact serves both Layer 2 (prevention) and Layer 3 (recovery)
        // through the same CID, with no re-attestation needed.
        bytes memory evidence = abi.encode(
            "OffchainScore",
            address(scorer),
            suspectAgent,
            REASONING_CID
        );

        vm.prank(beneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, CLAIM_AMOUNT, evidence);

        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.beneficiary, beneficiary);
        assertEq(aap.evidenceHashes(claimId), keccak256(evidence),
            "stored evidence hash must match submitted payload");

        // ── Step 5: Resolver re-reads the score from the scorer to verify ──
        (
            OffchainScorerMock.ScorerVerdict reVerdict,
            uint8 reConfidence,
            bytes32 reCID
        ) = scorer.score(suspectAgent);
        assertEq(uint8(reVerdict), uint8(OffchainScorerMock.ScorerVerdict.DENY));
        assertTrue(reConfidence >= CONFIDENCE_THRESHOLD);
        assertEq(reCID, REASONING_CID,
            "the CID consumed by the resolver must equal the one cited in the claim evidence");

        bytes memory approvalReason = abi.encode(
            "score_verified",
            suspectAgent,
            reConfidence,
            REASONING_CID
        );

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, CLAIM_AMOUNT, approvalReason);

        // ── Step 6: Payout ─────────────────────────────────────────────
        aap.payout(claimId);

        IAAP.Claim memory paid = aap.getClaim(claimId);
        assertEq(uint8(paid.state), uint8(IAAP.ClaimState.Paid));
        assertEq(token.balanceOf(beneficiary), CLAIM_AMOUNT);

        // The shared-evidence invariant: the reasoningCID consumed by Layer 2
        // (task rejection) and Layer 3 (claim filing) is identical.
        emit log_bytes32(REASONING_CID);
    }
}
