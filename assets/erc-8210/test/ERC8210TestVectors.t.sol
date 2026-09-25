// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {
    IAAP,
    AssuranceAccount, JobAssurance, Claim,
    CoverageType, AccountStatus, AssuranceState, ClaimState,
    AssuranceDeposited, AssuranceWithdrawn,
    AssuranceCommitted, AssuranceReleased, AssuranceExpired,
    ClaimFiled, ClaimResolved, ClaimPaid
} from "../contracts/interfaces/IAAP.sol";
import {AAPMock} from "../contracts/mocks/AAPMock.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

/// @title ERC-8210 Test Vectors
/// @notice Implements the 14 test scenarios specified in the ERC-8210 Test Cases section.
/// @dev Each test_ function maps 1:1 to a numbered scenario in the spec.
contract ERC8210TestVectors is Test {

    AAPMock internal aap;
    MockERC20 internal token;

    address internal agent    = address(0xA1);
    address internal beneficiary = address(0xB1);
    address internal resolver_   = address(0xC1);
    address internal evaluator = address(0xD1);
    address internal outsider  = address(0xE1);

    bytes32 internal constant JOB_ID = keccak256("test-job-1");
    uint256 internal constant DEPOSIT = 10_000e6;   // 10 000 mUSDC
    uint256 internal constant COMMIT  = 5_000e6;    // 5 000 mUSDC
    uint64  internal constant EXPIRY  = 1_000_000;  // absolute timestamp

    function setUp() public {
        token = new MockERC20();
        aap = new AAPMock(address(token), resolver_);

        // Fund agent
        token.mint(agent, DEPOSIT);
        vm.prank(agent);
        token.approve(address(aap), type(uint256).max);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    function _deposit(uint256 amount) internal {
        vm.prank(agent);
        aap.depositAssurance(amount);
    }

    function _commit(bytes32 jobId, CoverageType cType, uint256 amount, uint64 expiry)
        internal
        returns (bytes32)
    {
        vm.prank(agent);
        return aap.commitToJob(jobId, cType, beneficiary, amount, expiry);
    }

    function _fileClaim(bytes32 assuranceId, uint256 amount) internal returns (bytes32) {
        vm.prank(beneficiary);
        return aap.fileClaim(assuranceId, amount, "");
    }

    function _resolve(bytes32 claimId, bool approved, uint256 amount) internal {
        vm.prank(resolver_);
        aap.resolveClaim(claimId, approved, amount, "");
    }

    function _payout(bytes32 claimId) internal {
        aap.payout(claimId);
    }

    /// @dev Assert the core accounting invariant: totalFunded == available + locked + paidOut.
    function _assertInvariant(address who) internal view {
        AssuranceAccount memory acct = aap.getAssuranceAccount(who);
        assertEq(
            acct.totalFunded,
            acct.availableAmount + acct.lockedAmount + acct.paidOutAmount,
            "INVARIANT: totalFunded != available + locked + paidOut"
        );
    }

    // =======================================================================
    // Test 1 — Full happy path (assurance path)
    // depositAssurance -> commitToJob -> Job completes -> releaseCommitment
    // =======================================================================

    function test_01_FullHappyPath_AssurancePath() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // Verify commitment locked
        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, DEPOSIT - COMMIT);
        assertEq(acct.lockedAmount, COMMIT);

        // Job completes successfully
        aap.setJobState(JOB_ID, AAPMock.JobState.Completed);

        vm.prank(agent);
        aap.releaseCommitment(aid);

        // Verify release
        JobAssurance memory ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Released);

        acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, DEPOSIT);
        assertEq(acct.lockedAmount, 0);

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 2 — Full happy path (claims path)
    // depositAssurance -> commitToJob -> Job fails -> fileClaim ->
    // resolveClaim(approved) -> payout
    // =======================================================================

    function test_02_FullHappyPath_ClaimsPath() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // Job fails
        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);

        bytes32 cid = _fileClaim(aid, COMMIT);

        // Verify Claimed state
        JobAssurance memory ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Claimed);

        Claim memory c = aap.getClaim(cid);
        assertTrue(c.state == ClaimState.Filed);

        // Approve
        _resolve(cid, true, COMMIT);
        c = aap.getClaim(cid);
        assertTrue(c.state == ClaimState.Approved);
        assertEq(c.approvedAmount, COMMIT);

        // Payout
        uint256 balBefore = token.balanceOf(beneficiary);
        _payout(cid);

        // Verify final states
        c = aap.getClaim(cid);
        assertTrue(c.state == ClaimState.Paid);

        ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Paid);

        assertEq(token.balanceOf(beneficiary) - balBefore, COMMIT);

        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.paidOutAmount, COMMIT);
        assertEq(acct.lockedAmount, 0);

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 3 — Denial path
    // fileClaim -> resolveClaim(denied); Claim -> Denied, JobAssurance -> Active;
    // committedAmount stays in lockedAmount; subsequent fileClaim reverts;
    // new commitToJob for same (jobId, coverageType) reverts while prior Active;
    // renewal requires release or expiry first.
    // =======================================================================

    function test_03_DenialPath() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);
        bytes32 cid = _fileClaim(aid, COMMIT);

        // Deny the claim
        _resolve(cid, false, 0);

        Claim memory c = aap.getClaim(cid);
        assertTrue(c.state == ClaimState.Denied);

        JobAssurance memory ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Active);
        assertEq(ja.claimId, cid); // claimId retained

        // committedAmount remains in lockedAmount
        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.lockedAmount, COMMIT);

        // Subsequent fileClaim against same JobAssurance MUST revert (claimId != 0)
        vm.prank(beneficiary);
        vm.expectRevert("AAP: already claimed");
        aap.fileClaim(aid, COMMIT, "");

        // New commitToJob for same (jobId, coverageType) MUST revert while prior is Active
        vm.prank(agent);
        vm.expectRevert("AAP: duplicate commitment");
        aap.commitToJob(JOB_ID, CoverageType.JobFailure, beneficiary, 1_000e6, EXPIRY);

        // Renewal: expire the prior, then recommit
        vm.warp(EXPIRY + 1);
        aap.expireCommitment(aid);

        ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Expired);

        // Now recommit succeeds
        aap.setJobState(JOB_ID, AAPMock.JobState.Active); // reset job state
        bytes32 aid2 = _commit(JOB_ID, CoverageType.JobFailure, 1_000e6, uint64(EXPIRY + 100_000));
        assertTrue(aid2 != bytes32(0));

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 4 — Expiry path
    // commitToJob -> time exceeds expiry -> expireCommitment -> Expired;
    // committedAmount returned.
    // =======================================================================

    function test_04_ExpiryPath() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // Advance past expiry
        vm.warp(EXPIRY + 1);
        aap.expireCommitment(aid);

        JobAssurance memory ja = aap.getJobAssurance(aid);
        assertTrue(ja.state == AssuranceState.Expired);

        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, DEPOSIT);
        assertEq(acct.lockedAmount, 0);

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 5 — Premature expiry
    // expireCommitment before expiry MUST revert.
    // =======================================================================

    function test_05_PrematureExpiry() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // Warp to exactly expiry (not past)
        vm.warp(EXPIRY);

        vm.expectRevert("AAP: not expired");
        aap.expireCommitment(aid);
    }

    // =======================================================================
    // Test 6 — Insolvency
    // resolveClaim(approved) succeeds but payout reverts due to insufficient
    // lockedAmount; Claim remains Approved.
    // =======================================================================

    function test_06_Insolvency() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);
        bytes32 cid = _fileClaim(aid, COMMIT);
        _resolve(cid, true, COMMIT);

        // Simulate external slashing reducing lockedAmount
        aap.simulateSlashing(agent, COMMIT);

        // Payout MUST revert due to insufficient lockedAmount
        vm.expectRevert("AAP: insufficient locked (insolvency)");
        aap.payout(cid);

        // Claim remains Approved
        Claim memory c = aap.getClaim(cid);
        assertTrue(c.state == ClaimState.Approved);
    }

    // =======================================================================
    // Test 7 — Withdrawal boundary
    // withdrawAvailableAssurance succeeds up to availableAmount; attempting
    // to withdraw any portion of lockedAmount MUST revert.
    // =======================================================================

    function test_07_WithdrawalBoundary() public {
        _deposit(DEPOSIT);
        _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // availableAmount = DEPOSIT - COMMIT
        uint256 available = DEPOSIT - COMMIT;

        // Withdraw exactly availableAmount succeeds
        vm.prank(agent);
        aap.withdrawAvailableAssurance(available);

        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, 0);
        assertEq(acct.lockedAmount, COMMIT);

        // Attempting to withdraw even 1 wei MUST revert (would touch locked)
        vm.prank(agent);
        vm.expectRevert("AAP: insufficient available");
        aap.withdrawAvailableAssurance(1);

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 8 — Invalid state transitions
    // (a) Filing a Claim against a non-Active JobAssurance MUST revert.
    // (b) Calling payout on a non-Approved Claim MUST revert.
    // =======================================================================

    function test_08_InvalidStateTransitions() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // (a) Release the assurance, then try to file claim -> revert
        aap.setJobState(JOB_ID, AAPMock.JobState.Completed);
        vm.prank(agent);
        aap.releaseCommitment(aid);

        vm.prank(beneficiary);
        vm.expectRevert("AAP: not active");
        aap.fileClaim(aid, COMMIT, "");

        // (b) Create a new assurance, file claim, but don't resolve -> payout reverts
        bytes32 jobId2 = keccak256("test-job-2");
        aap.setJobState(jobId2, AAPMock.JobState.Active);
        bytes32 aid2 = _commit(jobId2, CoverageType.JobFailure, 1_000e6, EXPIRY);

        aap.setJobState(jobId2, AAPMock.JobState.Failed);
        bytes32 cid2 = _fileClaim(aid2, 1_000e6);

        // Claim is Filed, not Approved -> payout must revert
        vm.expectRevert("AAP: claim not approved");
        aap.payout(cid2);

        // Also verify: payout on a Denied claim reverts
        _resolve(cid2, false, 0);
        vm.expectRevert("AAP: claim not approved");
        aap.payout(cid2);
    }

    // =======================================================================
    // Test 9 — Eligibility gating
    // If the covered Job has not reached the required terminal state,
    // fileClaim MUST revert.
    // =======================================================================

    function test_09_EligibilityGating() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        // Job is still Active (not Failed) -> fileClaim must revert
        vm.prank(beneficiary);
        vm.expectRevert("AAP: job not failed");
        aap.fileClaim(aid, COMMIT, "");

        // Also test EvaluatorDispute: job not in Disputed state
        bytes32 jobId2 = keccak256("test-job-eval");
        aap.setJobState(jobId2, AAPMock.JobState.Active);
        bytes32 aid2 = _commit(jobId2, CoverageType.EvaluatorDispute, 1_000e6, EXPIRY);

        vm.prank(beneficiary);
        vm.expectRevert("AAP: job not disputed");
        aap.fileClaim(aid2, 1_000e6, "");

        // Also test SettlementDefault: job not in Completed state
        bytes32 jobId3 = keccak256("test-job-settle");
        aap.setJobState(jobId3, AAPMock.JobState.Active);
        bytes32 aid3 = _commit(jobId3, CoverageType.SettlementDefault, 1_000e6, EXPIRY);

        vm.prank(beneficiary);
        vm.expectRevert("AAP: job not completed for settlement default");
        aap.fileClaim(aid3, 1_000e6, "");
    }

    // =======================================================================
    // Test 10 — Adverse selection
    // If coverage conditions already qualify for a claim, commitToJob MUST revert.
    // =======================================================================

    function test_10_AdverseSelection() public {
        _deposit(DEPOSIT);

        // Job already failed -> commitToJob for JobFailure must revert
        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);

        vm.prank(agent);
        vm.expectRevert("AAP: job already failed");
        aap.commitToJob(JOB_ID, CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);

        // Job already disputed -> commitToJob for EvaluatorDispute must revert
        bytes32 jobId2 = keccak256("test-job-disputed");
        aap.setJobState(jobId2, AAPMock.JobState.Disputed);

        vm.prank(agent);
        vm.expectRevert("AAP: job already disputed");
        aap.commitToJob(jobId2, CoverageType.EvaluatorDispute, beneficiary, COMMIT, EXPIRY);
    }

    // =======================================================================
    // Test 11 — Duplicate commitment
    // If an Active or Claimed JobAssurance already exists for the same
    // (jobId, coverageType), a subsequent commitToJob MUST revert.
    // =======================================================================

    function test_11_DuplicateCommitment() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, 1_000e6, EXPIRY);

        // Active exists -> duplicate reverts
        vm.prank(agent);
        vm.expectRevert("AAP: duplicate commitment");
        aap.commitToJob(JOB_ID, CoverageType.JobFailure, beneficiary, 1_000e6, EXPIRY);

        // Transition to Claimed -> still reverts
        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);
        _fileClaim(aid, 1_000e6);

        vm.prank(agent);
        vm.expectRevert("AAP: duplicate commitment");
        aap.commitToJob(JOB_ID, CoverageType.JobFailure, beneficiary, 1_000e6, EXPIRY);

        // Different coverageType for same jobId is OK (job is Failed, not Disputed,
        // so EvaluatorDispute adverse selection check passes)
        bytes32 aid2 = _commit(JOB_ID, CoverageType.EvaluatorDispute, 1_000e6, EXPIRY);
        assertTrue(aid2 != bytes32(0));

        _assertInvariant(agent);
    }

    // =======================================================================
    // Test 12 — Amount validation
    // (a) fileClaim with requestedAmount == 0 MUST revert.
    // (b) resolveClaim(approved) with approvedAmount == 0 MUST revert.
    // =======================================================================

    function test_12_AmountValidation() public {
        _deposit(DEPOSIT);
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);

        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);

        // (a) requestedAmount == 0
        vm.prank(beneficiary);
        vm.expectRevert("AAP: zero requested");
        aap.fileClaim(aid, 0, "");

        // File valid claim for part (b)
        bytes32 cid = _fileClaim(aid, COMMIT);

        // (b) approvedAmount == 0 on approval
        vm.prank(resolver_);
        vm.expectRevert("AAP: zero approved");
        aap.resolveClaim(cid, true, 0, "");
    }

    // =======================================================================
    // Test 13 — Recusal rule enforcement
    // If resolveClaim for an EvaluatorDispute Claim is called by the
    // ERC-8183 Evaluator of that Job, it MUST revert.
    // =======================================================================

    function test_13_RecusalRuleEnforcement() public {
        _deposit(DEPOSIT);

        bytes32 jobId = keccak256("test-job-eval-recusal");
        aap.setJobState(jobId, AAPMock.JobState.Active);
        aap.setJobEvaluator(jobId, resolver_); // resolver IS the evaluator

        bytes32 aid = _commit(jobId, CoverageType.EvaluatorDispute, COMMIT, EXPIRY);

        aap.setJobState(jobId, AAPMock.JobState.Disputed);
        bytes32 cid = _fileClaim(aid, COMMIT);

        // Resolver who is also the evaluator -> MUST revert
        vm.prank(resolver_);
        vm.expectRevert("AAP: evaluator recusal");
        aap.resolveClaim(cid, true, COMMIT, "");

        // Also reverts on denial attempt
        vm.prank(resolver_);
        vm.expectRevert("AAP: evaluator recusal");
        aap.resolveClaim(cid, false, 0, "");
    }

    // =======================================================================
    // Test 14 — Invariant verification
    // After every operation, totalFunded == availableAmount + lockedAmount + paidOutAmount.
    // =======================================================================

    function test_14_InvariantVerification() public {
        // Step 1: deposit
        _deposit(DEPOSIT);
        _assertInvariant(agent);

        // Step 2: commit
        bytes32 aid = _commit(JOB_ID, CoverageType.JobFailure, COMMIT, EXPIRY);
        _assertInvariant(agent);

        // Step 3: partial withdrawal
        vm.prank(agent);
        aap.withdrawAvailableAssurance(2_000e6);
        _assertInvariant(agent);

        // Step 4: file claim
        aap.setJobState(JOB_ID, AAPMock.JobState.Failed);
        bytes32 cid = _fileClaim(aid, COMMIT);
        _assertInvariant(agent);

        // Step 5: resolve claim (approved)
        _resolve(cid, true, 3_000e6); // partial approval
        _assertInvariant(agent);

        // Step 6: payout
        _payout(cid);
        _assertInvariant(agent);

        // Verify final numbers
        AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        // Started with 10000, withdrew 2000, paid out 3000 -> totalFunded = 10000 - 2000 = 8000
        // paidOut = 3000, locked = commit(5000) - paidOut(3000) = 2000, available = 8000 - 2000 - 3000 = 3000
        assertEq(acct.totalFunded, 8_000e6);
        assertEq(acct.paidOutAmount, 3_000e6);
        assertEq(acct.lockedAmount, 2_000e6);
        assertEq(acct.availableAmount, 3_000e6);
    }
}
