// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {
    AssetLimit,
    GrantState,
    ISpendGrantRegistry,
    MAX_LIVE_DEBITS,
    Reason,
    SpendGrant,
    SpendGrantError
} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";
import {OldRingOracle} from "./OldRingOracle.sol";

/// @notice The registry's ring (consume, evict, usage, rollingUsage, liveDebits, and grantState's usage fields
/// and spendableNow) against the previous registry's ring (445bc54, `OldRingOracle.sol`) as an
/// independent model, over random debits, warps (including ten-year idle periods), evictions and cap updates.
/// Every step compares success and revert data, `check` against `consume`, and every view; spendableNow is
/// computed here by the plan's formula from the oracle and the token. The test's own counters prove the ring
/// filled (WINDOW_FULL), wrapped, and that each operation ran.
contract SpendGrantRingOracleTest is Test {
    SpendGrantRegistry internal registry;
    OldRingOracle internal oracle;
    MockERC20 internal token;
    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;

    bytes32 internal id;
    uint64 internal window;
    AssetLimit internal cur;
    uint256 internal version;
    uint256[15] internal hits;
    uint256 internal evictions;
    uint256 internal updates;
    uint256 internal idles;
    uint256 internal maxLive;
    bool internal fillMode;
    uint256 internal stepNo;

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        payee = makeAddr("payee");
        registry = new SpendGrantRegistry(executor);
        oracle = new OldRingOracle();
        token = new MockERC20();
        token.mint(principal, type(uint256).max);
        vm.prank(principal);
        token.approve(executor, type(uint256).max);
    }

    function _init(uint64 w, AssetLimit memory caps) internal {
        window = w;
        cur = caps;
        SpendGrant memory g;
        g.principal = principal;
        g.delegate = delegate;
        g.recipientMode = 1;
        g.windowSeconds = w;
        g.assets = new AssetLimit[](1);
        g.assets[0] = caps;
        g.validAfter = uint64(vm.getBlockTimestamp());
        g.validUntil = type(uint64).max;
        g.salt = 42;
        vm.prank(principal);
        id = registry.register(g);
        version = 1;
    }

    function _terms(AssetLimit memory caps) internal view returns (SpendGrant memory g) {
        (g,,,,) = registry.getGrant(id);
        g.assets[0] = caps;
    }

    // ------------------------------------------------------------ one step

    function step(uint256 r) external {
        require(msg.sender == address(this), "self only");
        uint256 op = r % 100;
        if (fillMode && op >= 80 && op < 85) op = 0;
        if (op < 72) {
            _consume(_amount(r >> 8));
        } else if (op < 80) {
            uint256[6] memory counts = [uint256(0), 1, 7, 100, 513, type(uint256).max];
            uint256 maxCount = counts[(r >> 8) % 6];
            registry.evict(id, address(token), maxCount);
            oracle.evict(id, address(token), maxCount);
            evictions++;
        } else if (op < 85) {
            _updateCaps(r >> 8);
        }
        _warp(r >> 64);
        _compareViews((r >> 128) % 25 == 0);
    }

    function _consume(uint256 amount) internal {
        (bool okCheck, Reason reason) = registry.check(id, delegate, address(token), amount, payee);
        vm.prank(executor);
        (bool s1, bytes memory ret1) = address(registry).call(
            abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, address(token), amount, payee))
        );
        (bool s2, bytes memory ret2) =
            address(oracle).call(abi.encodeCall(OldRingOracle.debit, (id, window, cur, address(token), amount)));
        assertEq(s1, s2, "new and old ring disagree on success");
        assertEq(ret1, ret2, "new and old ring disagree on revert data");
        assertEq(okCheck, s1, "P-EQ: check vs consume");
        if (!s1) assertEq(ret1, abi.encodeWithSelector(SpendGrantError.selector, reason), "P-EQ: reason");
        hits[uint8(reason)]++;
    }

    function _sat(uint256 a) internal pure returns (uint256) {
        return a >= type(uint128).max ? type(uint128).max : a;
    }

    function _updateCaps(uint256 r) internal {
        uint256 perCall = 1 + r % (_sat(cur.maxPerCall) * 2 + 1);
        if (r % 7 == 0) perCall = type(uint256).max;
        uint256 perWindow = perCall == type(uint256).max ? perCall : perCall + (r >> 16) % (_sat(cur.maxPerWindow) + 1);
        uint256 total = perWindow == type(uint256).max ? perWindow : perWindow + (r >> 40) % (_sat(cur.maxTotal) + 1);
        // Sometimes lower the lifetime cap to, or below, what is already spent.
        (uint256 spent,) = oracle.usage(id, address(token));
        if ((r >> 80) % 5 == 0 && spent > 0) {
            total = spent - (r >> 88) % spent;
            if (perWindow > total) perWindow = total;
            if (perCall > perWindow) perCall = perWindow;
        }
        AssetLimit memory n = AssetLimit(address(token), perCall, perWindow, total);
        SpendGrant memory t = _terms(n);
        vm.prank(principal);
        registry.update(id, version, t);
        version++;
        cur = n;
        updates++;
    }

    function _warp(uint256 r) internal {
        uint256 c = r % 100;
        uint256 w = uint256(window);
        uint256 by;
        if (fillMode) {
            // Fill the ring inside one window first, then cross windows now and then (partial expiry).
            if (stepNo < 1700 || c < 98) by = (r >> 8) % 2;
            else if (c < 99) by = w - 1 - (r >> 8) % 600;
            else by = w;
        } else if (c < 45) {
            by = 0;
        } else if (c < 80) {
            by = (r >> 8) % 11;
        } else if (window == type(uint64).max) {
            by = c < 99 ? (r >> 8) % 1000 : 3650 days;
        } else if (c < 86) {
            by = w - 1;
        } else if (c < 90) {
            by = w;
        } else if (c < 93) {
            by = w + 1;
        } else if (c < 99) {
            by = (r >> 8) % (2 * w + 1);
        } else {
            by = 3650 days;
        }
        if (by == 3650 days) idles++;
        vm.warp(vm.getBlockTimestamp() + by);
    }

    /// Amount drawn from the oracle's own usage, never from the registry under test.
    function _amount(uint256 r) internal view returns (uint256) {
        (uint256 windowSpent,) = oracle.rollingUsage(id, address(token));
        (uint256 spent,) = oracle.usage(id, address(token));
        uint256 windowRoom = cur.maxPerWindow > windowSpent ? cur.maxPerWindow - windowSpent : 0;
        uint256 totalRoom = cur.maxTotal > spent ? cur.maxTotal - spent : 0;
        uint256 room = cur.maxPerCall;
        if (windowRoom < room) room = windowRoom;
        if (totalRoom < room) room = totalRoom;
        if (room > type(uint192).max) room = type(uint192).max;
        uint256 c = r % 20;
        if (fillMode && c >= 13) c = 2 + c % 10;
        if (c == 0) return 0;
        if (c == 1) return 1;
        if (c < 12) return room == 0 ? 1 : 1 + (r >> 8) % room;
        if (c == 12) return room == 0 ? 1 : room;
        if (c == 13) return room + 1;
        if (c == 14) return cur.maxPerCall == type(uint256).max ? cur.maxPerCall : cur.maxPerCall + 1;
        if (c == 15) return uint256(type(uint192).max) + 1;
        if (c == 16) return windowRoom == type(uint256).max ? windowRoom : windowRoom + 1;
        if (c == 17) return totalRoom == type(uint256).max ? totalRoom : totalRoom + 1;
        if (c == 18) return uint256(type(uint192).max);
        return r >> 8;
    }

    function _compareViews(bool full) internal {
        address a = address(token);
        (uint256 s1, uint256 c1) = registry.usage(id, a);
        (uint256 s2, uint256 c2) = oracle.usage(id, a);
        assertEq(s1, s2, "usage.spent");
        assertEq(c1, c2, "usage.calls");
        (uint256 w1, uint256 l1) = registry.rollingUsage(id, a);
        (uint256 w2, uint256 l2) = oracle.rollingUsage(id, a);
        assertEq(w1, w2, "rollingUsage.spent");
        assertEq(l1, l2, "rollingUsage.calls");
        if (l2 > maxLive) maxLive = l2;
        uint256 k = full ? 2000 : 3;
        (uint256[] memory e1, uint256[] memory m1) = registry.liveDebits(id, a, k);
        (uint256[] memory e2, uint256[] memory m2) = oracle.liveDebits(id, a, k);
        assertEq(abi.encode(e1, m1), abi.encode(e2, m2), "liveDebits");

        GrantState memory g = registry.grantState(id, a);
        assertEq(g.spent, s2, "grantState.spent");
        assertEq(g.windowSpent, w2, "grantState.windowSpent");
        assertEq(g.liveDebits, l2, "grantState.liveDebits");
        assertEq(g.nextExpiry, e2.length == 0 ? 0 : e2[0], "grantState.nextExpiry");
        // spendableNow from the plan's formula, computed here from the oracle and the token.
        uint256 v = cur.maxPerWindow > w2 ? cur.maxPerWindow - w2 : 0;
        uint256 life = cur.maxTotal > s2 ? cur.maxTotal - s2 : 0;
        if (life < v) v = life;
        uint256 perDebit = cur.maxPerCall < type(uint192).max ? cur.maxPerCall : type(uint192).max;
        uint256 slots = (MAX_LIVE_DEBITS - l2) * perDebit;
        if (slots < v) v = slots;
        uint256 bal = token.balanceOf(principal);
        if (bal < v) v = bal;
        uint256 alw = token.allowance(principal, executor);
        if (alw < v) v = alw;
        assertEq(g.spendableNow, v, "grantState.spendableNow");
        assertEq(uint8(g.status), uint8(Reason.OK));
    }

    function _run(uint64 w, AssetLimit memory caps, uint256 steps, bytes32 seed) internal {
        _init(w, caps);
        for (uint256 i = 0; i < steps; i++) {
            seed = keccak256(abi.encode(seed, i));
            stepNo = i;
            this.step(uint256(seed));
        }
        _compareViews(true);
        console2.log("OK", hits[0]);
        console2.log("OVER_TX_CAP", hits[uint8(Reason.OVER_TX_CAP)]);
        console2.log("OVER_WINDOW_CAP", hits[uint8(Reason.OVER_WINDOW_CAP)]);
        console2.log("OVER_CUMULATIVE_CAP", hits[uint8(Reason.OVER_CUMULATIVE_CAP)]);
        console2.log("WINDOW_FULL", hits[uint8(Reason.WINDOW_FULL)]);
        console2.log("evictions", evictions);
        console2.log("updates", updates);
        console2.log("long idles", idles);
        console2.log("max live debits", maxLive);
        (, uint256 calls) = oracle.usage(id, address(token));
        console2.log("total debits", calls);
    }

    /// Successful debits, OVER_TX_CAP, and evictions happened; with `updatesAndIdles`, cap updates and
    /// ten-year idle periods too (fill mode replaces both).
    function _assertExercised(bool updatesAndIdles) internal view {
        assertGt(hits[uint8(Reason.OK)], 0, "no debit succeeded");
        assertGt(hits[uint8(Reason.OVER_TX_CAP)], 0, "OVER_TX_CAP not reached");
        assertGt(evictions, 0, "no evict");
        if (updatesAndIdles) {
            assertGt(updates, 0, "no cap update");
            assertGt(idles, 0, "no long idle");
        }
    }

    /// Fills the ring inside one window, then crosses windows now and then so that part of it expires and
    /// the refill wraps around the 1024 slots.
    function test_ringMatchesOldRing_fillsWrapsAndPartlyExpires_dayWindow() public {
        fillMode = true;
        _run(1 days, AssetLimit(address(token), 3, 5000, 1e7), 3200, "small");
        _assertExercised(false);
        assertGt(hits[uint8(Reason.WINDOW_FULL)], 0, "WINDOW_FULL not reached");
        assertEq(maxLive, MAX_LIVE_DEBITS, "ring never full");
        assertGt(hits[uint8(Reason.OK)], MAX_LIVE_DEBITS, "ring never wrapped");
    }

    function test_ringMatchesOldRing_capsBind_minuteWindow() public {
        _run(60, AssetLimit(address(token), 100, 1000, 20_000), 1500, "minute");
        _assertExercised(true);
        assertGt(hits[uint8(Reason.OVER_WINDOW_CAP)], 0);
        assertGt(hits[uint8(Reason.OVER_CUMULATIVE_CAP)], 0);
    }

    function test_ringMatchesOldRing_oneSecondWindow() public {
        _run(1, AssetLimit(address(token), 50, 60, 5000), 1500, "second");
        _assertExercised(true);
        assertGt(hits[uint8(Reason.OVER_CUMULATIVE_CAP)], 0);
    }

    function test_ringMatchesOldRing_windowNeverExpires() public {
        _run(type(uint64).max, AssetLimit(address(token), 5, 2000, 100_000), 1800, "forever");
        _assertExercised(true);
        assertGt(hits[uint8(Reason.OVER_WINDOW_CAP)], 0);
    }

    function test_ringMatchesOldRing_maxCapsHugeAmounts() public {
        uint256 m = type(uint256).max;
        _run(1 hours, AssetLimit(address(token), m, m, m), 1500, "huge");
        _assertExercised(true);
    }

    /// Short random runs; the deterministic runs above carry the coverage counters.
    function testFuzz_ringMatchesOldRing(bytes32 seed, uint8 w) public {
        uint64[5] memory windows = [uint64(1), 7, 60, 1 days, type(uint64).max];
        _run(windows[w % 5], AssetLimit(address(token), 10, 200, 3000), 120, seed);
    }
}
