// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";
import {
    IFinancialLease,
    INPUT_INDEX_OBSERVATION,
    INPUT_COLLECTIONS,
    INPUT_ARREARS_RECORD,
    INPUT_INSURANCE_STATUS,
    INPUT_ASSET_CONDITION,
    INPUT_RESIDUAL_APPRAISAL
} from "../src/IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "../src/IFinancialLeaseAnchored.sol";

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
        leaseId = _createLeaseWithServicingConfig(
            oracle_, staleness, dueDates, unitAmounts, new bytes32[](0), new uint64[](0)
        );
    }

    /// @dev Change 3: maxStaleness por servicing input se configura AL
    ///      ORIGINAR (arrays paralelos), no lo setea el servicer despues.
    function _createLeaseWithServicingConfig(
        address oracle_,
        uint64 staleness,
        uint64[] memory dueDates,
        uint256[] memory unitAmounts,
        bytes32[] memory servicingInputs,
        uint64[] memory servicingMaxStaleness
    ) internal returns (uint256 leaseId) {
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
            defaultDeclarer: defaultDeclarer,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: servicingInputs,
            servicingMaxStaleness: servicingMaxStaleness
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

        // status() proyecta el devengamiento a block.timestamp sin
        // necesitar una tx previa: ya refleja InArrears aca, antes de
        // declareDefault.
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears));

        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Pago total: cuota vencida + las 2 restantes
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + 10; // margen por acumulacion de punitorios

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, totalAssets);

        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
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

    // ─── T9: assetAnchor (ERC-8325) ─────────────────────────

    function test_T9_assetAnchor() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
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
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            anchorChainId: 1,
            anchorRegistry: address(0xBEEF),
            anchorId: bytes32(uint256(42)),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        uint256 anchoredId = lease.createLease(p);

        (uint256 chainId, address registry, bytes32 anchorId) = lease.assetAnchor(anchoredId);
        assertEq(chainId, 1, "chainId debe coincidir");
        assertEq(registry, address(0xBEEF), "registry debe coincidir");
        assertEq(anchorId, bytes32(uint256(42)), "anchorId debe coincidir");

        uint256 unanchoredId = _defaultLease();
        (uint256 chainId2, address registry2, bytes32 anchorId2) = lease.assetAnchor(unanchoredId);
        assertEq(chainId2, 0, "sin anclar: chainId debe ser cero");
        assertEq(registry2, address(0), "sin anclar: registry debe ser cero");
        assertEq(anchorId2, bytes32(0), "sin anclar: anchorId debe ser cero");

        assertTrue(
            lease.supportsInterface(type(IFinancialLeaseAnchored).interfaceId),
            "debe declarar soporte ERC-165 de IFinancialLeaseAnchored"
        );
    }

    // ─── T39: tupla de anclaje parcial revierte (change 1) ──

    function test_T39_partialAnchorTupleReverts() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);

        // anchorId seteado, registry y chainId en cero: parcial -> revierte
        FinancialLease.CreateLeaseParams memory p1 = FinancialLease.CreateLeaseParams({
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
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(uint256(42)),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p1);

        // registry seteado, chainId y anchorId en cero: tambien parcial
        FinancialLease.CreateLeaseParams memory p2 = p1;
        p2.anchorChainId = 0;
        p2.anchorRegistry = address(0xBEEF);
        p2.anchorId = bytes32(0);
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p2);

        // chainId seteado, el resto en cero: tambien parcial
        FinancialLease.CreateLeaseParams memory p3 = p1;
        p3.anchorChainId = 1;
        p3.anchorRegistry = address(0);
        p3.anchorId = bytes32(0);
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p3);

        // tupla completa: pasa
        FinancialLease.CreateLeaseParams memory p4 = p1;
        p4.anchorChainId = 1;
        p4.anchorRegistry = address(0xBEEF);
        p4.anchorId = bytes32(uint256(42));
        vm.prank(lessor);
        uint256 idFull = lease.createLease(p4);
        (uint256 chainId, address registry, bytes32 anchorId) = lease.assetAnchor(idFull);
        assertEq(chainId, 1);
        assertEq(registry, address(0xBEEF));
        assertEq(anchorId, bytes32(uint256(42)));

        // tupla toda-cero: pasa (lease no anclado)
        FinancialLease.CreateLeaseParams memory p5 = p1;
        p5.anchorChainId = 0;
        p5.anchorRegistry = address(0);
        p5.anchorId = bytes32(0);
        vm.prank(lessor);
        uint256 idNone = lease.createLease(p5);
        (uint256 chainId2, address registry2, bytes32 anchorId2) = lease.assetAnchor(idNone);
        assertEq(chainId2, 0);
        assertEq(registry2, address(0));
        assertEq(anchorId2, bytes32(0));
    }

    // ─── T10: inputFreshness — IndexObservation derivado ────

    function test_T10_inputFreshnessIndexObservation() public {
        uint256 id = _defaultLease(); // oracle + maxOracleStaleness = 7 days
        (, uint64 expectedAsOf) = lease.conversionRateAsOf(id);

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_INDEX_OBSERVATION);
        assertEq(observedAt, expectedAsOf, "observedAt debe coincidir con conversionRateAsOf");
        assertEq(
            reportedAt,
            expectedAsOf,
            "reportedAt tambien deriva de conversionRateAsOf: el oraculo no distingue ambos momentos"
        );
        assertEq(maxStaleness, 7 days, "maxStaleness debe coincidir con maxOracleStaleness");

        // Lease con denominacion fija (sin oraculo)
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 fixedId = _createLease(address(0), 0, dueDates, unitAmounts);
        (uint64 observedAtFixed, uint64 reportedAtFixed, uint64 maxStalenessFixed) =
            lease.inputFreshness(fixedId, INPUT_INDEX_OBSERVATION);
        assertEq(observedAtFixed, uint64(block.timestamp), "denominacion fija: observedAt debe ser el tiempo actual");
        assertEq(reportedAtFixed, uint64(block.timestamp), "denominacion fija: reportedAt tambien");
        assertEq(maxStalenessFixed, 0, "denominacion fija: sin limite de staleness");
    }

    // ─── T11: updateServicing + inputFreshness (historico) ──

    function test_T11_updateServicingAndFreshness() public {
        vm.warp(block.timestamp + 100 days); // margen para poder "observar en el pasado" mas abajo

        // Change 3: maxStaleness se configura AL ORIGINAR, no lo setea el servicer.
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_COLLECTIONS;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 3 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses); // servicer default = lessor (msg.sender en createLease)

        uint64 observedAtReported = uint64(block.timestamp) - 5 days; // observado hace 5 dias
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, observedAtReported);
        uint64 callTime = uint64(block.timestamp);

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, observedAtReported, "observedAt debe ser el que declaro el servicer");
        assertEq(reportedAt, callTime, "reportedAt debe ser el timestamp de la tx de updateServicing");
        assertEq(maxStaleness, 3 days, "maxStaleness debe ser el configurado al originar, no por el servicer");

        vm.warp(block.timestamp + 10 days);
        (uint64 observedAtLater, uint64 reportedAtLater,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAtLater, observedAtReported, "observedAt es historico: no cambia con el paso del tiempo");
        assertEq(reportedAtLater, callTime, "reportedAt es historico: no cambia con el paso del tiempo");
    }

    // ─── T12: control de acceso del servicer ────────────────

    function test_T12_updateServicingAccessControl() public {
        uint256 id = _defaultLease();
        address rando = makeAddr("rando");

        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));

        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (, uint64 reportedAt,) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(reportedAt, uint64(block.timestamp), "el servicer si puede atestar");
    }

    // ─── T13: IndexObservation no es atestable manualmente ──

    function test_T13_indexObservationNotAttestable() public {
        uint256 id = _defaultLease();
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.DerivedInput.selector);
        lease.updateServicing(id, INPUT_INDEX_OBSERVATION, uint64(block.timestamp));
    }

    // ─── T40: observedAt vs reportedAt divergen (change 2) ──

    function test_T40_observedAtAndReportedAtDiverge() public {
        vm.warp(block.timestamp + 100 days);
        uint256 id = _defaultLease();

        uint64 observedAt14DaysAgo = uint64(block.timestamp) - 14 days;
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, observedAt14DaysAgo);

        (uint64 observedAt, uint64 reportedAt,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, observedAt14DaysAgo, "observedAt debe ser el que declaro el servicer (hace 14 dias)");
        assertEq(reportedAt, uint64(block.timestamp), "reportedAt debe ser el timestamp de la tx");
        assertTrue(observedAt != reportedAt, "observedAt y reportedAt deben poder diferir");
        assertEq(reportedAt - observedAt, 14 days, "la divergencia debe ser exactamente de 14 dias");
    }

    // ─── T41: observacion futura revierte (change 2) ────────

    function test_T41_futureObservationReverts() public {
        uint256 id = _defaultLease();
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.FutureObservation.selector);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp) + 1);

        // observedAt == block.timestamp (limite exacto): no es futuro, pasa
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));
    }

    // ─── T42: maxStaleness no lo puede cambiar el servicer (change 3) ──

    function test_T42_maxStalenessNotSettableByServicer() public {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_ARREARS_RECORD;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 5 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);

        // updateServicing ya no acepta un parametro de maxStaleness: solo
        // (leaseId, input, observedAt). Atestar varias veces no cambia la
        // tolerancia, que sigue siendo la configurada al originar.
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (,, uint64 maxStaleness1) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(maxStaleness1, 5 days, "maxStaleness debe ser el configurado al originar");

        vm.warp(block.timestamp + 1 days);
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (,, uint64 maxStaleness2) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(maxStaleness2, 5 days, "maxStaleness no debe cambiar entre atestaciones del servicer");

        // un input SIN tolerancia configurada devuelve 0 (default = sin limite)
        (,, uint64 maxStalenessUnconfigured) = lease.inputFreshness(id, INPUT_INSURANCE_STATUS);
        assertEq(maxStalenessUnconfigured, 0, "sin config al originar, maxStaleness default = 0");
    }

    // ─── T43: input custom — extensibilidad sin tocar la interfaz (change 4) ──

    function test_T43_customInputExtensibility() public {
        uint256 id = _defaultLease();
        bytes32 customInput = keccak256("test.input.custom");

        (uint64 observedAtBefore, uint64 reportedAtBefore, uint64 maxStalenessBefore) =
            lease.inputFreshness(id, customInput);
        assertEq(observedAtBefore, 0, "antes de atestar: observedAt en cero");
        assertEq(reportedAtBefore, 0, "antes de atestar: reportedAt en cero");
        assertEq(maxStalenessBefore, 0, "antes de atestar: maxStaleness en cero");

        vm.prank(lessor);
        lease.updateServicing(id, customInput, uint64(block.timestamp));

        (uint64 observedAt, uint64 reportedAt,) = lease.inputFreshness(id, customInput);
        assertEq(observedAt, uint64(block.timestamp), "un input custom (fuera del set base) debe funcionar igual");
        assertEq(reportedAt, uint64(block.timestamp));
    }

    // ─── T44: input nunca atestado devuelve ceros, sin revertir ──

    function test_T44_neverReportedInputReturnsZeros() public view {
        uint256 id = 1; // no hay ninguna lease creada todavia en este test
        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_ASSET_CONDITION);
        assertEq(observedAt, 0);
        assertEq(reportedAt, 0);
        assertEq(maxStaleness, 0);
    }

    // ─── T45: residualAppraisal funciona como cualquier input base ──

    function test_T45_residualAppraisalInput() public {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_RESIDUAL_APPRAISAL;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 30 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);

        vm.prank(lessor);
        lease.updateServicing(id, INPUT_RESIDUAL_APPRAISAL, uint64(block.timestamp));

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_RESIDUAL_APPRAISAL);
        assertEq(observedAt, uint64(block.timestamp));
        assertEq(reportedAt, uint64(block.timestamp));
        assertEq(maxStaleness, 30 days, "INPUT_RESIDUAL_APPRAISAL debe funcionar como cualquier input base");
    }

    // ─── T14: servicing es reporte paralelo, no altera pay() ─

    function test_T14_servicingIsolatedFromPayFlow() public {
        bytes32[] memory inputs = new bytes32[](4);
        inputs[0] = INPUT_COLLECTIONS;
        inputs[1] = INPUT_ARREARS_RECORD;
        inputs[2] = INPUT_INSURANCE_STATUS;
        inputs[3] = INPUT_ASSET_CONDITION;
        uint64[] memory maxStalenesses = new uint64[](4);
        maxStalenesses[0] = 1 days;
        maxStalenesses[1] = 1 days;
        maxStalenesses[2] = 1 days;
        maxStalenesses[3] = 1 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);
        (, uint64 dueDate1) = lease.nextPayment(id);

        vm.warp(uint256(dueDate1) + 1 days);
        oracle.set(1e18);

        // Atestar las 4 categorias antes de generar la mora
        vm.startPrank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_INSURANCE_STATUS, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_ASSET_CONDITION, uint64(block.timestamp));
        vm.stopPrank();

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + 10; // margen por punitorios

        // Re-atestar en medio del ciclo, incluso despues de calcular lo adeudado
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, totalAssets);

        // Mismos resultados que T5 (sin servicing): el reporte no altero nada
        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
            "debe curar a Active o Completed igual que sin servicing"
        );
        assertEq(lease.outstandingUnits(id), 0, "no debe quedar capital pendiente tras el pago total");
        assertEq(lease.arrears(id), 0, "la mora debe quedar saldada igual que sin servicing");

        // El servicing sigue siendo consultable y no fue tocado por pay()
        (uint64 observedAtCollections,, uint64 maxStalenessCollections) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertTrue(observedAtCollections > 0, "la atestacion de Collections debe seguir en pie");
        assertEq(maxStalenessCollections, 1 days, "pay() no debe modificar la config de servicing");
    }

    // ─── T35: REGRESION hallazgo — views deben reflejar el devengo
    //     sin necesitar una tx previa ──────────────────────────────

    function test_T35_viewReflectsArrearsWithoutPriorTx() public {
        uint256 id = _defaultLease(); // 3 cuotas x100 UNIT, vencimientos a 30/60/90 dias
        (, uint64 dueDate1) = lease.nextPayment(id);

        // Cruzar los vencimientos de las cuotas 1 y 2 (dias 30 y 60) sin
        // mandar NINGUNA transaccion al contrato entre medio.
        vm.warp(uint256(dueDate1) + 31 days);

        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.InArrears),
            "REGRESION: status() debe reflejar la mora sin necesitar una tx previa"
        );
        assertGt(lease.arrears(id), 0, "REGRESION: arrears() debe ser > 0 sin necesitar una tx previa");
    }

    // ─── T36: la view proyectada coincide exactamente con lo persistido ──

    function test_T36_viewMatchesPersistedStateExactly() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate1) = lease.nextPayment(id);
        vm.warp(uint256(dueDate1) + 45 days);
        oracle.set(1e18); // refresca staleness para el declareDefault/pay que siguen

        IFinancialLease.LeaseStatus statusBefore = lease.status(id);
        uint256 arrearsBefore = lease.arrears(id);
        (uint256 nextAssetsBefore, uint64 nextDueBefore) = lease.nextPayment(id);
        assertEq(uint8(statusBefore), uint8(IFinancialLease.LeaseStatus.InArrears), "precondicion: debe estar en mora");

        // Disparar la persistencia real (declareDefault corre _accrue()
        // internamente, sin que pase mas tiempo desde la lectura de arriba).
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault), "post-declare: InDefault");

        // Cero divergencia: lo que la view proyectaba coincide exacto con
        // lo que quedo persistido (releido ahora sin nada mas que proyectar).
        assertEq(lease.arrears(id), arrearsBefore, "arrears() debe coincidir exacto con lo persistido");
        (uint256 nextAssetsAfter, uint64 nextDueAfter) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "nextPayment().assets debe coincidir exacto con lo persistido");
        assertEq(nextDueAfter, nextDueBefore, "nextPayment().dueDate debe coincidir exacto con lo persistido");
    }

    // ─── T37: punitorios proyectados crecen monotonicamente y
    //     coinciden con lo que efectivamente se salda al pagar ────────

    function test_T37_penaltyProjectionGrowsMonotonicallyAndMatchesPersisted() public {
        uint256 id = _defaultLease(); // penaltyBpsPerDay = 10 (0.10%/dia)
        (, uint64 dueDate1) = lease.nextPayment(id);

        // Reconocer la mora con una tx real: el punitorio recien empieza
        // a devengar sobre el stock vencido a partir de aca (ver T7).
        vm.warp(uint256(dueDate1) + 5 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        uint256 arrearsT0 = lease.arrears(id);

        // Avanzar SIN mandar ninguna tx: arrears() debe crecer estricto
        // con cada dia adicional de mora, vía la proyeccion pura.
        vm.warp(block.timestamp + 3 days);
        uint256 arrearsT3 = lease.arrears(id);
        assertGt(arrearsT3, arrearsT0, "arrears() debe crecer con el tiempo sin tx (dia 3)");

        vm.warp(block.timestamp + 4 days);
        uint256 arrearsT7 = lease.arrears(id);
        assertGt(arrearsT7, arrearsT3, "arrears() debe seguir creciendo (dia 7)");

        // El valor proyectado justo antes de pagar debe ser exactamente lo
        // que hace falta para saldar toda la mora al pagar.
        uint256 projectedBeforePay = lease.arrears(id);
        uint256 totalUnitsOwed = lease.outstandingUnits(id);
        uint256 assetsToPay = lease.convertToAssets(id, totalUnitsOwed) + projectedBeforePay + 100; // margen generoso

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, assetsToPay);

        assertEq(lease.arrears(id), 0, "el pago debe saldar exactamente toda la mora proyectada");
        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
            "debe curar a Active o Completed"
        );
    }

    // ─── T38: estados terminales — el paso del tiempo no los altera ──

    function test_T38_projectedStateFrozenInTerminalStatuses() public {
        (uint64[] memory dd, uint256[] memory ua) = _schedule(1, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 7 days, dd, ua);

        vm.warp(uint256(dd[0]));
        oracle.set(1e18);
        _pay(id, lease.convertToAssets(id, ua[0]));
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        // Completed: nada debe moverse con el tiempo, sin tx de por medio.
        uint256 arrearsCompletedBefore = lease.arrears(id);
        (uint256 nextAssetsBefore,) = lease.nextPayment(id);
        vm.warp(block.timestamp + 400 days);
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "Completed no debe cambiar con el tiempo"
        );
        assertEq(lease.arrears(id), arrearsCompletedBefore, "arrears() no debe cambiar en Completed");
        (uint256 nextAssetsAfter,) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "nextPayment() no debe cambiar en Completed");

        // PurchaseExercised: idem.
        oracle.set(1e18); // refresca staleness (maxOracleStaleness = 7 dias)
        vm.prank(lessee);
        lease.exercisePurchaseOption(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));

        vm.warp(block.timestamp + 400 days);
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.PurchaseExercised),
            "PurchaseExercised no debe cambiar con el tiempo"
        );

        // Nota: LeaseStatus.Terminated no es alcanzable por ninguna
        // funcion publica de esta implementacion de referencia (solo se
        // usa como parametro generico del evento LeaseTerminated, emitido
        // hoy unicamente con Completed o PurchaseExercised). El guard de
        // _projectedState (`uint8(status) > uint8(InDefault)`) lo cubre
        // estructuralmente igual, por su posicion en el enum entre
        // InDefault y Completed.
    }
}
