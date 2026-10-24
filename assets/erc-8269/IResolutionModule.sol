// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ClaimKind, ResolutionCode, Tranche} from "./CaapM1Types.sol";

/// @title IResolutionModule — Typed dispute resolution for LeaseBond
/// @notice The module decides cases; LeaseBond retains and transfers collateral.
interface IResolutionModule {
    enum Phase {
        None,
        Commit,
        Reveal,
        Validation,
        Deliberation,
        Appealable,
        Final,
        Cancelled
    }

    struct PolicyDescriptor {
        bytes32 policyHash;
        bytes32 validatorSetRoot;
        bytes32 quorumRuleHash;
        bytes32 stakeRuleHash;
        bytes32 appealRuleHash;
        bytes32 timeoutRuleHash;
        bytes32 evidenceRuleHash;
        uint64 moduleVersion;
    }

    struct CaseRequest {
        address leaseBond;
        uint256 bondId;
        uint256 claimId;
        bytes32 obligationId;
        ClaimKind claimKind;
        address claimant;
        address respondent;
        bytes32 claimCommitment;
        bytes32 initialEvidenceRoot;
        bytes32 policyHash;
    }

    struct Payout {
        Tranche tranche;
        address recipient;
        uint128 amount;
        uint32 purposeCode;
    }

    struct Decision {
        bytes32 caseId;
        ResolutionCode code;
        bytes32 acceptedEvidenceRoot;
        bytes32 appraisalSetRoot;
        bytes32 reasonHash;
        bytes32 payoutRoot;
        bytes32 priorDecisionDigest;
        bytes32 policyHash;
        uint64 decidedAt;
    }

    event CaseOpened(
        bytes32 indexed caseId,
        address indexed leaseBond,
        uint256 indexed claimId,
        uint256 bondId,
        bytes32 obligationId,
        ClaimKind claimKind,
        bytes32 policyHash
    );
    event PhaseAdvanced(bytes32 indexed caseId, Phase from, Phase to);
    event EvidenceCommitted(bytes32 indexed caseId, address indexed party, bytes32 commitment);
    event EvidenceRevealed(bytes32 indexed caseId, address indexed party, bytes32 disclosureRoot);
    event ValidationReferenced(
        bytes32 indexed caseId,
        address indexed validator,
        bytes32 requestHash,
        bytes32 responseHash
    );
    event DecisionProposed(bytes32 indexed caseId, bytes32 indexed decisionDigest, bytes32 payoutRoot);
    event Appealed(bytes32 indexed caseId, address indexed appellant, bytes32 groundsRoot);
    event CaseFinalized(bytes32 indexed caseId, bytes32 indexed decisionDigest, ResolutionCode code);
    event CaseCancelled(bytes32 indexed caseId, bytes32 reasonHash);

    /// @notice Stable domain identifier for this implementation and version.
    function moduleId() external view returns (bytes32);

    /// @notice Descriptor committed by the bond before collateral is posted.
    function policyDescriptor() external view returns (PolicyDescriptor memory);

    /// @notice Opens one case. Only the named LeaseBond may open its case.
    /// @dev caseId is domain-separated by chain, module, bond, claim, obligation, and policy.
    function openCase(CaseRequest calldata request) external returns (bytes32 caseId);

    /// @notice Commits evidence before reveal; msg.sender is the committing party.
    function commitEvidence(bytes32 caseId, bytes32 commitment) external;

    /// @notice Reveals a CAAP-TELEMETRY disclosure root and salt.
    /// @dev The module recomputes the domain-separated commitment for msg.sender.
    function revealEvidence(bytes32 caseId, bytes32 disclosureRoot, bytes32 salt) external;

    /// @notice References an appraisal, including an ERC-8004 validation record if policy permits.
    /// @dev A reference is evidence input, never by itself a final economic decision.
    function submitValidationReference(
        bytes32 caseId,
        bytes32 requestHash,
        bytes32 responseHash
    ) external;

    /// @notice Proposes a typed allocation with a policy-specific quorum proof.
    /// @dev payoutRoot MUST equal the canonical commitment to payouts.
    function proposeDecision(
        bytes32 caseId,
        Decision calldata proposed,
        Payout[] calldata payouts,
        bytes calldata quorumProof
    ) external returns (bytes32 decisionDigest);

    /// @notice Opens the policy-defined appeal path and authorizes any required deposit.
    function appeal(
        bytes32 caseId,
        bytes32 groundsRoot,
        bytes calldata depositAuthorization
    ) external;

    /// @notice Executes the policy-defined timeout transition for the current phase.
    function timeout(bytes32 caseId) external;

    /// @notice Finalizes only after quorum and appeal requirements are satisfied.
    function finalize(bytes32 caseId) external returns (bytes32 decisionDigest);

    function phase(bytes32 caseId) external view returns (Phase);

    function getCase(bytes32 caseId) external view returns (CaseRequest memory);

    function getFinalDecision(bytes32 caseId)
        external
        view
        returns (Decision memory decision, Payout[] memory payouts);

    function isFinal(bytes32 caseId) external view returns (bool);
}
