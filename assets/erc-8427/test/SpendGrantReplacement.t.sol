// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, NATIVE, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";

/// @dev What the "Replacing a grant" section relies on: a grant cannot be changed in place, a
/// replacement stacks with the earlier grant until that grant is revoked, a replacement nobody has
/// handed to the delegate cannot be spent, and a replacement starts with fresh lifetime and window usage.
contract SpendGrantReplacementTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;

    SpendGrantRegistry internal registry; // this test contract is its executor
    address internal principal;
    address internal delegate;
    address internal recipient;

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);
        registry = new SpendGrantRegistry(address(this));
        vm.warp(1_700_000_000);
    }

    function test_replacement_stacksUntilTheEarlierGrantIsRevoked() public {
        SpendGrant memory earlier = _grant(1, 100, 100, 1000);
        SpendGrant memory lower = _grant(2, 10, 10, 100);

        // Released before the revocation: both are live, and the delegate spends the sum in one window.
        registry.consume(earlier, _sign(earlier), delegate, NATIVE, 100, recipient);
        registry.consume(lower, _sign(lower), delegate, NATIVE, 10, recipient);

        // Only the revocation ends the earlier grant.
        vm.prank(principal);
        registry.revoke(_hash(earlier));
        assertTrue(registry.revoked(principal, _hash(earlier)));
        _expect(Reason.REVOKED);
        registry.consume(earlier, _sign(earlier), delegate, NATIVE, 1, recipient);
    }

    function test_replacement_heldBackCannotBeSpent() public {
        // The delegate knows every term of the replacement but was not given the signature.
        SpendGrant memory lower = _grant(2, 10, 10, 100);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(lower, hex"", delegate, NATIVE, 10, recipient);
    }

    function test_replacement_lifetimeCapStartsAgainFromZero() public {
        SpendGrant memory earlier = _grant(1, 1000, 1000, 1000);
        registry.consume(earlier, _sign(earlier), delegate, NATIVE, 700, recipient);
        vm.prank(principal);
        registry.revoke(_hash(earlier));

        // After the revocation the earlier usage is frozen, so a wallet can size the replacement from it.
        (uint256 earlierSpent,) = registry.usage(_hash(earlier), NATIVE);
        assertEq(earlierSpent, 700);

        // "Lowered" to 800 by reissue: 800 more, not the 100 the principal meant. 1500 across both.
        SpendGrant memory lower = _grant(2, 800, 800, 800);
        (uint256 freshSpent, uint256 freshCalls) = registry.usage(_hash(lower), NATIVE);
        assertEq(freshSpent, 0);
        assertEq(freshCalls, 0);
        registry.consume(lower, _sign(lower), delegate, NATIVE, 800, recipient);
        (uint256 lowerSpent,) = registry.usage(_hash(lower), NATIVE);
        assertEq(earlierSpent + lowerSpent, 1500);

        // Sized from what the earlier grant had left, the replacement allows exactly that.
        uint256 left = 1000 - earlierSpent;
        SpendGrant memory netted = _grant(3, left, left, left);
        registry.consume(netted, _sign(netted), delegate, NATIVE, left, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        registry.consume(netted, _sign(netted), delegate, NATIVE, 1, recipient);
    }

    function test_replacement_windowStartsEmptyUnlessItsStartIsDelayed() public {
        SpendGrant memory earlier = _grant(1, 1000, 1000, 10_000);
        registry.consume(earlier, _sign(earlier), delegate, NATIVE, 1000, recipient);
        vm.prank(principal);
        registry.revoke(_hash(earlier));

        // The earlier grant's window is still full, yet the replacement spends its whole window now.
        (uint256 earlierRolling,) = registry.rollingUsage(_hash(earlier), NATIVE);
        assertEq(earlierRolling, 1000);
        SpendGrant memory lower = _grant(2, 100, 100, 1000);
        registry.consume(lower, _sign(lower), delegate, NATIVE, 100, recipient);

        // A replacement whose validAfter is the earlier grant's last expiry closes that gap.
        (uint256[] memory expiresAt,) = registry.liveDebits(_hash(earlier), NATIVE, 1024);
        uint256 lastExpiry = expiresAt[expiresAt.length - 1];
        SpendGrant memory delayed = _grant(3, 100, 100, 1000);
        delayed.validAfter = uint64(lastExpiry);
        bytes memory delayedSig = _sign(delayed);

        (bool ok, bytes memory ret) = address(registry).call(
            abi.encodeCall(registry.consume, (delayed, delayedSig, delegate, NATIVE, 100, recipient))
        );
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantError.selector, Reason.NOT_YET_VALID));

        vm.warp(lastExpiry);
        (earlierRolling,) = registry.rollingUsage(_hash(earlier), NATIVE);
        assertEq(earlierRolling, 0);
        registry.consume(delayed, delayedSig, delegate, NATIVE, 100, recipient);
        (uint256 delayedRolling,) = registry.rollingUsage(_hash(delayed), NATIVE);
        assertEq(delayedRolling, 100);
    }

    // ---------------------------------------------------------------- helpers

    function _grant(uint256 salt, uint256 perCall, uint256 perWindow, uint256 total)
        internal
        view
        returns (SpendGrant memory m)
    {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = salt;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(NATIVE, perCall, perWindow, total);
    }

    function _hash(SpendGrant memory m) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(registry), m);
    }

    function _sign(SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, _hash(m));
        return abi.encodePacked(r, s, v);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }
}
