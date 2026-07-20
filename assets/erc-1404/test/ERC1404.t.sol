// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC1404} from "../src/ERC1404.sol";

/**
 * @notice Tests for the {ERC1404} whitelist-restricted token.
 */
contract ERC1404Test is Test {
    /**
     * @notice The restricted token instance under test.
     */
    ERC1404 token;

    /**
     * @notice The deploying account, which owns the token.
     */
    address owner = address(this);
    /**
     * @notice A test account used as a token sender/recipient.
     */
    address alice = makeAddr("alice");
    /**
     * @notice A test account used as a token sender/recipient.
     */
    address bob = makeAddr("bob");

    /**
     * @notice The initial total supply minted to the owner at deployment.
     */
    uint256 constant SUPPLY = 1_000_000e18;

    /**
     * @notice Deploys a fresh restricted token before each test.
     */
    function setUp() public {
        token = new ERC1404("Restricted Token", "RST", SUPPLY);
    }

    // -------------------------------------------------------------------------
    // Non-view tests
    // -------------------------------------------------------------------------

    /**
     * @notice detectTransferRestriction returns TRANSFER_OK when both parties are whitelisted.
     */
    function test_noRestrictionWhenBothWhitelisted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.TRANSFER_OK());
    }

    /**
     * @notice detectTransferRestriction flags a sender that is not whitelisted.
     */
    function test_senderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.SENDER_NOT_WHITELISTED());
    }

    /**
     * @notice detectTransferRestriction flags a recipient that is not whitelisted.
     */
    function test_recipientNotWhitelisted() public {
        token.setWhitelisted(alice, true);
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.RECIPIENT_NOT_WHITELISTED());
    }

    /**
     * @notice A transfer succeeds and updates balances when the transfer is unrestricted.
     */
    function test_transferSucceedsWhenUnrestricted() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        token.setWhitelisted(bob, true);
        vm.prank(alice);
        bool ok = token.transfer(bob, 50e18);

        assertTrue(ok);
        assertEq(token.balanceOf(bob), 50e18);
    }

    /**
     * @notice A transfer reverts when the sender is not whitelisted.
     */
    function test_transferRevertsWhenSenderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        address stranger = makeAddr("stranger");
        deal(address(token), stranger, 10e18);

        vm.prank(stranger);
        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transfer(bob, 1e18);
    }

    /**
     * @notice A transfer reverts when the recipient is not whitelisted.
     */
    function test_transferRevertsWhenRecipientNotWhitelisted() public {
        // owner is whitelisted by construction; bob is not
        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transfer(bob, 1e18);
    }

    /**
     * @notice A transferFrom succeeds and updates balances when the transfer is unrestricted.
     */
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

    /**
     * @notice A transferFrom reverts when the source account is not whitelisted.
     */
    function test_transferFromRevertsWhenSenderNotWhitelisted() public {
        token.setWhitelisted(bob, true);
        deal(address(token), alice, 10e18);

        vm.prank(alice);
        token.approve(bob, 10e18);

        vm.prank(bob);
        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transferFrom(alice, bob, 1e18);
    }

    /**
     * @notice A transferFrom reverts when the recipient is not whitelisted.
     */
    function test_transferFromRevertsWhenRecipientNotWhitelisted() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(owner, 100e18);

        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transferFrom(alice, bob, 1e18);
    }

    /**
     * @notice The owner can add an address to the whitelist.
     */
    function test_ownerCanAddToWhitelist() public {
        token.setWhitelisted(alice, true);
        assertTrue(token.whitelist(alice));
    }

    /**
     * @notice The owner can remove an address from the whitelist.
     */
    function test_ownerCanRemoveFromWhitelist() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(alice, false);
        assertFalse(token.whitelist(alice));
    }

    /**
     * @notice A non-owner cannot modify the whitelist.
     */
    function test_nonOwnerCannotSetWhitelist() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.setWhitelisted(bob, true);
    }

    /**
     * @notice Whitelisting the zero address reverts.
     */
    function test_setWhitelistedZeroAddressReverts() public {
        vm.expectRevert(ERC1404.AddressZeroNotAllowed.selector);
        token.setWhitelisted(address(0), true);
    }

    /**
     * @notice The owner cannot transfer once removed from the whitelist.
     */
    function test_ownerTransferBlockedAfterRemoval() public {
        token.setWhitelisted(owner, false);
        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transfer(alice, 1e18);
    }

    /**
     * @notice The owner can mint tokens to a whitelisted address.
     */
    function test_ownerCanMintToWhitelistedAddress() public {
        token.setWhitelisted(alice, true);
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    /**
     * @notice Minting to a non-whitelisted recipient reverts with a restriction error.
     */
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

    /**
     * @notice A non-owner cannot mint tokens.
     */
    function test_nonOwnerCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.mint(alice, 500e18);
    }

    /**
     * @notice The owner can burn tokens from a whitelisted address.
     */
    function test_ownerCanBurnFromWhitelistedAddress() public {
        token.setWhitelisted(alice, true);
        token.mint(alice, 500e18);
        token.burn(alice, 200e18);
        assertEq(token.balanceOf(alice), 300e18);
    }

    /**
     * @notice Burning from a non-whitelisted holder reverts with a restriction error.
     */
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

    /**
     * @notice A non-owner cannot burn tokens.
     */
    function test_nonOwnerCannotBurn() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.burn(owner, 1e18);
    }

    /**
     * @notice Ownership transfer moves owner-only privileges to the new owner.
     */
    function test_transferOwnership() public {
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);

        vm.prank(alice);
        token.setWhitelisted(bob, true);
        assertTrue(token.whitelist(bob));
    }

    /**
     * @notice The previous owner loses management rights after ownership transfer.
     */
    function test_oldOwnerCannotManageAfterTransfer() public {
        token.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        token.setWhitelisted(bob, true);
    }

    /**
     * @notice Transferring ownership to the zero address reverts.
     */
    function test_transferOwnershipToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        token.transferOwnership(address(0));
    }

    // -------------------------------------------------------------------------
    // View tests
    // -------------------------------------------------------------------------

    /**
     * @notice detectTransferRestriction checks the sender before the recipient.
     */
    function test_detectChecksFromBeforeTo() public view {
        // alice not whitelisted, bob not whitelisted → sender check fires first
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.SENDER_NOT_WHITELISTED());
    }

    /**
     * @notice messageForTransferRestriction returns the OK message for code 0.
     */
    function test_messageCode0() public view {
        assertEq(token.messageForTransferRestriction(0), token.MESSAGE_TRANSFER_OK());
    }

    /**
     * @notice messageForTransferRestriction returns the sender-not-whitelisted message for code 1.
     */
    function test_messageCode1() public view {
        assertEq(token.messageForTransferRestriction(1), token.MESSAGE_SENDER_NOT_WHITELISTED());
    }

    /**
     * @notice messageForTransferRestriction returns the recipient-not-whitelisted message for code 2.
     */
    function test_messageCode2() public view {
        assertEq(token.messageForTransferRestriction(2), token.MESSAGE_RECIPIENT_NOT_WHITELISTED());
    }

    /**
     * @notice messageForTransferRestriction returns the unknown-restriction message for an unrecognised code.
     */
    function test_messageUnknownCode() public view {
        assertEq(token.messageForTransferRestriction(99), token.MESSAGE_UNKNOWN_RESTRICTION());
    }

    /**
     * @notice supportsInterface reports support for the ERC-1404 interface id.
     */
    function test_supportsERC1404Interface() public view {
        assertTrue(token.supportsInterface(0xab84a5c8));
    }

    /**
     * @notice supportsInterface reports support for the ERC-165 interface id.
     */
    function test_supportsERC165Interface() public view {
        assertTrue(token.supportsInterface(0x01ffc9a7));
    }

    /**
     * @notice supportsInterface returns false for an unsupported interface id.
     */
    function test_doesNotSupportRandomInterface() public view {
        assertFalse(token.supportsInterface(0xdeadbeef));
    }
}
