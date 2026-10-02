// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, MAX_LIVE_DEBITS, NATIVE, Reason, SpendGrant, SpendGrantError} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Naive reference model: stores every debit and recomputes usage/rollingUsage by a full
/// O(n) scan under the same liveness rule and the same MAX_LIVE_DEBITS bound, to differentially
/// test the registry's ring-buffer implementation. Cheap for the short step counts it's used
/// with; see `RingModel` below for the long-running (fill-and-wrap) variant.
contract NaiveModel {
    struct Debit {
        uint64 time;
        uint256 amount;
    }

    uint64 public windowSeconds;
    Debit[] internal _debits;
    uint256 public spent;
    uint256 public calls;

    constructor(uint64 windowSeconds_) {
        windowSeconds = windowSeconds_;
    }

    /// @dev The spec's primary form (`now < stamped + window`), written independently of the
    /// registry's `_live` (`now - stamped < window`) so this is a genuine differential check
    /// rather than a restatement of the same code. Equivalent for all reachable `(now, stamped,
    /// window)` here since `stamped`/`window` are uint64 and `now` is a realistic block time, so
    /// `stamped + window` cannot overflow uint256.
    function _live(uint64 time) internal view returns (bool) {
        return block.timestamp < uint256(time) + uint256(windowSeconds);
    }

    function _liveCount() internal view returns (uint256 n) {
        for (uint256 i = 0; i < _debits.length; i++) {
            if (_live(_debits[i].time)) n++;
        }
    }

    /// @dev Mirrors the registry's exact check order for a single-asset grant already past
    /// structure/signature/time/recipient checks: OVER_TX_CAP, OVER_WINDOW_CAP,
    /// OVER_CUMULATIVE_CAP, WINDOW_FULL.
    function tryConsume(uint256 amount, uint256 maxPerCall, uint256 maxPerWindow, uint256 maxTotal)
        external
        returns (bool ok, Reason reason)
    {
        if (amount == 0 || amount > maxPerCall || amount > type(uint192).max) {
            return (false, Reason.OVER_TX_CAP);
        }
        (uint256 rollingSpent,) = rollingUsage();
        if (rollingSpent + amount > maxPerWindow) return (false, Reason.OVER_WINDOW_CAP);
        if (spent + amount > maxTotal) return (false, Reason.OVER_CUMULATIVE_CAP);
        if (_liveCount() >= MAX_LIVE_DEBITS) return (false, Reason.WINDOW_FULL);

        _debits.push(Debit({time: uint64(block.timestamp), amount: amount}));
        spent += amount;
        calls += 1;
        return (true, Reason.OK);
    }

    function rollingUsage() public view returns (uint256 rollingSpent, uint256 liveCalls) {
        for (uint256 i = 0; i < _debits.length; i++) {
            if (_live(_debits[i].time)) {
                rollingSpent += _debits[i].amount;
                liveCalls++;
            }
        }
    }

    function usage() external view returns (uint256, uint256) {
        return (spent, calls);
    }

    /// @dev Unexpired debits in insertion (oldest-first) order, by full scan.
    function liveDebits() external view returns (uint256[] memory expiresAt, uint256[] memory amounts) {
        uint256 n = _liveCount();
        expiresAt = new uint256[](n);
        amounts = new uint256[](n);
        uint256 j;
        for (uint256 i = 0; i < _debits.length; i++) {
            if (_live(_debits[i].time)) {
                expiresAt[j] = uint256(_debits[i].time) + uint256(windowSeconds);
                amounts[j] = _debits[i].amount;
                j++;
            }
        }
    }
}

