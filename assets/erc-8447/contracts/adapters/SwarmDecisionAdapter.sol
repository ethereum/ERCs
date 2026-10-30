// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import {ISwarmRegistry} from "../interfaces/ISwarmRegistry.sol";
import {ACDFTypes as A} from "./interfaces/ACDFTypes.sol";
import {IACDFRegistry} from "./interfaces/IACDFRegistry.sol";
import {IACDFPolicyRegistry} from "./interfaces/IACDFPolicyRegistry.sol";

/// @title  SwarmDecisionAdapter — a swarm decision point held by an ERC-8436 collective decision
/// @notice Deploy one adapter per (deciding role, threshold, window) configuration and name its
///         address as the ADDRESS authority of the decision points it should hold. Anyone may
///         `open` a proposal: the adapter checks that it really holds the point, that the supplied
///         roster is exactly the active members of the deciding role at this moment, registers a
///         fresh policy version whose fixed roster is that snapshot, and files a CONSUMER_FILED
///         issue bound to the swarm, the decision point, the exact registry call proposed, the
///         charter version and the phase. Once the issue is Final with a decision, anyone may
///         `execute`: a Yes performs the recorded call on the registry as the authority — unless the
///         swarm's commitment version or phase has changed since filing: a decision is taken under
///         one set of commitments and in one phase, and is performed under no other — a No records
///         that nothing is to be done, a NoDecision is the status quo and triggers nothing. Members
///         admitted after the snapshot take part in later decisions, never in the one under way.
contract SwarmDecisionAdapter {
    ISwarmRegistry      public immutable swarms;
    IACDFRegistry       public immutable decisions;
    IACDFPolicyRegistry public immutable policies;
    bytes32 public immutable decidingRole;   // the role whose active members form the roster
    uint32  public immutable kNumerator;     // approvals needed = ceil(n * kNumerator / kDenominator), at least 1
    uint32  public immutable kDenominator;
    uint64  public immutable window;         // seconds the roster has to vote
    uint64  public immutable margin;         // execution margin before the swarm's own deadlines

    bytes32 public constant EFFECT_YES  = keccak256("sai.enact");
    bytes32 public constant EFFECT_NO   = keccak256("sai.refuse");
    bytes32 public constant DISPOSITION = keccak256("sai.status-quo");
    bytes32 public constant DESCRIPTOR  = keccak256("sai.decision-adapter.v1");

    struct Proposal {
        bool            exists;
        bool            enacted;
        bytes32         swarmId;
        T.DecisionPoint decisionPoint;
        uint32          charterVersion;     // charter version the proposal was filed under (part of the subject)
        uint32          commitmentVersion;  // a material amendment in between invalidates the proposal
        uint32          phase;              // phase the proposal was filed in (part of the subject); an advance in between invalidates it
        bytes           call;               // exact registry calldata proposed
    }

    mapping(bytes32 => Proposal) public proposalOf;   // issueId => proposal
    mapping(bytes32 => uint32)   public familyVersion; // family => latest version registered here
    mapping(bytes32 => bytes32)  public familyLatest;  // family => latest policyId

    event ProposalOpened(bytes32 indexed issueId, bytes32 indexed swarmId, T.DecisionPoint indexed decisionPoint,
                         bytes32 policyId, bytes call, uint64 consumerDeadline);
    event ProposalEnacted(bytes32 indexed issueId, bytes32 indexed effectId);
    event ProposalEnactmentFailed(bytes32 indexed issueId, bytes32 indexed effectId, bytes reason);

    constructor(ISwarmRegistry swarms_, IACDFRegistry decisions_, bytes32 decidingRole_,
                uint32 kNumerator_, uint32 kDenominator_, uint64 window_, uint64 margin_)
    {
        require(address(swarms_) != address(0) && address(decisions_) != address(0), "SAIDecision: zero address");
        require(kDenominator_ > 0 && kNumerator_ > 0 && kNumerator_ <= kDenominator_, "SAIDecision: threshold");
        require(window_ > 0, "SAIDecision: window");
        swarms = swarms_;
        decisions = decisions_;
        policies = decisions_.policies();
        decidingRole = decidingRole_;
        kNumerator = kNumerator_;
        kDenominator = kDenominator_;
        window = window_;
        margin = margin_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) { return interfaceId == 0x01ffc9a7; }

    // ------------------------------------------------------------------ questions and selectors

    function questionOf(T.DecisionPoint dp) public pure returns (bytes32) {
        string[16] memory names = ["activate", "abort", "suspend", "resume", "advance", "conclude", "dissolve", "succeed",
                                   "admit", "remove", "reinstate", "amend", "attach", "detach", "set-account", "represent"];
        return keccak256(abi.encodePacked("sai.dp.", names[uint256(dp)]));
    }

    /// The registry functions a decision point may enact. SUCCEED and REPRESENT are not enactable
    /// through this adapter.
    function allowed(T.DecisionPoint dp, bytes4 selector) public pure returns (bool) {
        if (dp == T.DecisionPoint.ACTIVATE) return selector == ISwarmRegistry.activate.selector;
        if (dp == T.DecisionPoint.ABORT) return selector == ISwarmRegistry.abort.selector;
        if (dp == T.DecisionPoint.SUSPEND) return selector == ISwarmRegistry.suspend.selector;
        if (dp == T.DecisionPoint.RESUME) return selector == ISwarmRegistry.resume.selector;
        if (dp == T.DecisionPoint.ADVANCE) return selector == ISwarmRegistry.advance.selector;
        if (dp == T.DecisionPoint.CONCLUDE) return selector == ISwarmRegistry.conclude.selector;
        if (dp == T.DecisionPoint.DISSOLVE) return selector == ISwarmRegistry.dissolve.selector;
        if (dp == T.DecisionPoint.ADMIT) {
            return selector == ISwarmRegistry.admit.selector || selector == ISwarmRegistry.substitute.selector
                || selector == ISwarmRegistry.remove.selector;
        }
        if (dp == T.DecisionPoint.REMOVE) {
            return selector == ISwarmRegistry.remove.selector || selector == ISwarmRegistry.suspendMember.selector;
        }
        if (dp == T.DecisionPoint.REINSTATE) return selector == ISwarmRegistry.reinstate.selector;
        if (dp == T.DecisionPoint.AMEND) {
            return selector == ISwarmRegistry.amend.selector || selector == ISwarmRegistry.setCharterURI.selector;
        }
        if (dp == T.DecisionPoint.ATTACH) return selector == ISwarmRegistry.attach.selector;
        if (dp == T.DecisionPoint.DETACH) return selector == ISwarmRegistry.detach.selector;
        if (dp == T.DecisionPoint.SET_ACCOUNT) return selector == ISwarmRegistry.setAccount.selector;
        return false;
    }

    function familyOf(bytes32 swarmId, T.DecisionPoint dp) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), swarmId, dp));
    }

    // ------------------------------------------------------------------ open

    /// @param call   the exact registry calldata to perform on Yes; its first argument must be `swarmId`
    /// @param roster every active member of the deciding role, in any order; checked for completeness
    function open(bytes32 swarmId, T.DecisionPoint dp, bytes calldata call, address[] calldata roster)
        external returns (bytes32 issueId)
    {
        T.Authority memory a = swarms.authorityOf(swarmId, dp);
        require(a.kind == T.AuthorityKind.ADDRESS && a.target == address(this), "SAIDecision: not the authority");
        require(call.length >= 36 && allowed(dp, bytes4(call[:4])), "SAIDecision: call not allowed");
        require(bytes32(call[4:36]) == swarmId, "SAIDecision: call targets another swarm");

        // roster snapshot: exactly the active members of the deciding role, now
        (uint32 active,) = swarms.roleCount(swarmId, decidingRole);
        require(roster.length == active && active > 0, "SAIDecision: roster incomplete");
        for (uint256 i = 0; i < roster.length; i++) {
            T.Member memory m = swarms.getMember(swarmId, roster[i]);
            require(m.status == T.MemberStatus.ACTIVE && m.roleId == decidingRole, "SAIDecision: not a deciding member");
            for (uint256 j = 0; j < i; j++) require(roster[j] != roster[i], "SAIDecision: duplicate member");
        }

        bytes32 policyId = _registerPolicy(swarmId, dp, roster);
        T.Swarm memory s = swarms.getSwarm(swarmId);
        uint64 consumerDeadline = _consumerDeadline(swarmId, s);

        A.IssueInput memory input;
        input.policyId = policyId;
        input.mode = A.AcceptanceMode.CONSUMER_FILED;
        input.consumer = address(this);
        input.subject = A.Subject({
            chainId: block.chainid,
            target: address(swarms),
            id: uint256(swarmId),
            dataHash: keccak256(abi.encode(dp, call, s.charterVersion, s.phase))
        });
        input.question = questionOf(dp);
        input.effectYes = EFFECT_YES;
        input.effectNo = EFFECT_NO;
        input.disposition = DISPOSITION;
        // one unfinished binding proceeding per concrete proposal; a proposal is a call in a phase
        input.obligationId = keccak256(abi.encode(swarmId, dp, call, s.phase));
        input.consumerDeadline = consumerDeadline;
        issueId = decisions.file(input);

        Proposal storage p = proposalOf[issueId];
        p.exists = true;
        p.swarmId = swarmId;
        p.decisionPoint = dp;
        p.charterVersion = s.charterVersion;
        p.commitmentVersion = s.commitmentVersion;
        p.phase = s.phase;
        p.call = call;
        emit ProposalOpened(issueId, swarmId, dp, policyId, call, consumerDeadline);
    }

    function _registerPolicy(bytes32 swarmId, T.DecisionPoint dp, address[] calldata roster) private returns (bytes32 policyId) {
        uint32 n = uint32(roster.length);
        uint32 k = uint32((uint256(n) * kNumerator + kDenominator - 1) / kDenominator);
        if (k == 0) k = 1;
        bytes32 family = familyOf(swarmId, dp);
        uint32 version = familyVersion[family] + 1;

        A.PolicySpec memory spec;
        spec.family = family;
        spec.version = version;
        spec.previous = familyLatest[family];
        spec.updateAuthority = address(this);
        spec.bodies = new A.BodySpec[](1);
        spec.bodies[0] = A.BodySpec({
            kind: A.BodyKind.ROSTER_KOFN, acceptance: A.Acceptance.ON_CHAIN_TALLY, members: roster, k: k, window: window
        });
        spec.nodes = new A.Node[](1);
        spec.nodes[0] = A.Node({
            op: A.Combinator.BODY, body: 0, k: 0, target: 0, vetoBody: 0, silence: A.VetoSilence.PASS_THROUGH,
            children: new uint32[](0)
        });
        spec.maxAppeals = 0;
        spec.appealWindow = 0;
        spec.appealable = 0;
        spec.appealStanding = A.AppealStanding.ANYONE;
        spec.appealMode = A.AppealMode.PRESERVE_UNLESS_OVERTURNED;
        spec.maxTotalDuration = window;
        spec.ackWindow = 0;
        spec.allowAdvisory = false;
        spec.descriptorHash = DESCRIPTOR;

        policyId = policies.registerPolicy(spec);
        familyVersion[family] = version;
        familyLatest[family] = policyId;
    }

    /// The earlier of the swarm's hard deadline and the current phase's input window end (when that
    /// end is still ahead: a decision taken after the window closed — advancing a bidding phase, for
    /// instance — is bounded by the hard deadline alone), minus the execution margin; zero when
    /// neither bounds the proposal.
    function _consumerDeadline(bytes32 swarmId, T.Swarm memory s) private view returns (uint64) {
        uint256 earliest = swarms.hardDeadlineOf(swarmId);
        if (s.state == T.LifecycleState.ACTIVE) {
            T.PhaseSpec memory ph = swarms.phaseSpecOf(swarmId, s.phase);
            if (ph.inputWindow != 0) {
                uint256 end = uint256(s.phaseStartedAt) + ph.inputWindow;
                if (end > block.timestamp && (earliest == 0 || end < earliest)) earliest = end;
            }
        }
        if (earliest == 0) return 0;
        require(earliest > block.timestamp + margin + window, "SAIDecision: no execution window");
        uint256 deadline = earliest - margin;
        require(deadline <= type(uint64).max, "SAIDecision: deadline overflow");
        return uint64(deadline);
    }

    // ------------------------------------------------------------------ execute

    /// Performs a Final decision. Permissionless; the caller chooses nothing: the recorded call is
    /// the only thing this function can perform, and only on Yes.
    function execute(bytes32 issueId) external {
        Proposal storage p = proposalOf[issueId];
        require(p.exists, "SAIDecision: unknown issue");
        require(!p.enacted, "SAIDecision: already enacted");
        A.Result memory r = decisions.getResult(issueId);
        require(r.state == A.ProcedureState.Final, "SAIDecision: not final");
        require(r.outcomeType == A.OutcomeType.Decided, "SAIDecision: no decision; status quo");

        if (!r.outcomeYes) {
            p.enacted = true;
            decisions.recordEnactment(issueId, EFFECT_NO, A.EnactmentStatus.Enacted, bytes32(0));
            emit ProposalEnacted(issueId, EFFECT_NO);
            return;
        }
        // a proposal decided under one set of member commitments and in one phase is not executed
        // under another: `advance` is relative, so a Yes obtained in an earlier phase would perform a
        // different transition than the one voted on, and after a SELECT advance it would have been
        // decided by a roster that is no longer the swarm's
        T.Swarm memory now = swarms.getSwarm(p.swarmId);
        require(now.commitmentVersion == p.commitmentVersion, "SAIDecision: commitments changed");
        require(now.phase == p.phase, "SAIDecision: phase changed");
        (bool ok, bytes memory err) = address(swarms).call(p.call);
        if (ok) {
            p.enacted = true;
            decisions.recordEnactment(issueId, EFFECT_YES, A.EnactmentStatus.Enacted, bytes32(uint256(uint160(msg.sender))));
            emit ProposalEnacted(issueId, EFFECT_YES);
        } else {
            decisions.recordEnactment(issueId, EFFECT_YES, A.EnactmentStatus.Failed, keccak256(err));
            emit ProposalEnactmentFailed(issueId, EFFECT_YES, err);
        }
    }
}
