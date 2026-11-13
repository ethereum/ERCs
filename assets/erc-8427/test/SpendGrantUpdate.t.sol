// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Changing a registered grant, end to end: the delegate spends a token through the executor by id. An
/// update changes one grant in place and keeps its usage, so a lowered lifetime cap holds with no sizing and the
/// window does not restart. Separate grants still stack until the earlier one is revoked. A new grant, which a
/// change of delegate or window needs, starts with no usage.
/// @dev Replaces SpendGrantReplacement.t.sol. Its test that a replacement held back from the delegate cannot be
/// spent is superseded: a grant exists only once registered, so there is no signed replacement to hold back.
contract SpendGrantUpdateTest is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    uint64 internal constant WINDOW = 1 days;
    uint256 internal constant FUNDS = 1_000_000;

    SpendGrantRegistry internal registry;
    SpendGrantExecutor internal executor;
    MockERC20 internal token;
    address internal principal;
    address internal delegate;
    address internal delegate2;
    address internal payee;

    function setUp() public {
        vm.warp(1_700_000_000);
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        delegate2 = makeAddr("delegate2");
        payee = makeAddr("payee");
        token = new MockERC20();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        registry = new SpendGrantRegistry(predicted);
        executor = new SpendGrantExecutor(registry);
        assertEq(address(executor), predicted);
        token.mint(principal, FUNDS);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);
    }

    /// ted0x's case: maxTotal 1000, 700 spent, update to 800. The delegate keeps the id and can spend 100 more,
    /// and the principal did no arithmetic: the caps in force are the current terms', over all usage since
    /// registration.
    function test_update_loweredLifetimeCapStopsSpendingAt800() public {
        SpendGrant memory g = _terms(1, 1000, 1000, 1000, delegate);
        bytes32 id = _register(g);
        _spend(delegate, id, 700);

        // A window later, so only the lifetime cap can bind.
        vm.warp(vm.getBlockTimestamp() + WINDOW);
        g.assets[0] = AssetLimit(address(token), 800, 800, 800);
        vm.prank(principal);
        registry.update(id, 1, g);
        (, uint256 version,,,) = registry.getGrant(id);
        assertEq(version, 2);

        _assertCheck(id, delegate, 101, 10);
        _spend(delegate, id, 100);
        assertEq(token.balanceOf(payee), 800);
        assertEq(token.balanceOf(principal), FUNDS - 800);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 800);
        assertEq(calls, 2);

        vm.prank(delegate);
        vm.expectRevert(_err(10)); // OVER_CUMULATIVE_CAP
        executor.spend(id, address(token), 1, payee);
    }

    /// An update does not restart the window: spends from before it count against the window cap in force and
    /// expire on their own schedule. With 200 unexpired, raising the window cap from 200 to 250 lets exactly 50
    /// more through, not 250, and the first spend leaves the window a window after it was made.
    function test_update_windowDoesNotRestart() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _terms(1, 200, 200, 5000, delegate);
        bytes32 id = _register(g);
        _spend(delegate, id, 100);
        vm.warp(t0 + 100);
        _spend(delegate, id, 100);

        vm.warp(t0 + 200);
        g.assets[0] = AssetLimit(address(token), 250, 250, 5000);
        vm.prank(principal);
        registry.update(id, 1, g);
        (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, address(token));
        assertEq(windowSpent, 200);
        assertEq(live, 2);
        _assertCheck(id, delegate, 51, 9);
        _spend(delegate, id, 50);

        vm.warp(t0 + WINDOW - 1);
        _assertCheck(id, delegate, 1, 9);
        vm.warp(t0 + WINDOW);
        _spend(delegate, id, 100);
        assertEq(token.balanceOf(payee), 350);

        vm.prank(delegate);
        vm.expectRevert(_err(9)); // OVER_WINDOW_CAP: 100 + 50 + 100 unexpired
        executor.spend(id, address(token), 1, payee);
    }

    /// Two registered grants to one delegate are two ids with two budgets: both spend in one window, together
    /// past either grant's window cap, until the principal revokes the earlier one. Only the revocation ends it.
    function test_separateGrantsStackUntilTheEarlierIsRevoked() public {
        bytes32 earlier = _register(_terms(1, 100, 200, 1000, delegate));
        bytes32 later = _register(_terms(2, 10, 20, 100, delegate));
        assertTrue(earlier != later);

        _spend(delegate, earlier, 100);
        _spend(delegate, later, 10);
        assertEq(token.balanceOf(payee), 110);
        _assertCheck(earlier, delegate, 100, 0);

        vm.prank(principal);
        registry.revoke(earlier);
        _spend(delegate, later, 10);
        assertEq(token.balanceOf(payee), 120);

        vm.prank(delegate);
        vm.expectRevert(_err(5)); // REVOKED, with 100 of window room left
        executor.spend(earlier, address(token), 1, payee);
    }

    /// The fresh-usage case: changing the delegate (a key rotation) takes revoke + register, and the new id starts
    /// with no lifetime or window usage. The old grant spent 700 of 1000; a new grant to the new key with
    /// maxTotal 800 spends 800 more in the same window, 1500 across the two.
    function test_rotation_newGrantStartsWithZeroUsage() public {
        bytes32 old = _register(_terms(1, 1000, 1000, 1000, delegate));
        _spend(delegate, old, 700);
        vm.prank(principal);
        registry.revoke(old);
        (uint256 oldSpent,) = registry.usage(old, address(token));
        assertEq(oldSpent, 700);

        bytes32 rotated = _register(_terms(2, 800, 800, 800, delegate2));
        (uint256 spent, uint256 calls) = registry.usage(rotated, address(token));
        (uint256 windowSpent, uint256 live) = registry.rollingUsage(rotated, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);
        assertEq(windowSpent, 0);
        assertEq(live, 0);

        _spend(delegate2, rotated, 800);
        assertEq(token.balanceOf(payee), 1500);

        vm.prank(delegate);
        vm.expectRevert(_err(5)); // REVOKED: the old key's grant
        executor.spend(old, address(token), 1, payee);
    }

    /// What the warning asks of a rotation: size the new grant against the old grant's usage. To hold lifetime
    /// spend at 800 across the two, the new grant's caps are 800 - 700 = 100.
    function test_rotation_sizedAgainstOldUsageHoldsTheTotal() public {
        bytes32 old = _register(_terms(1, 1000, 1000, 1000, delegate));
        _spend(delegate, old, 700);
        vm.prank(principal);
        registry.revoke(old);
        (uint256 oldSpent,) = registry.usage(old, address(token));
        uint256 left = 800 - oldSpent;
        assertEq(left, 100);

        bytes32 rotated = _register(_terms(2, left, left, left, delegate2));
        _spend(delegate2, rotated, 100);
        assertEq(token.balanceOf(payee), 800);

        vm.warp(vm.getBlockTimestamp() + WINDOW);
        vm.prank(delegate2);
        vm.expectRevert(_err(10)); // OVER_CUMULATIVE_CAP
        executor.spend(rotated, address(token), 1, payee);
    }

    /// A new grant's window starts empty too. Started now, it spends a whole window cap while the old grant's
    /// window is still full; started at the old grant's last expiry, it waits until that window is empty.
    function test_rotation_delayedStartClosesTheWindowGap() public {
        bytes32 old = _register(_terms(1, 1000, 1000, 10_000, delegate));
        _spend(delegate, old, 1000);
        vm.prank(principal);
        registry.revoke(old);
        (uint256 oldWindow,) = registry.rollingUsage(old, address(token));
        assertEq(oldWindow, 1000);

        bytes32 immediate = _register(_terms(2, 100, 100, 1000, delegate2));
        _spend(delegate2, immediate, 100);
        assertEq(token.balanceOf(payee), 1100);

        (uint256[] memory expiresAt,) = registry.liveDebits(old, address(token), 1024);
        uint256 lastExpiry = expiresAt[expiresAt.length - 1];
        SpendGrant memory late = _terms(3, 100, 100, 1000, delegate2);
        late.validAfter = uint64(lastExpiry);
        bytes32 delayed = _register(late);
        _assertCheck(delayed, delegate2, 100, 3);

        vm.warp(lastExpiry);
        (oldWindow,) = registry.rollingUsage(old, address(token));
        assertEq(oldWindow, 0);
        _spend(delegate2, delayed, 100);
        assertEq(token.balanceOf(payee), 1200);

        vm.prank(delegate2);
        vm.expectRevert(_err(9)); // OVER_WINDOW_CAP
        executor.spend(delayed, address(token), 1, payee);
    }

    // ---------------------------------------------------------------- helpers

    function _terms(uint256 salt, uint256 perCall, uint256 perWindow, uint256 total, address d)
        internal
        view
        returns (SpendGrant memory g)
    {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = principal;
        g.delegate = d;
        g.recipientMode = 0;
        g.recipient = payee;
        g.windowSeconds = WINDOW;
        g.validAfter = t;
        g.validUntil = t + 30 days;
        g.salt = salt;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(address(token), perCall, perWindow, total);
    }

    function _register(SpendGrant memory g) internal returns (bytes32 id) {
        vm.prank(principal);
        id = registry.register(g);
    }

    function _spend(address d, bytes32 id, uint256 amount) internal {
        vm.prank(d);
        executor.spend(id, address(token), amount, payee);
    }

    /// `check` gives the literal reason number for this spend of the token to the payee.
    function _assertCheck(bytes32 id, address d, uint256 amount, uint8 reason) internal view {
        (bool ok, Reason r) = registry.check(id, d, address(token), amount, payee);
        assertEq(uint8(r), reason);
        assertEq(ok, reason == 0);
    }

    /// `SpendGrantError(uint8)` carrying the literal reason number.
    function _err(uint8 reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
    }
}
