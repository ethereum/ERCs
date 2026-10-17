// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {ChainlinkConversionOracle} from "../src/oracles/ChainlinkConversionOracle.sol";
import {ComposedConversionOracle} from "../src/oracles/ComposedConversionOracle.sol";
import {AttestedConversionOracle} from "../src/oracles/AttestedConversionOracle.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {MockERC20} from "./FinancialLease.t.sol";

contract OracleAdaptersTest is Test {
    MockAggregator feedA;
    MockAggregator feedB;

    /// @dev T21 needs an "old" timestamp fixed BEFORE a vm.warp
    ///      and compared AFTER it. With the optimizer enabled, solc treats
    ///      block.timestamp as pure within the tx and may rematerialize
    ///      the TIMESTAMP opcode at the point of use instead of reading the
    ///      saved local -- correct under real EVM semantics (the
    ///      timestamp does not change within a tx), but it breaks tests that use
    ///      vm.warp (a cheatcode solc does not know about) to simulate time
    ///      passing between "instants" within the same test tx.
    ///      A contract constant does not suffer from this.
    uint64 internal constant FEED_TS = 1_700_000_000;

    address owner = makeAddr("owner");
    address attester = makeAddr("attester");
    address rando = makeAddr("rando");

    function setUp() public {
        feedA = new MockAggregator(8);
        feedB = new MockAggregator(8);
    }

    // ─── T20: decimal scaling feed -> payment asset ───────────

    function test_T20_scalingAcrossDecimals() public {
        feedA.setAnswer(1500e8);
        feedA.setUpdatedAt(block.timestamp);

        ChainlinkConversionOracle o6 = new ChainlinkConversionOracle(address(feedA), 6);
        (uint256 rate6,) = o6.latestRate();
        assertEq(rate6, 1500e6, "8-dec feed + 6-dec payment must give 1500e6");

        ChainlinkConversionOracle o18 = new ChainlinkConversionOracle(address(feedA), 18);
        (uint256 rate18,) = o18.latestRate();
        assertEq(rate18, 1500e18, "8-dec feed + 18-dec payment must give 1500e18");
    }

    // ─── T21: asOf = the feed's updatedAt, not block.timestamp ──

    function test_T21_asOfTracksFeedNotBlockTimestamp() public {
        vm.warp(FEED_TS);
        feedA.setAnswer(1e8);
        feedA.setUpdatedAt(FEED_TS);

        ChainlinkConversionOracle o = new ChainlinkConversionOracle(address(feedA), 18);
        vm.warp(FEED_TS + 30 days);

        (, uint64 asOf) = o.latestRate();
        assertEq(asOf, FEED_TS, "asOf must be the feed's updatedAt, not the current timestamp");
    }

    // ─── T22: invalid feed answers ────────────────────────────

    function test_T22_invalidAnswerReverts() public {
        ChainlinkConversionOracle o = new ChainlinkConversionOracle(address(feedA), 18);

        feedA.setAnswer(0);
        feedA.setUpdatedAt(block.timestamp);
        vm.expectRevert(ChainlinkConversionOracle.InvalidAnswer.selector);
        o.latestRate();

        feedA.setAnswer(-1);
        vm.expectRevert(ChainlinkConversionOracle.InvalidAnswer.selector);
        o.latestRate();

        feedA.setAnswer(1e8);
        feedA.setUpdatedAt(0);
        vm.expectRevert(ChainlinkConversionOracle.IncompleteRound.selector);
        o.latestRate();
    }

    // ─── T23: composition of two feeds ────────────────────────

    function test_T23_composedRateAndAsOf() public {
        // feedA: UVA/ARS = 100, feedB: ARS/USD = 0.001 (both 8 decimals)
        feedA.setAnswer(100e8);
        feedA.setUpdatedAt(1_000_000);
        feedB.setAnswer(0.001e8);
        feedB.setUpdatedAt(2_000_000);

        ComposedConversionOracle o = new ComposedConversionOracle(address(feedA), address(feedB), false, 6);
        (uint256 rate, uint64 asOf) = o.latestRate();

        assertEq(rate, 0.1e6, "composed rate must be the normalized product");
        assertEq(asOf, 1_000_000, "asOf must be the older of the two feeds");

        // invertB: feedB is quoted the other way round (USD/ARS = 1000) and is inverted to
        // obtain the same effective ARS/USD = 0.001.
        feedB.setAnswer(1000e8);
        ComposedConversionOracle oInv = new ComposedConversionOracle(address(feedA), address(feedB), true, 6);
        (uint256 rateInv,) = oInv.latestRate();
        assertEq(rateInv, 0.1e6, "invertB must divide instead of multiplying");
    }

    // ─── T24: attested oracle ──────────────────────────────────

    function test_T24_attestedOracle() public {
        AttestedConversionOracle o = new AttestedConversionOracle(owner, attester);

        vm.expectRevert(AttestedConversionOracle.NotYetAttested.selector);
        o.latestRate();

        vm.prank(rando);
        vm.expectRevert(AttestedConversionOracle.NotAttester.selector);
        o.attest(2e18);

        vm.prank(attester);
        o.attest(2e18);
        (uint256 rate, uint64 asOf) = o.latestRate();
        assertEq(rate, 2e18);
        assertEq(asOf, uint64(block.timestamp));
    }

    // ─── T25: end-to-end with the lease ─────────────────────────

    function test_T25_endToEndWithLease() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        address lessor = makeAddr("lessor25");
        address lessee = makeAddr("lessee25");

        token.mint(lessee, 1_000_000e6);
        vm.prank(lessee);
        token.approve(address(lease), type(uint256).max);

        feedA.setAnswer(1e8); // initial 1:1 rate
        feedA.setUpdatedAt(block.timestamp);
        ChainlinkConversionOracle oracle = new ChainlinkConversionOracle(address(feedA), 6);

        uint64[] memory dueDates = new uint64[](3);
        uint256[] memory unitAmounts = new uint256[](3);
        dueDates[0] = uint64(block.timestamp) + 30 days;
        dueDates[1] = uint64(block.timestamp) + 60 days;
        dueDates[2] = uint64(block.timestamp) + 90 days;
        unitAmounts[0] = 100e18;
        unitAmounts[1] = 100e18;
        unitAmounts[2] = 100e18;

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10e18,
            penaltyBpsPerDay: 10,
            defaultDeclarer: address(0),
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        uint256 id = lease.createLease(p);

        (uint256 assets1,) = lease.nextPayment(id);
        vm.prank(lessee);
        lease.pay(id, assets1);
        uint256 unitsAfterFirst = lease.outstandingUnits(id);

        // Move the feed: the same nominal installment now costs more assets
        feedA.setAnswer(2e8);
        feedA.setUpdatedAt(block.timestamp);
        (uint256 assets2,) = lease.nextPayment(id);
        assertTrue(assets2 > assets1, "with the feed moved, the installment must cost more assets");

        vm.prank(lessee);
        lease.pay(id, assets2);
        assertEq(
            unitsAfterFirst - lease.outstandingUnits(id),
            100e18,
            "unitsSettled must advance by schedule units, not by assets"
        );

        // A third installment is still pending (the lease is still Active, not
        // Completed): with the feed frozen beyond maxOracleStaleness,
        // pay() must revert StaleOracle instead of trying to charge.
        vm.warp(block.timestamp + 8 days);
        vm.prank(lessee);
        vm.expectRevert(FinancialLease.StaleOracle.selector);
        lease.pay(id, 1e6);
    }

    // ─── T26: fix S1-02 — out-of-range feed decimals revert ──

    function test_T26_decimalsOutOfRangeReverts() public {
        feedA.setDecimals(31); // MAX_SANE_DECIMALS = 30
        vm.expectRevert(ChainlinkConversionOracle.DecimalsOutOfRange.selector);
        new ChainlinkConversionOracle(address(feedA), 18);

        feedA.setDecimals(30); // the exact limit must pass
        new ChainlinkConversionOracle(address(feedA), 18);

        feedA.setDecimals(31);
        feedB.setDecimals(8);
        vm.expectRevert(ComposedConversionOracle.DecimalsOutOfRange.selector);
        new ComposedConversionOracle(address(feedA), address(feedB), false, 18);

        feedA.setDecimals(8);
        feedB.setDecimals(31);
        vm.expectRevert(ComposedConversionOracle.DecimalsOutOfRange.selector);
        new ComposedConversionOracle(address(feedA), address(feedB), false, 18);
    }

    // ─── T27: fix S2-01 — a future asOf reverts in pay(), no underflow ──

    function test_T27_futureAsOfReverts() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        address lessor27 = makeAddr("lessor27");
        address lessee27 = makeAddr("lessee27");
        token.mint(lessee27, 1_000_000e6);
        vm.prank(lessee27);
        token.approve(address(lease), type(uint256).max);

        feedA.setAnswer(1e8);
        feedA.setUpdatedAt(block.timestamp + 1000); // future asOf
        ChainlinkConversionOracle oracle = new ChainlinkConversionOracle(address(feedA), 6);

        uint64[] memory dueDates = new uint64[](1);
        uint256[] memory unitAmounts = new uint256[](1);
        dueDates[0] = uint64(block.timestamp) + 30 days;
        unitAmounts[0] = 100e18;

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee27,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 0, // no limit -- isolates the future-asOf guard from the staleness check
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 0,
            penaltyBpsPerDay: 10,
            defaultDeclarer: address(0),
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor27);
        uint256 id = lease.createLease(p);

        vm.prank(lessee27);
        vm.expectRevert(FinancialLease.FutureObservation.selector);
        lease.pay(id, 1e6);
    }

    // ─── T28: fix S2-02 — feed decimals changed after deploy revert ──

    function test_T28_decimalsChangedAfterConstructionReverts() public {
        feedA.setAnswer(1e8);
        feedA.setUpdatedAt(block.timestamp);
        ChainlinkConversionOracle o = new ChainlinkConversionOracle(address(feedA), 18);
        o.latestRate(); // works normally

        feedA.setDecimals(6); // the feed "changes" convention after deploy
        vm.expectRevert(ChainlinkConversionOracle.DecimalsChanged.selector);
        o.latestRate();

        // ComposedConversionOracle: same criterion, for either of the two feeds
        feedA.setDecimals(8);
        feedB.setAnswer(1e8);
        feedB.setUpdatedAt(block.timestamp);
        ComposedConversionOracle co = new ComposedConversionOracle(address(feedA), address(feedB), false, 18);
        co.latestRate();

        feedB.setDecimals(6);
        vm.expectRevert(ComposedConversionOracle.DecimalsChanged.selector);
        co.latestRate();
    }

    // ─── T29: fix S2-03 — attesting rate = 0 reverts ───────────────────

    function test_T29_attestZeroRateReverts() public {
        AttestedConversionOracle o = new AttestedConversionOracle(owner, attester);

        vm.prank(attester);
        vm.expectRevert(AttestedConversionOracle.InvalidRate.selector);
        o.attest(0);

        vm.prank(attester);
        o.attest(1e18); // a later valid attestation does work
        (uint256 rate,) = o.latestRate();
        assertEq(rate, 1e18);
    }

    // ─── T30: fix S2-08 — explicit division by zero in ComposedConversionOracle ──

    function test_T30_composedZeroDenominatorReverts() public {
        feedA.setAnswer(100e8);
        feedA.setUpdatedAt(block.timestamp);

        // feedB normalizes to exactly 0: minimal raw price (1) with
        // the maximum allowed decimals (30) -> 1 * 1e18 / 1e30 = 0
        // (floor).
        feedB.setDecimals(30);
        feedB.setAnswer(1);
        feedB.setUpdatedAt(block.timestamp);

        ComposedConversionOracle o = new ComposedConversionOracle(address(feedA), address(feedB), true, 18);
        vm.expectRevert(ComposedConversionOracle.InvalidAnswer.selector);
        o.latestRate();
    }
}
