// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IAAP — Minimal subset of the ERC-8210 (Agent Assurance Protocol) interface
/// @notice This is a faithful subset of the ERC-8210 v1 specification, including
///         only the types and functions exercised by the three reference scenarios
///         in this folder. All function signatures, struct fields, and enum values
///         match the canonical spec at:
///         https://github.com/ethereum/ERCs/pull/1632
///
///         For the full interface (including AssuranceAccount lifecycle, JobAssurance
///         expiry, payout, and additional getters), refer to the canonical spec.
interface IAAP {
    // ─────────────────────────────────────────────────────────────────
    // Enums (matching ERC-8210 v1 spec)
    // ─────────────────────────────────────────────────────────────────

    enum CoverageType {
        JobFailure,        // Provider non-performance
        EvaluatorDispute,  // Evaluator decision challenged
        SettlementDefault, // Fund release failure after valid completion
        AMLFreeze,         // Extension-reserved
        SlashingLoss       // Extension-reserved
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

    // ─────────────────────────────────────────────────────────────────
    // Structs (matching ERC-8210 v1 spec)
    // ─────────────────────────────────────────────────────────────────

    struct JobAssurance {
        bytes32      assuranceId;
        address      assuredAgent;
        address      beneficiary;
        bytes32      coveredJob;
        CoverageType coverageType;
        uint256      committedAmount;
        uint64       expiry;
        uint256      chainId;
        bytes32      claimId;
        AssuranceState state;
    }

    struct Claim {
        bytes32    claimId;
        bytes32    assuranceId;
        address    beneficiary;
        uint256    requestedAmount;
        uint256    approvedAmount;
        ClaimState state;
        uint64     filedAt;
        uint64     resolvedAt;
    }

    // ─────────────────────────────────────────────────────────────────
    // Events (matching ERC-8210 v1 spec)
    // ─────────────────────────────────────────────────────────────────

    event AssuranceCommitted(
        bytes32 indexed assuranceId,
        address indexed assuredAgent,
        bytes32 jobId,
        address indexed beneficiary,
        CoverageType coverageType,
        uint256 committedAmount,
        uint64 expiry
    );

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

    // ─────────────────────────────────────────────────────────────────
    // Functions used by scenarios (matching ERC-8210 v1 spec)
    // ─────────────────────────────────────────────────────────────────

    /// @notice Deposit collateral into the caller's AssuranceAccount.
    function depositAssurance(uint256 amount) external;

    /// @notice Create an assurance commitment for a specific Job.
    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external returns (bytes32 assuranceId);

    /// @notice File a Claim against an active JobAssurance.
    /// @dev    `evidence` is an opaque bytes payload. Scenarios in this folder
    ///         encode upstream references, slash record references, and offchain
    ///         scoring CIDs into this payload, demonstrating that all forms of
    ///         provenance composition can be carried by `evidence` without
    ///         expanding the core spec interface.
    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata evidence
    ) external returns (bytes32 claimId);

    /// @notice Resolve a pending Claim. Caller must be an authorized resolver.
    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata reason
    ) external;

    /// @notice Settle an approved Claim. Permissionless.
    function payout(bytes32 claimId) external;

    /// @notice Query a JobAssurance by its identifier.
    function getJobAssurance(bytes32 assuranceId) external view returns (JobAssurance memory);

    /// @notice Query a Claim by its identifier.
    function getClaim(bytes32 claimId) external view returns (Claim memory);
}
