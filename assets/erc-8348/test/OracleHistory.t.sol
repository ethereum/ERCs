// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";
import {IConversionOracle} from "../src/IConversionOracle.sol";
import {IFinancialLease} from "../src/IFinancialLease.sol";
import {ChainlinkConversionOracle} from "../src/oracles/ChainlinkConversionOracle.sol";
import {ComposedConversionOracle} from "../src/oracles/ComposedConversionOracle.sol";
import {AttestedConversionOracle} from "../src/oracles/AttestedConversionOracle.sol";
import {FreshnessHistory, NoRoundHistory} from "../src/oracles/FreshnessHistory.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {MockERC20} from "./FinancialLease.t.sol";

/// @dev A "Chainlink-compatible" feed without usable round history:
///      latestRoundData returns round id 0 and getRoundData is absent.
contract LegacyAggregator {
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 1e8, block.timestamp, block.timestamp, 0);
    }
}

/// @dev Generic oracle that reports a zero rate and claims a fresh history.
contract ZeroRateOracle {
    function latestRate() external view returns (uint256, uint64) {
        return (0, uint64(block.timestamp));
    }

    function continuouslyFresh(uint64, uint64, uint64) external pure returns (bool) {
        return true;
    }
}

/// @dev History that never proves freshness.
contract NeverFreshOracle {
    function latestRate() external view returns (uint256, uint64) {
        return (1e18, uint64(block.timestamp));
    }

    function continuouslyFresh(uint64, uint64, uint64) external pure returns (bool) {
        return false;
    }
}

/// @dev An IConversionOracle without IConversionOracleHistory.
contract NoHistoryOracle is IConversionOracle {
    function latestRate() external view returns (uint256, uint64) {
        return (1e18, uint64(block.timestamp));
    }
}

