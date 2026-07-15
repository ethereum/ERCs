// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { TwoPhaseEscrow } from "../contracts/TwoPhaseEscrow.sol";
import { ITwoPhaseEscrow } from "../contracts/ITwoPhaseEscrow.sol";
import { MockERC20 } from "../contracts/MockERC20.sol";
import { MockERC721 } from "../contracts/MockERC721.sol";
import { Mock1155 } from "../contracts/Mock1155.sol";

contract TwoPhaseEscrowTest is Test {
    TwoPhaseEscrow internal escrow;
    MockERC20 internal erc20;
    MockERC721 internal erc721;
    Mock1155 internal erc1155;

    address internal alice = makeAddr("alice"); // sender
    address internal bob = makeAddr("bob"); // receiver
    address internal eve = makeAddr("eve"); // wrong recipient

    uint256 internal constant TOK = 1;
    uint64 internal expiry;

    uint256 internal constant SECRET_KEY = uint256(keccak256("out-of-band secret key"));

    function setUp() public {
        escrow = new TwoPhaseEscrow();
        erc20 = new MockERC20();
        erc721 = new MockERC721();
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

    /*──────────────────────── helpers ────────────────────────*/

    function _commit() internal pure returns (address) {
        return vm.addr(SECRET_KEY);
    }

    function _secretSig(uint256 id, address caller) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SECRET_KEY, escrow.acceptDigest(id, caller));
        return abi.encodePacked(r, s, v);
    }

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

    function _initiate(ITwoPhaseEscrow.Asset memory asset) internal returns (uint256 id) {
        uint256 value = asset.kind == ITwoPhaseEscrow.AssetType.Native ? asset.amount : 0;
        vm.prank(alice);
        id = escrow.initiateTransfer{ value: value }(asset, bob, expiry, _commit());
    }

    function _accept(uint256 id) internal {
        // Sig computed first: _secretSig makes an external view call (acceptDigest),
        // which would otherwise consume the prank meant for acceptTransfer.
        bytes memory sig = _secretSig(id, bob);
        vm.prank(bob);
        escrow.acceptTransfer(id, sig);
    }

    /*──────────────────────── native ETH ─────────────────────*/

    function test_native_initiateAccept() public {
        uint256 id = _initiate(_native(5 ether));

        assertEq(address(escrow).balance, 5 ether, "escrow holds ETH");
        assertEq(bob.balance, 0);

        _accept(id);

        assertEq(bob.balance, 5 ether, "receiver paid");
        assertEq(address(escrow).balance, 0, "escrow drained");
    }

    function test_native_revoke_refunds() public {
        uint256 id = _initiate(_native(5 ether));

        vm.prank(alice);
        escrow.revokeTransfer(id);
        assertEq(alice.balance, 100 ether, "sender fully refunded");
    }

    function test_native_reclaim_afterExpiry() public {
        uint256 id = _initiate(_native(5 ether));

        vm.warp(expiry + 1);
        vm.prank(alice);
        escrow.reclaimExpired(id);
        assertEq(alice.balance, 100 ether, "sender reclaimed");
    }

    function test_native_revert_valueMismatch() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer{ value: 1 ether }(_native(5 ether), bob, expiry, _commit());
    }

    /*──────────────────────── ERC-20 ─────────────────────────*/

    function test_erc20_initiateAccept() public {
        uint256 id = _initiate(_asset20(100 ether));

        assertEq(erc20.balanceOf(address(escrow)), 100 ether, "escrow holds tokens");

        _accept(id);
        assertEq(erc20.balanceOf(bob), 100 ether, "receiver credited");
    }

    function test_erc20_revert_valueSent() public {
        vm.deal(alice, 101 ether);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer{ value: 1 ether }(_asset20(100 ether), bob, expiry, _commit());
    }

    /*──────────────────────── ERC-721 ────────────────────────*/

    function test_erc721_initiateAccept() public {
        uint256 id = _initiate(_asset721());

        assertEq(erc721.ownerOf(TOK), address(escrow), "escrow holds NFT");

        _accept(id);
        assertEq(erc721.ownerOf(TOK), bob, "receiver owns NFT");
    }

    function test_erc721_revert_amountNotOne() public {
        ITwoPhaseEscrow.Asset memory a = _asset721();
        a.amount = 2;
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAmount.selector);
        escrow.initiateTransfer(a, bob, expiry, _commit());
    }

    /*──────────────────────── ERC-1155 ───────────────────────*/

    function test_erc1155_initiateAccept() public {
        uint256 id = _initiate(_asset1155(20));

        assertEq(erc1155.balanceOf(address(escrow), TOK), 20, "escrow holds units");

        _accept(id);
        assertEq(erc1155.balanceOf(bob, TOK), 20, "receiver credited");
    }

    /*──────────────────────── access control ─────────────────*/

    function test_accept_revert_nonReceiver() public {
        uint256 id = _initiate(_native(1 ether));

        bytes memory sig = _secretSig(id, eve);
        vm.prank(eve);
        vm.expectRevert(ITwoPhaseEscrow.NotReceiver.selector);
        escrow.acceptTransfer(id, sig);
    }

    function test_revoke_revert_notSender() public {
        uint256 id = _initiate(_native(1 ether));

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.NotSender.selector);
        escrow.revokeTransfer(id);
    }

    /*──────────────────────── secret proof ───────────────────*/

    /// @dev A signature observed in the mempool is unusable by any other caller.
    function test_revert_replayedSigWrongCaller() public {
        uint256 id = _initiate(_native(5 ether));
        bytes memory bobsSig = _secretSig(id, bob);

        vm.prank(eve);
        vm.expectRevert(ITwoPhaseEscrow.NotReceiver.selector);
        escrow.acceptTransfer(id, bobsSig);
    }

    /// @dev Mistaken submission from the wrong account leaks only a signature bound
    ///      to that account: unusable even by the bound receiver; key stays private.
    function test_revert_sigBoundToWrongAccount() public {
        uint256 id = _initiate(_native(5 ether));
        bytes memory sigForEve = _secretSig(id, eve);

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.BadSecret.selector);
        escrow.acceptTransfer(id, sigForEve);
    }

    function test_revert_wrongKeySig() public {
        uint256 id = _initiate(_native(5 ether));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(uint256(keccak256("wrong key")), escrow.acceptDigest(id, bob));
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.BadSecret.selector);
        escrow.acceptTransfer(id, badSig);
    }

    function test_revert_garbageSig() public {
        uint256 id = _initiate(_native(5 ether));

        vm.prank(bob);
        vm.expectRevert(ITwoPhaseEscrow.BadSecret.selector);
        escrow.acceptTransfer(id, hex"deadbeef");
    }

    function test_revert_zeroCommit() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadCommit.selector);
        escrow.initiateTransfer{ value: 1 ether }(_native(1 ether), bob, expiry, address(0));
    }

    function test_revokeAndReclaim_needNoSecret() public {
        uint256 id = _initiate(_native(1 ether));
        vm.prank(alice);
        escrow.revokeTransfer(id);

        expiry = uint64(block.timestamp + 1 hours);
        uint256 id2 = _initiate(_native(1 ether));
        vm.warp(expiry + 1);
        vm.prank(alice);
        escrow.reclaimExpired(id2);

        assertEq(alice.balance, 100 ether, "sender got everything back without the secret");
    }

    /*──────────────────────── input validation ───────────────*/

    function test_revert_nativeWithTokenAddress() public {
        ITwoPhaseEscrow.Asset memory a = _native(1 ether);
        a.token = address(erc20);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAsset.selector);
        escrow.initiateTransfer{ value: 1 ether }(a, bob, expiry, _commit());
    }

    function test_revert_erc20ZeroToken() public {
        ITwoPhaseEscrow.Asset memory a =
            ITwoPhaseEscrow.Asset(ITwoPhaseEscrow.AssetType.ERC20, address(0), 0, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadAsset.selector);
        escrow.initiateTransfer(a, bob, expiry, _commit());
    }

    function test_revert_selfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadReceiver.selector);
        escrow.initiateTransfer{ value: 1 ether }(_native(1 ether), alice, expiry, _commit());
    }

    function test_revert_expiryOutOfBounds() public {
        vm.startPrank(alice);
        vm.expectRevert(ITwoPhaseEscrow.BadExpiry.selector);
        escrow.initiateTransfer{ value: 1 ether }(
            _native(1 ether), bob, uint64(block.timestamp + 10 minutes - 1), _commit()
        );
        vm.expectRevert(ITwoPhaseEscrow.BadExpiry.selector);
        escrow.initiateTransfer{ value: 1 ether }(
            _native(1 ether), bob, uint64(block.timestamp + 7 days + 1), _commit()
        );
        vm.stopPrank();
    }

    /*──────────────────────── ETH containment ────────────────*/

    function test_noStrayEth_directSendReverts() public {
        vm.prank(alice);
        (bool ok,) = address(escrow).call{ value: 1 ether }("");
        assertFalse(ok, "no receive(): ETH enters only via initiate");
    }

    function test_supportsInterface() public view {
        assertTrue(escrow.supportsInterface(type(ITwoPhaseEscrow).interfaceId));
    }
}
