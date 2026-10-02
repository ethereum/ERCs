// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TaskToken} from "../contracts/TaskToken.sol";
import {ITaskToken} from "../contracts/interfaces/ITaskToken.sol";
import {ITaskTender} from "../contracts/interfaces/ITaskTender.sol";
import {IOnchainTaskDocument} from "../contracts/interfaces/IOnchainTaskDocument.sol";
import {HashlockVerifier} from "../contracts/verifiers/HashlockVerifier.sol";

/// A contract fulfiller that reads contract state DURING the payout callback.
/// If checks-effects-interactions holds, the completion count is already
/// incremented and the vault is already debited when the ether lands here.
contract ObservingFulfiller {
    TaskToken public t;
    uint256 public tokenId;
    uint256 public seenCompletions;
    uint256 public seenEscrow;
    uint256 public gasOnReceive;
    bool public received;

    constructor(TaskToken _t) { t = _t; }

    function submit(uint256 id, bytes32 rh) external returns (uint256) {
        tokenId = id;
        return t.submitFulfillment(id, rh, "");
    }

    receive() external payable {
        received = true;
        gasOnReceive = gasleft();
        seenCompletions = t.completionsOf(tokenId);
        seenEscrow = t.escrowBalanceOf(tokenId);
    }
}

/// A contract fulfiller that refuses payment: a multisig with a guard, a splitter with
/// a bug, a proxy whose implementation was swapped. Settlement must survive it.
contract RevertingFulfiller {
    function submit(address t, uint256 id, bytes32 rh) external returns (uint256) {
        return ITaskTender(t).submitFulfillment(id, rh, "");
    }
    receive() external payable { revert("nope"); }
}

/// A deflationary ("fee-on-transfer") ERC-20: the recipient receives less than
/// `amount`, so vault credit MUST be measured by the balance difference.
contract FeeERC20 {
    uint256 public constant FEE_BPS = 100; // 1%
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address sp, uint256 amount) external returns (bool) {
        allowance[msg.sender][sp] = amount; return true;
    }
    function _move(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount - (amount * FEE_BPS) / 10000; // the fee evaporates
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount); return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount; _move(from, to, amount); return true;
    }
}

/// A plain, well-behaved ERC-20 for the refund-path checks.
contract MinimalERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address sp, uint256 amount) external returns (bool) {
        allowance[msg.sender][sp] = amount; return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
}


/// A fulfiller that is expensive rather than hostile: it records the payment and
/// writes a page of its own state. Well beyond any bounded push budget, and exactly
/// the receiver the credit path has to make whole.
contract HeavyFulfiller {
    ITaskTender public t;
    uint256[40] public slots;
    uint256 public taken;

    constructor(address _t) { t = ITaskTender(_t); }

    function submit(uint256 id, bytes32 rh) external returns (uint256) {
        return t.submitFulfillment(id, rh, "");
    }

    receive() external payable {
        taken += msg.value;
        for (uint256 i = 0; i < 40; i++) slots[i] = i + 1;
    }
}

/// An ERC-20 whose `transfer` answers with a word that is not a clean bool. Decoding
/// it as one reverts, which on the settlement path would wedge the submission the
/// non-reverting payout exists to protect.
contract MalformedERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address sp, uint256 amount) external returns (bool) {
        allowance[msg.sender][sp] = amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
    /// Returns 0x02 in the return word: neither `true` nor `false` to abi.decode.
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount;
        assembly {
            mstore(0, 2)
            return(0, 32)
        }
    }
}

/// An ERC-20 whose `transfer` replies with a single byte: too short to be any bool.
/// Reading it MUST NOT throw; it MUST be treated as a failed transfer and credited.
contract ShortReplyERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address sp, uint256 amount) external returns (bool) {
        allowance[msg.sender][sp] = amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
    function transfer(address, uint256) external pure returns (bool) {
        assembly {
            mstore(0, 1)
            return(0, 1)
        }
    }
}

