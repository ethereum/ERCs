// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/EvaluatorRegistryWithStake.sol";
import "../contracts/interfaces/IAAP.sol";

/// @title Scenario 4 — Stateless Solvency-Aware Claim Assessment
/// @notice Demonstrates that EvaluatorSlashed and EvaluatorStakeUpdated
///         emitted in the same transaction enable stateless solvency
///         assessment: a downstream consumer can determine both the slash
///         details AND the evaluator's post-slash balance from log data
///         alone, without local state or additional RPC calls.
///
///         Layer mapping:
///           - Layer 1 (Structure): the evaluator registry manages stake
///           - Layer 2 (Behavior):  slash + stake-update signals serve as
///             behavioral evidence of misconduct and solvency state
///           - Layer 3 (Recovery):  AAP claim is filed with enriched
///             evidence containing both event references
contract Scenario4_SolvencyAwareClaimAssessment is Test {
    AAPMockMinimal              aap;
    MockERC20                   token;
    EvaluatorRegistryWithStake  registry;

    address dishonestEval     = makeAddr("dishonestEvaluator");
    address assuredAgent      = makeAddr("assuredAgent");
    address harmedBeneficiary = makeAddr("harmedBeneficiary");
    address resolver          = makeAddr("resolver");
    address registryOperator  = makeAddr("registryOperator");

    uint256 constant DEPOSIT       = 1000e18;
    uint256 constant COMMIT        = 500e18;
    uint64  constant FAR_FUTURE    = type(uint64).max;
    uint256 constant CLAIM_AMOUNT  = 500e18;
    uint256 constant STAKE_AMOUNT  = 2000e18;
    uint256 constant SLASH_AMOUNT  = 800e18;
    uint256 constant JOB_ID        = 77;
    bytes32 constant SLASH_REASON  = bytes32("front_running");

    function setUp() public {
        token    = new MockERC20("Assurance Token", "ASR");
        aap      = new AAPMockMinimal(address(token), resolver);
        registry = new EvaluatorRegistryWithStake();

        token.mint(assuredAgent, DEPOSIT * 10);
        vm.prank(assuredAgent);
        token.approve(address(aap), type(uint256).max);
    }

    function test_SolvencyAwareClaimAssessment() public {
        // Step 1: Evaluator stakes
        vm.prank(dishonestEval);
        vm.expectEmit(true, false, false, true, address(registry));
        emit EvaluatorRegistryWithStake.EvaluatorStakeUpdated(
            dishonestEval, 0, STAKE_AMOUNT
        );
        registry.depositStake(STAKE_AMOUNT);
        assertEq(registry.stakeBalances(dishonestEval), STAKE_AMOUNT);

        // Step 2: Assured agent commits
        vm.startPrank(assuredAgent);
        aap.depositAssurance(DEPOSIT);
        bytes32 assuranceId = aap.commitToJob(
            bytes32(JOB_ID),
            IAAP.CoverageType.EvaluatorDispute,
            harmedBeneficiary,
            COMMIT,
            FAR_FUTURE
        );
        vm.stopPrank();

        // Step 3: Slash — both events in one tx
        // slashEvaluator() emits EvaluatorSlashed AND EvaluatorStakeUpdated
        // in the same transaction. A stateless indexer reading the tx logs:
        //   log[0]: EvaluatorSlashed(evaluator, jobId, 800e18, "front_running")
        //   log[1]: EvaluatorStakeUpdated(evaluator, 2000e18, 1200e18)
        // From these two logs alone, the indexer knows what happened, how
        // much was slashed, and the evaluator's remaining stake — no RPC
        // call, no local state.
        vm.prank(registryOperator);
        vm.expectEmit(true, true, false, true, address(registry));
        emit EvaluatorRegistryWithStake.EvaluatorSlashed(
            dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON
        );
        vm.expectEmit(true, false, false, true, address(registry));
        emit EvaluatorRegistryWithStake.EvaluatorStakeUpdated(
            dishonestEval, STAKE_AMOUNT, STAKE_AMOUNT - SLASH_AMOUNT
        );
        registry.slashEvaluator(dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON);
        assertEq(registry.stakeBalances(dishonestEval), STAKE_AMOUNT - SLASH_AMOUNT);

        // Step 4: Enriched evidence payload with both references
        bytes32 slashHash = registry.buildEvidenceHash(JOB_ID);
        assertTrue(slashHash != bytes32(0));
        bytes32 stakeHash = registry.buildStakeEvidenceHash(dishonestEval);
        assertTrue(stakeHash != bytes32(0));

        bytes memory evidence = abi.encode(
            "SolvencyAwareSlash",
            address(registry),
            JOB_ID,
            slashHash,
            dishonestEval,
            stakeHash
        );

        vm.prank(harmedBeneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, CLAIM_AMOUNT, evidence);

        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.beneficiary, harmedBeneficiary);
        assertEq(aap.evidenceHashes(claimId), keccak256(evidence));

        // Step 5: Resolver verifies both slash and solvency
        assertEq(registry.buildEvidenceHash(JOB_ID), slashHash);
        assertEq(registry.buildStakeEvidenceHash(dishonestEval), stakeHash);

        bytes memory approvalReason = abi.encode(
            "slash_and_solvency_verified",
            dishonestEval,
            JOB_ID,
            registry.stakeBalances(dishonestEval)
        );
        vm.prank(resolver);
        aap.resolveClaim(claimId, true, CLAIM_AMOUNT, approvalReason);

        // Step 6: Payout
        aap.payout(claimId);
        IAAP.Claim memory paid = aap.getClaim(claimId);
        assertEq(uint8(paid.state), uint8(IAAP.ClaimState.Paid));
        assertEq(token.balanceOf(harmedBeneficiary), CLAIM_AMOUNT);
    }

    function test_ZeroStakePostSlash_FullWipeout() public {
        // Edge case: slash depletes entire stake. A stateless indexer
        // seeing EvaluatorStakeUpdated(evaluator, X, 0) knows the
        // evaluator has zero future deterrent — no additional query.
        uint256 exactSlash = STAKE_AMOUNT;

        vm.prank(dishonestEval);
        registry.depositStake(STAKE_AMOUNT);

        vm.startPrank(assuredAgent);
        aap.depositAssurance(DEPOSIT);
        bytes32 assuranceId = aap.commitToJob(
            bytes32(JOB_ID),
            IAAP.CoverageType.EvaluatorDispute,
            harmedBeneficiary,
            COMMIT,
            FAR_FUTURE
        );
        vm.stopPrank();

        vm.prank(registryOperator);
        vm.expectEmit(true, false, false, true, address(registry));
        emit EvaluatorRegistryWithStake.EvaluatorStakeUpdated(
            dishonestEval, STAKE_AMOUNT, 0
        );
        registry.slashEvaluator(dishonestEval, JOB_ID, exactSlash, SLASH_REASON);
        assertEq(registry.stakeBalances(dishonestEval), 0);

        bytes32 stakeHash = registry.buildStakeEvidenceHash(dishonestEval);
        bytes32 slashHash = registry.buildEvidenceHash(JOB_ID);
        bytes memory evidence = abi.encode(
            "SolvencyAwareSlash", address(registry), JOB_ID,
            slashHash, dishonestEval, stakeHash
        );

        vm.prank(harmedBeneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, CLAIM_AMOUNT, evidence);

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, CLAIM_AMOUNT, "full_wipeout");

        aap.payout(claimId);
        IAAP.Claim memory paid = aap.getClaim(claimId);
        assertEq(uint8(paid.state), uint8(IAAP.ClaimState.Paid));
    }
}