/// @title Oracle history (IConversionOracleHistory) and the lease's use of it
/// @dev Timestamps are absolute constants (T0 + k), never a saved
///      block.timestamp: see the optimizer note in OracleAdapters.t.sol.
contract OracleHistoryTest is Test {
    uint64 internal constant T0 = 1_700_000_000;
    uint64 internal constant TOL = 1500;

    MockAggregator feed;
    ChainlinkConversionOracle cl;

    function setUp() public {
        vm.warp(T0 + 10_000);
        feed = new MockAggregator(8);
        cl = new ChainlinkConversionOracle(address(feed), 18);
    }

    function _rounds(uint64[] memory offsets) internal {
        for (uint256 i = 0; i < offsets.length; i++) {
            feed.pushRound(1e8, T0 + offsets[i]);
        }
    }

    function _arr3(uint64 a, uint64 b, uint64 c) internal pure returns (uint64[] memory r) {
        r = new uint64[](3);
        (r[0], r[1], r[2]) = (a, b, c);
    }

    // ─── H1: no gap -> fresh over the whole window ───────────────────────
    function test_H1_chainlink_noGapIsFresh() public {
        _rounds(_arr3(1000, 2000, 3000));
        assertTrue(cl.continuouslyFresh(T0 + 1000, T0 + 3000, TOL));
        // gap exactly equal to the tolerance is not stale
        assertTrue(cl.continuouslyFresh(T0 + 1000, T0 + 2500, 1000));
    }

    // ─── H2: a gap > tolerance inside the window -> not fresh ─────────────
    function test_H2_chainlink_gapInsideWindowIsStale() public {
        _rounds(_arr3(1000, 1100, 3000)); // gap 1900 > 1500
        assertFalse(cl.continuouslyFresh(T0 + 1000, T0 + 3000, TOL));
        assertFalse(cl.continuouslyFresh(T0 + 2600, T0 + 3000, TOL), "instant 2600 is 1500+ old");
        assertTrue(cl.continuouslyFresh(T0 + 3000, T0 + 3000, TOL), "fresh at the recovery itself");
        assertTrue(cl.continuouslyFresh(T0 + 1000, T0 + 2500, TOL), "window before the gap");
    }

    // ─── H3: an unusable round counts as an outage ──────────────────────
    /// @dev While a round with answer <= 0 is the latest, latestRate reverts
    ///      and pay() is impossible, even though no time gap exceeds the
    ///      tolerance. The walk must treat that interval as stale, or the
    ///      declarer could act in the block the feed recovers.
    function test_H3_chainlink_invalidRoundIsAnOutage() public {
        feed.pushRound(1e8, T0 + 1000);
        feed.pushRound(0, T0 + 1010); // latestRate reverts from here...
        feed.pushRound(1e8, T0 + 1400); // ...until here; no gap > 1500
        assertFalse(cl.continuouslyFresh(T0 + 1000, T0 + 1400, TOL), "invalid interval inside the window");
        assertTrue(cl.continuouslyFresh(T0 + 1400, T0 + 1400, TOL), "window after the invalid interval");
        feed.pushRound(1e8, T0 + 2000);
        assertTrue(cl.continuouslyFresh(T0 + 1400, T0 + 2000, TOL));
    }

    // ─── H4: history that does not reach back -> false, no revert ────────
    function test_H4_chainlink_historyTooShortIsFalse() public {
        _rounds(_arr3(1000, 2000, 3000));
        assertFalse(cl.continuouslyFresh(T0 + 500, T0 + 3000, TOL));
    }

    // ─── H5: round cap -> fail-closed ────────────────────────────────────
    function test_H5_chainlink_roundCapFailsClosed() public {
        uint256 n = FreshnessHistory.MAX_STEPS + 50;
        for (uint256 i = 0; i < n; i++) {
            feed.pushRound(1e8, T0 + i);
        }
        uint64 last = uint64(T0 + n - 1);
        assertTrue(cl.continuouslyFresh(last - 100, last, TOL), "inside the cap");
        assertFalse(cl.continuouslyFresh(T0 + 10, last, TOL), "beyond the cap: not proven");
    }

    // ─── H6: composition is fresh iff both feeds are ─────────────────────
    function test_H6_composed_requiresBothFeeds() public {
        MockAggregator b = new MockAggregator(8);
        _rounds(_arr3(1000, 2000, 3000));
        b.pushRound(1e8, T0 + 1000);
        b.pushRound(1e8, T0 + 3000); // gap 2000
        ComposedConversionOracle c = new ComposedConversionOracle(address(feed), address(b), false, 18);
        assertFalse(c.continuouslyFresh(T0 + 1000, T0 + 3000, TOL));
        b.pushRound(1e8, T0 + 3100);
        assertTrue(c.continuouslyFresh(T0 + 3000, T0 + 3000, TOL));
        assertTrue(c.continuouslyFresh(T0 + 1000, T0 + 3000, 2000));
    }

    // ─── H7: attested oracle keeps the recording time of each attestation
    function test_H7_attested_history() public {
        address att = makeAddr("attester");
        AttestedConversionOracle a = new AttestedConversionOracle(address(this), att);
        assertFalse(a.continuouslyFresh(T0 + 10_000, T0 + 10_000, TOL), "never attested: false, no revert");

        vm.warp(T0 + 1000);
        vm.prank(att);
        a.attest(1e18);
        vm.warp(T0 + 3000);
        vm.prank(att);
        a.attest(1e18);
        assertEq(a.attestationCount(), 2);
        assertFalse(a.continuouslyFresh(T0 + 1000, T0 + 3000, TOL));
        assertTrue(a.continuouslyFresh(T0 + 1000, T0 + 3000, 2000));
    }

    // ─── H8: lease origination requires history when a tolerance is set ──
    function test_H8_createLeaseRequiresHistory() public {
        FinancialLease lease = new FinancialLease();
        NoHistoryOracle nh = new NoHistoryOracle();

        vm.expectRevert(FinancialLease.OracleWithoutHistory.selector);
        lease.createLease(_params(address(nh), 7 days));

        vm.expectRevert(FinancialLease.OracleWithoutHistory.selector);
        lease.createLease(_params(address(cl), 1)); // grace would be 0

        // No tolerance: the index is never stale, the rule does not apply.
        uint256 id0 = lease.createLease(_params(address(nh), 0));
        assertEq(lease.recoveryGrace(id0), 0);
        // Fixed denomination.
        uint256 id1 = lease.createLease(_params(address(0), 0));
        assertEq(lease.recoveryGrace(id1), 0);
        // With history.
        uint256 id2 = lease.createLease(_params(address(cl), 7 days));
        assertEq(lease.recoveryGrace(id2), 3.5 days);
    }

    // ─── H9: end-to-end with a Chainlink-style feed ──────────────────────
    function test_H9_leaseWithChainlinkFeed_recoveryGrace() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        address lessee = makeAddr("lessee");
        // tolerance 2 h, grace 1 h; feed heartbeat 30 min
        uint64 tol = 2 hours;
        feed.pushRound(1e8, T0 + 10_000);
        uint256 id = lease.createLease(_paramsFull(address(cl), tol, address(token), lessee, T0 + 10_000 + 1 days));

        // feed updates every 30 min until well past the due date
        uint256 t = T0 + 10_000;
        while (t < T0 + 10_000 + 1 days + 6 hours) {
            t += 30 minutes;
            feed.pushRound(1e8, t);
        }
        vm.warp(t);
        lease.declareDefault(id); // continuously fresh: allowed
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    function test_H10_leaseWithChainlinkFeed_outageThenGrace() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        address lessee = makeAddr("lessee");
        uint64 tol = 2 hours;
        feed.pushRound(1e8, T0 + 10_000);
        uint256 id = lease.createLease(_paramsFull(address(cl), tol, address(token), lessee, T0 + 10_000 + 1 days));

        uint256 t = T0 + 10_000;
        while (t < T0 + 10_000 + 1 days) {
            t += 30 minutes;
            feed.pushRound(1e8, t);
        }
        // 3 h outage straddling the due date, then the feed resumes at t + 3 h
        uint256 r = t + 3 hours;
        vm.warp(r);
        vm.expectRevert(FinancialLease.PaymentPathUnavailable.selector);
        lease.declareDefault(id);

        feed.pushRound(1e8, r);
        vm.expectRevert(FinancialLease.RecoveryGraceActive.selector);
        lease.declareDefault(id);

        feed.pushRound(1e8, r + 30 minutes);
        vm.warp(r + 59 minutes);
        vm.expectRevert(FinancialLease.RecoveryGraceActive.selector);
        lease.declareDefault(id);

        vm.warp(r + 1 hours);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── H11: adapters reject a feed whose rounds cannot be walked ──────
    function test_H11_adapterRejectsFeedWithoutRoundHistory() public {
        LegacyAggregator legacy = new LegacyAggregator();
        vm.expectRevert(NoRoundHistory.selector);
        new ChainlinkConversionOracle(address(legacy), 18);
        vm.expectRevert(NoRoundHistory.selector);
        new ComposedConversionOracle(address(feed), address(legacy), false, 18);
    }

    // ─── H12: gas of the guard at the round cap's edge ───────────────────
    /// @dev Worst case that still succeeds: the grace window spans 250 rounds
    ///      (cap 256). Logged, not asserted: it is the price of rule B with a
    ///      high-frequency feed and a long grace.
    function test_H12_gasNearRoundCap() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        uint64 tol = 2 hours; // G = 1 h
        feed.pushRound(1e8, T0 + 10_000);
        uint256 id = lease.createLease(_paramsFull(address(cl), tol, address(token), makeAddr("lessee"), T0 + 10_000 + 1));
        uint256 t = T0 + 10_000;
        for (uint256 i = 0; i < 250; i++) {
            t += 15; // 250 rounds in 3750 s > G
            feed.pushRound(1e8, t);
        }
        vm.warp(t);
        uint256 g0 = gasleft();
        lease.declareDefault(id);
        emit log_named_uint("declareDefault gas, ~240 rounds in the grace window", g0 - gasleft());
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── H13: no tolerance, unusable rate -> default still blocked ───────
    /// @dev With maxStaleness = 0 the index is never "stale", but if the rate
    ///      cannot be read, pay() reverts, so default actions must revert too.
    function test_H13_zeroTolerance_unreadableRateBlocksDefault() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        feed.pushRound(1e8, T0 + 10_000);
        uint256 id = lease.createLease(_paramsFull(address(cl), 0, address(token), makeAddr("lessee"), T0 + 10_000 + 1));
        vm.warp(T0 + 10_000 + 1 days);
        feed.pushRound(0, T0 + 10_000 + 1 days); // invalid answer: latestRate reverts
        vm.expectRevert(ChainlinkConversionOracle.InvalidAnswer.selector);
        lease.declareDefault(id);
        feed.pushRound(1e8, T0 + 10_000 + 1 days);
        lease.declareDefault(id); // rate readable again, no tolerance: allowed
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── H14: a zero rate now blocks default actions ─────────────────────
    function test_H14_zeroRateBlocksDefault() public {
        FinancialLease lease = new FinancialLease();
        ZeroRateOracle z = new ZeroRateOracle();
        uint256 id = lease.createLease(_paramsFull(address(z), 7 days, makeAddr("token"), makeAddr("lessee"), T0 + 10_000 + 1));
        vm.warp(T0 + 10_000 + 1 days);
        vm.expectRevert(FinancialLease.PaymentPathUnavailable.selector);
        lease.declareDefault(id);
    }

    // ─── H15: stored histories cannot hold unusable entries ──────────────
    /// @dev walkStored sees timestamps only, so the stored-history oracles
    ///      must reject unusable values at write time.
    function test_H15_storedHistoriesRejectZeroRate() public {
        MockUVAOracle m = new MockUVAOracle(1e18);
        vm.expectRevert(MockUVAOracle.InvalidRate.selector);
        m.set(0);
        address att = makeAddr("attester");
        AttestedConversionOracle a = new AttestedConversionOracle(address(this), att);
        vm.prank(att);
        vm.expectRevert(AttestedConversionOracle.InvalidRate.selector);
        a.attest(0);
    }

    // ─── H17: more than 256 rounds within G -> default blocked (liveness loss)
    /// @dev Documents the cost of fail-closed: the feed is fresh the whole
    ///      time (every 6 s, tolerance 1 h, G 30 min = 300 rounds), but the
    ///      walk cannot prove it within 256 steps, so a genuine default is
    ///      refused for as long as that cadence lasts.
    function test_H17_tooManyRoundsInGraceBlocksGenuineDefault() public {
        FinancialLease lease = new FinancialLease();
        uint64 tol = 1 hours;
        feed.pushRound(1e8, T0 + 10_000);
        uint256 id = lease.createLease(_paramsFull(address(cl), tol, makeAddr("token"), makeAddr("lessee"), T0 + 10_000 + 1));
        uint256 t = T0 + 10_000;
        for (uint256 i = 0; i < 400; i++) {
            t += 6;
            feed.pushRound(1e8, t);
        }
        vm.warp(t);
        vm.expectRevert(FinancialLease.RecoveryGraceActive.selector);
        lease.declareDefault(id);
    }

    // ─── H18: an oracle whose history never proves freshness ─────────────
    /// @dev Origination only checks that continuouslyFresh answers; it cannot
    ///      tell useful history from none. Such a lease can never default.
    function test_H18_neverFreshOracleMakesDefaultImpossible() public {
        FinancialLease lease = new FinancialLease();
        NeverFreshOracle nf = new NeverFreshOracle();
        uint256 id = lease.createLease(_paramsFull(address(nf), 7 days, makeAddr("token"), makeAddr("lessee"), T0 + 10_000 + 1));
        vm.warp(T0 + 10_000 + 30 days);
        vm.expectRevert(FinancialLease.RecoveryGraceActive.selector);
        lease.declareDefault(id);
    }

    // ─── H21: same timestamp, one round invalid -> fail closed ───────────
    /// @dev Two rounds share a timestamp; a transaction between them in that
    ///      block would have seen the invalid one, so the window is not proven.
    function test_H21_sameTimestampInvalidRoundFailsClosed() public {
        feed.pushRound(1e8, T0 + 1000);
        feed.pushRound(0, T0 + 1200);
        feed.pushRound(1e8, T0 + 1200);
        assertFalse(cl.continuouslyFresh(T0 + 1000, T0 + 1300, TOL));
        assertTrue(cl.continuouslyFresh(T0 + 1300, T0 + 1300, TOL), "window entirely after the shared timestamp");
    }

    // ─── helpers ─────────────────────────────────────────────────────────
    function _params(address oracle_, uint64 tol) internal returns (FinancialLease.CreateLeaseParams memory) {
        return _paramsFull(oracle_, tol, makeAddr("token"), makeAddr("lessee"), T0 + 100 days);
    }

    function _paramsFull(address oracle_, uint64 tol, address token, address lessee, uint256 due)
        internal
        view
        returns (FinancialLease.CreateLeaseParams memory p)
    {
        uint64[] memory dd = new uint64[](1);
        dd[0] = uint64(due);
        uint256[] memory ua = new uint256[](1);
        ua[0] = 100e18;
        p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "test",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://test/history",
            paymentAsset: token,
            denomSymbol: "UVA",
            oracle: oracle_,
            maxStaleness: tol,
            dueDates: dd,
            unitAmounts: ua,
            purchasePriceUnits: 1e18,
            penaltyBpsPerDay: 10,
            defaultDeclarer: address(this),
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
    }
}
