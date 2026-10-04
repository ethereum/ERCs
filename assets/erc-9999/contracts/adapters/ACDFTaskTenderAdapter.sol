// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ACDFTypes as T} from "../ACDFTypes.sol";
import {IACDFRegistry} from "../interfaces/IACDFRegistry.sol";
import {IACDFPolicyRegistry} from "../interfaces/IACDFPolicyRegistry.sol";
import {ITaskTender8414} from "../interfaces/ITaskTender8414.sol";

/// @title  ACDFTaskTenderAdapter — ERC-8414 acceptance authority backed by an ACDF policy
/// @notice Set this contract as a task's `acceptanceAuthority`. For a Pending submission anyone
///         may `open` a case: the adapter files a CONSUMER_FILED issue bound to the exact
///         submission (tokenId, submissionId, resultHash, cited taskVersion) and to a deadline
///         that leaves room for BOTH 8414 clocks — the judgment window (which bounds
///         `rejectFulfillment`) and `settleBy` (which bounds `acceptFulfillment`) — minus an
///         execution margin. Once the issue is Final with a decision, anyone may `execute`:
///         the adapter calls the real `acceptFulfillment` / `rejectFulfillment`, records the
///         enactment, and on failure records Failed without touching the decision. A Final
///         NoDecision triggers nothing here: ERC-8414's own `claimUnjudged` clock governs.
///
///         The adapter does not assume any judgment fee from the task vault (the upstream
///         kernel has none); juror compensation is a separate arrangement.
contract ACDFTaskTenderAdapter {
    IACDFRegistry   public immutable registry;
    ITaskTender8414 public immutable task;
    bytes32         public immutable policyId;
    /// Seconds reserved between the procedure's hard cap and the earliest 8414 deadline so
    /// that the execution transaction can still land. Arrival, not formation, is what counts.
    uint64          public immutable margin;

    bytes32 public constant QUESTION       = keccak256("acdf.erc8414.acceptance.v1");
    bytes32 public constant EFFECT_ACCEPT  = keccak256("erc8414.acceptFulfillment");
    bytes32 public constant EFFECT_REJECT  = keccak256("erc8414.rejectFulfillment");
    bytes32 public constant DISPOSITION    = keccak256("erc8414.noDecision.deferToJudgmentClock");

    struct Case {
        bool    exists;
        bool    enacted;
        uint256 tokenId;
        uint256 submissionId;
        bytes32 resultHash;
        uint64  taskVersion;
        uint64  consumerDeadline;
    }

    mapping(bytes32 => Case) public caseOf;      // issueId => case
    mapping(bytes32 => bytes32) public issueOf;  // caseKey => latest issueId

    event CaseOpened(bytes32 indexed issueId, uint256 indexed tokenId, uint256 indexed submissionId,
                     bytes32 resultHash, uint64 taskVersion, uint64 consumerDeadline);
    event CaseEnacted(bytes32 indexed issueId, bytes32 indexed effectId);
    event CaseEnactmentFailed(bytes32 indexed issueId, bytes32 indexed effectId, bytes reason);

    constructor(IACDFRegistry registry_, ITaskTender8414 task_, bytes32 policyId_, uint64 margin_) {
        require(address(registry_) != address(0) && address(task_) != address(0), "ACDF8414: zero address");
        require(registry_.policies().policyExists(policyId_), "ACDF8414: unknown policy");
        registry = registry_;
        task = task_;
        policyId = policyId_;
        margin = margin_;
    }

    /// ERC-165: this is a JUDGED authority. It deliberately does not declare ITaskVerifier,
    /// so the task contract routes its submissions through accept/reject, never machine settlement.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7;
    }

    function caseKey(uint256 tokenId, uint256 submissionId, bytes32 resultHash, uint64 taskVersion)
        public pure returns (bytes32)
    {
        return keccak256(abi.encode(tokenId, submissionId, resultHash, taskVersion));
    }

    /// Opens the ACDF issue for a Pending, judged-path submission. Permissionless: the
    /// adapter, not the caller, is the consumer, and every parameter comes from the task.
    function open(uint256 tokenId, uint256 submissionId) external returns (bytes32 issueId) {
        require(task.acceptanceAuthorityOf(tokenId) == address(this), "ACDF8414: not the acceptance authority");
        ITaskTender8414.Submission memory s = task.submissionOf(tokenId, submissionId);
        require(s.status == ITaskTender8414.SubmissionStatus.Pending, "ACDF8414: not pending");
        require(!s.machineSettled, "ACDF8414: machine-path submission");

        ITaskTender8414.TenderTerms memory t = task.tenderTermsOf(tokenId);
        uint256 earliest = uint256(s.submittedAt) + t.judgmentWindow;   // bounds rejectFulfillment
        if (t.settleBy != 0 && t.settleBy < earliest) earliest = t.settleBy; // bounds acceptFulfillment
        require(earliest > block.timestamp + margin, "ACDF8414: no execution window");
        uint64 consumerDeadline = uint64(earliest - margin);

        bytes32 key = caseKey(tokenId, submissionId, s.resultHash, s.taskVersion);
        bytes32 prev = issueOf[key];
        if (prev != bytes32(0)) {
            // one live binding per obligation; a decided case is never re-litigated by re-filing
            T.Result memory pr = registry.getResult(prev);
            require(pr.state == T.ProcedureState.Final && pr.outcomeType == T.OutcomeType.NoDecision,
                    "ACDF8414: case open or decided");
        }

        T.IssueInput memory input;
        input.policyId = policyId;
        input.mode = T.AcceptanceMode.CONSUMER_FILED;
        input.consumer = address(this);
        input.subject = T.Subject({
            chainId: block.chainid,
            target: address(task),
            id: tokenId,
            dataHash: keccak256(abi.encode(submissionId, s.resultHash, s.taskVersion))
        });
        input.question = QUESTION;
        input.effectYes = EFFECT_ACCEPT;
        input.effectNo = EFFECT_REJECT;
        input.disposition = DISPOSITION;
        input.consumerDeadline = consumerDeadline; // registry: admittedAt + maxTotalDuration <= deadline
        issueId = registry.file(input);

        caseOf[issueId] = Case({
            exists: true, enacted: false, tokenId: tokenId, submissionId: submissionId,
            resultHash: s.resultHash, taskVersion: s.taskVersion, consumerDeadline: consumerDeadline
        });
        issueOf[key] = issueId;
        emit CaseOpened(issueId, tokenId, submissionId, s.resultHash, s.taskVersion, consumerDeadline);
    }

    /// Executes a Final decision through the real ERC-8414 interface. Permissionless, but the
    /// caller chooses nothing: the bound task, token, submission and the effect implied by the
    /// recorded outcome are the only things this function can do.
    function execute(bytes32 issueId) external {
        Case storage c = caseOf[issueId];
        require(c.exists, "ACDF8414: unknown issue");
        require(!c.enacted, "ACDF8414: already enacted");
        T.Result memory r = registry.getResult(issueId);
        require(r.state == T.ProcedureState.Final, "ACDF8414: not final");
        require(r.outcomeType == T.OutcomeType.Decided, "ACDF8414: no decision; judgment clock governs");

        // the submission executed must be the submission judged
        ITaskTender8414.Submission memory s = task.submissionOf(c.tokenId, c.submissionId);
        require(s.resultHash == c.resultHash && s.taskVersion == c.taskVersion, "ACDF8414: submission mismatch");

        bytes32 effect = r.outcomeYes ? EFFECT_ACCEPT : EFFECT_REJECT;
        bool ok;
        bytes memory err;
        if (r.outcomeYes) {
            try task.acceptFulfillment(c.tokenId, c.submissionId) { ok = true; } catch (bytes memory e) { err = e; }
        } else {
            try task.rejectFulfillment(c.tokenId, c.submissionId) { ok = true; } catch (bytes memory e) { err = e; }
        }
        if (ok) {
            c.enacted = true;
            registry.recordEnactment(issueId, effect, T.EnactmentStatus.Enacted, bytes32(uint256(uint160(msg.sender))));
            emit CaseEnacted(issueId, effect);
        } else {
            // the decision stands; the effect simply did not land this time
            registry.recordEnactment(issueId, effect, T.EnactmentStatus.Failed, keccak256(err));
            emit CaseEnactmentFailed(issueId, effect, err);
        }
    }
}