/// Second assertion layer: the normative clauses that TaskToken.t.sol leaves
/// unasserted — every `MUST emit`, the post-cancellation and post-freeze
/// closures, the authority gates reachable only through operator approval,
/// rejection terminality across BOTH settlement paths, the expiry refund route,
/// unbounded tenders, native funding arithmetic, per-token submission ids, and
/// checks-effects-interactions on payout.
contract TaskTokenCoverageTest is Test {
    TaskToken t;
    HashlockVerifier hashlock;

    address owner     = address(0xA11CE);
    address publisher = address(0xB0B);
    address judge     = address(0x1CDE);
    address funder    = address(0xF00D);
    address funder2   = address(0xFEED);
    address worker    = address(0xCAFE);
    address worker2   = address(0xBEEF);
    address rando     = address(0xBAD);

    bytes32 TD  = sha256("TASK.md v1");
    bytes32 TH  = sha256("taskroot v1");
    bytes32 TH2 = sha256("taskroot v2");
    bytes32 RES = sha256("deliverable");

    function terms() internal pure returns (ITaskTender.TenderTerms memory) {
        return ITaskTender.TenderTerms(address(0), 1 ether, 2, 0, 0, 0, 0, 7 days);
    }

    function setUp() public {
        t = new TaskToken("Task Token", "TASK");
        hashlock = new HashlockVerifier();
        vm.deal(funder, 100 ether);
        vm.deal(funder2, 100 ether);
        vm.deal(rando, 100 ether);
        vm.deal(worker2, 100 ether);
    }

    function mintDefault() internal returns (uint256) {
        return t.mintTask(owner, publisher, judge, TD, TH, "ipfs://task-v1", terms());
    }

    // ---------------- every MUST-emit clause in the specification
    function test_genesis_events() public {
        uint256 next = t.nextId();
        vm.expectEmit(true, true, true, true);
        emit ITaskToken.TaskUpdated(next, TD, TH, 1);
        vm.expectEmit(true, true, true, true);
        emit ITaskToken.TaskUpdateAuthorityChanged(next, address(0), publisher);
        vm.expectEmit(true, true, true, true);
        emit ITaskTender.AcceptanceAuthorityChanged(next, address(0), judge);
        uint256 id = mintDefault();
        assertEq(id, next);
    }

    function test_lifecycle_events() public {
        uint256 id = mintDefault();

        vm.expectEmit(true, true, true, true);
        emit ITaskToken.TaskURIUpdated(id, "ar://mirror");
        vm.prank(publisher);
        t.setTaskURI(id, "ar://mirror");

        vm.expectEmit(true, true, true, true);
        emit ITaskToken.TaskUpdated(id, TD, TH2, 2);
        vm.prank(publisher);
        t.updateTask(id, TD, TH2);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.TenderFunded(id, funder, 3 ether, 3 ether);
        vm.prank(funder);
        t.fundTask{value: 3 ether}(id, 3 ether);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.FulfillmentSubmitted(id, 1, worker, RES, "ipfs://r", 2);
        vm.prank(worker);
        t.submitFulfillment(id, RES, "ipfs://r");

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.FulfillmentAccepted(id, 1, worker, 1 ether);
        vm.prank(judge);
        t.acceptFulfillment(id, 1);

        bytes32 _h1 = sha256("d2");
        vm.prank(worker);
        t.submitFulfillment(id, _h1, "");
        vm.expectEmit(true, true, true, true);
        emit ITaskTender.FulfillmentRejected(id, 2);
        vm.prank(judge);
        t.rejectFulfillment(id, 2);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.AcceptanceAuthorityChanged(id, judge, rando);
        vm.prank(judge);
        t.setAcceptanceAuthority(id, rando);

        vm.expectEmit(true, true, true, true);
        emit ITaskToken.TaskFrozen(id);
        vm.prank(publisher);
        t.freezeTask(id);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.TenderCancelled(id);
        vm.prank(publisher);
        t.cancelTask(id);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.EscrowReclaimed(id, funder, 2 ether);
        vm.prank(funder);
        t.reclaimEscrow(id);
    }

    function test_document_and_residual_events() public {
        bytes memory doc = "# doc";
        uint256 id = t.mintTask(owner, publisher, judge, sha256(doc), TH, "u", terms());
        vm.expectEmit(true, true, true, true);
        emit IOnchainTaskDocument.TaskDocumentPublished(id, sha256(doc));
        vm.prank(publisher);
        t.publishTaskDocument(id, doc);

        uint256 id2 = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id2, 1 ether);
        vm.prank(rando);
        (bool ok, ) = payable(t.vaultOf(id2)).call{value: 1 ether}("");
        assertTrue(ok);
        vm.prank(publisher);
        t.cancelTask(id2);
        vm.expectEmit(true, true, true, true);
        emit ITaskTender.ResidualReclaimed(id2, owner, 1 ether);
        vm.prank(owner);
        t.reclaimResidual(id2);
    }

    // ---------------- cancellation stops NEW work; it does not void delivered work
    function test_post_cancellation_closure() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 3 ether}(id, 3 ether);
        vm.prank(worker);
        t.submitFulfillment(id, RES, "");
        vm.prank(publisher);
        t.cancelTask(id);

        // closed: nothing new comes in, and cancellation is irreversible
        vm.prank(funder);
        vm.expectRevert();
        t.fundTask{value: 1 ether}(id, 1 ether);
        bytes32 _h2 = sha256("x");
        vm.prank(worker);
        vm.expectRevert();
        t.submitFulfillment(id, _h2, "");
        vm.prank(publisher);
        vm.expectRevert();
        t.cancelTask(id);
        // and the money already owed cannot be walked away with
        vm.prank(funder);
        vm.expectRevert();
        t.reclaimEscrow(id);
        vm.prank(owner);
        vm.expectRevert();
        t.reclaimResidual(id);

        // open: the delivered submission is still judgeable, and still pays
        assertEq(t.pendingOf(id), 1);
        assertEq(t.lockedEscrowOf(id), 1 ether);
        uint256 b = worker.balance;
        vm.prank(judge);
        t.acceptFulfillment(id, 1);
        assertEq(worker.balance - b, 1 ether);
        assertEq(t.pendingOf(id), 0);
        // only now, with nothing outstanding, may the funder be refunded
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(t.escrowBalanceOf(id), 0);
    }

    // ---------------- the judgment deadline: silence is not a free option
    function test_unjudged_claim_after_deadline() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "https://delivery.example/report.pdf");
        // the demander reads the deliverable, then cancels AND goes silent
        vm.prank(publisher);
        t.cancelTask(id);
        vm.expectRevert(); // the window is still open
        t.claimUnjudged(id, sid);

        vm.warp(block.timestamp + 7 days + 1);
        uint256 b = worker.balance;
        vm.expectEmit(true, true, true, false); // permissionless: any caller
        emit ITaskTender.FulfillmentClaimedUnjudged(id, sid, worker, 0);
        t.claimUnjudged(id, sid);
        assertEq(worker.balance - b, 1 ether);
        assertEq(t.completionsOf(id), 1);
        assertEq(uint8(t.submissionOf(id, sid).status),
                 uint8(ITaskTender.SubmissionStatus.Accepted));
        vm.expectRevert(); // not pending any more
        t.claimUnjudged(id, sid);
    }

    // ---------------- a default is still a paced settlement
    function test_unjudged_claim_respects_epoch_pacing() public {
        // a standing tender: five periods of budget, at most one settlement per period
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
            ITaskTender.TenderTerms(address(0), 1 ether, 5, 0, 0, 1 days, 1, 1 hours));
        vm.prank(funder);
        t.fundTask{value: 5 ether}(id, 5 ether);
        // pacing bounds settlement, not submission: all five may be delivered at once
        vm.startPrank(worker);
        for (uint256 i = 0; i < 5; i++) t.submitFulfillment(id, sha256(abi.encodePacked("r", i)), "");
        vm.stopPrank();
        assertEq(t.pendingOf(id), 5);

        // the judge goes silent for the whole window
        vm.warp(block.timestamp + 1 hours + 1);
        uint64 epoch = uint64(block.timestamp / 1 days);
        t.claimUnjudged(id, 1);
        assertEq(t.completionsInEpochOf(id, epoch), 1);
        vm.expectRevert(); // a second default in the same epoch would drain the cadence
        t.claimUnjudged(id, 2);
        assertEq(t.escrowBalanceOf(id), 4 ether); // the budget is NOT drained

        // the claim is queued, not lost
        vm.warp(block.timestamp + 1 days);
        t.claimUnjudged(id, 2);
        assertEq(t.completionsOf(id), 2);
        assertEq(t.escrowBalanceOf(id), 3 ether);
    }

    // ---------------- the right to refuse expires with the window
    function test_rejection_expires_with_the_judgment_window() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 s1 = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.rejectFulfillment(id, s1);   // inside the window: still allowed
        assertEq(uint8(t.submissionOf(id, s1).status),
                 uint8(ITaskTender.SubmissionStatus.Rejected));

        bytes32 _h3 = sha256("second");
        vm.prank(worker);
        uint256 s2 = t.submitFulfillment(id, _h3, "");
        vm.warp(block.timestamp + 7 days + 1);
        // without this rule a judge could sit out the whole window and then front-run
        // the fulfiller's claim with a refusal, leaving the deadline decorative
        vm.prank(judge);
        vm.expectRevert();
        t.rejectFulfillment(id, s2);
        uint256 b = worker.balance;
        t.claimUnjudged(id, s2);
        assertEq(worker.balance - b, 1 ether);
    }

    // ---------------- the settlement mode is snapshotted at delivery
    function test_settlement_mode_is_snapshotted_at_delivery() public {
        uint256 id = mintDefault();              // judged at the moment of delivery
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        assertFalse(t.submissionOf(id, sid).machineSettled);

        // the demander swaps a verifier into the judgment slot after receiving the work
        vm.prank(judge);
        t.setAcceptanceAuthority(id, address(hashlock));
        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert(); // the delivery was not made under machine settlement
        t.releaseExpired(id, sid);
        uint256 b = worker.balance;
        t.claimUnjudged(id, sid);   // the deadline follows the delivery, not the slot
        assertEq(worker.balance - b, 1 ether);
    }

    // ---------------- a fulfiller that will not take the money must not wedge the tender
    function test_undeliverable_payout_is_credited_not_reverted() public {
        RevertingFulfiller rf = new RevertingFulfiller();
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        uint256 sid = rf.submit(address(t), id, RES);

        vm.expectEmit(true, true, true, true);
        emit ITaskTender.PayoutCredited(id, sid, address(rf), 1 ether);
        vm.prank(judge);
        t.acceptFulfillment(id, sid);

        assertEq(uint8(t.submissionOf(id, sid).status),
                 uint8(ITaskTender.SubmissionStatus.Accepted));
        assertEq(t.pendingOf(id), 0);                 // nothing is wedged
        assertEq(t.creditOf(id, address(rf)), 1 ether);
        assertEq(t.escrowBalanceOf(id), 2 ether);     // the money is still in the vault

        // the credited reward is owed, so it is not refundable to the funder
        vm.prank(publisher);
        t.cancelTask(id);
        uint256 b = funder.balance;
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(funder.balance - b, 1 ether);
        assertEq(t.escrowBalanceOf(id), 1 ether);
    }

    // ---------------- an extreme but legal judgment window must not panic
    function test_maximal_judgment_window_does_not_overflow() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
            ITaskTender.TenderTerms(address(0), 1 ether, 1, 0, 0, 0, 0, type(uint64).max));
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        // the deadline is unreachable, so both remedies are simply closed -- and neither
        // may panic on the arithmetic that computes it
        vm.expectRevert();
        t.claimUnjudged(id, sid);
        vm.prank(judge);
        t.rejectFulfillment(id, sid);   // refusal is still open, since the window has not passed
        assertEq(uint8(t.submissionOf(id, sid).status),
                 uint8(ITaskTender.SubmissionStatus.Rejected));
    }

    // ---------------- refunds do not depend on who reclaims first
    function test_refund_is_independent_of_reclaim_order() public {
        uint256[2] memory paidFirst;
        for (uint256 k = 0; k < 2; k++) {
            uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                ITaskTender.TenderTerms(address(0), 1 ether, 1, 0, 0, 0, 0, 7 days));
            vm.prank(funder);
            t.fundTask{value: 2 ether}(id, 2 ether);
            vm.prank(funder2);
            t.fundTask{value: 1 ether}(id, 1 ether);
            vm.prank(worker);
            uint256 sid = t.submitFulfillment(id, RES, "");
            vm.prank(judge);
            t.acceptFulfillment(id, sid);          // 1 ETH paid, 2 ETH left in the pool
            vm.prank(publisher);
            t.cancelTask(id);

            uint256 a0 = funder.balance;
            if (k == 0) {
                vm.prank(funder);
                t.reclaimEscrow(id);
                vm.prank(funder2);
                t.reclaimEscrow(id);
            } else {
                vm.prank(funder2);
                t.reclaimEscrow(id);
                vm.prank(funder);
                t.reclaimEscrow(id);
            }
            paidFirst[k] = funder.balance - a0;
        }
        assertEq(paidFirst[0], paidFirst[1]);   // same share either way
    }

    // ---------------- machine tenders cannot be bricked by junk submissions
    function test_release_expired_frees_a_squatted_slot() public {
        uint256 id = t.mintTask(owner, publisher, address(hashlock), TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 1, 0, 0, 0, 0, 7 days));
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        bytes32 _h4 = sha256("junk");
        vm.prank(rando);
        uint256 sid = t.submitFulfillment(id, _h4, "");
        // with no judge to reject it, this one submission holds the only slot and the
        // whole vault: without a release it would freeze the tender forever
        assertEq(t.pendingOf(id), 1);
        assertEq(t.lockedEscrowOf(id), 1 ether);
        vm.expectRevert(); // the window has not elapsed
        t.releaseExpired(id, sid);

        vm.warp(block.timestamp + 7 days + 1);
        vm.expectEmit(true, true, true, false);
        emit ITaskTender.SubmissionReleased(id, sid, 0);
        t.releaseExpired(id, sid); // permissionless
        assertEq(uint8(t.submissionOf(id, sid).status),
                 uint8(ITaskTender.SubmissionStatus.Rejected));
        assertEq(t.pendingOf(id), 0);
        assertEq(t.lockedEscrowOf(id), 0);
        // the tender lives again for a genuine solver
        bytes32 _h5 = sha256("real attempt");
        vm.prank(worker);
        t.submitFulfillment(id, _h5, "");
        assertEq(t.pendingOf(id), 1);
    }

    function test_release_expired_is_machine_path_only() public {
        uint256 id = mintDefault(); // judged
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(); // a judged tender has a judge; silence pays the worker instead
        t.releaseExpired(id, sid);
        t.claimUnjudged(id, sid); // the correct remedy on this path
        assertEq(t.completionsOf(id), 1);
    }

    // ---------------- the default belongs to the judged path only
    function test_unjudged_claim_blocked_on_machine_path() public {
        uint256 id = t.mintTask(owner, publisher, address(hashlock), TD, TH, "u", terms());
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        bytes32 _h6 = sha256("garbage");
        vm.prank(rando);
        uint256 sid = t.submitFulfillment(id, _h6, "");
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(); // no judge to default: code decides, and code said no
        t.claimUnjudged(id, sid);
    }

    // ---------------- a delivery reserves a slot and a reward
    function test_delivery_reserves_slot_and_reward() public {
        uint256 id = mintDefault(); // maxCompletions = 2
        vm.prank(worker);
        vm.expectRevert(); // an unfunded tender may not take delivery at all
        t.submitFulfillment(id, RES, "");

        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        vm.prank(worker);
        t.submitFulfillment(id, RES, "");
        assertEq(t.pendingOf(id), 1);
        assertEq(t.lockedEscrowOf(id), 1 ether);
        bytes32 _h7 = sha256("d2");
        vm.prank(worker2);
        vm.expectRevert(); // a second delivery the vault could not pay for
        t.submitFulfillment(id, _h7, "");

        vm.prank(funder);
        t.fundTask{value: 1 ether}(id, 1 ether);
        bytes32 _h8 = sha256("d2");
        vm.prank(worker2);
        t.submitFulfillment(id, _h8, "");
        assertEq(t.pendingOf(id), 2);
        bytes32 _h9 = sha256("d3");
        vm.prank(rando);
        vm.expectRevert(); // both slots are now reserved by delivered work
        t.submitFulfillment(id, _h9, "");

        // an explicit rejection releases the reservation, on the record
        vm.prank(judge);
        t.rejectFulfillment(id, 2);
        assertEq(t.pendingOf(id), 1);
        assertEq(t.lockedEscrowOf(id), 1 ether);
        bytes32 _h10 = sha256("d3");
        vm.prank(rando);
        t.submitFulfillment(id, _h10, ""); // the freed slot is usable again
        assertEq(t.pendingOf(id), 2);
    }

    // ---------------- freeze binds content, nothing else
    function test_freeze_scope() public {
        uint256 id = mintDefault();
        vm.prank(publisher);
        t.freezeTask(id);
        vm.prank(publisher);
        vm.expectRevert();
        t.updateTaskWithDocument(id, "new", TH2);
        vm.prank(publisher);
        t.setUpdateAuthority(id, rando);
        assertEq(t.updateAuthorityOf(id), rando);
        vm.prank(rando);
        t.cancelTask(id);
        assertTrue(t.isTenderCancelled(id));
        assertTrue(t.isTaskFrozen(id)); // cancellation is a tender act, not a binding act
    }

    // ---------------- authority gates not exercised by the primary suite
    function test_authority_gates() public {
        uint256 id = mintDefault();
        vm.prank(rando);
        vm.expectRevert();
        t.setTaskURI(id, "x");
        vm.prank(rando);
        vm.expectRevert();
        t.setUpdateAuthority(id, rando);
        vm.prank(rando);
        vm.expectRevert();
        t.updateTaskWithDocument(id, "d", TH2);
        vm.prank(rando);
        vm.expectRevert();
        t.publishTaskDocument(id, "d");
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        t.submitFulfillment(id, RES, "");
        vm.prank(rando);
        vm.expectRevert();
        t.rejectFulfillment(id, 1);
    }

    // ---------------- operator approval confers nothing (approve() is covered elsewhere)
    function test_operator_approval_confers_nothing() public {
        uint256 id = mintDefault();
        vm.prank(owner);
        t.setApprovalForAll(rando, true);
        assertTrue(t.isApprovedForAll(owner, rando));
        vm.startPrank(rando);
        vm.expectRevert();
        t.updateTask(id, TD, TH2);
        vm.expectRevert();
        t.freezeTask(id);
        vm.expectRevert();
        t.cancelTask(id);
        vm.expectRevert();
        t.setTaskURI(id, "x");
        vm.expectRevert();
        t.setUpdateAuthority(id, rando);
        vm.expectRevert();
        t.setAcceptanceAuthority(id, rando);
        vm.stopPrank();
        // residual: cancel first, so the ONLY thing standing between the operator
        // and the money is the owner check itself
        vm.prank(rando);
        (bool ok, ) = payable(t.vaultOf(id)).call{value: 1 ether}("");
        assertTrue(ok);
        vm.prank(publisher);
        t.cancelTask(id);
        vm.prank(rando);
        vm.expectRevert();
        t.reclaimResidual(id);
        uint256 b = owner.balance;
        vm.prank(owner);
        t.reclaimResidual(id);
        assertEq(owner.balance - b, 1 ether); // only the owner, never the operator
        assertEq(t.escrowBalanceOf(id), 0);   // nothing else was in the vault
    }

    // ---------------- a rejected submission is dead on BOTH paths
    function test_rejection_terminal_across_paths() public {
        bytes memory answer = "42";
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 3, 0, 0, 0, 0, 7 days));
        vm.prank(funder);
        t.fundTask{value: 3 ether}(id, 3 ether);
        bytes32 commitment = sha256(abi.encodePacked(answer, worker));
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, commitment, "");
        vm.prank(judge);
        t.rejectFulfillment(id, sid);

        // judgment migrates from an EOA to a verifier contract: the dead stays dead
        vm.prank(judge);
        t.setAcceptanceAuthority(id, address(hashlock));
        bytes32 _h11 = sha256(answer);
        vm.prank(publisher);
        hashlock.commitAnswer(address(t), id, _h11);
        vm.prank(rando);
        vm.expectRevert();
        t.settleFulfillment(id, sid, answer);

        // rejection is per-submission, never a ban on the fulfiller
        vm.prank(worker);
        uint256 sid2 = t.submitFulfillment(id, commitment, "");
        vm.prank(rando);
        t.settleFulfillment(id, sid2, answer);
        assertEq(t.completionsOf(id), 1);
        vm.prank(rando);
        vm.expectRevert(); // an Accepted submission cannot be settled twice
        t.settleFulfillment(id, sid2, answer);
    }

    // ---------------- refunds open on settleBy expiry, not only on cancellation
    function test_reclaim_on_expiry_without_cancellation() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
            ITaskTender.TenderTerms(address(0), 1 ether, 0,
                uint64(block.timestamp + 100), uint64(block.timestamp + 200), 0, 0, 7 days));
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(funder2);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(funder);
        vm.expectRevert();
        t.reclaimEscrow(id);

        vm.warp(block.timestamp + 300);
        uint256 b = funder.balance;
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(funder.balance - b, 2 ether);
        assertFalse(t.isTenderCancelled(id)); // the expiry route, not the cancel route
        vm.prank(funder);
        vm.expectRevert();
        t.reclaimEscrow(id); // outstanding contribution is now zero
        assertEq(t.escrowBalanceOf(id), 2 ether); // the other funder is untouched
    }

    // ---------------- maxCompletions == 0 is unbounded
    function test_unbounded_completions() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 0, 0, 0, 0, 0, 7 days));
        vm.prank(funder);
        t.fundTask{value: 5 ether}(id, 5 ether);
        for (uint256 i = 0; i < 4; i++) {
            bytes32 _h12 = sha256(abi.encodePacked("d", i));
            vm.prank(worker);
            t.submitFulfillment(id, _h12, "");
        }
        vm.startPrank(judge);
        for (uint256 i = 1; i <= 4; i++) t.acceptFulfillment(id, i);
        vm.stopPrank();
        assertEq(t.completionsOf(id), 4); // the bounded default would have stopped at 2
    }

    // ---------------- native tender: msg.value MUST equal amount
    function test_native_funding_amount_must_match() public {
        uint256 id = mintDefault();
        vm.startPrank(funder);
        vm.expectRevert();
        t.fundTask{value: 1 ether}(id, 2 ether);
        vm.expectRevert();
        t.fundTask{value: 2 ether}(id, 1 ether);
        vm.expectRevert();
        t.fundTask{value: 0}(id, 1 ether);
        vm.stopPrank();
    }

    // ---------------- submission ids are per-token and start at 1
    function test_submission_ids_are_per_token() public {
        uint256 a = mintDefault();
        uint256 b = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(a, 2 ether);
        vm.prank(funder);
        t.fundTask{value: 1 ether}(b, 1 ether);
        vm.startPrank(worker);
        t.submitFulfillment(a, sha256("a1"), "");
        t.submitFulfillment(a, sha256("a2"), "");
        uint256 first = t.submitFulfillment(b, sha256("b1"), "");
        vm.stopPrank();
        assertEq(first, 1); // not 3
        assertEq(t.submissionCountOf(a), 2);
        assertEq(t.submissionCountOf(b), 1);
    }

    // ---------------- remaining views on a nonexistent token
    function test_nonexistent_views_remaining() public {
        vm.expectRevert();
        t.submissionOf(4242, 1);
        vm.expectRevert();
        t.taskDocument(4242);
        vm.expectRevert();
        t.tokenURI(4242);
    }

    // ---------------- state changes precede the asset transfer; contracts can be paid
    function test_cei_and_contract_fulfiller() public {
        ObservingFulfiller f = new ObservingFulfiller(t);
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        uint256 sid = f.submit(id, RES);
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertTrue(f.received());                 // not gas-starved by transfer()
        assertEq(f.seenCompletions(), 1);         // effects already applied...
        assertEq(f.seenEscrow(), 1 ether);        // ...including the vault debit
        assertGt(f.gasOnReceive(), 2300);         // real gas forwarded, not the stipend
    }

    // ---------------- nonstandard assets: credit follows the balance difference
    function test_fee_on_transfer_erc20() public {
        FeeERC20 fee = new FeeERC20();
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(fee), 50e18, 1, 0, 0, 0, 0, 7 days));
        fee.mint(funder, 500e18);
        vm.prank(funder);
        fee.approve(address(t), 500e18);
        vm.prank(funder);
        t.fundTask(id, 100e18);
        address vault = t.vaultOf(id);
        assertEq(fee.balanceOf(vault), 99e18);              // 1% evaporated in transit
        assertEq(t.escrowBalanceOf(id), fee.balanceOf(vault)); // credit follows reality
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertGt(fee.balanceOf(worker), 0);
        assertEq(t.escrowBalanceOf(id), fee.balanceOf(vault)); // still exact after a lossy payout
    }

    // ---------------- ERC-20 refund + residual, the paths only proven in native currency
    function test_erc20_refund_and_residual() public {
        MinimalERC20 usd = new MinimalERC20();
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(usd), 10e18, 5, 0, 0, 0, 0, 7 days));
        usd.mint(funder, 100e18);
        usd.mint(funder2, 100e18);
        vm.prank(funder);
        usd.approve(address(t), 100e18);
        vm.prank(funder2);
        usd.approve(address(t), 100e18);
        vm.prank(funder);
        t.fundTask(id, 30e18);
        vm.prank(funder2);
        t.fundTask(id, 10e18);
        usd.mint(t.vaultOf(id), 10e18);                     // anonymous ERC-20 gift
        assertEq(t.escrowBalanceOf(id), 50e18);

        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertEq(usd.balanceOf(worker), 10e18);

        vm.prank(publisher);
        t.cancelTask(id);
        vm.prank(funder);
        t.reclaimEscrow(id);
        vm.prank(funder2);
        t.reclaimEscrow(id);
        // the gift absorbed the whole reward, so both funders are made whole
        assertEq(usd.balanceOf(funder), 100e18);
        assertEq(usd.balanceOf(funder2), 100e18);
        assertEq(t.escrowBalanceOf(id), 0);
        vm.prank(owner);
        vm.expectRevert(); // gift fully consumed: there is no residual to take
        t.reclaimResidual(id);
    }

    // ---------------- the last funder out releases the pool; the dust reaches the owner
    function test_refund_dust_is_not_stranded() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1, 1, 0, 0, 0, 0, 7 days));
        vm.deal(funder, 10); vm.deal(funder2, 10);
        vm.prank(funder);
        t.fundTask{value: 2}(id, 2);
        vm.prank(funder2);
        t.fundTask{value: 1}(id, 1);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        vm.prank(publisher);
        t.cancelTask(id);

        vm.prank(funder);
        t.reclaimEscrow(id);      // 2 * 2 / 3 = 1
        vm.prank(funder2);
        t.reclaimEscrow(id);      // 1 * 2 / 3 = 0
        assertEq(t.escrowBalanceOf(id), 1);          // one wei of flooring dust

        uint256 before = owner.balance;
        vm.prank(owner);
        t.reclaimResidual(id);                       // MUST reach the owner, not lock
        assertEq(owner.balance - before, 1);
        assertEq(t.escrowBalanceOf(id), 0);
    }

    // ---------------- funding closes once the pro-rata ratio has been fixed
    // Cancellation trips the earlier "cancelled" guard, so the refund-snapshot guard is
    // reachable only on the other refund route: a tender whose settleBy has passed.
    function test_no_funding_after_refunds_open() public {
        uint64 settleBy = uint64(block.timestamp + 30 days);
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 2, 0, settleBy, 0, 0, 7 days));
        vm.prank(funder); t.fundTask{value: 3 ether}(id, 3 ether);
        vm.prank(worker); uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);  t.acceptFulfillment(id, sid);  // 1 ether spent, 2 remain

        vm.warp(uint256(settleBy) + 1);                  // refunds unlock without cancelling
        vm.prank(funder); t.reclaimEscrow(id);           // snapshots pool 2 / denom 3

        vm.prank(funder2);
        vm.expectRevert("TaskToken: refunding");         // would be refunded against a
        t.fundTask{value: 3 ether}(id, 3 ether);         // denominator taken before it existed
    }

    // ---------------- an expensive receiver is credited AND can actually collect
    function test_credit_is_withdrawable_by_expensive_receiver() public {
        HeavyFulfiller h = new HeavyFulfiller(address(t));
        uint256 id = mintDefault();
        vm.deal(funder, 10 ether);
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        uint256 sid = h.submit(id, RES);
        vm.prank(judge);
        t.acceptFulfillment(id, sid);

        assertEq(t.creditOf(id, address(h)), 1 ether);   // push was too expensive
        assertEq(uint8(t.submissionOf(id, sid).status), uint8(ITaskTender.SubmissionStatus.Accepted));
        assertEq(t.pendingOf(id), 0);

        t.withdrawCredit(id, address(h));                // pull path: no gas cap
        assertEq(h.taken(), 1 ether);
        assertEq(t.creditOf(id, address(h)), 0);
    }

    // ---------------- a token that answers with a malformed word must not wedge anything
    // 0x02 is not a clean bool, but it IS a non-zero word and the transfer really happened,
    // so the lenient reading pays outright. The property under test is that reading the
    // reply cannot throw: abi.decode(bool) on this word reverted, and wedged the submission.
    function test_malformed_erc20_reply_does_not_revert() public {
        MalformedERC20 m = new MalformedERC20();
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(m), 50e18, 1, 0, 0, 0, 0, 7 days));
        m.mint(funder, 500e18);
        vm.prank(funder); m.approve(address(t), 500e18);
        vm.prank(funder); t.fundTask(id, 100e18);
        vm.prank(worker); uint256 sid = t.submitFulfillment(id, RES, "");

        vm.prank(judge);
        t.acceptFulfillment(id, sid);                    // MUST NOT revert on the reply
        assertEq(uint8(t.submissionOf(id, sid).status), uint8(ITaskTender.SubmissionStatus.Accepted));
        assertEq(t.pendingOf(id), 0);                    // nothing wedged
        assertEq(m.balanceOf(worker), 50e18);            // paid outright: the word read as success
        assertEq(t.creditOf(id, worker), 0);             // so no credit was needed
    }

    // ---------------- a reply too short to decode is a failed transfer: credited, never thrown
    function test_short_erc20_reply_is_credited_not_thrown() public {
        ShortReplyERC20 m = new ShortReplyERC20();
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(m), 50e18, 1, 0, 0, 0, 0, 7 days));
        m.mint(funder, 500e18);
        vm.prank(funder); m.approve(address(t), 500e18);
        vm.prank(funder); t.fundTask(id, 100e18);
        vm.prank(worker); uint256 sid = t.submitFulfillment(id, RES, "");

        vm.prank(judge);
        t.acceptFulfillment(id, sid);                    // MUST NOT revert
        assertEq(uint8(t.submissionOf(id, sid).status), uint8(ITaskTender.SubmissionStatus.Accepted));
        assertEq(t.pendingOf(id), 0);
        assertEq(t.creditOf(id, worker), 50e18);         // the unreadable reply became a credit
    }

    // ---------------- a default claim must leave outstanding credit fully backed
    // The reservation check already keeps the vault solvent against every pending
    // submission, so reading the raw balance here was not exploitable in this
    // implementation -- but it was the wrong quantity, and a default claim paid out of
    // credited money would leave the credit unbacked. This asserts the invariant the
    // corrected check protects: after a claim, the vault still covers what it owes.
    function test_claim_unjudged_leaves_credit_backed() public {
        HeavyFulfiller h = new HeavyFulfiller(address(t));
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 3, 0, 0, 0, 0, 7 days));
        vm.deal(funder, 10 ether);
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);

        vm.prank(worker);
        uint256 sid1 = t.submitFulfillment(id, RES, "");
        uint256 sid2 = h.submit(id, sha256("heavy"));
        vm.prank(judge);
        t.acceptFulfillment(id, sid2);

        assertEq(t.creditOf(id, address(h)), 1 ether);
        assertEq(t.escrowBalanceOf(id), 2 ether);   // the raw balance still shows it all

        vm.warp(block.timestamp + 8 days);
        t.claimUnjudged(id, sid1);                  // the silent judge pays the worker

        assertEq(t.escrowBalanceOf(id), 1 ether);
        assertEq(t.creditOf(id, address(h)), 1 ether);
        assertTrue(t.escrowBalanceOf(id) >= t.creditOf(id, address(h)));  // still backed
        t.withdrawCredit(id, address(h));           // and still collectable
        assertEq(h.taken(), 1 ether);
    }
}
