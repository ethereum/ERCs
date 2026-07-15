// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { TwoPhaseNFT } from "../contracts/TwoPhaseNFT.sol";
import { ERC721TwoPhase } from "../contracts/ERC721TwoPhase.sol";
import { IERC721TwoPhase } from "../contracts/IERC721TwoPhase.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ERC721TwoPhaseTest is Test {
    TwoPhaseNFT internal nft;

    address internal alice = makeAddr("alice"); // sender / owner
    address internal bob = makeAddr("bob"); // receiver
    address internal eve = makeAddr("eve"); // wrong recipient

    uint256 internal constant TOK = 1;
    uint64 internal expiry;

    function setUp() public {
        nft = new TwoPhaseNFT();
        nft.mint(alice, TOK);
        expiry = uint64(block.timestamp + 1 hours);
    }

    function _initiate() internal returns (uint256 id) {
        vm.prank(alice);
        id = nft.initiateTransfer(bob, TOK, expiry);
    }

    /*──────────────────────── happy path ─────────────────────*/

    function test_initiate_locksButKeepsOwner() public {
        uint256 id = _initiate();

        assertEq(nft.ownerOf(TOK), alice, "owner unchanged while pending");
        assertTrue(nft.isLocked(TOK), "token locked");

        IERC721TwoPhase.PendingTransfer memory t = nft.pendingTransfer(id);
        assertEq(t.from, alice);
        assertEq(t.to, bob);
        assertEq(t.tokenId, TOK);
        assertEq(uint8(t.status), uint8(IERC721TwoPhase.Status.Pending));
    }

    function test_accept_movesOwnership() public {
        uint256 id = _initiate();

        vm.prank(bob);
        nft.acceptTransfer(id);

        assertEq(nft.ownerOf(TOK), bob, "ownership moved to receiver");
        assertFalse(nft.isLocked(TOK), "token unlocked after accept");
        assertEq(uint8(nft.pendingTransfer(id).status), uint8(IERC721TwoPhase.Status.Accepted));
    }

    /*──────────────────────── access control ─────────────────*/

    function test_accept_revert_nonReceiver() public {
        uint256 id = _initiate();
        vm.prank(eve);
        vm.expectRevert(IERC721TwoPhase.NotReceiver.selector);
        nft.acceptTransfer(id);
    }

    function test_revoke_bySender_unlocks() public {
        uint256 id = _initiate();

        vm.prank(alice);
        nft.revokeTransfer(id);

        assertEq(nft.ownerOf(TOK), alice, "owner still sender");
        assertFalse(nft.isLocked(TOK), "unlocked after revoke");
    }

    function test_revoke_revert_notSender() public {
        uint256 id = _initiate();
        vm.prank(bob);
        vm.expectRevert(IERC721TwoPhase.NotSender.selector);
        nft.revokeTransfer(id);
    }

    function test_revoke_revert_afterAccept() public {
        uint256 id = _initiate();
        vm.prank(bob);
        nft.acceptTransfer(id);

        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.NotPending.selector);
        nft.revokeTransfer(id);
    }

    function test_initiate_revert_notOwner() public {
        vm.prank(eve);
        vm.expectRevert(IERC721TwoPhase.NotOwner.selector);
        nft.initiateTransfer(bob, TOK, expiry);
    }

    /*──────────────────────── lock enforcement ───────────────*/

    function test_pendingToken_cannotBeTransferred() public {
        _initiate();
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.TokenLocked.selector);
        nft.transferFrom(alice, eve, TOK);
    }

    function test_pendingToken_cannotBeReInitiated() public {
        _initiate();
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.AlreadyPending.selector);
        nft.initiateTransfer(eve, TOK, expiry);
    }

    function test_unlockedAfterRevoke_transferable() public {
        uint256 id = _initiate();
        vm.prank(alice);
        nft.revokeTransfer(id);

        vm.prank(alice);
        nft.transferFrom(alice, eve, TOK);
        assertEq(nft.ownerOf(TOK), eve, "transferable again once unlocked");
    }

    /*──────────────────────── expiry / reclaim ───────────────*/

    function test_reclaim_afterExpiry() public {
        uint256 id = _initiate();
        vm.warp(expiry + 1);

        vm.prank(alice);
        nft.reclaimExpired(id);

        assertEq(nft.ownerOf(TOK), alice);
        assertFalse(nft.isLocked(TOK));
        assertEq(uint8(nft.pendingTransfer(id).status), uint8(IERC721TwoPhase.Status.Reclaimed));
    }

    function test_reclaim_revert_beforeExpiry() public {
        uint256 id = _initiate();
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.NotExpired.selector);
        nft.reclaimExpired(id);
    }

    /*──────────────────────── input validation ───────────────*/

    function test_initiate_revert_zeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.BadReceiver.selector);
        nft.initiateTransfer(address(0), TOK, expiry);
    }

    function test_initiate_revert_selfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.BadReceiver.selector);
        nft.initiateTransfer(alice, TOK, expiry);
    }

    function test_initiate_revert_expiryTooShort() public {
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.BadExpiry.selector);
        nft.initiateTransfer(bob, TOK, uint64(block.timestamp + 10 minutes - 1));
    }

    function test_initiate_revert_expiryTooLong() public {
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.BadExpiry.selector);
        nft.initiateTransfer(bob, TOK, uint64(block.timestamp + 7 days + 1));
    }

    /*──────────────────────── plain transfer atomic ──────────*/

    function test_plainTransfer_staysAtomic() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, TOK);
        assertEq(nft.ownerOf(TOK), bob, "plain transfer instant when unlocked");
    }

    /*──────────────────────── committed (secret) mode ────────*/

    /// @dev The "secret" is a throwaway PRIVATE KEY delivered out-of-band; only its
    ///      address is committed on-chain (see ERC20 suite for full rationale).
    uint256 internal constant SECRET_KEY = uint256(keccak256("out-of-band secret key"));

    function _commit() internal pure returns (address) {
        return vm.addr(SECRET_KEY);
    }

    function _secretSig(uint256 id, address caller) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SECRET_KEY, nft.acceptDigest(id, caller));
        return abi.encodePacked(r, s, v);
    }

    function _initiateCommitted() internal returns (uint256 id) {
        vm.prank(alice);
        id = nft.initiateTransferWithCommit(bob, TOK, expiry, _commit());
    }

    function test_committed_acceptWithSecretSig_movesOwnership() public {
        uint256 id = _initiateCommitted();
        assertEq(nft.pendingTransfer(id).commit, _commit(), "commit stored");

        // Sig computed first: _secretSig makes an external view call (acceptDigest),
        // which would otherwise consume the prank meant for acceptTransfer.
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        nft.acceptTransfer(id, sig);

        assertEq(nft.ownerOf(TOK), bob, "ownership moved");
        assertFalse(nft.isLocked(TOK), "unlocked after accept");
    }

    /// @dev A signature observed in the mempool is unusable by any other caller.
    function test_committed_revert_replayedSigWrongCaller() public {
        uint256 id = _initiateCommitted();
        bytes memory bobsSig = _secretSig(id, bob);

        vm.prank(eve);
        vm.expectRevert(IERC721TwoPhase.NotReceiver.selector);
        nft.acceptTransfer(id, bobsSig);
    }

    /// @dev Mistaken submission from the wrong account leaks only a signature bound
    ///      to that account — unusable even by the bound receiver; key stays private.
    function test_committed_revert_sigBoundToWrongAccount() public {
        uint256 id = _initiateCommitted();
        bytes memory sigForEve = _secretSig(id, eve);

        vm.prank(bob);
        vm.expectRevert(IERC721TwoPhase.BadSecret.selector);
        nft.acceptTransfer(id, sigForEve);
    }

    function test_committed_revert_wrongKeySig() public {
        uint256 id = _initiateCommitted();
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(uint256(keccak256("wrong key")), nft.acceptDigest(id, bob));

        vm.prank(bob);
        vm.expectRevert(IERC721TwoPhase.BadSecret.selector);
        nft.acceptTransfer(id, abi.encodePacked(r, s, v));
    }

    function test_committed_revert_plainAccept() public {
        uint256 id = _initiateCommitted();
        vm.prank(bob);
        vm.expectRevert(IERC721TwoPhase.SecretRequired.selector);
        nft.acceptTransfer(id);
    }

    function test_committed_revert_zeroCommit() public {
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.BadCommit.selector);
        nft.initiateTransferWithCommit(bob, TOK, expiry, address(0));
    }

    function test_plain_revert_sigAccept() public {
        uint256 id = _initiate();
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        vm.expectRevert(IERC721TwoPhase.BadSecret.selector);
        nft.acceptTransfer(id, sig);
    }

    function test_committed_revoke_needsNoSecret() public {
        uint256 id = _initiateCommitted();
        vm.prank(alice);
        nft.revokeTransfer(id);
        assertEq(nft.ownerOf(TOK), alice, "owner unchanged, no secret needed");
        assertFalse(nft.isLocked(TOK));
    }

    function test_committed_lockStillEnforced() public {
        _initiateCommitted();
        vm.prank(alice);
        vm.expectRevert(IERC721TwoPhase.TokenLocked.selector);
        nft.transferFrom(alice, eve, TOK);
    }

    /*──────────────────────── ERC-165 ────────────────────────*/

    function test_supportsInterface() public view {
        assertTrue(nft.supportsInterface(type(IERC721TwoPhase).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));
        assertFalse(nft.supportsInterface(0xffffffff));
    }
}
