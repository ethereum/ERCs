// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    IAAP,
    AssuranceAccount, JobAssurance, Claim,
    CoverageType, AccountStatus, AssuranceState, ClaimState,
    AssuranceDeposited, AssuranceWithdrawn, AccountStatusChanged,
    AssuranceCommitted, AssuranceReleased, AssuranceExpired,
    ClaimFiled, ClaimResolved, ClaimPaid
} from "../interfaces/IAAP.sol";

import {IERC20} from "../interfaces/IERC20.sol";

/// @title AAPMock — Minimal mock implementation of ERC-8210 IAAP for test vectors.
/// @notice Implements the core state machines and invariants described in ERC-8210.
///         NOT intended for production use.
contract AAPMock is IAAP {

    // ---- Storage ----

    IERC20 public immutable settlementAsset;
    address public resolver;

    mapping(address => AssuranceAccount) internal _accounts;
    mapping(bytes32 => JobAssurance) internal _assurances;
    mapping(bytes32 => Claim) internal _claims;

    /// @dev Tracks (agent, jobId, coverageType) -> assuranceId to enforce duplicate-commitment rule.
    mapping(bytes32 => bytes32) internal _commitmentKeys;

    uint256 internal _assuranceNonce;
    uint256 internal _claimNonce;

    // ---- Mock helpers for ERC-8183 Job state simulation ----

    enum JobState { Active, Completed, Failed, Disputed }

    mapping(bytes32 => JobState) public jobStates;
    mapping(bytes32 => address) public jobEvaluators;

    // ---- Constructor ----

    constructor(address _settlementAsset, address _resolver) {
        settlementAsset = IERC20(_settlementAsset);
        resolver = _resolver;
    }

    // ---- Mock control functions (for test setup) ----

    function setJobState(bytes32 jobId, JobState state) external {
        jobStates[jobId] = state;
    }

    function setJobEvaluator(bytes32 jobId, address evaluator) external {
        jobEvaluators[jobId] = evaluator;
    }

    /// @dev Simulate external slashing of lockedAmount for insolvency test.
    function simulateSlashing(address agent, uint256 amount) external {
        AssuranceAccount storage acct = _accounts[agent];
        require(acct.lockedAmount >= amount, "AAP: slash exceeds locked");
        acct.lockedAmount -= amount;
        acct.totalFunded -= amount;
    }

    // ---- AssuranceAccount lifecycle ----

    function depositAssurance(uint256 amount) external {
        require(amount > 0, "AAP: zero deposit");
        settlementAsset.transferFrom(msg.sender, address(this), amount);

        AssuranceAccount storage acct = _accounts[msg.sender];
        if (acct.agent == address(0)) {
            acct.agent = msg.sender;
            acct.settlementAsset = address(settlementAsset);
            acct.status = AccountStatus.Active;
            emit AccountStatusChanged(msg.sender, AccountStatus.Active);
        }
        acct.totalFunded += amount;
        acct.availableAmount += amount;

        emit AssuranceDeposited(msg.sender, amount, acct.availableAmount);
    }

    function withdrawAvailableAssurance(uint256 amount) external {
        AssuranceAccount storage acct = _accounts[msg.sender];
        require(acct.agent != address(0), "AAP: no account");
        require(acct.status == AccountStatus.Active, "AAP: account paused");

        uint256 withdrawAmount = amount == type(uint256).max ? acct.availableAmount : amount;
        require(withdrawAmount <= acct.availableAmount, "AAP: insufficient available");

        acct.availableAmount -= withdrawAmount;
        acct.totalFunded -= withdrawAmount;

        settlementAsset.transfer(msg.sender, withdrawAmount);
        emit AssuranceWithdrawn(msg.sender, withdrawAmount, acct.availableAmount);
    }

    function getAssuranceAccount(address agent) external view returns (AssuranceAccount memory) {
        return _accounts[agent];
    }

    // ---- JobAssurance lifecycle ----

    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external returns (bytes32 assuranceId) {
        require(uint8(coverageType) <= uint8(CoverageType.SettlementDefault), "AAP: unsupported coverage type");

        AssuranceAccount storage acct = _accounts[msg.sender];
        require(acct.agent != address(0), "AAP: no account");
        require(acct.status == AccountStatus.Active, "AAP: account paused");
        require(amount > 0, "AAP: zero amount");
        require(amount <= acct.availableAmount, "AAP: insufficient available");
        require(beneficiary != address(0), "AAP: zero beneficiary");

        // Duplicate commitment check (before adverse selection so that existing
        // Active/Claimed assurances are caught even when the job is already claimable)
        bytes32 commitKey = keccak256(abi.encodePacked(msg.sender, jobId, coverageType));
        bytes32 existingId = _commitmentKeys[commitKey];
        if (existingId != bytes32(0)) {
            AssuranceState existingState = _assurances[existingId].state;
            require(
                existingState != AssuranceState.Active && existingState != AssuranceState.Claimed,
                "AAP: duplicate commitment"
            );
        }

        // Adverse selection: coverage condition must not already qualify for a claim
        _requireNotAlreadyClaimable(jobId, coverageType);

        // Generate assuranceId
        _assuranceNonce++;
        assuranceId = keccak256(abi.encodePacked("AAP_ASSURANCE", msg.sender, jobId, coverageType, _assuranceNonce));

        // Update account
        acct.availableAmount -= amount;
        acct.lockedAmount += amount;

        // Store assurance
        _assurances[assuranceId] = JobAssurance({
            assuranceId: assuranceId,
            assuredAgent: msg.sender,
            beneficiary: beneficiary,
            coveredJob: jobId,
            coverageType: coverageType,
            committedAmount: amount,
            expiry: expiry,
            chainId: block.chainid,
            claimId: bytes32(0),
            state: AssuranceState.Active
        });

        _commitmentKeys[commitKey] = assuranceId;

        emit AssuranceCommitted(assuranceId, msg.sender, jobId, beneficiary, coverageType, amount, expiry);
    }

    function releaseCommitment(bytes32 assuranceId) external {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.assuredAgent == msg.sender, "AAP: not assured agent");
        require(ja.state == AssuranceState.Active, "AAP: not active");

        // Job must have reached successful completion terminal state
        require(jobStates[ja.coveredJob] == JobState.Completed, "AAP: job not completed");

        // Return funds
        AssuranceAccount storage acct = _accounts[msg.sender];
        acct.lockedAmount -= ja.committedAmount;
        acct.availableAmount += ja.committedAmount;

        ja.state = AssuranceState.Released;

        emit AssuranceReleased(assuranceId, msg.sender, ja.committedAmount);
    }

    function expireCommitment(bytes32 assuranceId) external {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.assuranceId != bytes32(0), "AAP: nonexistent");
        require(ja.state == AssuranceState.Active, "AAP: not active");
        require(block.timestamp > ja.expiry, "AAP: not expired");

        // Return funds
        AssuranceAccount storage acct = _accounts[ja.assuredAgent];
        acct.lockedAmount -= ja.committedAmount;
        acct.availableAmount += ja.committedAmount;

        ja.state = AssuranceState.Expired;

        emit AssuranceExpired(assuranceId);
    }

    function getJobAssurance(bytes32 assuranceId) external view returns (JobAssurance memory) {
        return _assurances[assuranceId];
    }

    // ---- Claim lifecycle ----

    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata /* evidence */
    ) external returns (bytes32 claimId) {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.state == AssuranceState.Active, "AAP: not active");
        require(msg.sender == ja.beneficiary, "AAP: not beneficiary");
        require(ja.claimId == bytes32(0), "AAP: already claimed");
        require(requestedAmount > 0, "AAP: zero requested");
        require(requestedAmount <= ja.committedAmount, "AAP: exceeds committed");

        // Eligibility gating: verify ERC-8183 Job state
        _requireClaimEligible(ja.coveredJob, ja.coverageType);

        // Generate claimId
        _claimNonce++;
        claimId = keccak256(abi.encodePacked("AAP_CLAIM", assuranceId, _claimNonce));

        _claims[claimId] = Claim({
            claimId: claimId,
            assuranceId: assuranceId,
            beneficiary: msg.sender,
            requestedAmount: requestedAmount,
            approvedAmount: 0,
            state: ClaimState.Filed,
            filedAt: uint64(block.timestamp),
            resolvedAt: 0
        });

        ja.claimId = claimId;
        ja.state = AssuranceState.Claimed;

        emit ClaimFiled(claimId, assuranceId, msg.sender, requestedAmount);
    }

    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata /* reason */
    ) external {
        require(msg.sender == resolver, "AAP: not resolver");

        Claim storage c = _claims[claimId];
        require(c.state == ClaimState.Filed, "AAP: claim not filed");

        JobAssurance storage ja = _assurances[c.assuranceId];

        // Recusal rule: EvaluatorDispute claims cannot be resolved by the Job's evaluator
        if (ja.coverageType == CoverageType.EvaluatorDispute) {
            require(msg.sender != jobEvaluators[ja.coveredJob], "AAP: evaluator recusal");
        }

        c.resolvedAt = uint64(block.timestamp);

        if (approved) {
            require(approvedAmount > 0, "AAP: zero approved");
            require(approvedAmount <= c.requestedAmount, "AAP: exceeds requested");
            c.approvedAmount = approvedAmount;
            c.state = ClaimState.Approved;
        } else {
            c.approvedAmount = 0;
            c.state = ClaimState.Denied;
            // Revert JobAssurance to Active; claimId is NOT cleared
            ja.state = AssuranceState.Active;
        }

        emit ClaimResolved(claimId, c.assuranceId, approved, approved ? approvedAmount : 0, msg.sender);
    }

    function payout(bytes32 claimId) external {
        Claim storage c = _claims[claimId];
        require(c.state == ClaimState.Approved, "AAP: claim not approved");

        JobAssurance storage ja = _assurances[c.assuranceId];
        AssuranceAccount storage acct = _accounts[ja.assuredAgent];

        require(acct.lockedAmount >= c.approvedAmount, "AAP: insufficient locked (insolvency)");

        // Debit from locked, credit to paidOut (checks-effects-interactions)
        acct.lockedAmount -= c.approvedAmount;
        acct.paidOutAmount += c.approvedAmount;

        c.state = ClaimState.Paid;
        ja.state = AssuranceState.Paid;

        // Transfer
        settlementAsset.transfer(c.beneficiary, c.approvedAmount);

        emit ClaimPaid(claimId, c.assuranceId, c.beneficiary, c.approvedAmount);
    }

    function getClaim(bytes32 claimId) external view returns (Claim memory) {
        return _claims[claimId];
    }

    // ---- Internal helpers ----

    /// @dev Check that coverage conditions do NOT already qualify for a claim (adverse selection guard).
    function _requireNotAlreadyClaimable(bytes32 jobId, CoverageType cType) internal view {
        if (cType == CoverageType.JobFailure) {
            require(jobStates[jobId] != JobState.Failed, "AAP: job already failed");
        } else if (cType == CoverageType.EvaluatorDispute) {
            require(jobStates[jobId] != JobState.Disputed, "AAP: job already disputed");
        } else if (cType == CoverageType.SettlementDefault) {
            // SettlementDefault requires completed + attribution; simplified check
            require(jobStates[jobId] != JobState.Failed, "AAP: settlement already failed");
        }
    }

    /// @dev Verify that the ERC-8183 eligibility conditions are met for filing a claim.
    function _requireClaimEligible(bytes32 jobId, CoverageType cType) internal view {
        if (cType == CoverageType.JobFailure) {
            require(jobStates[jobId] == JobState.Failed, "AAP: job not failed");
        } else if (cType == CoverageType.EvaluatorDispute) {
            require(jobStates[jobId] == JobState.Disputed, "AAP: job not disputed");
        } else if (cType == CoverageType.SettlementDefault) {
            require(jobStates[jobId] == JobState.Completed, "AAP: job not completed for settlement default");
        }
    }
}