/// @dev A second, O(1)-amortized reference model for long-running differential runs (thousands
/// of steps) where `NaiveModel`'s O(n) full scan would be too slow. Deliberately structured
/// differently from the registry's fixed-size modulo ring: an append-only dynamic array plus a
/// monotonic `head` pointer, so a wraparound/indexing bug in the registry's `tail % N` ring is
/// unlikely to be mirrored here by construction.
contract RingModel {
    uint64 public windowSeconds;
    uint256[] internal _times;
    uint256[] internal _amounts;
    uint256 internal _head;
    uint256 public spent;
    uint256 public calls;
    uint256 public windowSpent;

    constructor(uint64 windowSeconds_) {
        windowSeconds = windowSeconds_;
    }

    function _live(uint256 time) internal view returns (bool) {
        return block.timestamp < time + uint256(windowSeconds);
    }

    function _evictExpired() internal {
        uint256 head = _head;
        while (head < _times.length && !_live(_times[head])) {
            windowSpent -= _amounts[head];
            unchecked {
                ++head;
            }
        }
        _head = head;
    }

    function tryConsume(uint256 amount, uint256 maxPerCall, uint256 maxPerWindow, uint256 maxTotal)
        external
        returns (bool ok, Reason reason)
    {
        if (amount == 0 || amount > maxPerCall || amount > type(uint192).max) {
            return (false, Reason.OVER_TX_CAP);
        }
        _evictExpired();
        uint256 live = _times.length - _head;
        if (windowSpent + amount > maxPerWindow) return (false, Reason.OVER_WINDOW_CAP);
        if (spent + amount > maxTotal) return (false, Reason.OVER_CUMULATIVE_CAP);
        if (live >= MAX_LIVE_DEBITS) return (false, Reason.WINDOW_FULL);

        _times.push(block.timestamp);
        _amounts.push(amount);
        windowSpent += amount;
        spent += amount;
        calls += 1;
        return (true, Reason.OK);
    }

    function rollingUsage() external returns (uint256, uint256) {
        _evictExpired();
        return (windowSpent, _times.length - _head);
    }

    function usage() external view returns (uint256, uint256) {
        return (spent, calls);
    }
}

