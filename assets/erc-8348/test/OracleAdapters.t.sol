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

    address owner = makeAddr("owner");
    address attester = makeAddr("attester");
    address rando = makeAddr("rando");

    function setUp() public {
        feedA = new MockAggregator(8);
        feedB = new MockAggregator(8);
    }

    // ─── T20: escalado de decimales feed -> payment asset ────

    function test_T20_scalingAcrossDecimals() public {
        feedA.setAnswer(1500e8);
        feedA.setUpdatedAt(block.timestamp);

        ChainlinkConversionOracle o6 = new ChainlinkConversionOracle(address(feedA), 6);
        (uint256 rate6,) = o6.latestRate();
        assertEq(rate6, 1500e6, "feed 8 dec + pay 6 dec debe dar 1500e6");

        ChainlinkConversionOracle o18 = new ChainlinkConversionOracle(address(feedA), 18);
        (uint256 rate18,) = o18.latestRate();
        assertEq(rate18, 1500e18, "feed 8 dec + pay 18 dec debe dar 1500e18");
    }

    // ─── T21: asOf = updatedAt del feed, no block.timestamp ──

    function test_T21_asOfTracksFeedNotBlockTimestamp() public {
        uint256 oldUpdatedAt = block.timestamp;
        feedA.setAnswer(1e8);
        feedA.setUpdatedAt(oldUpdatedAt);

        ChainlinkConversionOracle o = new ChainlinkConversionOracle(address(feedA), 18);
        vm.warp(block.timestamp + 30 days);

        (, uint64 asOf) = o.latestRate();
        assertEq(asOf, uint64(oldUpdatedAt), "asOf debe ser el updatedAt del feed, no el timestamp actual");
    }

    // ─── T22: respuestas invalidas del feed ───────────────────

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

    // ─── T23: composicion de dos feeds ────────────────────────

    function test_T23_composedRateAndAsOf() public {
        // feedA: UVA/ARS = 100, feedB: ARS/USD = 0.001 (ambos 8 decimales)
        feedA.setAnswer(100e8);
        feedA.setUpdatedAt(1_000_000);
        feedB.setAnswer(0.001e8);
        feedB.setUpdatedAt(2_000_000);

        ComposedConversionOracle o = new ComposedConversionOracle(address(feedA), address(feedB), false, 6);
        (uint256 rate, uint64 asOf) = o.latestRate();

        assertEq(rate, 0.1e6, "rate compuesto debe ser el producto normalizado");
        assertEq(asOf, 1_000_000, "asOf debe ser el mas viejo de los dos feeds");

        // invertB: feedB cotiza al reves (USD/ARS = 1000) y se invierte para
        // obtener el mismo ARS/USD = 0.001 efectivo.
        feedB.setAnswer(1000e8);
        ComposedConversionOracle oInv = new ComposedConversionOracle(address(feedA), address(feedB), true, 6);
        (uint256 rateInv,) = oInv.latestRate();
        assertEq(rateInv, 0.1e6, "invertB debe dividir en lugar de multiplicar");
    }

    // ─── T24: oraculo atestado ─────────────────────────────────

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

    // ─── T25: end-to-end con el lease ───────────────────────────

    function test_T25_endToEndWithLease() public {
        FinancialLease lease = new FinancialLease();
        MockERC20 token = new MockERC20();
        address lessor = makeAddr("lessor25");
        address lessee = makeAddr("lessee25");

        token.mint(lessee, 1_000_000e6);
        vm.prank(lessee);
        token.approve(address(lease), type(uint256).max);

        feedA.setAnswer(1e8); // rate 1:1 inicial
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

        // Mover el feed: la misma cuota nominal ahora cuesta mas assets
        feedA.setAnswer(2e8);
        feedA.setUpdatedAt(block.timestamp);
        (uint256 assets2,) = lease.nextPayment(id);
        assertTrue(assets2 > assets1, "con el feed movido, la cuota debe costar mas assets");

        vm.prank(lessee);
        lease.pay(id, assets2);
        assertEq(
            unitsAfterFirst - lease.outstandingUnits(id),
            100e18,
            "unitsSettled debe avanzar por unidades de cronograma, no por assets"
        );

        // Queda una tercera cuota pendiente (el lease sigue Active, no
        // Completed): con el feed congelado mas alla de maxOracleStaleness,
        // pay() debe revertir StaleOracle en lugar de intentar cobrar.
        vm.warp(block.timestamp + 8 days);
        vm.prank(lessee);
        vm.expectRevert(FinancialLease.StaleOracle.selector);
        lease.pay(id, 1e6);
    }
}
