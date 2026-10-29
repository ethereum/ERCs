// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFDisputeRegistry} from "../interfaces/IADRFDisputeRegistry.sol";
import {IADRFJudgmentMethod} from "../interfaces/IADRFJudgmentMethod.sol";
import {ACDFTypes as A} from "../interfaces/acdf/ACDFTypes.sol";
import {IACDFRegistry} from "../interfaces/acdf/IACDFRegistry.sol";
import {IACDFPolicyRegistry} from "../interfaces/acdf/IACDFPolicyRegistry.sol";

/// @title  ADRFACDFBridge — J-profile v1: a JUDGED sub-question decided by an ERC-8436 collective decision
/// @notice The bridge is the ERC-8436 consumer. For each JUDGED sub-question it files one Binding issue in
///         CONSUMER_FILED mode under the ERC-8436 policy named by the method parameters, with one binary
///         question ("does the proposition hold?") and the fixed effect pair TRUE / FALSE. It imports only a
///         Final result, read from the ERC-8436 registry itself, and pushes it to the dispute registry with
///         its full provenance (registry, issue, policy, source round, round count, adoption flag, reason).
///         Review of a JUDGED sub-question is the ERC-8436 appeal of that issue, open to whoever the ERC-8436
///         policy admits; the bridge imports after the issue is Final, so `review` can never succeed here.
contract ADRFACDFBridge is IADRFJudgmentMethod {
    IADRFDisputeRegistry public immutable adrf;
    IACDFRegistry public immutable acdf;
    IACDFPolicyRegistry public immutable acdfPolicies;

    bytes32 public constant EFFECT_TRUE = keccak256("adrf:finding/TRUE");
    bytes32 public constant EFFECT_FALSE = keccak256("adrf:finding/FALSE");
    bytes32 public constant DISPOSITION_UNDETERMINED = keccak256("adrf:finding/UNDETERMINED");
    bytes32 public constant QUESTION = keccak256("adrf:judgment/v1");

    struct Link { bytes32 caseId; uint32 subQuestion; bool imported; }

    mapping(bytes32 => bytes32) public issueOf;  // keccak256(abi.encode(caseId, subQuestion)) => issueId
    mapping(bytes32 => Link) public linkOf;      // issueId => case link

    event IssueOpened(bytes32 indexed caseId, uint32 indexed subQuestion, bytes32 indexed issueId, bytes32 acdfPolicyId);
    event ResultImported(bytes32 indexed caseId, uint32 indexed subQuestion, bytes32 indexed issueId, T.Value value, uint32 sourceRound, uint32 roundCount, bool adoptedFromEarlierRound);

    error Bridge_NotRegistry(address caller);
    error Bridge_AlreadyOpened(bytes32 caseId, uint32 subQuestion);
    error Bridge_NotOpened(bytes32 caseId, uint32 subQuestion);
    error Bridge_NotFinal(bytes32 issueId);
    error Bridge_AlreadyImported(bytes32 issueId);
    error Bridge_ReviewUnavailable(bytes32 issueId);

    constructor(IADRFDisputeRegistry adrf_, IACDFRegistry acdf_) {
        adrf = adrf_;
        acdf = acdf_;
        acdfPolicies = acdf_.policies();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFJudgmentMethod).interfaceId;
    }

    /// The ERC-8436 policy's hard cap: the dispute policy's decision window must hold it.
    function maxDuration(bytes32 params) external view returns (uint64) {
        if (!acdfPolicies.policyExists(params)) return 0;
        return acdfPolicies.timingOf(params).maxTotalDuration;
    }

    /// Called by the dispute registry when a JUDGED sub-question is opened. The registry has already verified
    /// the upstream authority (binding, standing, effects, clock); the bridge files as the consumer and commits
    /// the fixed effect pair. `deadline` is the sub-question's decision deadline, passed as the consumer deadline
    /// so that the whole ERC-8436 procedure, appeals included, fits before the dispute must be decided.
    function open(bytes32 caseId, uint32 subQuestion, bytes32 proposition, bytes32 params, uint64 deadline)
        external returns (bytes32 handle)
    {
        if (msg.sender != address(adrf)) revert Bridge_NotRegistry(msg.sender);
        bytes32 key = keccak256(abi.encode(caseId, subQuestion));
        if (issueOf[key] != bytes32(0)) revert Bridge_AlreadyOpened(caseId, subQuestion);

        A.IssueInput memory input;
        input.policyId = params;
        input.mode = A.AcceptanceMode.CONSUMER_FILED;
        input.consumer = address(this);
        input.subject = A.Subject({chainId: block.chainid, target: address(adrf), id: uint256(caseId), dataHash: proposition});
        input.question = keccak256(abi.encode(QUESTION, subQuestion));
        input.effectYes = EFFECT_TRUE;
        input.effectNo = EFFECT_FALSE;
        input.disposition = DISPOSITION_UNDETERMINED;
        input.obligationId = key;
        input.consumerDeadline = deadline;

        handle = acdf.file(input);
        issueOf[key] = handle;
        linkOf[handle] = Link({caseId: caseId, subQuestion: subQuestion, imported: false});
        emit IssueOpened(caseId, subQuestion, handle, params);
    }

    /// Review through the bridge is not available: a result is imported only once the ERC-8436 issue is Final,
    /// and a Final issue admits no appeal. Reviews of a JUDGED sub-question happen as ERC-8436 appeals before
    /// import, under the ERC-8436 policy's own standing rule.
    function review(bytes32 caseId, uint32 subQuestion) external view {
        if (msg.sender != address(adrf)) revert Bridge_NotRegistry(msg.sender);
        bytes32 issueId = issueOf[keccak256(abi.encode(caseId, subQuestion))];
        if (issueId == bytes32(0)) revert Bridge_NotOpened(caseId, subQuestion);
        revert Bridge_ReviewUnavailable(issueId);
    }

    /// Anyone may import a Final result. The value is read from the ERC-8436 registry, never from a receipt:
    /// Decided + outcomeYes => TRUE; Decided + !outcomeYes => FALSE (the proposition was blocked under the
    /// rule, not refuted); NoDecision => UNDETERMINED. Provenance is carried whole, including finality by adoption.
    function importResult(bytes32 caseId, uint32 subQuestion) external {
        bytes32 key = keccak256(abi.encode(caseId, subQuestion));
        bytes32 issueId = issueOf[key];
        if (issueId == bytes32(0)) revert Bridge_NotOpened(caseId, subQuestion);
        Link storage link = linkOf[issueId];
        if (link.imported) revert Bridge_AlreadyImported(issueId);
        A.Result memory r = acdf.getResult(issueId);
        if (r.state != A.ProcedureState.Final) revert Bridge_NotFinal(issueId);

        T.Value value = T.Value.UNDETERMINED;
        if (r.outcomeType == A.OutcomeType.Decided) value = r.outcomeYes ? T.Value.TRUE : T.Value.FALSE;
        T.JudgmentSource memory src = T.JudgmentSource({
            registry: address(acdf),
            issueId: issueId,
            policyId: r.policyId,
            sourceRound: r.sourceRound,
            roundCount: r.roundCount,
            adoptedFromEarlierRound: r.adoptedFromEarlierRound,
            reason: uint8(r.reason)
        });
        link.imported = true;
        adrf.recordJudgedFinding(caseId, subQuestion, value, keccak256(abi.encode(r)), src);
        if (r.outcomeType == A.OutcomeType.Decided) {
            acdf.recordEnactment(issueId, r.outcomeYes ? EFFECT_TRUE : EFFECT_FALSE, A.EnactmentStatus.Enacted, caseId);
        }
        emit ResultImported(caseId, subQuestion, issueId, value, r.sourceRound, r.roundCount, r.adoptedFromEarlierRound);
    }
}
