// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFPolicyRegistry} from "./IADRFPolicyRegistry.sol";

/// @title  IADRFDisputeRegistry — AI Dispute Resolution Framework, dispute registry (reference v0.1)
/// @notice The normative record of bindings, cases, findings, round decisions, rulings, enactment
///         reports and leads. It never moves funds and never executes effects: executors named by the
///         binding read the ruling and enact within their own authority, then report.
interface IADRFDisputeRegistry {
    // ------------------------------------------------------------------ events
    event BindingRegistered(bytes32 indexed bindingId, address indexed source, bytes32 indexed policyId, T.AcceptanceMode mode, bytes32 scopeKey);
    event BindingRevoked(bytes32 indexed bindingId, address indexed source);

    event CaseFiled(bytes32 indexed caseId, bytes32 indexed policyId, bytes32 indexed bindingId, address claimant, address respondent, bytes32 proposition);
    event CaseAdmitted(bytes32 indexed caseId, T.EffectClass effectClass, uint64 admittedAt, uint64 decisionDeadline, uint64 hardDeadline);
    event CaseNotAdmitted(bytes32 indexed caseId, T.Reason reason);
    event CaseDowngraded(bytes32 indexed caseId, T.Reason reason);
    event CaseAccepted(bytes32 indexed caseId, address indexed respondent);
    event CaseWithdrawn(bytes32 indexed caseId);
    event CaseAnswered(bytes32 indexed caseId, address indexed respondent);

    event EvidenceSubmitted(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed party, bytes32 commitment, string uri);
    event JudgmentOpened(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed method, bytes32 handle);
    event FindingRecorded(bytes32 indexed caseId, uint32 indexed subQuestion, uint32 round, T.Value value, uint8 supportKinds, T.Reason reason, address acceptedBy);
    event RoundDecided(bytes32 indexed caseId, uint32 indexed round, T.SubstantiveResult result, T.Reason reason, bool bySilence, uint64 reviewOpenUntil);
    event ReviewRequested(bytes32 indexed caseId, uint32 indexed newRound, uint8 reviewType, address indexed by);
    event CaseFinalized(bytes32 indexed caseId, T.ProcedureState state, T.SubstantiveResult result, T.Reason reason, uint32 sourceRound, bool adoptedFromEarlierRound);

    event EnactmentReported(bytes32 indexed caseId, bytes32 indexed effectId, address indexed reporter, T.EnactmentStatus status, bytes32 ref);
    event LeadReported(bytes32 indexed objectKey, address indexed reporter, bytes32 commitment, string uri);

    /// ERC-165: implementers MUST report `type(IADRFDisputeRegistry).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function policies() external view returns (IADRFPolicyRegistry);

    // ------------------------------------------------------------------ bindings
    function bind(T.BindingInput calldata input) external returns (bytes32 bindingId);
    function revokeBinding(bytes32 bindingId) external;

    // ------------------------------------------------------------------ filing and admission
    function file(bytes32 bindingId, T.ClaimInput calldata claim) external returns (bytes32 caseId);
    function fileAdvisory(bytes32 policyId, T.ClaimInput calldata claim, uint64 eventAt, uint64 normDeclaredAt) external returns (bytes32 caseId);
    function accept(bytes32 caseId) external;
    function expireAcceptance(bytes32 caseId) external;
    function withdraw(bytes32 caseId) external;

    // ------------------------------------------------------------------ evidence and resolution
    function submitEvidence(bytes32 caseId, uint32 subQuestion, bytes32 commitment, string calldata uri) external;
    function answer(bytes32 caseId) external;
    function applySilence(bytes32 caseId) external;
    function resolveFormal(bytes32 caseId, uint32 subQuestion, bytes calldata inputs) external;
    function resolveEvidenced(bytes32 caseId, uint32 subQuestion, bytes calldata bundle) external;
    function openJudgment(bytes32 caseId, uint32 subQuestion) external;
    function recordJudgedFinding(bytes32 caseId, uint32 subQuestion, T.Value value, bytes32 resultHash, T.JudgmentSource calldata source) external;

    // ------------------------------------------------------------------ decision, review and finality
    function decide(bytes32 caseId) external;
    function expireDecision(bytes32 caseId) external;
    function requestReview(bytes32 caseId, uint8 reviewType, uint32[] calldata subQuestions) external;
    function finalize(bytes32 caseId) external;
    function enforceDeadline(bytes32 caseId) external;

    // ------------------------------------------------------------------ enactment log and leads
    function reportEnactment(bytes32 caseId, bytes32 effectId, T.EnactmentStatus status, bytes32 ref) external;
    function reportLead(T.ObjectRef calldata object, bytes32 commitment, string calldata uri) external;

    // ------------------------------------------------------------------ reads
    function getBinding(bytes32 bindingId) external view returns (T.Binding memory);
    function isAuthorizedEffect(bytes32 bindingId, bytes32 effectId) external view returns (bool);
    function isExecutor(bytes32 bindingId, address account) external view returns (bool);
    function isBeneficiary(bytes32 bindingId, address account) external view returns (bool);
    function getCase(bytes32 caseId) external view returns (T.CaseHeader memory);
    function getClock(bytes32 caseId) external view returns (T.CaseClock memory);
    function getSubQuestion(bytes32 caseId, uint32 subQuestion) external view returns (T.SubQuestion memory);
    function getFinding(bytes32 caseId, uint32 subQuestion) external view returns (T.Finding memory);
    function getRound(bytes32 caseId, uint32 round) external view returns (T.RoundRecord memory);
    function getRuling(bytes32 caseId) external view returns (T.Ruling memory);
    function getEnactment(bytes32 caseId, bytes32 effectId) external view returns (T.Enactment memory);
    function activeCaseOf(bytes32 exclusivityKey) external view returns (bytes32);
    function finalCaseOf(bytes32 exclusivityKey) external view returns (bytes32);
    /// `proposition` is the decisive sub-question's proposition: the contested point of a Binding case.
    function exclusivityKeyOf(address source, bytes32 obligationRef, bytes32 proposition) external pure returns (bytes32);
    function objectKeyOf(T.ObjectRef calldata object) external pure returns (bytes32);

    // ERC-6372
    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
