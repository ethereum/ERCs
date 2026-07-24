// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FinancialLeaseTest is Test {
    FinancialLease lease;
    MockERC20 token;
    MockUVAOracle oracle;

    address lessor = makeAddr("lessor");
    address lessee = makeAddr("lessee");
    address newLessee = makeAddr("newLessee");
    address defaultDeclarer = makeAddr("defaultDeclarer");

    uint64 constant DAY = 1 days;
    uint256 constant UNIT = 1e18;

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        oracle = new MockUVAOracle(1e18);

        token.mint(lessee, 1_000_000e18);
        vm.prank(lessee);
        token.approve(address(lease), type(uint256).max);
    }

    // ─── helpers ────────────────────────────────────────────

    function _schedule(uint256 n, uint256 amountEach)
        internal
        view
        returns (uint64[] memory dueDates, uint256[] memory unitAmounts)
    {
        dueDates = new uint64[](n);
        unitAmounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            dueDates[i] = uint64(block.timestamp) + uint64((i + 1) * 30 days);
            unitAmounts[i] = amountEach;
        }
    }

    function _createLease(address oracle_, uint64 staleness, uint64[] memory dueDates, uint256[] memory unitAmounts)
        internal
        returns (uint256 leaseId)
    {
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: oracle_,
            maxStaleness: staleness,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10, // 0.10%/día
            defaultDeclarer: defaultDeclarer
        });
        vm.prank(lessor);
        leaseId = lease.createLease(p);
    }

    function _defaultLease() internal returns (uint256 leaseId) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        leaseId = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
    }

    function _pay(uint256 leaseId, uint256 assets) internal {
        vm.prank(lessee);
        lease.pay(leaseId, assets);
    }

    // ─── T1: pago con índice móvil ─────────────────────────

    function test_T1_paymentWithMovingIndex() public {
        uint256 id1 = _defaultLease();
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id2 = _createLease(address(oracle), 7 days, dueDates, unitAmounts);

        // Pagar la primera cuota de id1 con rate = 1.0
        (uint256 assets1,) = lease.nextPayment(id1);
        _pay(id1, assets1);

        // Mover el oráculo y pagar la misma cuota nominal en id2
        oracle.set(2e18);
        (uint256 assets2,) = lease.nextPayment(id2);
        _pay(id2, assets2);

        assertEq(lease.outstandingUnits(id1), lease.outstandingUnits(id2), "unitsSettled debe ser identico");
        assertTrue(assets2 > assets1, "assets debe diferir con el rate movido");
        assertEq(assets2, assets1 * 2, "al duplicarse el rate, assets se duplica");
    }

    // ─── T2: redondeo direccional ───────────────────────────

    function test_T2_directionalRounding() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
        oracle.set(1_333_333_333_333_333_333); // rate no divide exacto

        (uint256 assetsDue,) = lease.nextPayment(id);
        // nextPayment usa Ceil -> pagar exactamente eso siempre debe saldar la cuota
        uint256 outstandingBefore = lease.outstandingUnits(id);
        _pay(id, assetsDue);
        assertEq(lease.outstandingUnits(id), outstandingBefore - unitAmounts[0], "la cuota completa debe saldarse");

        // El contrato nunca acredita mas unidades que las efectivamente cubiertas (Floor)
        // Verificado indirectamente: reconstruimos otra lease y pagamos 1 wei menos de asset
        (uint64[] memory dd2, uint256[] memory ua2) = _schedule(1, 100 * UNIT);
        uint256 id2 = _createLease(address(oracle), 7 days, dd2, ua2);
        uint256 underpay = assetsDue - 1;
        uint256 expectedUnitsFloor = (underpay * 1e18) / oracle.rate();
        _pay(id2, underpay);
        assertEq(lease.outstandingUnits(id2), ua2[0] - expectedUnitsFloor, "floor exacto en subpago");
        assertTrue(lease.outstandingUnits(id2) > 0, "1 wei menos no debe saldar la cuota");
    }

    // ─── T3: cesion con flujo ───────────────────────────────

    function test_T3_assignmentMidStream() public {
        uint256 id = _defaultLease();
        (uint256 assets1,) = lease.nextPayment(id);
        _pay(id, assets1);

        // Transferir el NFT (posicion del lessor) a mitad de contrato
        vm.prank(lessor);
        lease.transferFrom(lessor, newLessee, id);
        assertEq(lease.lessor(id), newLessee);

        uint256 balBefore = token.balanceOf(newLessee);
        (uint256 assets2,) = lease.nextPayment(id);
        _pay(id, assets2);

        assertEq(token.balanceOf(newLessee), balBefore + assets2, "el nuevo owner debe recibir el pago");
    }

    // ─── T4: staleness ──────────────────────────────────────

    function test_T4_staleOracleReverts() public {
        uint256 id = _defaultLease();
        oracle.set(1e18); // fija asOf = now

        vm.warp(block.timestamp + 8 days); // maxStaleness = 7 dias

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.StaleOracle.selector);
        lease.pay(id, 100 * UNIT);
    }

    // ─── T5: ciclo de default ───────────────────────────────

    function test_T5_defaultCycle() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate1) = lease.nextPayment(id);

        vm.warp(uint256(dueDate1) + 1 days);
        oracle.set(1e18); // refresca staleness

        // trigger accrual via un pago nulo no es posible (NothingDue si 0);
        // usamos declareDefault que tambien accrua internamente.
        assertEq(uint8(lease.status(id)), uint8(FinancialLease.LeaseStatus.Active));

        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(FinancialLease.LeaseStatus.InDefault));

        // Pago total: cuota vencida + las 2 restantes
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + 10; // margen por acumulacion de punitorios

        vm.expectEmit(true, false, false, false);
        emit FinancialLease.DefaultCured(id);
        _pay(id, totalAssets);

        FinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == FinancialLease.LeaseStatus.Active || finalStatus == FinancialLease.LeaseStatus.Completed,
            "debe curar a Active o Completed"
        );
        assertEq(lease.outstandingUnits(id), 0, "no debe quedar capital pendiente tras el pago total");
    }

    // ─── T6: REGRESION bug (a) ──────────────────────────────

    function test_T6_paidFlagWhileInArrears() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);

        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);

        // Forzar accrual (paga una lease dummy no sirve; usamos declareDefault indirectamente)
        vm.prank(defaultDeclarer);
        lease.declareDefault(id); // esto llama _accrue() y marca la cuota 0 como vencida impaga

        (,, bool paid) = lease.paymentAt(id, 0);
        assertFalse(paid, "la cuota vencida impaga no debe figurar como paid");
    }

    // ─── T7: REGRESION bug (b) ──────────────────────────────

    function test_T7_penaltyDoesNotReducePrincipal() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);

        // Paso 1: cruzar el vencimiento y formalizar el default. Esto vuelca
        // la cuota 0 a arrearsPrincipalUnits, pero (por fix c) el propio call
        // de _accrue que la vuelca todavia no le aplica punitorios: el stock
        // vencido usado para calcular el punitorio se lee ANTES del while que
        // agrega la cuota recien vencida.
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        // Paso 2: dejar correr dias adicionales para que el stock de 100 units
        // ya vencidas devengue punitorios en el proximo _accrue.
        vm.warp(block.timestamp + 10 days);
        oracle.set(1e18); // refresca staleness

        uint256 outstandingBefore = lease.outstandingUnits(id);
        uint256 lessorBalBefore = token.balanceOf(lessor);

        // Pagar exactamente el capital vencido (100 units) + el punitorio
        // devengado en los 10 dias sobre ese stock (10bps/dia * 10 dias =
        // 1 unit), sin alcanzar a cubrir las cuotas futuras todavia no
        // vencidas (fix d capa a lo efectivamente adeudado, no dona el resto).
        _pay(id, 101 * UNIT);

        uint256 outstandingAfter = lease.outstandingUnits(id);
        uint256 principalPaid = outstandingBefore - outstandingAfter;
        assertEq(principalPaid, 100 * UNIT, "outstandingUnits debe reducirse SOLO por el capital de la cuota vencida");

        uint256 pulled = token.balanceOf(lessor) - lessorBalBefore;
        assertGt(pulled, principalPaid, "el pago real debe incluir punitorios ademas del capital");
        assertEq(lease.arrears(id), 0, "toda la mora (capital + punitorios) debe quedar saldada");
    }

    // ─── fuzz extra sobre T2 ────────────────────────────────

    function testFuzz_T2_floorNeverOvercredits(uint256 rate, uint256 assets) public {
        rate = bound(rate, 1e6, 1e30); // evitar rate=0 y overflow patologico
        assets = bound(assets, 0, 1_000_000e18);

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 1_000_000e18);
        oracle.set(rate);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts);

        token.mint(lessee, assets);
        vm.prank(lessee);
        token.approve(address(lease), assets);

        uint256 expectedUnitsFloor = (assets * 1e18) / rate;
        if (expectedUnitsFloor == 0) {
            vm.prank(lessee);
            vm.expectRevert(FinancialLease.NothingDue.selector);
            lease.pay(id, assets);
            return;
        }

        uint256 outstandingBefore = lease.outstandingUnits(id);
        _pay(id, assets);
        uint256 unitsSettled = outstandingBefore - lease.outstandingUnits(id);

        assertLe(unitsSettled, expectedUnitsFloor, "settledUnits nunca debe exceder el floor de lo pagado");
    }
}
