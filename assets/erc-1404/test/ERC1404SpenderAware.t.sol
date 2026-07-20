// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1404SpenderAware} from "../src/ERC1404SpenderAware.sol";
import {ERC1404} from "../src/ERC1404.sol";
import {IERC1404SpenderAware} from "../src/IERC1404SpenderAware.sol";
import {IERC1404} from "../src/IERC1404.sol";

/**
 * @notice Tests for the spender-aware extension added by {ERC1404SpenderAware}.
 * @dev The base whitelist behaviour is already covered by {ERC1404Test}; these tests focus on
 *      `detectTransferRestrictionFrom`, its enforcement in `transferFrom`, and the extension ERC-165 id.
 */
contract ERC1404SpenderAwareTest is Test {
    /**
     * @notice The restricted token instance under test.
     */
    ERC1404SpenderAware token;

    /**
     * @notice The deploying account, which owns the token and is whitelisted by construction.
     */
    address owner = address(this);
    /**
     * @notice Token holder used as the `from` of delegated transfers.
     */
    address alice = makeAddr("alice");
    /**
     * @notice Recipient used as the `to` of delegated transfers.
     */
    address bob = makeAddr("bob");
    /**
     * @notice Operator used as the `spender` of delegated transfers.
     */
    address carol = makeAddr("carol");

    /**
     * @notice The initial total supply minted to the owner at deployment.
     */
    uint256 constant SUPPLY = 1_000_000e18;

    /**
     * @notice Deploys a fresh spender-aware restricted token before each test.
     */
    function setUp() public {
        token = new ERC1404SpenderAware("Restricted Token", "RST", SUPPLY);
    }

    // -------------------------------------------------------------------------
    // detectTransferRestrictionFrom
    // -------------------------------------------------------------------------

    /**
     * @notice Returns TRANSFER_OK when spender, from and to all satisfy the policy.
     */
    function test_detectFrom_okWhenAllWhitelisted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        token.setWhitelisted(carol, true);
        assertEq(token.detectTransferRestrictionFrom(carol, alice, bob, 1e18), token.TRANSFER_OK());
    }

    /**
     * @notice When spender == from, the result equals detectTransferRestriction(from, to, value).
     */
    function test_detectFrom_equalsBaseWhenSpenderIsFrom() public {
        token.setWhitelisted(alice, true);
        // to (bob) not whitelisted -> both should report the recipient code
        assertEq(
            token.detectTransferRestrictionFrom(alice, alice, bob, 1e18),
            token.detectTransferRestriction(alice, bob, 1e18)
        );
        assertEq(token.detectTransferRestrictionFrom(alice, alice, bob, 1e18), token.RECIPIENT_NOT_WHITELISTED());
    }

    /**
     * @notice A spender-specific restriction is reported even when from and to satisfy the policy.
     */
    function test_detectFrom_flagsUnwhitelistedSpender() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        // carol (spender) not whitelisted
        assertEq(token.detectTransferRestrictionFrom(carol, alice, bob, 1e18), token.SPENDER_NOT_WHITELISTED());
        // the base method cannot observe the spender and still reports OK
        assertEq(token.detectTransferRestriction(alice, bob, 1e18), token.TRANSFER_OK());
    }

    /**
     * @notice The base from/to policy takes precedence over the spender check.
     */
    function test_detectFrom_baseRestrictionBeatsSpender() public view {
        // nobody whitelisted except owner; from (alice) fails first
        assertEq(token.detectTransferRestrictionFrom(carol, alice, bob, 1e18), token.SENDER_NOT_WHITELISTED());
    }

    // -------------------------------------------------------------------------
    // transferFrom enforcement
    // -------------------------------------------------------------------------

    /**
     * @notice transferFrom succeeds when spender, from and to are all whitelisted.
     */
    function test_transferFrom_succeedsWhenSpenderWhitelisted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        token.setWhitelisted(carol, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(carol, 50e18);

        vm.prank(carol);
        bool ok = token.transferFrom(alice, bob, 50e18);
        assertTrue(ok);
        assertEq(token.balanceOf(bob), 50e18);
    }

    /**
     * @notice transferFrom reverts with the spender code when the operator is not whitelisted.
     */
    function test_transferFrom_revertsWhenSpenderNotWhitelisted() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(carol, 50e18);

        // Read the expected code/message before pranking, so the view calls don't consume the prank.
        uint8 expectedCode = token.SPENDER_NOT_WHITELISTED();
        string memory expectedMessage = token.MESSAGE_SPENDER_NOT_WHITELISTED();

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(ERC1404.TransferRestricted.selector, expectedCode, expectedMessage));
        // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
        token.transferFrom(alice, bob, 1e18);
    }

    /**
     * @notice A holder spending their own tokens via transferFrom is not blocked by the spender check.
     */
    function test_transferFrom_spenderEqualsFromSucceeds() public {
        token.setWhitelisted(alice, true);
        token.setWhitelisted(bob, true);
        assertTrue(token.transfer(alice, 100e18));

        vm.prank(alice);
        token.approve(alice, 50e18);

        vm.prank(alice);
        bool ok = token.transferFrom(alice, bob, 50e18);
        assertTrue(ok);
        assertEq(token.balanceOf(bob), 50e18);
    }

    // -------------------------------------------------------------------------
    // messageForTransferRestriction
    // -------------------------------------------------------------------------

    /**
     * @notice The extension code maps to its message, and inherited codes still resolve.
     */
    function test_messageForExtensionCode() public view {
        assertEq(token.messageForTransferRestriction(3), token.MESSAGE_SPENDER_NOT_WHITELISTED());
        assertEq(token.messageForTransferRestriction(0), token.MESSAGE_TRANSFER_OK());
        assertEq(token.messageForTransferRestriction(1), token.MESSAGE_SENDER_NOT_WHITELISTED());
        assertEq(token.messageForTransferRestriction(2), token.MESSAGE_RECIPIENT_NOT_WHITELISTED());
        assertEq(token.messageForTransferRestriction(99), token.MESSAGE_UNKNOWN_RESTRICTION());
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    /**
     * @notice supportsInterface reports both the mandatory ERC-1404 id and the extension id.
     */
    function test_supportsBothInterfaceIds() public view {
        assertTrue(token.supportsInterface(0xab84a5c8)); // mandatory ERC-1404
        assertTrue(token.supportsInterface(0x78a8de7d)); // spender-aware extension
        assertTrue(token.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(token.supportsInterface(0xdeadbeef));
    }

    /**
     * @notice The advertised extension id is the explicit exclusive-or of all three selectors, and is
     *         NOT the value Solidity derives from the interface type. `type(I).interfaceId` excludes
     *         inherited selectors, so it covers only `detectTransferRestrictionFrom`. This test pins the
     *         id against accidental drift and documents why it is hardcoded rather than derived.
     */
    function test_extensionIdIsXorOfThreeSelectors() public view {
        bytes4 xorOfThree = IERC1404.detectTransferRestriction.selector
            ^ IERC1404.messageForTransferRestriction.selector
            ^ IERC1404SpenderAware.detectTransferRestrictionFrom.selector;

        assertTrue(xorOfThree == bytes4(0x78a8de7d), "extension id must equal XOR of all three selectors");
        assertTrue(token.supportsInterface(xorOfThree));

        // Footgun guard: type(I).interfaceId covers only the directly declared method, so it must not
        // be used to derive the extension id.
        assertTrue(
            type(IERC1404SpenderAware).interfaceId == IERC1404SpenderAware.detectTransferRestrictionFrom.selector,
            "type().interfaceId should cover only the directly declared method"
        );
        assertTrue(type(IERC1404SpenderAware).interfaceId != bytes4(0x78a8de7d));
    }

    // -------------------------------------------------------------------------
    // Consistency invariant (reporting <-> enforcement)
    // -------------------------------------------------------------------------

    /**
     * @notice For any spender configuration, a non-zero detectTransferRestrictionFrom code holds
     *         if and only if transferFrom is rejected.
     */
    function testFuzz_reportMatchesEnforcement(bool wlFrom, bool wlTo, bool wlSpender) public {
        if (wlFrom) token.setWhitelisted(alice, true);
        if (wlTo) token.setWhitelisted(bob, true);
        if (wlSpender) token.setWhitelisted(carol, true);

        // fund alice regardless (owner is whitelisted, so transfer to alice needs alice whitelisted;
        // use deal to sidestep the funding path and isolate the transferFrom policy check)
        deal(address(token), alice, 10e18);
        vm.prank(alice);
        token.approve(carol, 10e18);

        uint8 code = token.detectTransferRestrictionFrom(carol, alice, bob, 1e18);

        // TRANSFER_OK is 0; compare against the literal to avoid a view call consuming the prank below.
        if (code == 0) {
            vm.prank(carol);
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            assertTrue(token.transferFrom(alice, bob, 1e18));
        } else {
            vm.prank(carol);
            vm.expectRevert();
            // forge-lint: disable-next-line(erc20-unchecked-transfer) — call is expected to revert
            token.transferFrom(alice, bob, 1e18);
        }
    }
}
