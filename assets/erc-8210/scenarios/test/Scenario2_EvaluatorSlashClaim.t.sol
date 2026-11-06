// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mocks/AAPMockMinimal.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/EvaluatorRegistryMock.sol";
import "../contracts/interfaces/IAAP.sol";

/// @title Scenario 2 — EvaluatorSlashed → fileClaim
/// @notice Demonstrates that an `EvaluatorSlashed` event from an external
///         evaluator registry can serve as automatic claim eligibility proof:
///         the harmed party encodes the slash record into the AAP `evidence`
///         payload, and the resolver verifies it directly against the registry.
///
///         Layer mapping:
///           - Layer 1 (Structure): the evaluator registry (8183-side)
///           - Layer 2 (Behavior):  the slash event itself, signaling misconduct
///           - Layer 3 (Recovery):  AAP claim is filed with the slash record as
///             evidence, no second adjudication needed
contract Scenario2_EvaluatorSlashClaim is Test {
    AAPMockMinimal        aap;
    MockERC20             token;
    EvaluatorRegistryMock registry;

    address dishonestEval    = makeAddr("dishonestEvaluator");
    address assuredAgent     = makeAddr("assuredAgent");
    address harmedBeneficiary = makeAddr("harmedBeneficiary");
    address resolver         = makeAddr("resolver");
    address registryOperator = makeAddr("registryOperator");

    uint256 constant DEPOSIT      = 1000e18;
    uint256 constant COMMIT       = 750e18;
    uint64  constant FAR_FUTURE   = type(uint64).max;
    uint256 constant CLAIM_AMOUNT = 750e18;
    uint256 constant SLASH_AMOUNT = 1_000e18;
    uint256 constant JOB_ID       = 42;
    bytes32 constant SLASH_REASON = bytes32("biased_scoring");

    function setUp() public {
        token    = new MockERC20("Assurance Token", "ASR");
        aap      = new AAPMockMinimal(address(token), resolver);
        registry = new EvaluatorRegistryMock();

        token.mint(assuredAgent, DEPOSIT * 10);
        vm.prank(assuredAgent);
        token.approve(address(aap), type(uint256).max);
    }

    function test_EvaluatorSlashToClaim() public {
        // ── Step 1: AssuredAgent posts collateral and commits to the disputed Job ──
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

        // ── Step 2: Registry slashes the dishonest evaluator for misconduct ──
        vm.prank(registryOperator);
        vm.expectEmit(true, true, false, true, address(registry));
        emit EvaluatorRegistryMock.EvaluatorSlashed(
            dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON
        );
        registry.slashEvaluator(dishonestEval, JOB_ID, SLASH_AMOUNT, SLASH_REASON);

        bytes32 slashHash = registry.buildEvidenceHash(JOB_ID);
        assertTrue(slashHash != bytes32(0), "slash hash should be non-zero");

        // ── Step 3: Beneficiary files a claim, encoding the slash reference
        //           into the evidence payload ──────────────────────────
        // The evidence payload binds the claim to the on-chain slash record.
        // The resolver can re-derive the slash hash from the registry to
        // verify that the evidence is authentic.
        bytes memory evidence = abi.encode(
            "EvaluatorSlashed",
            address(registry),
            JOB_ID,
            slashHash
        );

        vm.prank(harmedBeneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, CLAIM_AMOUNT, evidence);

        IAAP.Claim memory c = aap.getClaim(claimId);
        assertEq(c.beneficiary, harmedBeneficiary);
        assertEq(aap.evidenceHashes(claimId), keccak256(evidence),
            "stored evidence hash must match submitted payload");

        // ── Step 4: Resolver verifies the slash and approves ──────────
        // Re-derive the slash hash from the registry. If it matches the
        // hash committed in the evidence payload, the slash is authentic
        // and no further adjudication is needed.
        bytes32 reDerivedSlashHash = registry.buildEvidenceHash(JOB_ID);
        assertEq(reDerivedSlashHash, slashHash,
            "registry must return same slash hash for replay verification");

        bytes memory approvalReason = abi.encode(
            "slash_verified",
            dishonestEval,
            JOB_ID
        );

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, CLAIM_AMOUNT, approvalReason);

        // ── Step 5: Payout ─────────────────────────────────────────────
        aap.payout(claimId);

        IAAP.Claim memory paid = aap.getClaim(claimId);
        assertEq(uint8(paid.state), uint8(IAAP.ClaimState.Paid));
        assertEq(token.balanceOf(harmedBeneficiary), CLAIM_AMOUNT,
            "harmed beneficiary should receive payout");
    }
}
