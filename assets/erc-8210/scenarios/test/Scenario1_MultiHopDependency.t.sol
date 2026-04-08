// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/ChainedJobsMock.sol";

/// @title Scenario 1 — Multi-Hop Dependency Tracking
/// @notice Demonstrates that AAP's `upstream` field can link a claim to an
///         external dependency graph (A→B→C→D), enabling root-cause tracing.
contract Scenario1_MultiHopDependency is Test {
    AAPMockMinimal  aap;
    MockERC20       token;
    ChainedJobsMock pipeline;

    address operator = makeAddr("operator");
    address claimant = makeAddr("claimant");
    address reviewer = makeAddr("reviewer");

    uint256 constant CLAIM_AMOUNT = 500e18;

    function setUp() public {
        // Deploy token and AAP
        token = new MockERC20("Assurance Token", "ASR");
        aap   = new AAPMockMinimal(address(token), reviewer);

        // Fund AAP with tokens for payouts
        token.mint(address(aap), 10_000e18);

        // Deploy pipeline
        pipeline = new ChainedJobsMock();
    }

    function test_MultiHopDependencyTracking() public {
        // ── Step 1: Operator creates a 4-job pipeline ──────────────────
        vm.startPrank(operator);

        uint256 jobA = pipeline.createJob(bytes32("DataIngest"), 0);
        uint256 jobB = pipeline.createJob(bytes32("Transform"),  jobA);
        uint256 jobC = pipeline.createJob(bytes32("Validate"),   jobB);
        uint256 jobD = pipeline.createJob(bytes32("Publish"),    jobC);

        assertEq(jobA, 1, "Job A should be ID 1");
        assertEq(jobD, 4, "Job D should be ID 4");

        // ── Step 2: Jobs A and B complete; C fails; D publishes bad data
        pipeline.setStatus(jobA, ChainedJobsMock.JobStatus.Completed);
        pipeline.setStatus(jobB, ChainedJobsMock.JobStatus.Completed);
        pipeline.setStatus(jobC, ChainedJobsMock.JobStatus.Failed);
        pipeline.setStatus(jobD, ChainedJobsMock.JobStatus.Completed);

        vm.stopPrank();

        // ── Step 3: Claimant files a claim referencing the pipeline ────
        bytes32 upstreamRef = pipeline.upstreamHash(jobD);
        bytes32 evidence    = keccak256(abi.encode("pipeline_failure", jobD));

        vm.prank(claimant);
        uint256 claimId = aap.fileClaim(CLAIM_AMOUNT, evidence, upstreamRef);

        // Verify claim was stored correctly
        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.claimant,     claimant);
        assertEq(c.amount,       CLAIM_AMOUNT);
        assertEq(c.upstream,     upstreamRef);
        assertEq(uint8(c.status), uint8(IAAP.ClaimStatus.Filed));

        // ── Step 4: Reviewer traces the root cause ─────────────────────
        uint256[] memory chain = pipeline.traceToRoot(jobD);

        // Chain should be [4, 3, 2, 1] (leaf → root)
        assertEq(chain.length, 4, "Chain should have 4 hops");
        assertEq(chain[0], jobD, "First element is the leaf job");
        assertEq(chain[3], jobA, "Last element is the root job");

        // Find the failed job in the chain
        uint256 failedJobId;
        for (uint256 i = 0; i < chain.length; i++) {
            (, ChainedJobsMock.JobStatus status,,) = pipeline.jobs(chain[i]);
            if (status == ChainedJobsMock.JobStatus.Failed) {
                failedJobId = chain[i];
                break;
            }
        }
        assertEq(failedJobId, jobC, "Root cause should be Job C (Validate)");

        // ── Step 5: Reviewer approves the claim ────────────────────────
        bytes32 reason = keccak256(abi.encode("root_cause_job", failedJobId));

        vm.prank(reviewer);
        aap.reviewClaim(claimId, IAAP.Verdict.Approve, reason);

        // Verify final state
        IAAP.Claim memory resolved = aap.getClaim(claimId);
        assertEq(uint8(resolved.status), uint8(IAAP.ClaimStatus.Approved));
        assertEq(token.balanceOf(claimant), CLAIM_AMOUNT, "Claimant should receive payout");
    }
}
