// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {WhitelistRuleEngine} from "../src/engine/WhitelistRuleEngine.sol";
import {RestrictedToken} from "../src/engine/RestrictedToken.sol";
import {IERC1404Restriction} from "../src/engine/IERC1404Restriction.sol";

/**
 * @notice Tests for the standalone {WhitelistRuleEngine} and a {RestrictedToken} bound to it.
 */
contract WhitelistRuleEngineTest is Test {
    /**
     * @notice Rule engine under test that enforces the whitelist policy.
     */
    WhitelistRuleEngine engine;

    /**
     * @notice Restricted token wired to the engine for end-to-end transfer checks.
     */
    RestrictedToken token;

    /**
     * @notice Deployer and engine owner; holds the initial token supply.
     */
    address owner = address(this);

    /**
     * @notice Sample account used as sender or recipient in tests.
     */
    address alice = makeAddr("alice");

    /**
     * @notice Sample account used as sender or recipient in tests.
     */
    address bob = makeAddr("bob");

    /**
     * @notice Initial token supply minted to the deployer.
     */
    uint256 constant SUPPLY = 1_000_000e18;

    /**
     * @notice Deploys the engine and token, then whitelists the owner so it can move the initial supply.
     */
    function setUp() public {
        engine = new WhitelistRuleEngine();
        token = new RestrictedToken("Restricted", "RST", SUPPLY, engine);
        // Deployer (owner) holds the initial supply; whitelist it so it can move tokens.
        engine.setWhitelisted(owner, true);
    }

    // -------------------------------------------------------------------------
    // detectTransferRestriction — mirrors the table in EXAMPLE_ERC_1404.md
    // -------------------------------------------------------------------------

    /**
     * @notice detectTransferRestriction returns TRANSFER_OK when both parties are whitelisted.
     */
    function test_noRestrictionWhenBothWhitelisted() public {
        engine.setWhitelisted(alice, true);
        engine.setWhitelisted(bob, true);
        assertEq(engine.detectTransferRestriction(alice, bob, 1e18), engine.TRANSFER_OK());
    }

    /**
     * @notice detectTransferRestriction flags SENDER_NOT_WHITELISTED when only the recipient is whitelisted.
     */
    function test_senderNotWhitelisted() public {
        engine.setWhitelisted(bob, true);
        assertEq(engine.detectTransferRestriction(alice, bob, 1e18), engine.SENDER_NOT_WHITELISTED());
    }

    /**
     * @notice detectTransferRestriction flags RECIPIENT_NOT_WHITELISTED when only the sender is whitelisted.
     */
    function test_recipientNotWhitelisted() public {
        engine.setWhitelisted(alice, true);
        assertEq(engine.detectTransferRestriction(alice, bob, 1e18), engine.RECIPIENT_NOT_WHITELISTED());
    }

    // -------------------------------------------------------------------------
    // Whitelist management
    // -------------------------------------------------------------------------

    /**
     * @notice The owner can add an address to the whitelist.
     */
    function test_ownerCanAddToWhitelist() public {
        engine.setWhitelisted(alice, true);
        assertTrue(engine.whitelist(alice));
    }

    /**
     * @notice The owner can remove a previously whitelisted address.
     */
    function test_ownerCanRemoveFromWhitelist() public {
        engine.setWhitelisted(alice, true);
        engine.setWhitelisted(alice, false);
        assertFalse(engine.whitelist(alice));
    }

    /**
     * @notice A non-owner calling setWhitelisted reverts with OwnableUnauthorizedAccount.
     */
    function test_nonOwnerCannotSetWhitelist() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        engine.setWhitelisted(bob, true);
    }

    /**
     * @notice Whitelisting the zero address reverts with AddressZeroNotAllowed.
     */
    function test_setWhitelistedZeroAddressReverts() public {
        vm.expectRevert(WhitelistRuleEngine.AddressZeroNotAllowed.selector);
        engine.setWhitelisted(address(0), true);
    }

    // -------------------------------------------------------------------------
    // Token wired to engine — reverts exactly when the engine returns non-zero
    // -------------------------------------------------------------------------

    /**
     * @notice Constructing a RestrictedToken with a zero engine address reverts with EngineAddressZero.
     */
    function test_constructorRejectsZeroEngine() public {
        vm.expectRevert(RestrictedToken.EngineAddressZero.selector);
        new RestrictedToken("Bad", "BAD", 0, IERC1404Restriction(address(0)));
    }

    /**
     * @notice Transfers succeed between whitelisted accounts and update balances.
     */
    function test_transferSucceedsWhenUnrestricted() public {
        engine.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        engine.setWhitelisted(bob, true);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 50e18));
        assertEq(token.balanceOf(bob), 50e18);
    }

    /**
     * @notice A transfer from a non-whitelisted sender reverts with TransferRestricted (sender not whitelisted).
     */
    function test_transferRevertsWhenSenderNotWhitelisted() public {
        engine.setWhitelisted(bob, true);
        address stranger = makeAddr("stranger");
        deal(address(token), stranger, 10e18);

        // Evaluate the engine view calls before prank so they don't consume it.
        bytes memory expected = abi.encodeWithSelector(
            RestrictedToken.TransferRestricted.selector,
            engine.SENDER_NOT_WHITELISTED(),
            engine.MESSAGE_SENDER_NOT_WHITELISTED()
        );
        vm.expectRevert(expected);
        vm.prank(stranger);
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transfer(bob, 1e18);
    }

    /**
     * @notice A transfer to a non-whitelisted recipient reverts with TransferRestricted (recipient not whitelisted).
     */
    function test_transferRevertsWhenRecipientNotWhitelisted() public {
        // owner is whitelisted in setUp; bob is not
        vm.expectRevert(
            abi.encodeWithSelector(
                RestrictedToken.TransferRestricted.selector,
                engine.RECIPIENT_NOT_WHITELISTED(),
                engine.MESSAGE_RECIPIENT_NOT_WHITELISTED()
            )
        );
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transfer(bob, 1e18);
    }

    /**
     * @notice transferFrom succeeds between whitelisted accounts and updates balances.
     */
    function test_transferFromSucceedsWhenUnrestricted() public {
        engine.setWhitelisted(alice, true);
        engine.setWhitelisted(bob, true);

        assertTrue(token.transfer(alice, 100e18));
        vm.prank(alice);
        token.approve(bob, 50e18);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 50e18));
        assertEq(token.balanceOf(bob), 50e18);
    }

    /**
     * @notice transferFrom to a non-whitelisted recipient reverts with TransferRestricted (recipient not whitelisted).
     */
    function test_transferFromRevertsWhenRecipientNotWhitelisted() public {
        engine.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(owner, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                RestrictedToken.TransferRestricted.selector,
                engine.RECIPIENT_NOT_WHITELISTED(),
                engine.MESSAGE_RECIPIENT_NOT_WHITELISTED()
            )
        );
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transferFrom(alice, bob, 1e18);
    }

    // -------------------------------------------------------------------------
    // Mint / burn — zero-address legs bypass the engine
    // -------------------------------------------------------------------------

    /**
     * @notice Minting to a non-whitelisted account succeeds because issuance bypasses the engine.
     */
    function test_mintBypassesWhitelist() public {
        // alice is not whitelisted, yet issuance to her succeeds
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    /**
     * @notice Burning from a non-whitelisted account succeeds because redemption bypasses the engine.
     */
    function test_burnBypassesWhitelist() public {
        deal(address(token), alice, 10e18);
        token.burn(alice, 10e18);
        assertEq(token.balanceOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // One engine, many tokens — shared rule set
    // -------------------------------------------------------------------------

    /**
     * @notice A single engine enforces the same whitelist across multiple tokens.
     */
    function test_engineSharedAcrossTokens() public {
        RestrictedToken token2 = new RestrictedToken("Restricted2", "RS2", SUPPLY, engine);

        // Whitelisting alice in the single engine unblocks her on both tokens.
        engine.setWhitelisted(alice, true);
        assertTrue(token.transfer(alice, 1e18));
        assertTrue(token2.transfer(alice, 1e18));
        assertEq(token.balanceOf(alice), 1e18);
        assertEq(token2.balanceOf(alice), 1e18);
    }

    // -------------------------------------------------------------------------
    // View-only checks
    // -------------------------------------------------------------------------

    /**
     * @notice detectTransferRestriction checks the sender before the recipient when neither is whitelisted.
     */
    function test_detectChecksFromBeforeTo() public view {
        // neither whitelisted → sender check fires first
        assertEq(engine.detectTransferRestriction(alice, bob, 1e18), engine.SENDER_NOT_WHITELISTED());
    }

    // -------------------------------------------------------------------------
    // messageForTransferRestriction — deterministic, non-empty messages
    // -------------------------------------------------------------------------

    /**
     * @notice messageForTransferRestriction(0) returns the TRANSFER_OK message.
     */
    function test_messageCode0() public view {
        assertEq(engine.messageForTransferRestriction(0), engine.MESSAGE_TRANSFER_OK());
    }

    /**
     * @notice messageForTransferRestriction(1) returns the sender-not-whitelisted message.
     */
    function test_messageCode1() public view {
        assertEq(engine.messageForTransferRestriction(1), engine.MESSAGE_SENDER_NOT_WHITELISTED());
    }

    /**
     * @notice messageForTransferRestriction(2) returns the recipient-not-whitelisted message.
     */
    function test_messageCode2() public view {
        assertEq(engine.messageForTransferRestriction(2), engine.MESSAGE_RECIPIENT_NOT_WHITELISTED());
    }

    /**
     * @notice messageForTransferRestriction returns the unknown-restriction message for an unrecognised code.
     */
    function test_messageUnknownCode() public view {
        assertEq(engine.messageForTransferRestriction(99), engine.MESSAGE_UNKNOWN_RESTRICTION());
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    /**
     * @notice The engine reports support for the ERC-1404 interface id.
     */
    function test_supportsERC1404Interface() public view {
        assertTrue(engine.supportsInterface(0xab84a5c8));
    }

    /**
     * @notice The engine reports support for the ERC-165 interface id.
     */
    function test_supportsERC165Interface() public view {
        assertTrue(engine.supportsInterface(0x01ffc9a7));
    }

    /**
     * @notice The engine reports no support for an unrelated random interface id.
     */
    function test_doesNotSupportRandomInterface() public view {
        assertFalse(engine.supportsInterface(0xdeadbeef));
    }
}