contract SpendGrantRingTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;

    SpendGrantRegistry internal registry;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);
        token = new MockERC20();
        registry = new SpendGrantRegistry(address(this));
        vm.warp(1_700_000_000);
    }

    function _grant(uint64 windowSeconds, uint256 maxPerCall, uint256 maxPerWindow, uint256 maxTotal, uint256 salt)
        internal
        view
        returns (SpendGrant memory m)
    {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = windowSeconds;
        m.validAfter = 0;
        m.validUntil = type(uint64).max;
        m.salt = salt;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(NATIVE, maxPerCall, maxPerWindow, maxTotal);
    }

    function _sig(SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(PRINCIPAL_PK, SpendGrantHash.digest(block.chainid, address(registry), m));
        return abi.encodePacked(r, s, v);
    }

    function _tryConsume(SpendGrant memory m, uint256 amount) internal returns (bool ok, Reason reason) {
        bytes memory sig = _sig(m);
        (bool callOk, bytes memory ret) =
            address(registry).call(abi.encodeCall(registry.consume, (m, sig, m.delegate, NATIVE, amount, recipient)));
        if (callOk) return (true, Reason.OK);
        if (ret.length == 36 && bytes4(ret) == SpendGrantError.selector) {
            reason = abi.decode(_slice(ret, 4), (Reason));
            return (false, reason);
        }
        revert("unexpected revert");
    }

    function _slice(bytes memory data, uint256 start) internal pure returns (bytes memory out) {
        out = new bytes(data.length - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = data[start + i];
        }
    }

    // -- model helpers: raw external calls so both NaiveModel and RingModel (same ABI) work -----

    function _modelTryConsume(address model, uint256 amount, uint256 maxPerCall, uint256 maxPerWindow, uint256 maxTotal)
        internal
        returns (bool ok, Reason reason)
    {
        (bool success, bytes memory ret) = model.call(
            abi.encodeWithSignature(
                "tryConsume(uint256,uint256,uint256,uint256)", amount, maxPerCall, maxPerWindow, maxTotal
            )
        );
        require(success, "model tryConsume failed");
        (ok, reason) = abi.decode(ret, (bool, Reason));
    }

    function _modelUsage(address model) internal view returns (uint256, uint256) {
        (bool success, bytes memory ret) = model.staticcall(abi.encodeWithSignature("usage()"));
        require(success, "model usage failed");
        return abi.decode(ret, (uint256, uint256));
    }

    function _modelRolling(address model) internal returns (uint256, uint256) {
        (bool success, bytes memory ret) = model.call(abi.encodeWithSignature("rollingUsage()"));
        require(success, "model rollingUsage failed");
        return abi.decode(ret, (uint256, uint256));
    }

    /// @dev 1: differential fuzz vs a naive full-scan model, including dt = 0, dt = windowSeconds,
    /// and dt = windowSeconds - 1, asserting identical accept/reject reasons and identical
    /// usage/rollingUsage after every step. maxTotal is small enough relative to maxPerCall/
    /// nSteps that OVER_CUMULATIVE_CAP is actually reachable, not just OVER_TX_CAP/WINDOW_CAP.
    function testFuzz_differentialAgainstNaiveModel(uint16 windowSecondsRaw, uint8 nSteps, uint256 seed) public {
        uint64 windowSeconds = uint64(bound(windowSecondsRaw, 2, 1000));
        uint256 maxPerCall = 1000;
        uint256 maxPerWindow = 5000;
        uint256 maxTotal = 20_000;
        nSteps = uint8(bound(nSteps, 1, 60));

        SpendGrant memory m = _grant(windowSeconds, maxPerCall, maxPerWindow, maxTotal, 1);
        NaiveModel model = new NaiveModel(windowSeconds);
        _runDifferential(m, address(model), maxPerCall, maxPerWindow, maxTotal, nSteps, seed, windowSeconds, true, 0);
    }

    /// @dev 1b: a tight-window variant (maxPerCall = 1, windowSeconds in [2, 4]) run for enough
    /// steps to both fill the ring to MAX_LIVE_DEBITS (hitting WINDOW_FULL) and wrap past it,
    /// checked step-by-step against `RingModel` (the O(n) `NaiveModel` is too slow over this many
    /// steps). The first MAX_LIVE_DEBITS + 4 steps are forced to dt = 0 (same block) so the ring
    /// deterministically fills and a WINDOW_FULL is guaranteed; later steps use fuzzed small dt so
    /// entries expire and the ring wraps.
    /// forge-config: default.fuzz.runs = 8
    function testFuzz_differentialSmallWindowReachesWrap(uint8 windowPick, uint256 seed) public {
        uint64 windowSeconds = uint64(bound(windowPick, 2, 4));
        uint256 maxPerCall = 1;
        uint256 maxPerWindow = 10_000;
        uint256 maxTotal = 1_000_000;
        uint256 nSteps = 2 * MAX_LIVE_DEBITS + 200;

        SpendGrant memory m = _grant(windowSeconds, maxPerCall, maxPerWindow, maxTotal, 7);
        RingModel model = new RingModel(windowSeconds);
        _runDifferential(
            m,
            address(model),
            maxPerCall,
            maxPerWindow,
            maxTotal,
            nSteps,
            seed,
            windowSeconds,
            false,
            MAX_LIVE_DEBITS + 4
        );
    }

    /// @dev Shared differential step-and-assert loop used by both fuzz tests above.
    /// `wideDt` picks dt from {0, windowSeconds-1, windowSeconds, random in [0, 2*windowSeconds]}.
    /// Otherwise, for the first `forcedZeroDtSteps` steps dt = 0 deterministically (to guarantee
    /// filling the ring); after that dt is fuzzed small (0, with an occasional 1-second warp) so
    /// entries expire and the ring wraps.
    function _runDifferential(
        SpendGrant memory m,
        address model,
        uint256 maxPerCall,
        uint256 maxPerWindow,
        uint256 maxTotal,
        uint256 nSteps,
        uint256 seed,
        uint64 windowSeconds,
        bool wideDt,
        uint256 forcedZeroDtSteps
    ) internal {
        bytes32 h = _hashOf(m);
        for (uint256 i = 0; i < nSteps; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 dt;
            if (wideDt) {
                uint256 dtPick = seed % 4;
                if (dtPick == 0) dt = 0;
                else if (dtPick == 1) dt = windowSeconds - 1;
                else if (dtPick == 2) dt = windowSeconds;
                else dt = (seed >> 8) % (uint256(windowSeconds) * 2 + 1);
            } else if (i < forcedZeroDtSteps) {
                dt = 0;
            } else {
                dt = (seed >> 8) % 5 == 0 ? 1 : 0;
            }
            vm.warp(block.timestamp + dt);

            uint256 amountPick = (seed >> 16) % 100;
            uint256 amount;
            if (amountPick == 0) amount = 0;
            else if (amountPick == 1) amount = maxPerCall + 1;
            else amount = 1 + ((seed >> 24) % maxPerCall);

            (bool expectOk, Reason expectReason) = _modelTryConsume(model, amount, maxPerCall, maxPerWindow, maxTotal);
            (bool actualOk, Reason actualReason) = _tryConsume(m, amount);

            assertEq(actualOk, expectOk);
            if (!expectOk) assertEq(uint8(actualReason), uint8(expectReason));

            (uint256 modelSpent, uint256 modelCalls) = _modelUsage(model);
            (uint256 regSpent, uint256 regCalls) = registry.usage(h, NATIVE);
            assertEq(regSpent, modelSpent);
            assertEq(regCalls, modelCalls);

            (uint256 modelRolling, uint256 modelLiveCalls) = _modelRolling(model);
            (uint256 regRolling, uint256 regLiveCalls) = registry.rollingUsage(h, NATIVE);
            assertEq(regRolling, modelRolling);
            assertEq(regLiveCalls, modelLiveCalls);

            if (wideDt) _assertLiveDebitsMatchModel(h, model, regRolling, regLiveCalls, seed);
        }
    }

    /// @dev liveDebits must equal the naive model's list exactly, agree with rollingUsage, and, for a
    /// fuzzed maxCount in [0, n + 1], return exactly the model's oldest min(maxCount, n) entries.
    function _assertLiveDebitsMatchModel(
        bytes32 h,
        address model,
        uint256 regRolling,
        uint256 regLiveCalls,
        uint256 seed
    ) internal view {
        (bool success, bytes memory ret) = model.staticcall(abi.encodeWithSignature("liveDebits()"));
        require(success, "model liveDebits failed");
        (uint256[] memory modelExpiresAt, uint256[] memory modelAmounts) = abi.decode(ret, (uint256[], uint256[]));
        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(h, NATIVE, type(uint256).max);
        assertEq(expiresAt, modelExpiresAt);
        assertEq(amounts, modelAmounts);
        assertEq(amounts.length, regLiveCalls);
        uint256 sum;
        for (uint256 i = 0; i < amounts.length; i++) {
            sum += amounts[i];
        }
        assertEq(sum, regRolling);

        uint256 k = (seed >> 40) % (modelAmounts.length + 2);
        uint256 m = k < modelAmounts.length ? k : modelAmounts.length;
        (uint256[] memory someAt, uint256[] memory someAmt) = registry.liveDebits(h, NATIVE, k);
        assertEq(someAt.length, m);
        assertEq(someAmt.length, m);
        for (uint256 i = 0; i < m; i++) {
            assertEq(someAt[i], modelExpiresAt[i]);
            assertEq(someAmt[i], modelAmounts[i]);
        }
    }

    function _hashOf(SpendGrant memory m) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(registry), m);
    }

    /// @dev 2: fill MAX_LIVE_DEBITS live debits, the next spend reverts WINDOW_FULL, then warp so
    /// some expire and keep spending past logical index 2*MAX_LIVE_DEBITS, asserting views stay
    /// exactly correct across the wrap (tracked against an explicit (time, count) batch model,
    /// not just a loose upper bound).
    function test_wrapAround_pastTwiceCapacity() public {
        uint64 windowSeconds = 100;
        SpendGrant memory m = _grant(windowSeconds, 1, type(uint192).max, type(uint192).max, 2);
        bytes32 h = _hashOf(m);

        // Every consume in this test lands at one of a handful of distinct block timestamps (no
        // per-call warp within a batch), so tracking (batchTime, batchCount) pairs and summing
        // the live ones reproduces the ring's exact live count/sum at each checkpoint below.
        uint256[] memory batchTime = new uint256[](32);
        uint256[] memory batchCount = new uint256[](32);
        uint256 nBatches = 1;
        batchTime[0] = block.timestamp;

        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            (bool ok,) = _tryConsume(m, 1);
            assertTrue(ok);
        }
        batchCount[0] = MAX_LIVE_DEBITS;

        (, uint256 liveCalls) = registry.rollingUsage(h, NATIVE);
        assertEq(liveCalls, _expectedLive(batchTime, batchCount, nBatches, windowSeconds));
        assertEq(liveCalls, MAX_LIVE_DEBITS);

        (bool full, Reason reason) = _tryConsume(m, 1);
        assertFalse(full);
        assertEq(uint8(reason), uint8(Reason.WINDOW_FULL));

        // Warp a full window past the single (same-block) batch of MAX_LIVE_DEBITS debits above,
        // so every one of them expires at once (age == windowSeconds expires, per spec).
        vm.warp(block.timestamp + windowSeconds);
        (, liveCalls) = registry.rollingUsage(h, NATIVE);
        assertEq(liveCalls, _expectedLive(batchTime, batchCount, nBatches, windowSeconds));
        assertEq(liveCalls, 0);

        uint256 totalCalls = MAX_LIVE_DEBITS;
        batchTime[1] = block.timestamp;
        nBatches = 2;
        for (uint256 i = 0; i < 2 * MAX_LIVE_DEBITS + 10; i++) {
            if (i % (MAX_LIVE_DEBITS / 4) == 0 && i != 0) {
                vm.warp(block.timestamp + windowSeconds);
                (, uint256 liveAfterWarp) = registry.rollingUsage(h, NATIVE);
                assertEq(liveAfterWarp, _expectedLive(batchTime, batchCount, nBatches, windowSeconds));
                assertEq(liveAfterWarp, 0);
                batchTime[nBatches] = block.timestamp;
                nBatches++;
            }
            (bool stepOk,) = _tryConsume(m, 1);
            assertTrue(stepOk);
            batchCount[nBatches - 1]++;
            totalCalls++;
        }

        (uint256 spent, uint256 calls) = registry.usage(h, NATIVE);
        assertEq(spent, totalCalls);
        assertEq(calls, totalCalls);
        (, liveCalls) = registry.rollingUsage(h, NATIVE);
        assertEq(liveCalls, _expectedLive(batchTime, batchCount, nBatches, windowSeconds));
        assertLe(liveCalls, MAX_LIVE_DEBITS);
    }

    function _expectedLive(
        uint256[] memory batchTime,
        uint256[] memory batchCount,
        uint256 nBatches,
        uint64 windowSeconds
    ) internal view returns (uint256 live) {
        uint256 ts = block.timestamp;
        for (uint256 i = 0; i < nBatches; i++) {
            if (ts - batchTime[i] < windowSeconds) live += batchCount[i];
        }
    }

    /// @dev 1: fills MAX_LIVE_DEBITS*3 logical slots one spend per second (amounts cycling
    /// 1..997), asserting after every spend that rollingUsage exactly equals the sum/count of the
    /// last min(k+1, MAX_LIVE_DEBITS) amounts. Periodically (once the ring is full) asserts a
    /// same-second extra spend reverts WINDOW_FULL. Finally warps +2 past the loop and asserts
    /// exactly MAX_LIVE_DEBITS - 2 live with the exact expected sum.
    function test_fullRingWrap_exactTracking() public {
        uint64 windowSeconds = uint64(MAX_LIVE_DEBITS);
        uint256 totalSteps = 3 * MAX_LIVE_DEBITS;
        SpendGrant memory m = _grant(windowSeconds, 997, 5_000_000, type(uint192).max, 5);
        bytes32 h = _hashOf(m);

        uint256[] memory amounts = new uint256[](totalSteps);
        uint256 sum;

        for (uint256 k = 0; k < totalSteps; k++) {
            vm.warp(block.timestamp + 1);
            uint256 amount = (k % 997) + 1;
            amounts[k] = amount;

            (bool ok,) = _tryConsume(m, amount);
            assertTrue(ok);

            sum += amount;
            if (k >= MAX_LIVE_DEBITS) sum -= amounts[k - MAX_LIVE_DEBITS];
            uint256 expectedLive = k + 1 < MAX_LIVE_DEBITS ? k + 1 : MAX_LIVE_DEBITS;

            (uint256 rolling, uint256 liveCalls) = registry.rollingUsage(h, NATIVE);
            assertEq(rolling, sum);
            assertEq(liveCalls, expectedLive);

            if (k + 1 >= MAX_LIVE_DEBITS && k % 300 == 0) {
                (bool extraOk, Reason extraReason) = _tryConsume(m, 1);
                assertFalse(extraOk);
                assertEq(uint8(extraReason), uint8(Reason.WINDOW_FULL));
            }
        }

        vm.warp(block.timestamp + 2);
        sum -= amounts[totalSteps - MAX_LIVE_DEBITS];
        sum -= amounts[totalSteps - MAX_LIVE_DEBITS + 1];
        (uint256 rollingFinal, uint256 liveFinal) = registry.rollingUsage(h, NATIVE);
        assertEq(liveFinal, MAX_LIVE_DEBITS - 2);
        assertEq(rollingFinal, sum);
    }

    /// @dev 3a: when the window is full AND the spend would also exceed the window cap, the
    /// registry must revert OVER_WINDOW_CAP (checked before WINDOW_FULL), not WINDOW_FULL.
    function test_ordering_overWindowCapBeforeWindowFull() public {
        uint64 windowSeconds = 365 days;
        SpendGrant memory m = _grant(windowSeconds, 1, MAX_LIVE_DEBITS, type(uint192).max, 3);

        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            (bool stepOk,) = _tryConsume(m, 1);
            assertTrue(stepOk);
        }
        // windowSpent == maxPerWindow == MAX_LIVE_DEBITS; ring is also full. Any further spend
        // must be OVER_WINDOW_CAP, not WINDOW_FULL.
        (bool ok, Reason reason) = _tryConsume(m, 1);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(Reason.OVER_WINDOW_CAP));
    }

    /// @dev 3b: an amount exceeding type(uint192).max reverts OVER_TX_CAP, using a grant whose
    /// maxPerCall would otherwise allow it.
    function test_ordering_overUint192MaxRevertsOverTxCap() public {
        SpendGrant memory m = _grant(1000, type(uint256).max, type(uint256).max, type(uint256).max, 4);

        (bool okMax,) = _tryConsume(m, type(uint192).max);
        assertTrue(okMax);

        (bool okOver, Reason reason) = _tryConsume(m, uint256(type(uint192).max) + 1);
        assertFalse(okOver);
        assertEq(uint8(reason), uint8(Reason.OVER_TX_CAP));
    }

    /// @dev 3c: when the ring is also full, OVER_CUMULATIVE_CAP must be checked (and revert)
    /// before WINDOW_FULL. windowSeconds 100, maxPerCall 10, maxPerWindow 1030, maxTotal 1034:
    /// spend 10, warp a full window (so it expires), then spend 1 x MAX_LIVE_DEBITS in one block
    /// (spent reaches exactly maxTotal, ring reaches exactly MAX_LIVE_DEBITS live). The next
    /// spend of 1 is within the window cap (1024+1 <= 1030) but over the cumulative cap.
    function test_ordering_overCumulativeCapBeforeWindowFull() public {
        uint64 windowSeconds = 100;
        SpendGrant memory m = _grant(windowSeconds, 10, 1030, 1034, 6);

        (bool ok0,) = _tryConsume(m, 10);
        assertTrue(ok0);

        vm.warp(block.timestamp + windowSeconds);

        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            (bool stepOk,) = _tryConsume(m, 1);
            assertTrue(stepOk);
        }

        (bool ok, Reason reason) = _tryConsume(m, 1);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(Reason.OVER_CUMULATIVE_CAP));
    }

    // -- liveDebits -----------------------------------------------------------------------------

    function test_liveDebits_emptyBeforeAnyDebit() public view {
        SpendGrant memory m = _grant(100, 10, 100, 1000, 21);
        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(_hashOf(m), NATIVE, 10);
        assertEq(expiresAt.length, 0);
        assertEq(amounts.length, 0);
    }

    /// @dev Oldest first, exact expiry boundary (a debit is gone at block.timestamp == expiresAt),
    /// same-block debits kept in order, and expired-but-not-yet-evicted debits skipped by the view.
    function test_liveDebits_oldestFirstAndExactBoundary() public {
        SpendGrant memory m = _grant(100, 10, 100, 1000, 22);
        bytes32 h = _hashOf(m);
        uint256 t0 = vm.getBlockTimestamp();

        _mustConsume(m, 5);
        vm.warp(t0 + 10);
        _mustConsume(m, 7);
        _mustConsume(m, 3);
        vm.warp(t0 + 60);
        _mustConsume(m, 9);

        uint256[] memory wantAt = new uint256[](4);
        uint256[] memory wantAmt = new uint256[](4);
        (wantAt[0], wantAt[1], wantAt[2], wantAt[3]) = (t0 + 100, t0 + 110, t0 + 110, t0 + 160);
        (wantAmt[0], wantAmt[1], wantAmt[2], wantAmt[3]) = (5, 7, 3, 9);
        _assertLive(h, wantAt, wantAmt);

        vm.warp(t0 + 99);
        _assertLive(h, wantAt, wantAmt);

        vm.warp(t0 + 100);
        _assertLive(h, _drop(wantAt, 1), _drop(wantAmt, 1));

        vm.warp(t0 + 110);
        _assertLive(h, _drop(wantAt, 3), _drop(wantAmt, 3));

        vm.warp(t0 + 160);
        _assertLive(h, _drop(wantAt, 4), _drop(wantAmt, 4));
    }

    function test_liveDebits_maxCountTruncatesOldestFirst() public {
        SpendGrant memory m = _grant(100, 10, 100, 1000, 23);
        bytes32 h = _hashOf(m);
        uint256 t0 = vm.getBlockTimestamp();
        _mustConsume(m, 1);
        vm.warp(t0 + 1);
        _mustConsume(m, 2);
        vm.warp(t0 + 2);
        _mustConsume(m, 3);

        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(h, NATIVE, 2);
        assertEq(expiresAt.length, 2);
        assertEq(amounts[0], 1);
        assertEq(amounts[1], 2);
        assertEq(expiresAt[0], t0 + 100);
        assertEq(expiresAt[1], t0 + 101);

        (expiresAt, amounts) = registry.liveDebits(h, NATIVE, 0);
        assertEq(expiresAt.length, 0);
        assertEq(amounts.length, 0);
    }

    /// @dev After the ring wraps, the view still returns the newest MAX_LIVE_DEBITS debits in order,
    /// with each expiry equal to its own spend time plus the window.
    function test_liveDebits_orderAcrossWrap() public {
        uint64 windowSeconds = uint64(MAX_LIVE_DEBITS);
        SpendGrant memory m = _grant(windowSeconds, 10, type(uint192).max, type(uint192).max, 24);
        bytes32 h = _hashOf(m);
        uint256 t0 = vm.getBlockTimestamp();
        uint256 steps = MAX_LIVE_DEBITS + 476;
        for (uint256 k = 0; k < steps; k++) {
            vm.warp(t0 + k);
            _mustConsume(m, 1 + (k % 7));
        }

        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(h, NATIVE, type(uint256).max);
        assertEq(expiresAt.length, MAX_LIVE_DEBITS);
        uint256 firstK = steps - MAX_LIVE_DEBITS;
        uint256 sum;
        for (uint256 i = 0; i < expiresAt.length; i++) {
            uint256 k = firstK + i;
            assertEq(expiresAt[i], t0 + k + windowSeconds);
            assertEq(amounts[i], 1 + (k % 7));
            sum += amounts[i];
        }
        (uint256 rolling, uint256 liveCalls) = registry.rollingUsage(h, NATIVE);
        assertEq(sum, rolling);
        assertEq(expiresAt.length, liveCalls);
    }

    /// @dev Stored head past MAX_LIVE_DEBITS with an expired-but-unevicted prefix whose skip crosses
    /// physical slot 1023 -> 0, then maxCount below the live count while that prefix exists.
    function test_liveDebits_prefixSkipAcrossWrapWithHeadPastCapacity() public {
        uint64 w = 100;
        SpendGrant memory m = _grant(w, 10, type(uint192).max, type(uint192).max, 25);
        bytes32 h = _hashOf(m);
        uint256 t = vm.getBlockTimestamp();

        _consumeMany(m, MAX_LIVE_DEBITS, 1); // logical 0..1023 at t
        vm.warp(t + 100);
        _consumeMany(m, 1000, 2); // evicts the first batch: head = 1024; logical 1024..2023 at t+100
        vm.warp(t + 150);
        _consumeMany(m, 24, 3); // logical 2024..2047 (physical 1000..1023) at t+150; ring full
        (bool ok, Reason why) = _tryConsume(m, 1);
        assertFalse(ok);
        assertEq(uint8(why), uint8(Reason.WINDOW_FULL));

        vm.warp(t + 200);
        _consumeMany(m, 500, 4); // evicts through logical 2023: head = 2024; logical 2048..2547 at t+200
        vm.warp(t + 250); // logical 2024..2047 expired but not evicted; the skip crosses 1023 -> 0

        (uint256[] memory at, uint256[] memory amt) = registry.liveDebits(h, NATIVE, type(uint256).max);
        assertEq(at.length, 500);
        for (uint256 i = 0; i < at.length; i++) {
            assertEq(at[i], t + 300);
            assertEq(amt[i], 4);
        }
        (uint256 rolling, uint256 calls) = registry.rollingUsage(h, NATIVE);
        assertEq(rolling, 2000);
        assertEq(calls, 500);

        (at, amt) = registry.liveDebits(h, NATIVE, 1);
        assertEq(at.length, 1);
        assertEq(at[0], t + 300);
        assertEq(amt[0], 4);

        (at, amt) = registry.liveDebits(h, NATIVE, 0);
        assertEq(at.length, 0);
    }

    /// @dev maxCount below the live count while an expired-but-unevicted prefix exists.
    function test_liveDebits_truncateAfterExpiredPrefix() public {
        SpendGrant memory m = _grant(100, 10, 100, 1000, 26);
        bytes32 h = _hashOf(m);
        uint256 t = vm.getBlockTimestamp();
        _mustConsume(m, 5);
        vm.warp(t + 50);
        _mustConsume(m, 6);
        vm.warp(t + 60);
        _mustConsume(m, 7);
        vm.warp(t + 100); // first debit expired, not evicted

        (uint256[] memory at, uint256[] memory amt) = registry.liveDebits(h, NATIVE, 1);
        assertEq(at.length, 1);
        assertEq(amt[0], 6);
        assertEq(at[0], t + 150);
        (at, amt) = registry.liveDebits(h, NATIVE, 2);
        assertEq(at.length, 2);
        assertEq(amt[1], 7);
    }

    /// @dev An asset the grant never spent returns nothing, even when another asset has debits.
    function test_liveDebits_unusedAssetIsEmpty() public {
        SpendGrant memory m = _grant(100, 10, 100, 1000, 27);
        _mustConsume(m, 5);
        (uint256[] memory at, uint256[] memory amt) =
            registry.liveDebits(_hashOf(m), address(0x1234), type(uint256).max);
        assertEq(at.length, 0);
        assertEq(amt.length, 0);
    }

    function _consumeMany(SpendGrant memory m, uint256 count, uint256 amount) internal {
        for (uint256 i = 0; i < count; i++) {
            _mustConsume(m, amount);
        }
    }

    function _mustConsume(SpendGrant memory m, uint256 amount) internal {
        (bool ok,) = _tryConsume(m, amount);
        assertTrue(ok);
    }

    function _assertLive(bytes32 h, uint256[] memory wantAt, uint256[] memory wantAmt) internal view {
        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(h, NATIVE, type(uint256).max);
        assertEq(expiresAt, wantAt);
        assertEq(amounts, wantAmt);
        (uint256 rolling, uint256 liveCalls) = registry.rollingUsage(h, NATIVE);
        uint256 sum;
        for (uint256 i = 0; i < amounts.length; i++) {
            sum += amounts[i];
        }
        assertEq(sum, rolling);
        assertEq(amounts.length, liveCalls);
    }

    /// @dev Copy of `a` without its first `n` elements.
    function _drop(uint256[] memory a, uint256 n) internal pure returns (uint256[] memory out) {
        out = new uint256[](a.length - n);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = a[n + i];
        }
    }
}
