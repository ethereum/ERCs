// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC1404} from "../src/ERC1404.sol";

contract ERC1404Test is Test {
    ERC1404 token;

    address owner = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new ERC1404("Restricted Token", "RST", SUPPLY);
    }

    // -------------------------------------------------------------------------
    // detectTransferRestriction
    // -------------------------------------------------------------------------

    function test_noRestrictionWhenBothWhitelisted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.TRANSFER_OK());
    }

    function test_senderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.SENDER_NOT_WHITELISTED());
    }

    function test_recipientNotWhitelisted() public {
        token.setWhitelisted(alice, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.RECIPIENT_NOT_WHITELISTED());
    }

    function test_detectChecksFromBeforeTo() public view {
        // alice not whitelisted, bob not whitelisted → sender check fires first
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.SENDER_NOT_WHITELISTED());
    }

    // -------------------------------------------------------------------------
    // messageForTransferRestriction — deterministic human-readable messages
    // -------------------------------------------------------------------------

    function test_messageCode0() public view {
        assertEq(token.messageForTransferRestriction(0), token.MESSAGE_TRANSFER_OK());
    }

    function test_messageCode1() public view {
        assertEq(token.messageForTransferRestriction(1), token.MESSAGE_SENDER_NOT_WHITELISTED());
    }

    function test_messageCode2() public view {
        assertEq(token.messageForTransferRestriction(2), token.MESSAGE_RECIPIENT_NOT_WHITELISTED());
    }

    function test_messageUnknownCode() public view {
        assertEq(token.messageForTransferRestriction(99), token.MESSAGE_UNKNOWN_RESTRICTION());
    }

    // -------------------------------------------------------------------------
    // transfer — succeeds when unrestricted
    // -------------------------------------------------------------------------

    function test_transferSucceedsWhenUnrestricted() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        token.setWhitelisted(bob, true);
        vm.prank(alice);
        bool ok = token.transfer(bob, 50e18);

        assertTrue(ok);
        assertEq(token.balanceOf(bob), 50e18);
    }

    // -------------------------------------------------------------------------
    // transfer — reverts when restricted
    // -------------------------------------------------------------------------

    function test_transferRevertsWhenSenderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        address stranger = makeAddr("stranger");
        deal(address(token), stranger, 10e18);

        vm.prank(stranger);
        vm.expectRevert();
        token.transfer(bob, 1e18);
    }

    function test_transferRevertsWhenRecipientNotWhitelisted() public {
        // owner is whitelisted by construction; bob is not
        vm.expectRevert();
        token.transfer(bob, 1e18);
    }

    // -------------------------------------------------------------------------
    // transferFrom — succeeds when unrestricted
    // -------------------------------------------------------------------------

    function test_transferFromSucceedsWhenUnrestricted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);

        assertTrue(token.transfer(alice, 100e18));
        vm.prank(alice);
        token.approve(bob, 50e18);

        vm.prank(bob);
        bool ok = token.transferFrom(alice, bob, 50e18);
        assertTrue(ok);
        assertEq(token.balanceOf(bob), 50e18);
    }

    // -------------------------------------------------------------------------
    // transferFrom — reverts when restricted
    // -------------------------------------------------------------------------

    function test_transferFromRevertsWhenSenderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        deal(address(token), alice, 10e18);

        vm.prank(alice);
        token.approve(bob, 10e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, 1e18);
    }

    function test_transferFromRevertsWhenRecipientNotWhitelisted() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(owner, 100e18);

        vm.expectRevert();
        token.transferFrom(alice, bob, 1e18);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_supportsERC1404Interface() public view {
        assertTrue(token.supportsInterface(0xab84a5c8));
    }

    function test_supportsERC165Interface() public view {
        assertTrue(token.supportsInterface(0x01ffc9a7));
    }

    function test_doesNotSupportRandomInterface() public view {
        assertFalse(token.supportsInterface(0xdeadbeef));
    }

    // -------------------------------------------------------------------------
    // Whitelist management
    // -------------------------------------------------------------------------

    function test_ownerCanAddToWhitelist() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.whitelist(alice));
    }

    function test_ownerCanRemoveFromWhitelist() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(alice, false);
        assertFalse(token.whitelist(alice));
    }

    function test_nonOwnerCannotSetWhitelist() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.setWhitelisted(bob, true);
    }

    function test_setWhitelistedZeroAddressReverts() public {
        vm.expectRevert(ERC1404.AddressZeroNotAllowed.selector);
        token.setWhitelisted(address(0), true);
    }

    function test_ownerTransferBlockedAfterRemoval() public {
        token.setWhitelisted(owner, false);
        vm.expectRevert();
        token.transfer(alice, 1e18);
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    function test_ownerCanMintToWhitelistedAddress() public {
        token.setWhitelisted(alice, true);
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    function test_mintRevertsWhenRecipientNotWhitelisted() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC1404.TransferRestricted.selector,
                token.RECIPIENT_NOT_WHITELISTED(),
                token.MESSAGE_RECIPIENT_NOT_WHITELISTED()
            )
        );
        token.mint(alice, 500e18);
    }

    function test_nonOwnerCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.mint(alice, 500e18);
    }

    // -------------------------------------------------------------------------
    // Burn
    // -------------------------------------------------------------------------

    function test_ownerCanBurnFromWhitelistedAddress() public {
        token.setWhitelisted(alice, true);
        token.mint(alice, 500e18);
        token.burn(alice, 200e18);
        assertEq(token.balanceOf(alice), 300e18);
    }

    function test_burnRevertsWhenHolderNotWhitelisted() public {
        deal(address(token), alice, 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC1404.TransferRestricted.selector,
                token.SENDER_NOT_WHITELISTED(),
                token.MESSAGE_SENDER_NOT_WHITELISTED()
            )
        );
        token.burn(alice, 10e18);
    }

    function test_nonOwnerCannotBurn() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.burn(owner, 1e18);
    }

    // -------------------------------------------------------------------------
    // Ownership transfer
    // -------------------------------------------------------------------------

    function test_transferOwnership() public {
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);

        vm.prank(alice);
        token.setWhitelisted(bob, true);
        assertTrue(token.whitelist(bob));
    }

    function test_oldOwnerCannotManageAfterTransfer() public {
        token.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        token.setWhitelisted(bob, true);
    }

    function test_transferOwnershipToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        token.transferOwnership(address(0));
    }
}
