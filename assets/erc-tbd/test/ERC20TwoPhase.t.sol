// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { TwoPhaseToken } from "../contracts/TwoPhaseToken.sol";
import { ERC20TwoPhase } from "../contracts/ERC20TwoPhase.sol";
import { IERC20TwoPhase } from "../contracts/IERC20TwoPhase.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ERC20TwoPhaseTest is Test {
    TwoPhaseToken internal token;

    address internal alice = makeAddr("alice"); // sender
    address internal bob = makeAddr("bob"); // receiver
    address internal eve = makeAddr("eve"); // wrong recipient

    uint64 internal expiry;

    function setUp() public {
        token = new TwoPhaseToken();
        token.mint(alice, 1_000_000 ether);
        expiry = uint64(block.timestamp + 1 hours);
    }

    function _initiate(uint256 amount) internal returns (uint256 id) {
        vm.prank(alice);
        id = token.initiateTransfer(bob, amount, expiry);
    }

    /*──────────────────────── happy path ─────────────────────*/

    function test_initiate_escrowsFromSender() public {
        uint256 amt = 100 ether;
        uint256 before = token.balanceOf(alice);
        uint256 id = _initiate(amt);

        assertEq(token.balanceOf(alice), before - amt, "sender debited");
        assertEq(token.balanceOf(bob), 0, "receiver not yet credited");
        assertEq(token.balanceOf(address(token)), amt, "escrow holds funds");

        IERC20TwoPhase.PendingTransfer memory t = token.pendingTransfer(id);
        assertEq(t.from, alice);
        assertEq(t.to, bob);
        assertEq(t.amount, amt);
        assertEq(uint8(t.status), uint8(IERC20TwoPhase.Status.Pending));
    }

    function test_accept_creditsReceiver() public {
        uint256 amt = 100 ether;
        uint256 id = _initiate(amt);

        vm.prank(bob);
        token.acceptTransfer(id);

        assertEq(token.balanceOf(bob), amt, "receiver credited");
        assertEq(token.balanceOf(address(token)), 0, "escrow drained");
        assertEq(uint8(token.pendingTransfer(id).status), uint8(IERC20TwoPhase.Status.Accepted));
    }

    /*──────────────────────── access control ─────────────────*/

    function test_accept_revert_nonReceiver() public {
        uint256 id = _initiate(100 ether);
        vm.prank(eve);
        vm.expectRevert(IERC20TwoPhase.NotReceiver.selector);
        token.acceptTransfer(id);
    }

    function test_revoke_bySender_refunds() public {
        uint256 amt = 100 ether;
        uint256 before = token.balanceOf(alice);
        uint256 id = _initiate(amt);

        vm.prank(alice);
        token.revokeTransfer(id);

        assertEq(token.balanceOf(alice), before, "sender fully refunded");
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(uint8(token.pendingTransfer(id).status), uint8(IERC20TwoPhase.Status.Revoked));
    }

    function test_revoke_revert_notSender() public {
        uint256 id = _initiate(100 ether);
        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.NotSender.selector);
        token.revokeTransfer(id);
    }

    function test_revoke_revert_afterAccept() public {
        uint256 id = _initiate(100 ether);
        vm.prank(bob);
        token.acceptTransfer(id);

        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.NotPending.selector);
        token.revokeTransfer(id);
    }

    function test_accept_revert_afterRevoke() public {
        uint256 id = _initiate(100 ether);
        vm.prank(alice);
        token.revokeTransfer(id);

        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.NotPending.selector);
        token.acceptTransfer(id);
    }

    /*──────────────────────── expiry / reclaim ───────────────*/

    function test_reclaim_afterExpiry() public {
        uint256 amt = 100 ether;
        uint256 before = token.balanceOf(alice);
        uint256 id = _initiate(amt);

        vm.warp(expiry + 1);
        vm.prank(alice);
        token.reclaimExpired(id);

        assertEq(token.balanceOf(alice), before, "sender reclaimed");
        assertEq(uint8(token.pendingTransfer(id).status), uint8(IERC20TwoPhase.Status.Reclaimed));
    }

    function test_reclaim_revert_beforeExpiry() public {
        uint256 id = _initiate(100 ether);
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.NotExpired.selector);
        token.reclaimExpired(id);
    }

    function test_reclaim_revert_notSender() public {
        uint256 id = _initiate(100 ether);
        vm.warp(expiry + 1);
        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.NotSender.selector);
        token.reclaimExpired(id);
    }

    /*──────────────────────── input validation ───────────────*/

    function test_initiate_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadAmount.selector);
        token.initiateTransfer(bob, 0, expiry);
    }

    function test_initiate_revert_zeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadReceiver.selector);
        token.initiateTransfer(address(0), 1 ether, expiry);
    }

    function test_initiate_revert_selfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadReceiver.selector);
        token.initiateTransfer(alice, 1 ether, expiry);
    }

    function test_initiate_revert_expiryTooShort() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadExpiry.selector);
        token.initiateTransfer(bob, 1 ether, uint64(block.timestamp + 10 minutes - 1));
    }

    function test_initiate_revert_expiryTooLong() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadExpiry.selector);
        token.initiateTransfer(bob, 1 ether, uint64(block.timestamp + 7 days + 1));
    }

    /*──────────────────────── atomic transfer untouched ──────*/

    function test_plainTransfer_staysAtomic() public {
        vm.prank(alice);
        token.transfer(bob, 50 ether);
        assertEq(token.balanceOf(bob), 50 ether, "plain transfer is instant");
    }

    /*──────────────────────── ERC-165 ────────────────────────*/

    function test_supportsInterface() public view {
        assertTrue(token.supportsInterface(type(IERC20TwoPhase).interfaceId));
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
        assertFalse(token.supportsInterface(0xffffffff));
    }

    /*──────────────────────── committed (secret) mode ────────*/

    /// @dev The "secret" is a throwaway PRIVATE KEY delivered out-of-band; only its
    ///      address is committed on-chain. Accepting requires a signature by this key
    ///      over acceptDigest(id, msg.sender) — the key itself never hits calldata.
    uint256 internal constant SECRET_KEY = uint256(keccak256("out-of-band secret key"));

    function _commit() internal pure returns (address) {
        return vm.addr(SECRET_KEY);
    }

    /// @dev Signature the secret key produces for `caller` accepting `id`.
    function _secretSig(uint256 id, address caller) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SECRET_KEY, token.acceptDigest(id, caller));
        return abi.encodePacked(r, s, v);
    }

    function _initiateCommitted(uint256 amount) internal returns (uint256 id) {
        vm.prank(alice);
        id = token.initiateTransferWithCommit(bob, amount, expiry, _commit());
    }

    function test_committed_acceptWithSecretSig_credits() public {
        uint256 amt = 100 ether;
        uint256 id = _initiateCommitted(amt);
        assertEq(token.pendingTransfer(id).commit, _commit(), "commit stored");

        // Sig computed first: _secretSig makes an external view call (acceptDigest),
        // which would otherwise consume the prank meant for acceptTransfer.
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        token.acceptTransfer(id, sig);

        assertEq(token.balanceOf(bob), amt, "receiver credited");
        assertEq(uint8(token.pendingTransfer(id).status), uint8(IERC20TwoPhase.Status.Accepted));
    }

    /// @dev A signature observed in the mempool (or leaked by a mistaken submission)
    ///      is unusable by any other caller: Eve replays Bob's valid signature.
    function test_committed_revert_replayedSigWrongCaller() public {
        uint256 id = _initiateCommitted(100 ether);
        bytes memory bobsSig = _secretSig(id, bob);

        vm.prank(eve);
        vm.expectRevert(IERC20TwoPhase.NotReceiver.selector);
        token.acceptTransfer(id, bobsSig);
    }

    /// @dev The mistaken-submission scenario the raw-preimage design failed: the
    ///      receiver signs for the WRONG account (fat-fingered wallet). That leaked
    ///      calldata contains only a signature over the wrong address — even the
    ///      bound receiver cannot use it, and the secret key remains private.
    function test_committed_revert_sigBoundToWrongAccount() public {
        uint256 id = _initiateCommitted(100 ether);
        bytes memory sigForEve = _secretSig(id, eve); // digest binds eve, not bob

        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.BadSecret.selector);
        token.acceptTransfer(id, sigForEve);
    }

    function test_committed_revert_wrongKeySig() public {
        uint256 id = _initiateCommitted(100 ether);
        uint256 wrongKey = uint256(keccak256("wrong key"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, token.acceptDigest(id, bob));

        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.BadSecret.selector);
        token.acceptTransfer(id, abi.encodePacked(r, s, v));
    }

    function test_committed_revert_garbageSig() public {
        uint256 id = _initiateCommitted(100 ether);
        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.BadSecret.selector);
        token.acceptTransfer(id, hex"deadbeef");
    }

    function test_committed_revert_plainAccept() public {
        uint256 id = _initiateCommitted(100 ether);
        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.SecretRequired.selector);
        token.acceptTransfer(id);
    }

    function test_committed_revert_zeroCommit() public {
        vm.prank(alice);
        vm.expectRevert(IERC20TwoPhase.BadCommit.selector);
        token.initiateTransferWithCommit(bob, 1 ether, expiry, address(0));
    }

    function test_plain_revert_sigAccept() public {
        uint256 id = _initiate(100 ether);
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        vm.expectRevert(IERC20TwoPhase.BadSecret.selector);
        token.acceptTransfer(id, sig);
    }

    function test_committed_revoke_needsNoSecret() public {
        uint256 before = token.balanceOf(alice);
        uint256 id = _initiateCommitted(100 ether);

        vm.prank(alice);
        token.revokeTransfer(id);
        assertEq(token.balanceOf(alice), before, "sender refunded without secret");
    }

    function test_committed_reclaim_needsNoSecret() public {
        uint256 before = token.balanceOf(alice);
        uint256 id = _initiateCommitted(100 ether);

        vm.warp(expiry + 1);
        vm.prank(alice);
        token.reclaimExpired(id);
        assertEq(token.balanceOf(alice), before, "sender reclaimed without secret");
    }

    /*──────────────────────── invariant / fuzz ───────────────*/

    /// @dev totalSupply == sum(balances) + sum(pending). Because pending funds are
    ///      escrowed in the token's own balance, sum(balances) already includes them,
    ///      so totalSupply must stay exactly constant across every lifecycle path.
    function testFuzz_supplyInvariant(uint256 amount, uint8 path) public {
        amount = bound(amount, 1, token.balanceOf(alice));
        uint256 supplyBefore = token.totalSupply();

        uint256 id = _initiate(amount);
        assertEq(token.totalSupply(), supplyBefore, "supply constant after initiate");
        assertEq(
            token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(token)),
            supplyBefore,
            "balances sum to supply while pending"
        );

        path = uint8(bound(path, 0, 2));
        if (path == 0) {
            vm.prank(bob);
            token.acceptTransfer(id);
            assertEq(token.balanceOf(bob), amount);
        } else if (path == 1) {
            vm.prank(alice);
            token.revokeTransfer(id);
        } else {
            vm.warp(expiry + 1);
            vm.prank(alice);
            token.reclaimExpired(id);
        }

        assertEq(token.totalSupply(), supplyBefore, "supply constant after settle");
        assertEq(token.balanceOf(address(token)), 0, "escrow empty after settle");
    }
}
