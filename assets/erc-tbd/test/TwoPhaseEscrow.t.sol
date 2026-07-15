// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { TwoPhaseEscrow } from "../contracts/TwoPhaseEscrow.sol";
import { ITwoPhaseEscrow } from "../contracts/ITwoPhaseEscrow.sol";
import { TwoPhaseToken } from "../contracts/TwoPhaseToken.sol";
import { TwoPhaseNFT } from "../contracts/TwoPhaseNFT.sol";
import { Mock1155 } from "../contracts/Mock1155.sol";

contract TwoPhaseEscrowTest is Test {
    TwoPhaseEscrow internal escrow;
    TwoPhaseToken internal erc20;
    TwoPhaseNFT internal erc721;
    Mock1155 internal erc1155;

    address internal alice = makeAddr("alice"); // sender
    address internal bob = makeAddr("bob"); // receiver
    address internal eve = makeAddr("eve"); // wrong recipient

    uint256 internal constant TOK = 1;
    uint64 internal expiry;

    function setUp() public {
        escrow = new TwoPhaseEscrow();
        erc20 = new TwoPhaseToken();
        erc721 = new TwoPhaseNFT();
        erc1155 = new Mock1155();

        vm.deal(alice, 100 ether);
        erc20.mint(alice, 1000 ether);
        erc721.mint(alice, TOK);
        erc1155.mint(alice, TOK, 50);

        vm.startPrank(alice);
        erc20.approve(address(escrow), type(uint256).max);
        erc721.approve(address(escrow), TOK);
        erc1155.setApprovalForAll(address(escrow), true);
        vm.stopPrank();

        expiry = uint64(block.timestamp + 1 hours);
    }

    /*──────────────────────── asset helpers ──────────────────*/

    function _native(uint256 amount) internal pure returns (ITwoPhaseEscrow.Asset memory) {
        return ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.Native, address(0), 0, amount);
    }

    function _asset20(uint256 amount) internal view returns (ITwoPhaseEscrow.Asset memory) {
        return ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.ERC20, address(erc20), 0, amount);
    }

    function _asset721() internal view returns (ITwoPhaseEscrow.Asset memory) {
        return ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.ERC721, address(erc721), TOK, 1);
    }

    function _asset1155(uint256 amount) internal view returns (ITwoPhaseEscrow.Asset memory) {
        return
            ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.ERC1155, address(erc1155), TOK, amount);
    }

    /*──────────────────────── native ETH ─────────────────────*/

    function test_native_initiateAccept() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer{ value: 5 ether }(_native(5 ether), bob, expiry);

        assertEq(address(escrow).balance, 5 ether, "escrow holds ETH");
        assertEq(bob.balance, 0);

        vm.prank(bob);
        escrow.acceptTransfer(id);

        assertEq(bob.balance, 5 ether, "receiver paid");
        assertEq(address(escrow).balance, 0, "escrow drained");
    }

    function test_native_revoke_refunds() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer{ value: 5 ether }(_native(5 ether), bob, expiry);

        vm.prank(alice);
        escrow.revokeTransfer(id);
        assertEq(alice.balance, 100 ether, "sender fully refunded");
    }

    function test_native_reclaim_afterExpiry() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer{ value: 5 ether }(_native(5 ether), bob, expiry);

        vm.warp(expiry + 1);
        vm.prank(alice);
        escrow.reclaimExpired(id);
        assertEq(alice.balance, 100 ether, "sender reclaimed");
    }

    function test_native_revert_valueMismatch() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer{ value: 1 ether }(_native(5 ether), bob, expiry);
    }

    /*──────────────────────── ERC-20 ─────────────────────────*/

    function test_erc20_initiateAccept() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer(_asset20(100 ether), bob, expiry);

        assertEq(erc20.balanceOf(address(escrow)), 100 ether, "escrow holds tokens");

        vm.prank(bob);
        escrow.acceptTransfer(id);
        assertEq(erc20.balanceOf(bob), 100 ether, "receiver credited");
    }

    function test_erc20_revert_valueSent() public {
        vm.deal(alice, 101 ether);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer{ value: 1 ether }(_asset20(100 ether), bob, expiry);
    }

    /*──────────────────────── ERC-721 ────────────────────────*/

    function test_erc721_initiateAccept() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer(_asset721(), bob, expiry);

        assertEq(erc721.ownerOf(TOK), address(escrow), "escrow holds NFT");

        vm.prank(bob);
        escrow.acceptTransfer(id);
        assertEq(erc721.ownerOf(TOK), bob, "receiver owns NFT");
    }

    function test_erc721_revert_amountNotOne() public {
        ITwoPhaseEscrow.Asset memory a = _asset721();
        a.amount = 2;
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer(a, bob, expiry);
    }

    /*──────────────────────── ERC-1155 ───────────────────────*/

    function test_erc1155_initiateAccept() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer(_asset1155(20), bob, expiry);

        assertEq(erc1155.balanceOf(address(escrow), TOK), 20, "escrow holds units");

        vm.prank(bob);
        escrow.acceptTransfer(id);
        assertEq(erc1155.balanceOf(bob, TOK), 20, "receiver credited");
    }

    /*──────────────────────── access control ─────────────────*/

    function test_accept_revert_nonReceiver() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer{ value: 1 ether }(_native(1 ether), bob, expiry);

        vm.prank(eve);
        vm.expectRevert(ITwoPhaseEscrow.NotReceiver.selector);
        escrow.acceptTransfer(id);
    }

    function test_revoke_revert_notSender() public {
        vm.prank(alice);
        uint256 id = escrow.initiateTransfer{ value: 1 ether }(_native(1 ether), bob, expiry);

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.NotSender.selector);
        escrow.revokeTransfer(id);
    }

    /*──────────────────────── committed (secret) mode ────────*/

    uint256 internal constant SECRET_KEY = uint256(keccak256("out-of-band secret key"));

    function _commit() internal pure returns (address) {
        return vm.addr(SECRET_KEY);
    }

    function _secretSig(uint256 id, address caller) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SECRET_KEY, escrow.acceptDigest(id, caller));
        return abi.encodePacked(r, s, v);
    }

    function _initiateCommittedNative() internal returns (uint256 id) {
        vm.prank(alice);
        id = escrow.initiateTransferWithCommit{ value: 5 ether }(
            _native(5 ether), bob, expiry, _commit()
        );
    }

    function test_committed_acceptWithSecretSig() public {
        uint256 id = _initiateCommittedNative();

        // Sig computed first: _secretSig makes an external view call (acceptDigest),
        // which would otherwise consume the prank meant for acceptTransfer.
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        escrow.acceptTransfer(id, sig);
        assertEq(bob.balance, 5 ether, "receiver paid");
    }

    /// @dev A signature observed in the mempool is unusable by any other caller.
    function test_committed_revert_replayedSigWrongCaller() public {
        uint256 id = _initiateCommittedNative();
        bytes memory bobsSig = _secretSig(id, bob);

        vm.prank(eve);
        vm.expectRevert(ITwoPhaseEscrow.NotReceiver.selector);
        escrow.acceptTransfer(id, bobsSig);
    }

    /// @dev Mistaken submission from the wrong account leaks only a signature bound
    ///      to that account — unusable even by the bound receiver; key stays private.
    function test_committed_revert_sigBoundToWrongAccount() public {
        uint256 id = _initiateCommittedNative();
        bytes memory sigForEve = _secretSig(id, eve);

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.BadSecret.selector);
        escrow.acceptTransfer(id, sigForEve);
    }

    function test_committed_revert_plainAccept() public {
        uint256 id = _initiateCommittedNative();
        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.SecretRequired.selector);
        escrow.acceptTransfer(id);
    }

    function test_committed_revert_zeroCommit() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadCommit.selector);
        escrow.initiateTransferWithCommit{ value: 1 ether }(
            _native(1 ether), bob, expiry, address(0)
        );
    }

    /*──────────────────────── input validation ───────────────*/

    function test_revert_nativeWithTokenAddress() public {
        ITwoPhaseEscrow.Asset memory a = _native(1 ether);
        a.token = address(erc20);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAsset.selector);
        escrow.initiateTransfer{ value: 1 ether }(a, bob, expiry);
    }

    function test_revert_erc20ZeroToken() public {
        ITwoPhaseEscrow.Asset memory a =
            ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.ERC20, address(0), 0, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAsset.selector);
        escrow.initiateTransfer(a, bob, expiry);
    }

    function test_revert_selfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadReceiver.selector);
        escrow.initiateTransfer{ value: 1 ether }(_native(1 ether), alice, expiry);
    }

    function test_revert_expiryOutOfBounds() public {
        vm.startPrank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadExpiry.selector);
        escrow.initiateTransfer{ value: 1 ether }(
            _native(1 ether), bob, uint64(block.timestamp + 10 minutes - 1)
        );
        vm.expectRevert(ITwoPhaseEscrow.BadExpiry.selector);
        escrow.initiateTransfer{ value: 1 ether }(
            _native(1 ether), bob, uint64(block.timestamp + 7 days + 1)
        );
        vm.stopPrank();
    }

    /*──────────────────────── ETH containment ────────────────*/

    function test_noStrayEth_directSendReverts() public {
        vm.prank(alice);
        (bool ok,) = address(escrow).call{ value: 1 ether }("");
        assertFalse(ok, "no receive(): ETH enters only via initiate");
    }
}
