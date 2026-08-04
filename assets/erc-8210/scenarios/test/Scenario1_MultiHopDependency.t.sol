// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/ChainedJobsMock.sol";
import "../contracts/interfaces/IAAP.sol";

/// @title Scenario 1 — Multi-Hop Dependency Tracking
/// @notice Demonstrates that ERC-8210's opaque `evidence` payload can carry an
///         upstream reference linking a Claim to a multi-job pipeline (A→B→C→D).
///         The core spec stays 1:1 Job-scoped; provenance composition lives
///         entirely in the evidence payload, not in the AAP interface.
///
///         Layer mapping (per the 3-layer architecture in the README):
///           - Layer 1 (Structure): the pipeline contract (ERC-8183-equivalent)
///           - Layer 2 (Behavior):  the reviewer reads the upstream chain to
///             identify the root cause
///           - Layer 3 (Recovery):  AAP claim is filed against a JobAssurance
///             whose evidence encodes the upstream reference
contract Scenario1_MultiHopDependency is Test {
    AAPMockMinimal  aap;
    MockERC20       token;
    ChainedJobsMock pipeline;

    address operator    = makeAddr("operator");
    address assuredAgent = makeAddr("assuredAgent");
    address beneficiary = makeAddr("beneficiary");
    address resolver    = makeAddr("resolver");

    uint256 constant DEPOSIT      = 1000e18;
    uint256 constant COMMIT       = 500e18;
    uint64  constant FAR_FUTURE   = type(uint64).max;
    uint256 constant CLAIM_AMOUNT = 500e18;

    function setUp() public {
        token = new MockERC20("Assurance Token", "ASR");
        aap   = new AAPMockMinimal(address(token), resolver);

        // Fund the assured agent and approve AAP
        token.mint(assuredAgent, DEPOSIT * 10);
        vm.prank(assuredAgent);
        token.approve(address(aap), type(uint256).max);

        pipeline = new ChainedJobsMock();
    }

    function test_MultiHopDependencyTracking() public {
        // ── Step 1: Operator creates a 4-job pipeline ──────────────────
        vm.startPrank(operator);
        uint256 jobA = pipeline.createJob(bytes32("DataIngest"), 0);
        uint256 jobB = pipeline.createJob(bytes32("Transform"),  jobA);
        uint256 jobC = pipeline.createJob(bytes32("Validate"),   jobB);
        uint256 jobD = pipeline.createJob(bytes32("Publish"),    jobC);

        // Jobs A and B complete; C fails; D publishes bad data anyway
        pipeline.setStatus(jobA, ChainedJobsMock.JobStatus.Completed);
        pipeline.setStatus(jobB, ChainedJobsMock.JobStatus.Completed);
        pipeline.setStatus(jobC, ChainedJobsMock.JobStatus.Failed);
        pipeline.setStatus(jobD, ChainedJobsMock.JobStatus.Completed);
        vm.stopPrank();

        // ── Step 2: AssuredAgent deposits and commits assurance for Job D ──
        // The JobAssurance is bound to jobD (the leaf job) at the spec level.
        // The fact that jobD depends on a failed upstream job is composition
        // metadata that lives in the evidence payload, not in the spec.
        vm.startPrank(assuredAgent);
        aap.depositAssurance(DEPOSIT);
        bytes32 jobIdD = bytes32(jobD);
        bytes32 assuranceId = aap.commitToJob(
            jobIdD,
            IAAP.CoverageType.JobFailure,
            beneficiary,
            COMMIT,
            FAR_FUTURE
        );
        vm.stopPrank();

        // ── Step 3: Beneficiary builds an evidence payload that encodes the
        //           upstream reference and files a claim ────────────────
        bytes32 upstreamRef = pipeline.upstreamHash(jobD);

        // The evidence payload is opaque to AAP. Here it carries:
        //   - the upstream root reference (pointing into the pipeline)
        //   - a marker for the failure type
        // A real implementation might encode an IPFS CID, an attestation, etc.
        bytes memory evidence = abi.encode(
            "pipeline_failure",
            jobD,
            upstreamRef
        );

        vm.prank(beneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, CLAIM_AMOUNT, evidence);

        // Verify the claim was stored correctly
        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.beneficiary,     beneficiary);
        assertEq(c.requestedAmount, CLAIM_AMOUNT);
        assertEq(uint8(c.state),    uint8(IAAP.ClaimState.Filed));

        // Verify the evidence hash matches what we submitted
        assertEq(aap.evidenceHashes(claimId), keccak256(evidence),
            "evidence hash must match the submitted payload");

        // ── Step 4: Resolver traces the root cause using the upstream chain ──
        uint256[] memory chain = pipeline.traceToRoot(jobD);
        assertEq(chain.length, 4, "chain should have 4 hops");
        assertEq(chain[0], jobD, "leaf is jobD");
        assertEq(chain[3], jobA, "root is jobA");

        uint256 failedJobId;
        for (uint256 i = 0; i < chain.length; i++) {
            (, ChainedJobsMock.JobStatus status,,) = pipeline.jobs(chain[i]);
            if (status == ChainedJobsMock.JobStatus.Failed) {
                failedJobId = chain[i];
                break;
            }
        }
        assertEq(failedJobId, jobC, "root cause should be jobC (Validate)");

        // ── Step 5: Resolver approves the claim ────────────────────────
        bytes memory reason = abi.encode("root_cause_job", failedJobId);

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, CLAIM_AMOUNT, reason);

        IAAP.Claim memory resolved = aap.getClaim(claimId);
        assertEq(uint8(resolved.state),  uint8(IAAP.ClaimState.Approved));
        assertEq(resolved.approvedAmount, CLAIM_AMOUNT);

        // ── Step 6: Payout (permissionless) ────────────────────────────
        aap.payout(claimId);

        IAAP.Claim memory paid = aap.getClaim(claimId);
        assertEq(uint8(paid.state), uint8(IAAP.ClaimState.Paid));
        assertEq(token.balanceOf(beneficiary), CLAIM_AMOUNT,
            "beneficiary should receive the payout");
    }
}
