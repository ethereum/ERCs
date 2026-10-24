// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {AssetLimit, GrantState, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice The ring by hand: fill all 1024 slots, let part of them expire, evict, refill across the wrap, idle
/// ten years; every expected view value is computed by hand, independently of the registry.
contract SpendGrantRingHandTest is Test {
    uint64 internal constant W = 1 days;
    SpendGrantRegistry internal registry;
    MockERC20 internal token;
    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;
    bytes32 internal id;

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        payee = makeAddr("payee");
        registry = new SpendGrantRegistry(executor);
        token = new MockERC20();
        token.mint(principal, 1e30);
        vm.prank(principal);
        token.approve(executor, type(uint256).max);
        SpendGrant memory g;
        g.principal = principal;
        g.delegate = delegate;
        g.recipient = payee;
        g.windowSeconds = W;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(address(token), 1, 10_000, 1_000_000);
        g.validAfter = uint64(vm.getBlockTimestamp());
        g.validUntil = type(uint64).max;
        g.salt = 7;
        vm.prank(principal);
        id = registry.register(g);
    }

    function _spend(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            vm.prank(executor);
            registry.consume(id, delegate, address(token), 1, payee);
        }
    }

    function _assertViews(uint256 live, uint256 firstExpiry, uint256 spendable, uint256 calls) internal view {
        (uint256 ws, uint256 wc) = registry.rollingUsage(id, address(token));
        assertEq(ws, live, "rolling spent");
        assertEq(wc, live, "rolling calls");
        (uint256[] memory e, uint256[] memory a) = registry.liveDebits(id, address(token), 2000);
        assertEq(e.length, live, "liveDebits length");
        if (live > 0) {
            assertEq(e[0], firstExpiry, "first expiresAt");
            assertEq(a[0], 1);
        }
        GrantState memory s = registry.grantState(id, address(token));
        assertEq(uint8(s.status), uint8(Reason.OK));
        assertEq(s.liveDebits, live, "state live");
        assertEq(s.windowSpent, live, "state windowSpent");
        assertEq(s.nextExpiry, live == 0 ? 0 : firstExpiry, "state nextExpiry");
        assertEq(s.spendableNow, spendable, "spendableNow");
        (uint256 sp, uint256 c) = registry.usage(id, address(token));
        assertEq(sp, calls);
        assertEq(c, calls);
    }

    function test_ringByHand_fullRingPartialExpiryEvictRefillAcrossWrapAndIdle() public {
        uint256 t0 = vm.getBlockTimestamp();
        _spend(512);
        vm.warp(t0 + 1);
        _spend(512);
        // Full: min(10000-1024, 1e6-1024, 0 slots) = 0.
        _assertViews(1024, t0 + W, 0, 1024);
        (, Reason r) = registry.check(id, delegate, address(token), 1, payee);
        assertEq(uint8(r), uint8(Reason.WINDOW_FULL));

        // The first 512 expire at t0 + W; the second 512 stay until t0 + 1 + W.
        vm.warp(t0 + W);
        _assertViews(512, t0 + 1 + W, 512, 1024);
        registry.evict(id, address(token), 100);
        _assertViews(512, t0 + 1 + W, 512, 1024);
        registry.evict(id, address(token), 10_000);
        _assertViews(512, t0 + 1 + W, 512, 1024);
        registry.evict(id, address(token), 10_000); // nothing left to drop
        _assertViews(512, t0 + 1 + W, 512, 1024);
        (bool ok,) = registry.check(id, delegate, address(token), 1, payee);
        assertTrue(ok);
        _spend(1);
        // 513 live: the 512 from t0+1 and the new one; slots (1024-513)*1 = 511.
        _assertViews(513, t0 + 1 + W, 511, 1025);

        // Fill to 1024 again across the wrap, then idle ten years: everything expired, nothing evicted.
        _spend(511);
        _assertViews(1024, t0 + 1 + W, 0, 1536);
        vm.warp(t0 + 3650 days);
        // min(10000, 1e6 - 1536, 1024 * 1) = 1024.
        _assertViews(0, 0, 1024, 1536);

        vm.cool(address(registry));
        uint256 g0 = gasleft();
        registry.check(id, delegate, address(token), 1, payee);
        console2.log("check over 1024 expired, cold", g0 - gasleft());
        vm.cool(address(registry));
        g0 = gasleft();
        registry.grantState(id, address(token));
        console2.log("grantState over 1024 expired, cold", g0 - gasleft());
        vm.cool(address(registry));
        g0 = gasleft();
        vm.prank(executor);
        registry.consume(id, delegate, address(token), 1, payee);
        console2.log("consume dropping 1024 expired, cold", g0 - gasleft());
        _assertViews(1, t0 + 3650 days + W, 1023, 1537);
    }

    /// `evict(grantId, asset, maxCount)` drops up to `maxCount` expired debits from storage and changes nothing any
    /// view returns. The reference drops exactly the lesser of `maxCount` and the expired debits it holds: 40 expired
    /// debits of 1, then evict(1), evict(24) and evict(100) leave the stored ring head at 1, 25 and 40 and the stored
    /// window sum at 39, 15 and 0.
    function test_evict_dropsUpToMaxCountExpiredDebitsFromStorage() public {
        uint256 t0 = vm.getBlockTimestamp();
        _spend(40);
        _assertViews(40, t0 + W, 1024 - 40, 40);
        vm.warp(t0 + W);
        // All 40 expired, still stored.
        _assertViews(0, 0, 1024, 40);
        _assertStored(0, 40);

        registry.evict(id, address(token), 1);
        _assertStored(1, 39);
        _assertViews(0, 0, 1024, 40);
        registry.evict(id, address(token), 24);
        _assertStored(25, 15);
        _assertViews(0, 0, 1024, 40);
        registry.evict(id, address(token), 100);
        _assertStored(40, 0);
        _assertViews(0, 0, 1024, 40);
    }

    /// The stored ring head and window sum of (id, token), which no view returns. The slots are from
    /// `forge inspect SpendGrantRegistry storage-layout --json`: `_usage` is slot 1, so this AssetUsage starts at
    /// keccak256(abi.encode(token, keccak256(abi.encode(id, 1)))); its `head` is member slot 0 at offset 0 (the low 8
    /// bytes of that word), and its `windowSpent` is member slot 2.
    function _assertStored(uint256 head, uint256 windowSpent) internal view {
        uint256 base = uint256(keccak256(abi.encode(address(token), keccak256(abi.encode(id, uint256(1))))));
        assertEq(uint64(uint256(vm.load(address(registry), bytes32(base)))), head, "stored head");
        assertEq(uint256(vm.load(address(registry), bytes32(base + 2))), windowSpent, "stored windowSpent");
    }
}
