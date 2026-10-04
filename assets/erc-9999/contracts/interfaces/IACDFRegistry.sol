// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ACDFTypes as T} from "../ACDFTypes.sol";
import {IACDFPolicyRegistry} from "./IACDFPolicyRegistry.sol";

/// @title  IACDFRegistry — Agent Collective Decision Framework issue registry (reference v0.2)
/// @notice The registry is the normative record of issue bindings, procedure state, formal
///         results and finality. It never executes external effects: relying contracts
///         ("consumers") read results and enforce their own committed effects within their
///         own authority. Policies live in a co-deployed IACDFPolicyRegistry.
interface IACDFRegistry {
    // ------------------------------------------------------------------ events
    event StandingAcceptanceRegistered(bytes32 indexed acceptanceId, address indexed consumer, bytes32 indexed policyId);
    event StandingAcceptanceRevoked(bytes32 indexed acceptanceId, address indexed consumer);

    event IssueFiled(bytes32 indexed issueId, bytes32 indexed policyId, T.AcceptanceMode mode, address indexed filer, address consumer);
    event IssueAdmitted(bytes32 indexed issueId, T.EffectClass effectClass, address indexed consumer, uint64 admittedAt, uint64 hardDeadline);
    event IssueAcknowledged(bytes32 indexed issueId, address indexed consumer);
    event IssueWithdrawn(bytes32 indexed issueId, T.Reason reason);

    event BallotCast(bytes32 indexed issueId, uint32 indexed round, uint32 indexed body, address voter, bool approve, bool signed);
    event BodyResultSubmitted(bytes32 indexed issueId, uint32 indexed round, uint32 indexed body, address submitter, T.NodeStatus status);
    event RoundSettled(bytes32 indexed issueId, uint32 indexed round, T.NodeStatus status, T.Reason reason, uint64 at, uint64 appealOpenUntil);
    event Appealed(bytes32 indexed issueId, uint32 indexed newRound, address indexed by);
    event Finalized(bytes32 indexed issueId, T.OutcomeType outcomeType, bool outcomeYes, T.Reason reason, uint32 sourceRound);

    event EnactmentRecorded(bytes32 indexed issueId, address indexed consumer, bytes32 indexed effectId, T.EnactmentStatus status, address reporter, bytes32 ref);
    /// ERC-1497-style evidence pointer, attached to an issue.
    event Evidence(bytes32 indexed issueId, address indexed party, string evidenceURI);

    /// ERC-165: implementers MUST report `type(IACDFRegistry).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function policies() external view returns (IACDFPolicyRegistry);

    // ------------------------------------------------------------------ authorization
    function registerStandingAcceptance(T.StandingAcceptanceInput calldata input) external returns (bytes32 acceptanceId);
    function revokeStandingAcceptance(bytes32 acceptanceId) external;

    // ------------------------------------------------------------------ issues
    function file(T.IssueInput calldata input) external returns (bytes32 issueId);
    function acknowledge(bytes32 issueId, bytes32 effectYes, bytes32 effectNo, bytes32 disposition, uint64 consumerDeadline) external;
    function admitAdvisory(bytes32 issueId) external;
    function expireUnacknowledged(bytes32 issueId) external;
    function withdraw(bytes32 issueId) external;
    function submitEvidence(bytes32 issueId, string calldata evidenceURI) external;

    // ------------------------------------------------------------------ voting
    function castBallot(bytes32 issueId, uint32 body, bool approve) external;
    function submitSignedBallots(bytes32 issueId, uint32 body, address[] calldata voters, bool[] calldata approves, bytes[] calldata signatures) external;
    function submitBodyResult(bytes32 issueId, uint32 body, T.NodeStatus status) external;

    // ------------------------------------------------------------------ rounds & finality
    function settleRound(bytes32 issueId) external;
    function appeal(bytes32 issueId) external;
    function finalize(bytes32 issueId) external;
    function enforceHardDeadline(bytes32 issueId) external;

    // ------------------------------------------------------------------ enactment log (informative)
    function recordEnactment(bytes32 issueId, bytes32 effectId, T.EnactmentStatus status, bytes32 ref) external;

    // ------------------------------------------------------------------ reads
    function getResult(bytes32 issueId) external view returns (T.Result memory);
    function getIssue(bytes32 issueId) external view returns (T.Issue memory);
    function getRound(bytes32 issueId, uint32 round) external view returns (T.RoundState memory);
    function getBodyState(bytes32 issueId, uint32 round, uint32 body) external view returns (T.BodyState memory);
    function bodyStatus(bytes32 issueId, uint32 round, uint32 body) external view returns (T.NodeStatus status, T.Reason reason, uint64 at);
    function nodeStatus(bytes32 issueId, uint32 round, uint32 node) external view returns (T.NodeStatus status, T.Reason reason, uint64 at);
    function hasVoted(bytes32 issueId, uint32 round, uint32 body, address voter) external view returns (bool);
    function activeIssueOf(address consumer, bytes32 obligationKey) external view returns (bytes32);
    function obligationKeyOf(address consumer, T.Subject calldata subject, bytes32 question) external pure returns (bytes32);
    function getEnactment(bytes32 issueId, address consumer, bytes32 effectId) external view returns (T.Enactment memory);
    function ballotDigest(bytes32 issueId, uint32 round, uint32 body, address voter, bool approve) external view returns (bytes32);

    // ERC-6372
    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}
