// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TaskToken} from "../contracts/TaskToken.sol";
import {TaskVault} from "../contracts/TaskVault.sol";
import {ITaskToken} from "../contracts/interfaces/ITaskToken.sol";
import {ITaskTender} from "../contracts/interfaces/ITaskTender.sol";
import {ITaskVerifier} from "../contracts/interfaces/ITaskVerifier.sol";
import {IOnchainTaskDocument} from "../contracts/interfaces/IOnchainTaskDocument.sol";
import {HashlockVerifier} from "../contracts/verifiers/HashlockVerifier.sol";
import {JuryPanel} from "../contracts/judgment/JuryPanel.sol";

contract MockERC20 {
    string public name = "Mock";
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

/// One assertion cluster per MUST clause of the TASK-KERNEL v3.0 specification.
contract TaskTokenTest is Test {
    TaskToken t;
    MockERC20 usd;
    HashlockVerifier hashlock;

    address owner     = address(0xA11CE);
    address publisher = address(0xB0B);     // update authority
    address judge     = address(0x1CDE);    // acceptance authority (judged path)
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
        usd = new MockERC20();
        hashlock = new HashlockVerifier();
        vm.deal(funder, 100 ether);
        vm.deal(funder2, 100 ether);
        vm.deal(worker, 1 ether);
        vm.deal(rando, 1 ether);
    }

    function mintDefault() internal returns (uint256 id) {
        id = t.mintTask(owner, publisher, judge, TD, TH, "ipfs://task-v1", terms());
    }

    // ---------------- ERC-165: interface ids discoverable
    function test_erc165() public view {
        assertTrue(t.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(t.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(t.supportsInterface(type(ITaskToken).interfaceId));
        assertTrue(t.supportsInterface(type(ITaskTender).interfaceId));
        assertTrue(t.supportsInterface(type(IOnchainTaskDocument).interfaceId));
        assertTrue(hashlock.supportsInterface(type(ITaskVerifier).interfaceId));
    }

    // ---------------- mint: full binding+vault+tender, version 1, genesis events
    function test_mint_genesis() public {
        uint256 id = mintDefault();
        ITaskToken.TaskBinding memory b = t.taskOf(id);
        assertEq(b.tdHash, TD);
        assertEq(b.taskHash, TH);
        assertEq(b.version, 1);
        assertEq(t.updateAuthorityOf(id), publisher);
        assertEq(t.acceptanceAuthorityOf(id), judge);
        assertEq(t.ownerOf(id), owner);
        assertEq(t.escrowBalanceOf(id), 0);
        assertEq(t.completionsOf(id), 0);
        assertFalse(t.isTaskFrozen(id));
        assertFalse(t.isTenderCancelled(id));
        // the vault exists, is distinct, and is unique per token
        address v1 = t.vaultOf(id);
        assertTrue(v1 != address(0) && v1 != address(t));
        uint256 id2 = mintDefault();
        assertTrue(t.vaultOf(id2) != v1);
    }

    function test_mint_rejects_placeholders() public {
        ITaskTender.TenderTerms memory tt = terms();
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, bytes32(0), TH, "u", tt);
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, bytes32(0), "u", tt);
        vm.expectRevert();
        t.mintTask(owner, address(0), judge, TD, TH, "u", tt);
        vm.expectRevert();
        t.mintTask(owner, publisher, address(0), TD, TH, "u", tt);
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "", tt);
        tt.rewardPerCompletion = 0;
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "u", tt);
        // settleBy < submitBy (both nonzero) forbidden
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "u",
                   ITaskTender.TenderTerms(address(0), 1 ether, 0, 100, 50, 0, 0, 7 days));
        // judgment must have a deadline
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "u",
                   ITaskTender.TenderTerms(address(0), 1 ether, 0, 0, 0, 0, 0, 0));
        // epoch fields must be both zero or both set
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "u",
                   ITaskTender.TenderTerms(address(0), 1 ether, 0, 0, 0, 1 days, 0, 7 days));
        vm.expectRevert();
        t.mintTask(owner, publisher, judge, TD, TH, "u",
                   ITaskTender.TenderTerms(address(0), 1 ether, 0, 0, 0, 0, 1, 7 days));
    }

    // ---------------- nonexistent tokenId MUST revert on all views
    function test_nonexistent_reverts() public {
        vm.expectRevert();
        t.taskOf(42);
        vm.expectRevert();
        t.taskURI(42);
        vm.expectRevert();
        t.updateAuthorityOf(42);
        vm.expectRevert();
        t.isTaskFrozen(42);
        vm.expectRevert();
        t.vaultOf(42);
        vm.expectRevert();
        t.tenderTermsOf(42);
        vm.expectRevert();
        t.acceptanceAuthorityOf(42);
        vm.expectRevert();
        t.escrowBalanceOf(42);
        vm.expectRevert();
        t.completionsOf(42);
        vm.expectRevert();
        t.completionsInEpochOf(42, 0);
        vm.expectRevert();
        t.isTenderCancelled(42);
        vm.expectRevert();
        t.submissionCountOf(42);
        vm.expectRevert();
        t.hasOnchainTaskDocument(42);
    }

    // ---------------- vault lock: the standard's most sensitive invariant
    function test_vault_lock() public {
        uint256 id = mintDefault();
        address payable vault = payable(t.vaultOf(id));
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        assertEq(vault.balance, 2 ether);                    // money literally in the token
        assertEq(t.escrowBalanceOf(id), 2 ether);            // escrow == live vault balance
        // nobody can drain: not owner, not authorities, not randos
        vm.prank(owner);
        vm.expectRevert();
        TaskVault(vault).payout(address(0), owner, 1 ether);
        vm.prank(publisher);
        vm.expectRevert();
        TaskVault(vault).payout(address(0), publisher, 1 ether);
        vm.prank(judge);
        vm.expectRevert();
        TaskVault(vault).payout(address(0), judge, 1 ether);
        // direct transfer to the vault counts as escrow (unattributed gift)
        vm.prank(rando);
        (bool ok, ) = vault.call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(t.escrowBalanceOf(id), 2.5 ether);
    }

    // ---------------- update rules: taskHash MUST differ; tdHash MAY stay
    function test_update_rules() public {
        uint256 id = mintDefault();
        vm.prank(publisher);
        vm.expectRevert(); // same taskHash forbidden
        t.updateTask(id, TD, TH);
        vm.prank(publisher);
        t.updateTask(id, TD, TH2); // tdHash unchanged: legitimate companion-only edit
        ITaskToken.TaskBinding memory b = t.taskOf(id);
        assertEq(b.version, 2);
        assertEq(b.tdHash, TD);
        assertEq(b.taskHash, TH2);
    }

    // ---------------- power separation: approvals never reach any power
    function test_approval_leakage_blocked() public {
        uint256 id = mintDefault();
        vm.prank(owner);
        t.approve(rando, id);
        vm.prank(owner);
        vm.expectRevert();
        t.updateTask(id, TD, TH2);
        vm.prank(rando);
        vm.expectRevert();
        t.updateTask(id, TD, TH2);
        vm.prank(rando);
        vm.expectRevert();
        t.freezeTask(id);
        vm.prank(rando);
        vm.expectRevert();
        t.cancelTask(id);
        vm.prank(owner);
        vm.expectRevert();
        t.setAcceptanceAuthority(id, rando);
        vm.prank(judge);
        vm.expectRevert();
        t.updateTask(id, TD, TH2);
        vm.prank(publisher);
        vm.expectRevert();
        t.setAcceptanceAuthority(id, rando);
    }

    // ---------------- authority transfers; zero forbidden; separately held
    function test_authority_transfers() public {
        uint256 id = mintDefault();
        vm.prank(publisher);
        vm.expectRevert();
        t.setUpdateAuthority(id, address(0));
        vm.prank(publisher);
        t.setUpdateAuthority(id, rando);
        assertEq(t.updateAuthorityOf(id), rando);
        assertEq(t.acceptanceAuthorityOf(id), judge);
        vm.prank(judge);
        vm.expectRevert();
        t.setAcceptanceAuthority(id, address(0));
        vm.prank(judge);
        t.setAcceptanceAuthority(id, worker2);
        assertEq(t.acceptanceAuthorityOf(id), worker2);
        assertEq(t.updateAuthorityOf(id), rando);
    }

    // ---------------- ERC-721 transfer moves the asset (vault included), not powers
    function test_transfer_moves_neither_authority() public {
        uint256 id = mintDefault();
        address vault = t.vaultOf(id);
        vm.prank(owner);
        t.transferFrom(owner, rando, id);
        assertEq(t.ownerOf(id), rando);
        assertEq(t.vaultOf(id), vault); // vault keyed to tokenId, travels with it
        assertEq(t.updateAuthorityOf(id), publisher);
        assertEq(t.acceptanceAuthorityOf(id), judge);
    }

    // ---------------- freeze: irreversible; binds content, not transport/tender
    function test_freeze() public {
        uint256 id = mintDefault();
        vm.prank(publisher);
        t.freezeTask(id);
        assertTrue(t.isTaskFrozen(id));
        vm.prank(publisher);
        vm.expectRevert();
        t.updateTask(id, TD, TH2);
        vm.prank(publisher);
        vm.expectRevert();
        t.freezeTask(id);
        vm.prank(publisher);
        t.setTaskURI(id, "ipfs://mirror");
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "ipfs://result");
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertEq(t.completionsOf(id), 1);
    }

    // ---------------- judged settlement: atomic; authority-only; solvency-gated
    function test_accept_settlement() public {
        uint256 id = mintDefault();
        // v3.0: solvency is enforced at DELIVERY, not at acceptance. Nobody is
        // asked to work against a vault that could not pay them.
        vm.prank(worker);
        vm.expectRevert(); // insufficient escrow to reserve
        t.submitFulfillment(id, RES, "");
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        assertEq(t.pendingOf(id), 1);
        assertEq(t.lockedEscrowOf(id), 1 ether); // the reward is now spoken for
        vm.prank(rando);
        vm.expectRevert(); // not acceptance authority
        t.acceptFulfillment(id, sid);
        uint256 before = worker.balance;
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertEq(worker.balance, before + 1 ether);
        assertEq(t.escrowBalanceOf(id), 1 ether);
        assertEq(t.completionsOf(id), 1);
        vm.prank(judge);
        vm.expectRevert(); // not pending anymore
        t.acceptFulfillment(id, sid);
    }

    // ---------------- machine settlement: hashlock verifier, permissionless
    function test_machine_settlement_hashlock() public {
        bytes memory answer = "42";
        // two slots and two rewards funded: a copied submission must be able to
        // EXIST (so we can prove it cannot settle), which under v3.0 reservation
        // means the tender has to have room and money for it.
        uint256 id = t.mintTask(owner, publisher, address(hashlock), TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 2, 0, 0, 0, 0, 7 days));
        bytes32 _h1 = sha256(answer);
        vm.prank(rando);
        vm.expectRevert(); // only update authority commits the answer
        hashlock.commitAnswer(address(t), id, _h1);
        bytes32 _h2 = sha256(answer);
        vm.prank(publisher);
        hashlock.commitAnswer(address(t), id, _h2);
        bytes32 _h3 = sha256("43");
        vm.prank(publisher);
        vm.expectRevert(); // set-once: no moving the goalposts
        hashlock.commitAnswer(address(t), id, _h3);

        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        // fulfiller commits the answer BOUND TO THEIR ADDRESS, then self-settles
        bytes32 commitment = sha256(abi.encodePacked(answer, worker));
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, commitment, "");
        // wrong proof: fails but submission stays Pending (NOT a rejection)
        vm.prank(worker);
        vm.expectRevert();
        t.settleFulfillment(id, sid, "41");
        assertEq(uint8(t.submissionOf(id, sid).status),
                 uint8(ITaskTender.SubmissionStatus.Pending));
        // a thief copying the commitment cannot settle their own copied submission
        vm.prank(rando);
        uint256 sidThief = t.submitFulfillment(id, commitment, "");
        vm.prank(rando);
        vm.expectRevert(); // commitment binds worker's address, not rando's
        t.settleFulfillment(id, sidThief, answer);
        // right proof, called by ANYONE, pays the submission's fulfiller
        uint256 before = worker.balance;
        vm.prank(rando);
        t.settleFulfillment(id, sid, answer);
        assertEq(worker.balance, before + 1 ether);
        assertEq(t.completionsOf(id), 1);
        // judged-path settle on a machine task with a non-verifier caller path:
        // settleFulfillment on a JUDGED task reverts (authority not a verifier)
        uint256 id2 = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 1 ether}(id2, 1 ether);
        vm.prank(worker);
        uint256 s2 = t.submitFulfillment(id2, RES, "");
        vm.prank(worker);
        vm.expectRevert();
        t.settleFulfillment(id2, s2, "");
    }

    // ---------------- epoch pacing: standing tender
    function test_epoch_pacing() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(0), 1 ether, 0, 0, 0, 1 days, 1, 7 days));
        vm.prank(funder);
        t.fundTask{value: 10 ether}(id, 10 ether);
        bytes32 _h4 = sha256("day1");
        vm.prank(worker);
        uint256 s1 = t.submitFulfillment(id, _h4, "");
        bytes32 _h5 = sha256("day1-again");
        vm.prank(worker);
        uint256 s2 = t.submitFulfillment(id, _h5, "");
        vm.prank(judge);
        t.acceptFulfillment(id, s1);
        uint64 epoch = uint64(block.timestamp / 1 days);
        assertEq(t.completionsInEpochOf(id, epoch), 1);
        vm.prank(judge);
        vm.expectRevert(); // epoch exhausted (max 1 per day)
        t.acceptFulfillment(id, s2);
        vm.warp(block.timestamp + 1 days); // next epoch opens
        vm.prank(judge);
        t.acceptFulfillment(id, s2);
        assertEq(t.completionsOf(id), 2);
    }

    // ---------------- jury panel: K-of-N judged authority
    function test_jury_panel() public {
        address[] memory jurors = new address[](3);
        jurors[0] = address(0x101); jurors[1] = address(0x102); jurors[2] = address(0x103);
        JuryPanel panel = new JuryPanel(jurors, 2, 3 days);
        uint256 id = t.mintTask(owner, publisher, address(panel), TD, TH, "u", terms());
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        // panel is a judged authority, not a verifier: machine path is closed
        vm.prank(worker);
        vm.expectRevert();
        t.settleFulfillment(id, sid, "");
        // non-juror cannot vote; jurors vote; quorum settles and pays
        vm.prank(rando);
        vm.expectRevert();
        panel.vote(address(t), id, sid, true);
        uint256 before = worker.balance;
        vm.prank(jurors[0]);
        panel.vote(address(t), id, sid, true);
        vm.prank(jurors[1]);
        panel.vote(address(t), id, sid, true); // 2-of-3 reached -> acceptFulfillment
        assertEq(worker.balance, before + 1 ether);
        assertEq(t.completionsOf(id), 1);
        // timeout default: a stalled case resolves to rejection, finalizable by anyone
        bytes32 _h6 = sha256("second try");
        vm.prank(worker);
        uint256 s2 = t.submitFulfillment(id, _h6, "");
        vm.prank(jurors[0]);
        panel.vote(address(t), id, s2, true); // 1-of-3, window opens
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(rando);
        panel.finalizeTimeout(address(t), id, s2);
        assertEq(uint8(t.submissionOf(id, s2).status),
                 uint8(ITaskTender.SubmissionStatus.Rejected));
    }

    // ---------------- ERC-20 tender: fund into vault, settle in the asset
    function test_fund_erc20() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
                                ITaskTender.TenderTerms(address(usd), 100e18, 1, 0, 0, 0, 0, 7 days));
        usd.mint(funder, 500e18);
        vm.prank(funder);
        usd.approve(address(t), 500e18);
        vm.prank(funder);
        vm.expectRevert(); // native value on ERC-20 tender forbidden
        t.fundTask{value: 1 ether}(id, 100e18);
        vm.prank(funder);
        t.fundTask(id, 100e18);
        assertEq(usd.balanceOf(t.vaultOf(id)), 100e18); // in the vault, visibly
        assertEq(t.escrowBalanceOf(id), 100e18);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid);
        assertEq(usd.balanceOf(worker), 100e18);
        assertEq(t.escrowBalanceOf(id), 0);
    }

    // ---------------- submission rules and version citation
    function test_submission_rules() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether); // two slots, two rewards reserved
        vm.prank(worker);
        vm.expectRevert(); // zero resultHash
        t.submitFulfillment(id, bytes32(0), "");
        vm.prank(worker);
        uint256 s1 = t.submitFulfillment(id, RES, "ipfs://r1");
        assertEq(s1, 1);
        ITaskTender.Submission memory s = t.submissionOf(id, s1);
        assertEq(s.fulfiller, worker);
        assertEq(s.taskVersion, 1);
        vm.prank(publisher);
        t.updateTask(id, TD, TH2);
        vm.prank(worker2);
        uint256 s2 = t.submitFulfillment(id, RES, "");
        assertEq(t.submissionOf(id, s2).taskVersion, 2);
    }

    function test_submitBy_deadline() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
            ITaskTender.TenderTerms(address(0), 1 ether, 0, uint64(block.timestamp + 100), 0, 0, 0, 7 days));
        vm.warp(block.timestamp + 101);
        vm.prank(worker);
        vm.expectRevert();
        t.submitFulfillment(id, RES, "");
    }

    function test_settleBy_deadline() public {
        uint256 id = t.mintTask(owner, publisher, judge, TD, TH, "u",
            ITaskTender.TenderTerms(address(0), 1 ether, 0,
                uint64(block.timestamp + 50), uint64(block.timestamp + 100), 0, 0, 7 days));
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.warp(block.timestamp + 101);
        vm.prank(judge);
        vm.expectRevert();
        t.acceptFulfillment(id, sid);
    }

    // ---------------- rejection: terminal, asset-free, resubmission allowed
    function test_reject_terminal() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 5 ether}(id, 5 ether);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.rejectFulfillment(id, sid);
        assertEq(t.escrowBalanceOf(id), 5 ether);
        vm.prank(judge);
        vm.expectRevert();
        t.acceptFulfillment(id, sid);
        bytes32 _h7 = sha256("deliverable v2");
        vm.prank(worker);
        uint256 s2 = t.submitFulfillment(id, _h7, "");
        vm.prank(judge);
        t.acceptFulfillment(id, s2);
    }

    // ---------------- maxCompletions bound
    function test_maxCompletions_bound() public {
        uint256 id = mintDefault(); // maxCompletions = 2
        vm.prank(funder);
        t.fundTask{value: 10 ether}(id, 10 ether);
        vm.prank(worker);
        uint256 s1 = t.submitFulfillment(id, RES, "");
        bytes32 _h8 = sha256("d2");
        vm.prank(worker2);
        uint256 s2 = t.submitFulfillment(id, _h8, "");
        // v3.0: the bound is consumed by DELIVERY, not by acceptance. Both slots are
        // now reserved, so a third worker cannot be lured into unpayable work.
        assertEq(t.pendingOf(id), 2);
        bytes32 _h9 = sha256("d3");
        vm.prank(rando);
        vm.expectRevert();
        t.submitFulfillment(id, _h9, "");
        vm.startPrank(judge);
        t.acceptFulfillment(id, s1);
        t.acceptFulfillment(id, s2);
        vm.stopPrank();
        assertEq(t.completionsOf(id), 2);
        assertEq(t.pendingOf(id), 0);
        bytes32 _h10 = sha256("late");
        vm.prank(worker);
        vm.expectRevert(); // completions exhausted
        t.submitFulfillment(id, _h10, "");
    }

    // ---------------- cancel + pro-rata reclaim over live vault balance
    function test_cancel_and_reclaim() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 3 ether}(id, 3 ether);
        vm.prank(funder2);
        t.fundTask{value: 1 ether}(id, 1 ether);
        vm.prank(funder);
        vm.expectRevert(); // tender still live
        t.reclaimEscrow(id);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid); // 3 ether remain
        vm.prank(publisher);
        t.cancelTask(id);
        assertTrue(t.isTenderCancelled(id));
        vm.prank(funder);
        vm.expectRevert();
        t.fundTask{value: 1 ether}(id, 1 ether);
        uint256 b1 = funder.balance;
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(funder.balance - b1, 2.25 ether); // 3 * 3/4
        uint256 b2 = funder2.balance;
        vm.prank(funder2);
        t.reclaimEscrow(id);
        assertEq(funder2.balance - b2, 0.75 ether);
        assertEq(t.escrowBalanceOf(id), 0);
        // binding untouched by the tender act
        assertEq(t.taskOf(id).taskHash, TH);
        assertEq(t.taskOf(id).version, 1);
    }

    // ---------------- gift residual goes to the token OWNER, never to funders
    function test_gift_residual_to_owner() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(rando);
        (bool ok, ) = payable(t.vaultOf(id)).call{value: 1 ether}(""); // anonymous gift
        assertTrue(ok);
        vm.prank(owner);
        vm.expectRevert(); // residual locked while tender live
        t.reclaimResidual(id);
        vm.prank(publisher);
        t.cancelTask(id);
        uint256 b1 = funder.balance;
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(funder.balance - b1, 2 ether); // funder gets contributions back, NOT the gift
        vm.prank(rando);
        vm.expectRevert(); // only the token owner may take the residual
        t.reclaimResidual(id);
        uint256 bo = owner.balance;
        vm.prank(owner);
        t.reclaimResidual(id);
        assertEq(owner.balance - bo, 1 ether); // ownerless money accrues to the asset holder
        assertEq(t.escrowBalanceOf(id), 0);
        vm.prank(owner);
        vm.expectRevert(); // nothing left
        t.reclaimResidual(id);
    }

    // ---------------- gift-first consumption: rewards spend gifts before funder money
    function test_gift_first_consumption() public {
        uint256 id = mintDefault();
        vm.prank(funder);
        t.fundTask{value: 2 ether}(id, 2 ether);
        vm.prank(rando);
        (bool ok, ) = payable(t.vaultOf(id)).call{value: 1 ether}(""); // gift covers first reward
        assertTrue(ok);
        vm.prank(worker);
        uint256 sid = t.submitFulfillment(id, RES, "");
        vm.prank(judge);
        t.acceptFulfillment(id, sid); // 1 ether paid: consumes the 1 ether gift entirely
        vm.prank(publisher);
        t.cancelTask(id);
        uint256 b1 = funder.balance;
        vm.prank(funder);
        t.reclaimEscrow(id);
        assertEq(funder.balance - b1, 2 ether); // funder fully protected by the gift
        vm.prank(owner);
        vm.expectRevert(); // gift fully consumed: no residual remains
        t.reclaimResidual(id);
    }

    // ---------------- on-chain document lifecycle (mirror semantics)
    function test_onchain_document() public {
        bytes memory doc = "# Build the verifier\nExact spec follows.";
        bytes32 docHash = sha256(doc);
        uint256 id = t.mintTask(owner, publisher, judge, docHash, TH, "u", terms());
        assertFalse(t.hasOnchainTaskDocument(id));
        vm.expectRevert();
        t.taskDocument(id);
        vm.prank(publisher);
        vm.expectRevert();
        t.publishTaskDocument(id, "wrong bytes");
        vm.prank(publisher);
        t.publishTaskDocument(id, doc);
        assertTrue(t.hasOnchainTaskDocument(id));
        assertEq(t.taskDocument(id), doc);
        assertEq(t.taskOf(id).version, 1);
        bytes32 _h11 = sha256("new doc");
        vm.prank(publisher);
        vm.expectRevert();
        t.updateTask(id, _h11, TH2);
        vm.prank(publisher);
        t.updateTaskWithDocument(id, "new doc", TH2);
        assertEq(t.taskOf(id).tdHash, sha256("new doc"));
        assertEq(t.taskOf(id).version, 2);
        assertEq(t.taskDocument(id), "new doc");
    }

    // ---------------- setTaskURI never bumps version
    function test_uri_outside_identity() public {
        uint256 id = mintDefault();
        vm.prank(publisher);
        t.setTaskURI(id, "ar://elsewhere");
        assertEq(t.taskOf(id).version, 1);
        assertEq(t.taskURI(id), "ar://elsewhere");
    }
}
