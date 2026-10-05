// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ACDFTypes as T} from "./ACDFTypes.sol";
import {IACDFRegistry} from "./interfaces/IACDFRegistry.sol";
import {IACDFPolicyRegistry} from "./interfaces/IACDFPolicyRegistry.sol";
import {SignatureChecker} from "./libraries/SignatureChecker.sol";

/// @title  ACDFRegistry — Agent Collective Decision Framework, issue registry (reference kernel v0.2)
/// @notice Non-upgradeable. An issue binds a subject + question + immutable policy version +
///         at most one consumer. Bodies vote inside rounds; the result of a round is the
///         composition of body decisions; finality is procedural.
///
///         Three dimensions are kept apart: procedure state (Filed / Deciding / Provisional /
///         Final / Withdrawn), outcome type (None / Decided / NoDecision) and enactment status
///         (per consumer and effect; authoritative at the consumer, logged here for information).
///
///         The kernel never calls external contracts except its co-deployed policy registry
///         (reads) and ERC-1271 signature checks.
contract ACDFRegistry is IACDFRegistry {
    using SignatureChecker for address;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant BALLOT_TYPEHASH =
        keccak256("Ballot(bytes32 issueId,uint32 round,uint32 body,address voter,bool approve)");

    IACDFPolicyRegistry public immutable override policies;

    struct Acceptance {
        bool      exists;
        bool      revoked;
        address   consumer;
        bytes32   policyId;
        address   subjectTarget;
        bytes32   question;
        address[] filers;
        bytes32   effectYes;
        bytes32   effectNo;
        bytes32   disposition;
        uint64    validUntil;
    }

    mapping(bytes32 => Acceptance) private _acceptances;
    uint256 private _acceptanceNonce;

    mapping(bytes32 => T.Issue) private _issues;
    uint256 private _issueNonce;
    mapping(bytes32 => T.RoundState[]) private _rounds;
    mapping(bytes32 => mapping(uint32 => mapping(uint32 => T.BodyState))) private _bodies;
    mapping(bytes32 => mapping(uint32 => mapping(uint32 => mapping(address => bool)))) private _voted;
    mapping(address => mapping(bytes32 => bytes32)) private _activeIssue;
    mapping(bytes32 => mapping(address => mapping(bytes32 => T.Enactment))) private _enactments;

    constructor(IACDFPolicyRegistry policies_) {
        require(address(policies_) != address(0), "ACDF: zero policy registry");
        policies = policies_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IACDFRegistry).interfaceId;
    }

    // ================================================================== authorization

    function registerStandingAcceptance(T.StandingAcceptanceInput calldata input)
        external returns (bytes32 acceptanceId)
    {
        require(policies.policyExists(input.policyId), "ACDF: unknown policy");
        require(input.effectYes != bytes32(0) && input.effectNo != bytes32(0), "ACDF: effects required");
        acceptanceId = keccak256(abi.encode(block.chainid, address(this), "acceptance", ++_acceptanceNonce));
        Acceptance storage a = _acceptances[acceptanceId];
        a.exists = true;
        a.consumer = msg.sender;
        a.policyId = input.policyId;
        a.subjectTarget = input.subjectTarget;
        a.question = input.question;
        for (uint256 i = 0; i < input.filers.length; i++) a.filers.push(input.filers[i]);
        a.effectYes = input.effectYes;
        a.effectNo = input.effectNo;
        a.disposition = input.disposition;
        a.validUntil = input.validUntil;
        emit StandingAcceptanceRegistered(acceptanceId, msg.sender, input.policyId);
    }

    /// Revocation stops NEW filings only; issues already admitted under the acceptance
    /// complete under their committed rules.
    function revokeStandingAcceptance(bytes32 acceptanceId) external {
        Acceptance storage a = _acceptances[acceptanceId];
        require(a.exists && msg.sender == a.consumer, "ACDF: not acceptance owner");
        a.revoked = true;
        emit StandingAcceptanceRevoked(acceptanceId, msg.sender);
    }

    // ================================================================== issues

    function file(T.IssueInput calldata input) external returns (bytes32 issueId) {
        require(policies.policyExists(input.policyId), "ACDF: unknown policy");
        issueId = keccak256(abi.encode(block.chainid, address(this), ++_issueNonce));
        T.Issue storage it = _issues[issueId];
        it.policyId = input.policyId;
        it.mode = input.mode;
        it.filer = msg.sender;
        it.subject = input.subject;
        it.question = input.question;
        it.filedAt = uint64(block.timestamp);
        it.state = T.ProcedureState.Filed;

        if (input.mode == T.AcceptanceMode.CONSUMER_FILED) {
            require(input.consumer == msg.sender, "ACDF: consumer must file");
            require(input.effectYes != bytes32(0) && input.effectNo != bytes32(0), "ACDF: effects required");
            it.consumer = msg.sender;
            it.effectYes = input.effectYes;
            it.effectNo = input.effectNo;
            it.disposition = input.disposition;
            emit IssueFiled(issueId, input.policyId, input.mode, msg.sender, msg.sender);
            _admit(issueId, T.EffectClass.Binding, input.consumerDeadline);
        } else if (input.mode == T.AcceptanceMode.STANDING_ACCEPTANCE) {
            Acceptance storage a = _acceptances[input.acceptanceId];
            require(a.exists && !a.revoked, "ACDF: acceptance unavailable");
            require(a.validUntil == 0 || block.timestamp <= a.validUntil, "ACDF: acceptance expired");
            require(a.policyId == input.policyId, "ACDF: policy not accepted");
            require(a.subjectTarget == address(0) || a.subjectTarget == input.subject.target, "ACDF: subject not accepted");
            require(a.question == bytes32(0) || a.question == input.question, "ACDF: question not accepted");
            if (a.filers.length > 0) {
                bool ok;
                for (uint256 i = 0; i < a.filers.length; i++) if (a.filers[i] == msg.sender) { ok = true; break; }
                require(ok, "ACDF: filer not accepted");
            }
            it.consumer = a.consumer;
            it.acceptanceId = input.acceptanceId;
            // parameters the consumer committed to; the filer cannot vary them
            it.effectYes = a.effectYes;
            it.effectNo = a.effectNo;
            it.disposition = a.disposition;
            emit IssueFiled(issueId, input.policyId, input.mode, msg.sender, a.consumer);
            _admit(issueId, T.EffectClass.Binding, 0);
        } else {
            // POST_ACK: stays Filed until the named consumer acknowledges — before any vote.
            require(policies.timingOf(input.policyId).ackWindow > 0, "ACDF: POST_ACK disabled");
            require(input.consumer != address(0), "ACDF: consumer required");
            it.consumer = input.consumer;
            it.effectYes = input.effectYes;   // proposal only; frozen at acknowledgment
            it.effectNo = input.effectNo;
            it.disposition = input.disposition;
            emit IssueFiled(issueId, input.policyId, input.mode, msg.sender, input.consumer);
        }
    }

    function acknowledge(bytes32 issueId, bytes32 effectYes, bytes32 effectNo, bytes32 disposition, uint64 consumerDeadline)
        external
    {
        T.Issue storage it = _issues[issueId];
        require(it.mode == T.AcceptanceMode.POST_ACK, "ACDF: not POST_ACK");
        require(it.state == T.ProcedureState.Filed, "ACDF: not awaiting acknowledgment");
        require(msg.sender == it.consumer, "ACDF: not the named consumer");
        require(block.timestamp <= uint256(it.filedAt) + policies.timingOf(it.policyId).ackWindow, "ACDF: ack window closed");
        require(effectYes != bytes32(0) && effectNo != bytes32(0), "ACDF: effects required");
        it.effectYes = effectYes;
        it.effectNo = effectNo;
        it.disposition = disposition;
        emit IssueAcknowledged(issueId, msg.sender);
        _admit(issueId, T.EffectClass.Binding, consumerDeadline);
    }

    function admitAdvisory(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.mode == T.AcceptanceMode.POST_ACK, "ACDF: not POST_ACK");
        require(it.state == T.ProcedureState.Filed, "ACDF: not awaiting acknowledgment");
        IACDFPolicyRegistry.Timing memory tm = policies.timingOf(it.policyId);
        require(block.timestamp > uint256(it.filedAt) + tm.ackWindow, "ACDF: ack window open");
        require(tm.allowAdvisory, "ACDF: advisory not allowed");
        it.consumer = address(0);
        it.effectYes = bytes32(0);
        it.effectNo = bytes32(0);
        it.disposition = bytes32(0);
        _admit(issueId, T.EffectClass.Advisory, 0);
    }

    function expireUnacknowledged(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.mode == T.AcceptanceMode.POST_ACK, "ACDF: not POST_ACK");
        require(it.state == T.ProcedureState.Filed, "ACDF: not awaiting acknowledgment");
        IACDFPolicyRegistry.Timing memory tm = policies.timingOf(it.policyId);
        require(block.timestamp > uint256(it.filedAt) + tm.ackWindow, "ACDF: ack window open");
        require(!tm.allowAdvisory, "ACDF: must admit as advisory");
        it.state = T.ProcedureState.Withdrawn;
        emit IssueWithdrawn(issueId, T.Reason.NO_ACCEPTANCE);
    }

    /// Unilateral withdrawal is possible only while Filed. Once admitted the roster,
    /// snapshot and windows are known; letting the filer restart would let it shop panels.
    function withdraw(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Filed, "ACDF: not withdrawable");
        require(msg.sender == it.filer, "ACDF: not filer");
        it.state = T.ProcedureState.Withdrawn;
        emit IssueWithdrawn(issueId, T.Reason.NONE);
    }

    function submitEvidence(bytes32 issueId, string calldata evidenceURI) external {
        T.ProcedureState s = _issues[issueId].state;
        require(s == T.ProcedureState.Filed || s == T.ProcedureState.Deciding || s == T.ProcedureState.Provisional,
                "ACDF: evidence closed");
        emit Evidence(issueId, msg.sender, evidenceURI);
    }

    function _admit(bytes32 issueId, T.EffectClass effectClass, uint64 consumerDeadline) private {
        T.Issue storage it = _issues[issueId];
        IACDFPolicyRegistry.Timing memory tm = policies.timingOf(it.policyId);
        uint64 nowTs = uint64(block.timestamp);
        uint64 hard = nowTs + tm.maxTotalDuration;
        if (consumerDeadline != 0) {
            // the whole procedure, including every appeal, must fit the consumer's remaining window
            require(hard <= consumerDeadline, "ACDF: insufficient window");
        }
        it.effectClass = effectClass;
        it.admittedAt = nowTs;
        it.consumerDeadline = consumerDeadline;
        it.hardDeadline = hard;
        if (effectClass == T.EffectClass.Binding) {
            bytes32 key = _obligationKey(it.consumer, it.subject, it.question);
            bytes32 existing = _activeIssue[it.consumer][key];
            if (existing != bytes32(0)) {
                T.ProcedureState es = _issues[existing].state;
                require(es == T.ProcedureState.Final || es == T.ProcedureState.Withdrawn, "ACDF: obligation active");
            }
            _activeIssue[it.consumer][key] = issueId;
            it.obligationKey = key;
        }
        it.state = T.ProcedureState.Deciding;
        _startRound(issueId, tm.roundDuration);
        emit IssueAdmitted(issueId, effectClass, it.consumer, nowTs, hard);
    }

    function _startRound(bytes32 issueId, uint64 roundDuration) private {
        T.Issue storage it = _issues[issueId];
        uint64 nowTs = uint64(block.timestamp);
        T.RoundState memory r;
        r.startedAt = nowTs;
        r.deadline = nowTs + roundDuration;
        _rounds[issueId].push(r);
        it.roundCount += 1;
    }

    // ================================================================== voting

    /// `round` binds the ballot to the round the voter intends, exactly as a signed ballot is
    /// bound by its digest: a transaction that lands after the round it was meant for has been
    /// settled and an appeal has opened the next one is refused, not counted in the new round.
    function castBallot(bytes32 issueId, uint32 round, uint32 body, bool approve) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Deciding, "ACDF: not deciding");
        require(round == it.roundCount, "ACDF: round mismatch");
        T.BodySpec memory b = policies.bodyOf(it.policyId, body);
        require(b.kind == T.BodyKind.ROSTER_KOFN && b.acceptance == T.Acceptance.ON_CHAIN_TALLY,
                "ACDF: body not on-chain tally");
        _castBallot(issueId, body, b, msg.sender, approve, false);
    }

    /// Batch acceptance of EIP-712 ballots. Shares the tally semantics of castBallot; the only
    /// difference is how the voter's intent reaches the registry. Acceptance time is the
    /// submission block. A signature is bound to (chainId, registry, issue, round, body, voter,
    /// approve) and carries no nonce: the voter's identity is the only key, so a second
    /// signature can never buy a second vote, and a round-1 signature is invalid in round 2.
    function submitSignedBallots(bytes32 issueId, uint32 body, address[] calldata voters,
                                 bool[] calldata approves, bytes[] calldata signatures) external
    {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Deciding, "ACDF: not deciding");
        T.BodySpec memory b = policies.bodyOf(it.policyId, body);
        require(b.kind == T.BodyKind.ROSTER_KOFN && b.acceptance == T.Acceptance.SIGNED_BALLOTS,
                "ACDF: body not signed ballots");
        uint256 n = voters.length;
        require(n >= 1 && approves.length == n && signatures.length == n, "ACDF: batch shape");
        for (uint256 i = 0; i < n; i++) {
            _acceptSigned(issueId, body, b, voters[i], approves[i], signatures[i]);
        }
    }

    function _acceptSigned(bytes32 issueId, uint32 body, T.BodySpec memory b, address voter, bool approve,
                           bytes calldata sig) private
    {
        bytes32 digest = _ballotDigest(issueId, _issues[issueId].roundCount, body, voter, approve);
        require(voter.isValid(digest, sig), "ACDF: bad signature");
        _castBallot(issueId, body, b, voter, approve, true);
    }

    function _castBallot(bytes32 issueId, uint32 body, T.BodySpec memory b, address voter, bool approve, bool signed)
        private
    {
        uint32 round = _issues[issueId].roundCount;
        T.RoundState storage r = _rounds[issueId][round - 1];
        require(block.timestamp <= uint256(r.startedAt) + b.window, "ACDF: body window closed");
        bool member;
        uint256 n = b.members.length;
        for (uint256 i = 0; i < n; i++) if (b.members[i] == voter) { member = true; break; }
        require(member, "ACDF: not a member");
        require(!_voted[issueId][round][body][voter], "ACDF: already voted");
        T.BodyState storage bs = _bodies[issueId][round][body];
        require(bs.decidedAt == 0, "ACDF: body decided");
        _voted[issueId][round][body][voter] = true;
        if (approve) {
            bs.yes += 1;
            if (bs.yes >= b.k) bs.decidedAt = uint64(block.timestamp);
        } else {
            bs.no += 1;
            if (uint256(bs.no) >= n - b.k + 1) bs.decidedAt = uint64(block.timestamp);
        }
        emit BallotCast(issueId, round, body, voter, approve, signed);
    }

    /// Same round binding as castBallot: a submitter's report names the round it answers.
    function submitBodyResult(bytes32 issueId, uint32 round, uint32 body, T.NodeStatus status) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Deciding, "ACDF: not deciding");
        require(round == it.roundCount, "ACDF: round mismatch");
        T.BodySpec memory b = policies.bodyOf(it.policyId, body);
        require(b.kind == T.BodyKind.AUTHORIZED_SUBMITTER, "ACDF: body not submitter");
        require(msg.sender == b.members[0], "ACDF: not the submitter");
        require(status != T.NodeStatus.Pending, "ACDF: status required");
        T.RoundState storage r = _rounds[issueId][round - 1];
        require(block.timestamp <= uint256(r.startedAt) + b.window, "ACDF: body window closed");
        T.BodyState storage bs = _bodies[issueId][round][body];
        require(!bs.submitted, "ACDF: already submitted");
        bs.submitted = true;
        bs.submitted_ = status;
        bs.decidedAt = uint64(block.timestamp);
        emit BodyResultSubmitted(issueId, round, body, msg.sender, status);
    }

    // ================================================================== evaluation (pure functions of ballots + time)

    function bodyStatus(bytes32 issueId, uint32 round, uint32 body)
        public view returns (T.NodeStatus status, T.Reason reason, uint64 at)
    {
        require(round >= 1 && round <= _issues[issueId].roundCount, "ACDF: round index");
        return _bodyStatus(issueId, round, body);
    }

    function _bodyStatus(bytes32 issueId, uint32 round, uint32 body)
        private view returns (T.NodeStatus status, T.Reason reason, uint64 at)
    {
        T.BodySpec memory b = policies.bodyOf(_issues[issueId].policyId, body);
        uint64 closeAt = _rounds[issueId][round - 1].startedAt + b.window;
        T.BodyState storage bs = _bodies[issueId][round][body];
        if (b.kind == T.BodyKind.ROSTER_KOFN) {
            if (bs.yes >= b.k) return (T.NodeStatus.Yes, T.Reason.NONE, bs.decidedAt);
            if (uint256(bs.no) >= b.members.length - b.k + 1) return (T.NodeStatus.No, T.Reason.NONE, bs.decidedAt);
            if (block.timestamp > closeAt) return (T.NodeStatus.NoDecision, T.Reason.QUORUM_NOT_MET, closeAt);
            return (T.NodeStatus.Pending, T.Reason.NONE, 0);
        } else {
            if (bs.submitted) return (bs.submitted_, T.Reason.NONE, bs.decidedAt);
            if (block.timestamp > closeAt) return (T.NodeStatus.NoDecision, T.Reason.SUBMITTER_SILENT, closeAt);
            return (T.NodeStatus.Pending, T.Reason.NONE, 0);
        }
    }

    function nodeStatus(bytes32 issueId, uint32 round, uint32 node)
        public view returns (T.NodeStatus status, T.Reason reason, uint64 at)
    {
        require(round >= 1 && round <= _issues[issueId].roundCount, "ACDF: round index");
        return _nodeStatus(issueId, round, node);
    }

    struct Tally {
        uint256 yes;
        uint256 no;
        uint256 pending;
        uint64 maxAt;
        uint64[] yesAt;
        uint64[] noAt;
    }

    function _nodeStatus(bytes32 issueId, uint32 round, uint32 node)
        private view returns (T.NodeStatus status, T.Reason reason, uint64 at)
    {
        T.Node memory nd = policies.nodeOf(_issues[issueId].policyId, node);
        if (nd.op == T.Combinator.BODY) return _bodyStatus(issueId, round, nd.body);
        if (nd.op == T.Combinator.VETO) return _vetoStatus(issueId, round, nd);

        Tally memory t = _gather(issueId, round, nd.children);
        uint256 m = nd.children.length;
        uint256 k = nd.op == T.Combinator.ALL ? m : (nd.op == T.Combinator.ANY ? 1 : nd.k);
        // yes is determined the moment the k-th approval arrives; no the moment the
        // (m-k+1)-th rejection arrives. Both instants are stable under later evaluation,
        // because a child that is still pending now can only resolve at a later instant.
        if (t.yes >= k) return (T.NodeStatus.Yes, T.Reason.NONE, _kthSmallest(t.yesAt, t.yes, k));
        if (t.no >= m - k + 1) return (T.NodeStatus.No, T.Reason.NONE, _kthSmallest(t.noAt, t.no, m - k + 1));
        if (t.pending > 0) return (T.NodeStatus.Pending, T.Reason.NONE, 0);
        return (T.NodeStatus.NoDecision, T.Reason.NOT_REACHED, t.maxAt);
    }

    function _gather(bytes32 issueId, uint32 round, uint32[] memory children) private view returns (Tally memory t) {
        uint256 m = children.length;
        t.yesAt = new uint64[](m);
        t.noAt = new uint64[](m);
        for (uint256 i = 0; i < m; i++) {
            (T.NodeStatus cs, , uint64 cat) = _nodeStatus(issueId, round, children[i]);
            if (cs == T.NodeStatus.Yes) { t.yesAt[t.yes++] = cat; }
            else if (cs == T.NodeStatus.No) { t.noAt[t.no++] = cat; }
            else if (cs == T.NodeStatus.Pending) { t.pending++; }
            if (cat > t.maxAt) t.maxAt = cat;
        }
    }

    /// VETO semantics. In the veto body an "approve" ballot means VETO and an explicit block
    /// decision means CLEARANCE. Nothing passes through while the veto window is open and the
    /// veto body is silent, whatever the guarded node says: a live veto right is never
    /// extinguished by an early settlement, so the final type cannot depend on call order.
    function _vetoStatus(bytes32 issueId, uint32 round, T.Node memory nd)
        private view returns (T.NodeStatus status, T.Reason reason, uint64 at)
    {
        (T.NodeStatus vs, , uint64 vat) = _bodyStatus(issueId, round, nd.vetoBody);
        if (vs == T.NodeStatus.Yes) return (T.NodeStatus.No, T.Reason.VETOED, vat);
        if (vs == T.NodeStatus.Pending) return (T.NodeStatus.Pending, T.Reason.NONE, 0);
        if (vs == T.NodeStatus.NoDecision && nd.silence == T.VetoSilence.REQUIRE_CLEARANCE) {
            return (T.NodeStatus.NoDecision, T.Reason.NO_CLEARANCE, vat);
        }
        // explicit clearance (No) in either mode, or silence under PASS_THROUGH
        (T.NodeStatus ts, T.Reason tr, uint64 tat) = _nodeStatus(issueId, round, nd.target);
        if (ts == T.NodeStatus.Pending) return (T.NodeStatus.Pending, T.Reason.NONE, 0);
        return (ts, tr, tat > vat ? tat : vat);
    }

    function _kthSmallest(uint64[] memory arr, uint256 len, uint256 k) private pure returns (uint64) {
        for (uint256 i = 1; i < len; i++) {
            uint64 v = arr[i]; uint256 j = i;
            while (j > 0 && arr[j - 1] > v) { arr[j] = arr[j - 1]; j--; }
            arr[j] = v;
        }
        return arr[k - 1];
    }

    // ================================================================== rounds & finality

    function settleRound(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Deciding, "ACDF: not deciding");
        (T.NodeStatus st, T.Reason rs, uint64 at) = _nodeStatus(issueId, it.roundCount, 0);
        require(st != T.NodeStatus.Pending, "ACDF: pending");
        _settle(issueId, st, rs, at);
    }

    function _settle(bytes32 issueId, T.NodeStatus st, T.Reason rs, uint64 at) private {
        T.Issue storage it = _issues[issueId];
        IACDFPolicyRegistry.Timing memory tm = policies.timingOf(it.policyId);
        T.RoundState storage r = _rounds[issueId][it.roundCount - 1];
        r.settled = true;
        r.status = st;
        r.reason = rs;
        r.at = at;

        uint8 bit = st == T.NodeStatus.NoDecision ? 2 : 1;
        bool canAppeal = (it.roundCount - 1) < tm.maxAppeals && (tm.appealable & bit) != 0;
        uint64 openUntil;
        if (canAppeal) {
            openUntil = at + tm.appealWindow;
            if (openUntil > it.hardDeadline) openUntil = it.hardDeadline;
            r.appealOpenUntil = openUntil;
        }
        emit RoundSettled(issueId, it.roundCount, st, rs, at, openUntil);
        // The appeal window runs from the instant the result was determined, not from the
        // settlement call: a late settlement cannot stretch the procedure.
        if (canAppeal && block.timestamp <= openUntil) {
            it.state = T.ProcedureState.Provisional;
        } else {
            _finalize(issueId);
        }
    }

    function appeal(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Provisional, "ACDF: not provisional");
        IACDFPolicyRegistry.Timing memory tm = policies.timingOf(it.policyId);
        T.RoundState storage r = _rounds[issueId][it.roundCount - 1];
        require(block.timestamp <= r.appealOpenUntil, "ACDF: appeal window closed");
        if (tm.appealStanding == T.AppealStanding.CONSUMER_OR_FILER) {
            require(msg.sender == it.consumer || msg.sender == it.filer, "ACDF: no standing");
        }
        it.state = T.ProcedureState.Deciding;
        _startRound(issueId, tm.roundDuration);
        emit Appealed(issueId, it.roundCount, msg.sender);
    }

    function finalize(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Provisional, "ACDF: not provisional");
        T.RoundState storage r = _rounds[issueId][it.roundCount - 1];
        require(block.timestamp > r.appealOpenUntil, "ACDF: appeal window open");
        _finalize(issueId);
    }

    /// Hard cap: anyone may close an issue still open past admittedAt + maxTotalDuration.
    function enforceHardDeadline(bytes32 issueId) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Deciding || it.state == T.ProcedureState.Provisional,
                "ACDF: not open");
        require(block.timestamp > it.hardDeadline, "ACDF: before hard deadline");
        if (it.state == T.ProcedureState.Deciding) {
            (T.NodeStatus st, T.Reason rs, uint64 at) = _nodeStatus(issueId, it.roundCount, 0);
            if (st == T.NodeStatus.Pending) { st = T.NodeStatus.NoDecision; rs = T.Reason.TOTAL_TIMEOUT; at = it.hardDeadline; }
            T.RoundState storage r = _rounds[issueId][it.roundCount - 1];
            r.settled = true; r.status = st; r.reason = rs; r.at = at;
            emit RoundSettled(issueId, it.roundCount, st, rs, at, 0);
        }
        _finalize(issueId);
    }

    /// Adopts the most recent round that produced a substantive decision. A later round that
    /// ended in NoDecision is recorded but does not erase an earlier decision. Final is
    /// terminal: no later round of the same issue can replace it.
    function _finalize(bytes32 issueId) private {
        T.Issue storage it = _issues[issueId];
        T.RoundState[] storage rounds = _rounds[issueId];
        uint256 n = rounds.length;
        bool found;
        for (uint256 i = n; i > 0 && !found; i--) {
            T.RoundState storage r = rounds[i - 1];
            if (r.settled && (r.status == T.NodeStatus.Yes || r.status == T.NodeStatus.No)) {
                it.outcomeType = T.OutcomeType.Decided;
                it.outcomeYes = r.status == T.NodeStatus.Yes;
                it.reason = r.reason;
                it.sourceRound = uint32(i);
                it.decidedAt = r.at;
                found = true;
            }
        }
        if (!found) {
            T.RoundState storage last = rounds[n - 1];
            it.outcomeType = T.OutcomeType.NoDecision;
            it.outcomeYes = false;
            it.reason = last.reason;
            it.sourceRound = uint32(n);
            it.decidedAt = last.at;
        }
        it.state = T.ProcedureState.Final;
        it.finalAt = uint64(block.timestamp);
        emit Finalized(issueId, it.outcomeType, it.outcomeYes, it.reason, it.sourceRound);
    }

    // ================================================================== enactment log

    /// Informative log. Only the bound consumer may report, only for the issue's own effects,
    /// only once Final. A Failed report never overwrites an Enacted record.
    function recordEnactment(bytes32 issueId, bytes32 effectId, T.EnactmentStatus status, bytes32 ref) external {
        T.Issue storage it = _issues[issueId];
        require(it.state == T.ProcedureState.Final, "ACDF: not final");
        require(it.effectClass == T.EffectClass.Binding && msg.sender == it.consumer, "ACDF: not the consumer");
        require(effectId == it.effectYes || effectId == it.effectNo, "ACDF: unknown effect");
        require(status != T.EnactmentStatus.NotEnacted, "ACDF: status required");
        T.Enactment storage e = _enactments[issueId][msg.sender][effectId];
        require(e.status != T.EnactmentStatus.Enacted, "ACDF: already enacted");
        e.status = status;
        e.reporter = msg.sender;
        e.ref = ref;
        e.at = uint64(block.timestamp);
        emit EnactmentRecorded(issueId, msg.sender, effectId, status, msg.sender, ref);
    }

    // ================================================================== reads

    function getResult(bytes32 issueId) external view returns (T.Result memory res) {
        T.Issue storage it = _issues[issueId];
        res.state = it.state;
        res.outcomeType = it.outcomeType;
        res.outcomeYes = it.outcomeYes;
        res.reason = it.reason;
        res.decidedAt = it.decidedAt;
        res.finalAt = it.finalAt;
        res.policyId = it.policyId;
        res.roundCount = it.roundCount;
        res.sourceRound = it.sourceRound;
        res.effectClass = it.effectClass;
        res.consumer = it.consumer;
        res.effectYes = it.effectYes;
        res.effectNo = it.effectNo;
        res.disposition = it.disposition;
    }

    function getIssue(bytes32 issueId) external view returns (T.Issue memory) { return _issues[issueId]; }

    function getRound(bytes32 issueId, uint32 round) external view returns (T.RoundState memory) {
        require(round >= 1 && round <= _issues[issueId].roundCount, "ACDF: round index");
        return _rounds[issueId][round - 1];
    }

    function getBodyState(bytes32 issueId, uint32 round, uint32 body) external view returns (T.BodyState memory) {
        return _bodies[issueId][round][body];
    }

    function hasVoted(bytes32 issueId, uint32 round, uint32 body, address voter) external view returns (bool) {
        return _voted[issueId][round][body][voter];
    }

    function activeIssueOf(address consumer, bytes32 obligationKey) external view returns (bytes32) {
        return _activeIssue[consumer][obligationKey];
    }

    function obligationKeyOf(address consumer, T.Subject calldata subject, bytes32 question) external pure returns (bytes32) {
        return _obligationKey(consumer, subject, question);
    }

    function _obligationKey(address consumer, T.Subject memory subject, bytes32 question) private pure returns (bytes32) {
        return keccak256(abi.encode(consumer, subject, question));
    }

    function getEnactment(bytes32 issueId, address consumer, bytes32 effectId) external view returns (T.Enactment memory) {
        return _enactments[issueId][consumer][effectId];
    }

    function ballotDigest(bytes32 issueId, uint32 round, uint32 body, address voter, bool approve)
        external view returns (bytes32)
    {
        return _ballotDigest(issueId, round, body, voter, approve);
    }

    function _ballotDigest(bytes32 issueId, uint32 round, uint32 body, address voter, bool approve)
        private view returns (bytes32)
    {
        bytes32 domain = keccak256(abi.encode(
            DOMAIN_TYPEHASH, keccak256("ACDF"), keccak256("1"), block.chainid, address(this)
        ));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, issueId, round, body, voter, approve));
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    // ERC-6372: one clock per registry instance.
    function clock() external view returns (uint48) { return uint48(block.timestamp); }
    function CLOCK_MODE() external pure returns (string memory) { return "mode=timestamp"; }
}
