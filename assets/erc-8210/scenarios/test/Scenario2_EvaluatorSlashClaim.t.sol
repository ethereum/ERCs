// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/EvaluatorRegistryMock.sol";

/// @title Scenario 2 — EvaluatorSlashed → fileClaim
/// @notice Demonstrates that a slash event from the EvaluatorRegistry serves as
///         automatic proof for an AAP claim, without re-adjudication.
contract Scenario2_EvaluatorSlashClaim is Test {
    AAPMockMinimal        aap;
    MockERC20             token;
    EvaluatorRegistryMock registry;

    address registryOperator = makeAddr("registryOperator");
    address dishonestEval    = makeAddr("dishonestEvaluator");
    address harmedAgent      = makeAddr("harmedAgent");
    address reviewer         = makeAddr("reviewer");

    uint256 constant JOB_ID         = 42;
    uint256 constant SLASH_AMOUNT   = 1_000e18;
    uint256 constant CLAIM_AMOUNT   = 750e18;
    bytes32 constant SLASH_REASON   = bytes32("biased_scoring");

    function setUp() public {
        token    = new MockERC20("Assurance Token", "ASR");
        aap      = new AAPMockMinimal(address(token), reviewer);
        registry = new EvaluatorRegistryMock();

        // Fund AAP
        token.mint(address(aap), 10_000e18);
    }

    function test_EvaluatorSlashToClaim() public {
        // ── Step 1: Registry operator slashes the dishonest evaluator ──
        vm.prank(registryOperator);
        vm.expectEmit(true, true, false, true, address(registry));
        emit EvaluatorRegistryMock.EvaluatorSlashed(
            dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON
        );
        registry.slashEvaluator(dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON);

        // Verify slash record exists
        (
            address recEval,
            uint256 recJob,
            uint256 recAmount,
            bytes32 recReason,
        ) = registry.slashRecords(JOB_ID);
        assertEq(recEval,   dishonestEval);
        assertEq(recJob,    JOB_ID);
        assertEq(recAmount, SLASH_AMOUNT);
        assertEq(recReason, SLASH_REASON);

        // ── Step 2: Harmed agent builds evidence from the slash record ─
        bytes32 evidenceHash = registry.buildEvidenceHash(JOB_ID);
        assertTrue(evidenceHash != bytes32(0), "Evidence hash should be non-zero");

        // ── Step 3: Harmed agent files a claim in AAP ──────────────────
        bytes32 upstreamRef = keccak256(abi.encode("EvaluatorSlashed", JOB_ID));

        vm.prank(harmedAgent);
        vm.expectEmit(true, true, false, true, address(aap));
        emit IAAP.ClaimFiled(0, harmedAgent, CLAIM_AMOUNT, evidenceHash);
        uint256 claimId = aap.fileClaim(CLAIM_AMOUNT, evidenceHash, upstreamRef);

        // Verify claim references the slash
        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.claimant,     harmedAgent);
        assertEq(c.evidenceHash, evidenceHash);
        assertEq(c.upstream,     upstreamRef);

        // ── Step 4: Reviewer verifies & approves (no re-adjudication) ─
        // The reviewer checks that the slash record matches the claim evidence.
        bytes32 recomputedEvidence = registry.buildEvidenceHash(JOB_ID);
        assertEq(recomputedEvidence, c.evidenceHash, "Evidence must match slash record");

        bytes32 approvalReason = keccak256(
            abi.encode("slash_verified", dishonestEval, JOB_ID)
        );

        vm.prank(reviewer);
        vm.expectEmit(true, false, false, true, address(aap));
        emit IAAP.ClaimReviewed(claimId, IAAP.Verdict.Approve, approvalReason);
        aap.reviewClaim(claimId, IAAP.Verdict.Approve, approvalReason);

        // ── Step 5: Verify payout ──────────────────────────────────────
        IAAP.Claim memory resolved = aap.getClaim(claimId);
        assertEq(uint8(resolved.status), uint8(IAAP.ClaimStatus.Approved));
        assertEq(token.balanceOf(harmedAgent), CLAIM_AMOUNT, "Harmed agent should receive payout");
    }
}
