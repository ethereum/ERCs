// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title ERC-8210: Agent Assurance Protocol — Core Interface
/// @notice Programmable fulfillment assurance primitive for Agent commerce.

// ---- Enums ----

enum CoverageType {
    JobFailure,        // Provider non-performance
    EvaluatorDispute,  // Evaluator decision challenged
    SettlementDefault, // Fund release failure after valid completion
    AMLFreeze,         // Extension-reserved
    SlashingLoss       // Extension-reserved
}

enum AccountStatus {
    Active,
    Paused
}

enum AssuranceState {
    Active,
    Claimed,
    Paid,
    Released,
    Expired
}

enum ClaimState {
    None,
    Filed,
    Challenged,
    Approved,
    Denied,
    Paid
}

// ---- Structs ----

struct AssuranceAccount {
    address agent;
    address settlementAsset;
    uint256 totalFunded;
    uint256 availableAmount;
    uint256 lockedAmount;
    uint256 paidOutAmount;
    AccountStatus status;
}

struct JobAssurance {
    bytes32 assuranceId;
    address assuredAgent;
    address beneficiary;
    bytes32 coveredJob;
    CoverageType coverageType;
    uint256 committedAmount;
    uint64 expiry;
    uint256 chainId;
    bytes32 claimId;
    AssuranceState state;
}

struct Claim {
    bytes32 claimId;
    bytes32 assuranceId;
    address beneficiary;
    uint256 requestedAmount;
    uint256 approvedAmount;
    ClaimState state;
    uint64 filedAt;
    uint64 resolvedAt;
}

// ---- Events ----

event AssuranceDeposited(address indexed agent, uint256 amount, uint256 newAvailableAmount);
event AssuranceWithdrawn(address indexed agent, uint256 amount, uint256 newAvailableAmount);
event AccountStatusChanged(address indexed agent, AccountStatus newStatus);

event AssuranceCommitted(
    bytes32 indexed assuranceId,
    address indexed assuredAgent,
    bytes32 jobId,
    address indexed beneficiary,
    CoverageType coverageType,
    uint256 committedAmount,
    uint64 expiry
);
event AssuranceReleased(bytes32 indexed assuranceId, address indexed assuredAgent, uint256 releasedAmount);
event AssuranceExpired(bytes32 indexed assuranceId);

event ClaimFiled(
    bytes32 indexed claimId,
    bytes32 indexed assuranceId,
    address indexed beneficiary,
    uint256 requestedAmount
);
event ClaimResolved(
    bytes32 indexed claimId,
    bytes32 indexed assuranceId,
    bool approved,
    uint256 approvedAmount,
    address indexed resolver
);
event ClaimPaid(
    bytes32 indexed claimId,
    bytes32 indexed assuranceId,
    address indexed beneficiary,
    uint256 amount
);

// ---- Interface ----

interface IAAP {
    function depositAssurance(uint256 amount) external;
    function withdrawAvailableAssurance(uint256 amount) external;
    function getAssuranceAccount(address agent) external view returns (AssuranceAccount memory);

    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external returns (bytes32 assuranceId);
    function releaseCommitment(bytes32 assuranceId) external;
    function expireCommitment(bytes32 assuranceId) external;
    function getJobAssurance(bytes32 assuranceId) external view returns (JobAssurance memory);

    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata evidence
    ) external returns (bytes32 claimId);
    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata reason
    ) external;
    function payout(bytes32 claimId) external;
    function getClaim(bytes32 claimId) external view returns (Claim memory);
}
