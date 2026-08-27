// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
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
    INPUT_RESIDUAL_APPRAISAL,
    TERMINATION_MUTUAL_AGREEMENT,
    TERMINATION_DEFAULT
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
            terminationDelay: 7 days,
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

        // Pago total: todo el capital pendiente (cuota vencida + las 2
        // restantes) MAS toda la mora reportada por arrears() (capital
        // vencido + punitorio ya devengado). Sobrepagar el capital vencido
        // no es un problema (pay() cappea a lo efectivamente adeudado,
        // ver fix (d)): el margen sale de una cantidad real leida del
        // contrato, no de una constante que dependa de cuanto punitorio
        // "deberia" haber devengado con tal o cual implementacion.
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + lease.arrears(id);

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

        // Paso 1: cruzar el vencimiento y formalizar el default. Post fix
        // S3-01 el punitorio se devenga en forma cerrada desde la fecha de
        // vencimiento real de cada tramo (dueDates[i]), no desde el
        // momento en que una tx "lo nota" — declareDefault ya no tiene
        // ningun efecto sobre CUANDO empieza a contar el punitorio.
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        // Paso 2: dejar correr dias adicionales para que el stock de 100
        // units ya vencidas siga devengando punitorio.
        vm.warp(block.timestamp + 10 days);
        oracle.set(1e18); // refresca staleness

        uint256 outstandingBefore = lease.outstandingUnits(id);
        uint256 lessorBalBefore = token.balanceOf(lessor);

        // Pagar EXACTAMENTE arrears(id): por definicion es el capital
        // vencido mas el punitorio devengado hasta ahora, sin alcanzar a
        // cubrir las cuotas futuras todavia no vencidas (fix d capa a lo
        // efectivamente adeudado, no dona el resto). No se asume ningun
        // numero de dias ni de unidades de punitorio de antemano — sale
        // de lo que el contrato reporta.
        _pay(id, lease.arrears(id));

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
            terminationDelay: 7 days,
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
            terminationDelay: 7 days,
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

        // Margen derivado de arrears(id) (capital vencido + punitorio
        // real), no de una constante — ver T5.
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + lease.arrears(id);

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
        // hoy unicamente con Completed o PurchaseExercised). Ahora que el
        // devengamiento es closed-form (fix S3-01, ver
        // audit/s3-01-fix.md), el guard equivalente esta implicito en que
        // ninguna funcion asigna Terminated: no requiere manejo especial.
    }

    // ─── T47: fix S3-01 — el punitorio historico de un tramo saldado
    //     no desaparece ni se duplica ──────────────────────────────

    function test_T47_historicalPenaltyPreservedAcrossPrincipalPayment() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(2, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts); // penaltyBpsPerDay = 10

        // Ambas cuotas vencidas: cuota0 60 dias tarde, cuota1 30 dias tarde.
        vm.warp(uint256(dueDates[1]) + 30 days);
        oracle.set(1e18);

        // Punitorio dinamico total antes de pagar: cuota0 (100*10*60/10000
        // = 6) + cuota1 (100*10*30/10000 = 3) = 9 UNIT.
        assertEq(lease.arrears(id), 209 * UNIT, "precondicion: 200 capital + 9 punitorio dinamico");

        // Pagar exactamente: 9 (todo el punitorio acumulado) + 100 (cuota0
        // entera). Esto cristaliza el punitorio de cuota0 (6 UNIT, a SU
        // propia fecha de vencimiento) y deja cuota1 con su capital
        // intacto — pero el punitorio YA acumulado de cuota1 (3 UNIT)
        // tambien queda pago, porque el punitorio es un unico pool
        // (crystallizedPenaltyUnits + dinamico) que se paga antes que
        // ningun capital, no un monto separable por tramo.
        _pay(id, 109 * UNIT);
        assertEq(
            lease.outstandingUnits(id), 100 * UNIT, "cuota0 debe quedar saldada, cuota1 intacta en capital"
        );
        assertEq(
            lease.arrears(id),
            100 * UNIT,
            "REGRESION S3-01: sin punitorio pendiente inmediatamente despues de pagarlo todo"
        );

        // Avanzar 10 dias mas SIN pagar: cuota1 pasa de 30 a 40 dias de
        // mora. Si el punitorio cristalizado de cuota0 (6 UNIT, ya
        // saldado en el paso anterior) se perdiera o se re-contara, este
        // numero saldria mal (revert por underflow si se perdiera la
        // cristalizacion — ver s3-01-fix.md — o un valor distinto de 101
        // si se contara dos veces). El valor correcto es exactamente el
        // delta nuevo de cuota1 (4 - 3 = 1 UNIT) sobre el capital
        // pendiente (100).
        vm.warp(block.timestamp + 10 days);
        assertEq(
            lease.arrears(id),
            101 * UNIT,
            "REGRESION S3-01: el punitorio ya pagado de cuota0 no debe reaparecer ni afectar el devengo nuevo de cuota1"
        );
    }

    // ─── T48: fix S3-01 — cristalizacion multi-tramo usa la fecha
    //     propia de CADA tramo, no una fecha comun para todo el pago ──

    function test_T48_multiTrancheCrystallizationUsesOwnDueDatePerTranche() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(2, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts); // penaltyBpsPerDay = 10

        // cuota0: 60 dias de mora. cuota1: 30 dias de mora. Punitorio
        // dinamico total: 6 + 3 = 9 UNIT. arrears() = 209 UNIT.
        vm.warp(uint256(dueDates[1]) + 30 days);
        oracle.set(1e18);
        assertEq(lease.arrears(id), 209 * UNIT, "precondicion");

        // Pagar 9 (punitorio) + 100 (cuota0 ENTERA) + 50 (cuota1 PARCIAL)
        // = 159. Si el codigo cristalizara con una fecha comun (ej.
        // reusando los 60 dias de cuota0 tambien para los 50 de cuota1,
        // o viceversa), el arrears() resultante daria un numero distinto
        // de 50 (51.5 si usa 60 para ambas; underflow/revert si usa 30
        // para ambas — verificado a mano en audit/s3-01-fix.md).
        uint256 lessorBalBefore = token.balanceOf(lessor);
        _pay(id, 159 * UNIT);
        uint256 pulled = token.balanceOf(lessor) - lessorBalBefore;

        assertEq(pulled, 159 * UNIT, "debe transferirse exactamente lo pagado (rate 1:1, sin redondeo)");
        assertEq(
            lease.arrears(id),
            50 * UNIT,
            "REGRESION S3-01: cristalizacion multi-tramo debe usar la fecha de vencimiento propia de cada tramo"
        );
        assertEq(lease.outstandingUnits(id), 50 * UNIT, "cuota0 saldada + mitad de cuota1");
    }

    // ─── T49: fix S3-01 — costo de gas de arrears() con cache ────────

    function test_T49_arrearsGasWithCacheOnLongSchedule() public {
        // 60 cuotas, penaltyBpsPerDay = 10. Prepagar las primeras 48
        // (todavia no vencidas en ese momento) en un unico pay(), lo que
        // avanza firstUnsettledIndex/cumBeforeFirstUnsettled a 48.
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(60, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts);

        _pay(id, 48 * 100 * UNIT);
        assertEq(lease.outstandingUnits(id), 12 * 100 * UNIT, "deben quedar las ultimas 12 cuotas");

        // Vencer las 12 restantes.
        vm.warp(uint256(dueDates[59]) + 1 days);
        oracle.set(1e18);

        uint256 g0 = gasleft();
        lease.arrears(id);
        uint256 gasUsed = g0 - gasleft();
        console2.log("T49 - gas de arrears() con 60 cuotas / 12 vencidas (cache activo):", gasUsed);

        // El prototipo aislado (audit/s3-01-diseno.md, seccion 2.4) midio
        // ~86,110 gas para el mismo escenario (12 vencidas, cache con
        // indice+suma). Este numero es sobre el contrato real (incluye
        // el overhead de ERC721/storage layout completo, no solo el
        // loop), asi que se espera "del mismo orden", no identico.
        assertLt(gasUsed, 150_000, "arrears() con cache no debe escalar con el largo total del cronograma (60)");
    }

    // ─── T50: fix S4-02 — solo el lessee saliente reasigna ───────────

    function test_T50_assignLesseeOnlyOutgoingLessee() public {
        uint256 id = _defaultLease(); // defaultDeclarer = defaultDeclarer (fijo, no-cero)

        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessee);
        lease.assignLessee(id, newLessee);
        assertEq(lease.lessee(id), newLessee, "el lessee saliente si puede reasignarse");
    }

    // ─── T51: fix S4-01 — defaultDeclarer sigue al NFT por default ──

    function test_T51_defaultDeclarerFollowsNftTransferByDefault() public {
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
            defaultDeclarer: address(0), // sin override: dinamico via ownerOf
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

        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);

        address rando = makeAddr("t51_rando");
        address newOwner = makeAddr("t51_newOwner");

        // Sin transferir nada: el lessor original (ownerOf actual) puede
        // declarar default; un tercero no.
        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        // Transferir el NFT de posicion del lessor.
        vm.prank(lessor);
        lease.transferFrom(lessor, newOwner, id);

        // El lessor VIEJO ya no tiene el poder — nadie llamo
        // assignDefaultDeclarer, es la resolucion dinamica la que lo saca.
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        // El NUEVO dueño del NFT si puede, automaticamente.
        vm.prank(newOwner);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── T52: fix S4-01 — delegacion explicita gateada por el owner actual ──

    function test_T52_assignDefaultDeclarerGatedByCurrentOwner() public {
        uint256 id = _defaultLease(); // defaultDeclarer = defaultDeclarer (fijo, no-cero)
        address riskManager = makeAddr("riskManager");

        // Solo el ownerOf ACTUAL (lessor) puede delegar — ni el lessee ni
        // el declarer vigente pueden reasignarse el rol a si mismos.
        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignDefaultDeclarer(id, riskManager);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignDefaultDeclarer(id, riskManager);

        vm.expectEmit(true, true, true, false);
        emit FinancialLease.DefaultDeclarerAssigned(id, defaultDeclarer, riskManager);
        vm.prank(lessor);
        lease.assignDefaultDeclarer(id, riskManager);

        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);

        // El declarer viejo perdio el poder; el delegado lo tiene.
        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        vm.prank(riskManager);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── T53: fix S4-02 — el ataque original queda bloqueado end-to-end ──

    function test_T53_S402AttackNoLongerPossible() public {
        // Reproduce el escenario de S4-02: lease llega a Completed, el
        // lessor (via defaultDeclarer, dejado en 0 al originar) intenta
        // designarse a si mismo como lessee para ejercer la opcion de
        // compra a costo cero.
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
            defaultDeclarer: address(0), // dejado sin especificar, como en el hallazgo original
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

        // El tomador paga toda la cuota puntualmente -> Completed.
        vm.warp(uint256(dueDates[0]));
        oracle.set(1e18);
        _pay(id, lease.convertToAssets(id, unitAmounts[0]));
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        // Paso del ataque original: el lessor, como defaultDeclarer
        // resuelto dinamicamente (es ownerOf(id)), intenta reasignarse
        // el lessee a si mismo via assignLessee. Con el fix, ya no tiene
        // ninguna via: assignLessee no lee defaultDeclarer en absoluto.
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, lessor);

        assertEq(lease.lessee(id), lessee, "el lessee original debe seguir siendo el titular de la opcion de compra");

        // El lessee legitimo SI puede ejercerla.
        oracle.set(1e18);
        vm.prank(lessee);
        lease.exercisePurchaseOption(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }

    // ─── Terminación anticipada (fix S6-01) ──────────────────────────

    // ─── T57: acuerdo mutuo desde Active ──────────────────────────

    function test_T57_mutualAgreementFromActive() public {
        uint256 id = _defaultLease(); // Active

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        vm.prank(lessor);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T58: acuerdo mutuo desde InDefault ───────────────────────

    function test_T58_mutualAgreementFromInDefault() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        vm.prank(lessor);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessee);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T59: acepta la parte equivocada ──────────────────────────

    function test_T59_wrongAccepterReverts() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        // el propio proponente no puede aceptarse a si mismo
        vm.prank(lessee);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.acceptTermination(id);

        // un tercero ajeno tampoco
        address rando = makeAddr("t59_rando");
        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.acceptTermination(id);

        // la contraparte correcta (el owner del NFT) si puede
        vm.prank(lessor);
        lease.acceptTermination(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T60: propuesta sobrescrita — vale la segunda ─────────────

    function test_T60_proposalOverwritten() public {
        uint256 id = _defaultLease();

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        bytes32 customReason = keccak256("t60.custom.reason");
        vm.prank(lessee);
        lease.proposeTermination(id, customReason); // A vuelve a proponer, con otra razon

        // Si aceptar todavia respetara la PRIMERA propuesta, esto no
        // cambiaria nada observable; lo que prueba que vale la SEGUNDA es
        // el evento emitido con la razon nueva.
        vm.expectEmit(true, true, false, false);
        emit FinancialLease.TerminationRecorded(id, customReason);
        vm.prank(lessor);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T61: terminateForDefault antes del timelock ──────────────

    function test_T61_terminateForDefaultBeforeTimelockReverts() public {
        uint256 id = _defaultLease(); // terminationDelay = 7 days
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        vm.warp(block.timestamp + 6 days); // < 7 dias de timelock
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.TimelockNotElapsed.selector);
        lease.terminateForDefault(id);
    }

    // ─── T62: terminateForDefault despues del timelock ────────────

    function test_T62_terminateForDefaultAfterTimelock() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        vm.warp(block.timestamp + 7 days); // exactamente el timelock
        vm.prank(lessor);
        lease.terminateForDefault(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T63: terminateForDefault desde Active/InArrears ──────────

    function test_T63_terminateForDefaultWrongStatusReverts() public {
        uint256 id = _defaultLease(); // Active

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);

        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears)); // derivado, sin declareDefault

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);
    }

    // ─── T64: terminateForDefault por alguien que no es el owner ──

    function test_T64_terminateForDefaultNotOwnerReverts() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        vm.warp(block.timestamp + 7 days);

        vm.prank(lessee); // no es el owner del NFT
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.terminateForDefault(id);

        vm.prank(defaultDeclarer); // tampoco, aunque sea quien declaro el default
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.terminateForDefault(id);
    }

    // ─── T65: createLease con terminationDelay == 0 ───────────────

    function test_T65_zeroTerminationDelayReverts() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            terminationDelay: 0,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidTerminationDelay.selector);
        lease.createLease(p);
    }

    // ─── T66: congelamiento tras terminar ─────────────────────────

    function test_T66_freezeAfterTermination() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 5 days); // mora corriendo
        oracle.set(1e18);

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id); // Active/InArrears -> Terminated, con mora corriendo

        uint256 arrearsAtTermination = lease.arrears(id);
        uint256 outstandingAtTermination = lease.outstandingUnits(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
        assertGt(arrearsAtTermination, 0, "precondicion: debia haber mora al momento de terminar");

        vm.warp(block.timestamp + 90 days);

        assertEq(lease.arrears(id), arrearsAtTermination, "CONGELAMIENTO: arrears() no debe cambiar tras terminar");
        assertEq(
            lease.outstandingUnits(id), outstandingAtTermination, "CONGELAMIENTO: outstandingUnits() no debe cambiar"
        );
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Terminated),
            "CONGELAMIENTO: status() debe seguir Terminated"
        );
    }

    // ─── T67: absorbencia — todo revierte sobre un lease Terminated ──

    function test_T67_allOperationsRevertOnTerminated() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.pay(id, 1 * UNIT);

        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.declareDefault(id);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.acceptTermination(id);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.exercisePurchaseOption(id);
    }

    // ─── T68: updateServicing SI funciona sobre un lease Terminated ──

    function test_T68_updateServicingWorksOnTerminated() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id);

        vm.prank(lessor); // servicer default = msg.sender de createLease = lessor
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));

        (uint64 observedAt,,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, uint64(block.timestamp), "updateServicing debe seguir funcionando post-terminacion");
    }

    // ─── T69: matriz completa de operaciones (test de conformidad) ──

    /// @dev Construye un lease fresco y lo lleva exactamente al status
    ///      pedido, con la menor cantidad de transacciones necesaria.
    ///      InDefault queda ademas con el timelock de terminationDelay
    ///      YA vencido, para poder testear terminateForDefault "tras
    ///      timelock" (T61/T62 cubren el borde antes/despues por separado).
    function _mkLeaseAtStatus(IFinancialLease.LeaseStatus target) internal returns (uint256 id) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);

        if (target == IFinancialLease.LeaseStatus.Active) return id;

        if (target == IFinancialLease.LeaseStatus.Completed) {
            vm.warp(uint256(dueDates[0]));
            oracle.set(1e18);
            _pay(id, lease.convertToAssets(id, unitAmounts[0]));
            return id;
        }

        if (target == IFinancialLease.LeaseStatus.PurchaseExercised) {
            vm.warp(uint256(dueDates[0]));
            oracle.set(1e18);
            _pay(id, lease.convertToAssets(id, unitAmounts[0]));
            oracle.set(1e18);
            vm.prank(lessee);
            lease.exercisePurchaseOption(id);
            return id;
        }

        // InArrears, InDefault, Terminated: todos cruzan el vencimiento primero.
        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);
        if (target == IFinancialLease.LeaseStatus.InArrears) return id;

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        if (target == IFinancialLease.LeaseStatus.InDefault) {
            vm.warp(block.timestamp + 7 days);
            return id;
        }

        vm.warp(block.timestamp + 7 days);
        vm.prank(lessor);
        lease.terminateForDefault(id);
        return id;
    }

    /// @dev Construccion dedicada para la fila de declareDefault: a
    ///      diferencia de las otras 6 operaciones, declareDefault exige
    ///      mora GENUINA ademas del status (`principalArrears == 0`
    ///      revierte incluso con status Active/InArrears) — reusar
    ///      _mkLeaseAtStatus(Active) daria un lease sin mora y el "✓" de
    ///      la matriz para esa celda seria imposible de alcanzar. Con
    ///      `persistAsInArrears = false`: mora generada pero nunca
    ///      notada por una tx (l.status sigue Active persistido, igual
    ///      que T35). Con `true`: un poke minimo (pay de 1 wei que no
    ///      cura) fuerza a pay() a persistir InArrears explicito antes de
    ///      declarar el default.
    function _mkLeaseWithArrears(bool persistAsInArrears) internal returns (uint256 id) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);
        if (persistAsInArrears) {
            _pay(id, 1); // poke minimo, no cura, fuerza l.status = InArrears
        }
    }

    function _tryPay(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.pay(id, 10 * UNIT) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryDeclareDefault(uint256 id) internal returns (bool ok) {
        vm.prank(defaultDeclarer);
        try lease.declareDefault(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryAssignLessee(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.assignLessee(id, newLessee) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryProposeTermination(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryAcceptTermination(uint256 id, bool statusAllowsPropose) internal returns (bool ok) {
        if (statusAllowsPropose) {
            vm.prank(lessee);
            try lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT) {} catch {}
        }
        vm.prank(lessor);
        try lease.acceptTermination(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryTerminateForDefault(uint256 id) internal returns (bool ok) {
        vm.prank(lessor);
        try lease.terminateForDefault(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryExercisePurchaseOption(uint256 id) internal returns (bool ok) {
        oracle.set(1e18); // refrescar staleness por si paso tiempo en la construccion
        vm.prank(lessee);
        try lease.exercisePurchaseOption(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryUpdateServicing(uint256 id) internal returns (bool ok) {
        vm.prank(lessor); // servicer default = quien origino (lessor)
        try lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp)) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function test_T69_fullOperationMatrix() public {
        IFinancialLease.LeaseStatus[6] memory statuses = [
            IFinancialLease.LeaseStatus.Active,
            IFinancialLease.LeaseStatus.InArrears,
            IFinancialLease.LeaseStatus.InDefault,
            IFinancialLease.LeaseStatus.Terminated,
            IFinancialLease.LeaseStatus.Completed,
            IFinancialLease.LeaseStatus.PurchaseExercised
        ];

        // Matriz exacta del punto 6 del pedido. Orden de columnas =
        // orden de `statuses` arriba.
        bool[6] memory expectPay = [true, true, true, false, false, false];
        bool[6] memory expectDeclareDefault = [true, true, false, false, false, false];
        bool[6] memory expectAssignLessee = [true, true, true, false, false, false];
        bool[6] memory expectProposeTermination = [true, true, true, false, false, false];
        bool[6] memory expectAcceptTermination = [true, true, true, false, false, false];
        bool[6] memory expectTerminateForDefault = [false, false, true, false, false, false];
        bool[6] memory expectExercisePurchaseOption = [false, false, false, false, true, false];
        bool[6] memory expectUpdateServicing = [true, true, true, true, true, true];

        // Fila de declareDefault por separado: es la unica operacion que
        // exige mora GENUINA ademas del status (ver _mkLeaseWithArrears).
        // Columnas 0-1 (Active/InArrears) usan la construccion dedicada;
        // columnas 2-5 (InDefault/Terminales) reusan _mkLeaseAtStatus
        // igual que el resto, porque ahi el status solo ya alcanza para
        // determinar el resultado.
        assertEq(_tryDeclareDefault(_mkLeaseWithArrears(false)), expectDeclareDefault[0], "matriz: declareDefault Active");
        assertEq(
            _tryDeclareDefault(_mkLeaseWithArrears(true)), expectDeclareDefault[1], "matriz: declareDefault InArrears"
        );
        for (uint256 s = 2; s < statuses.length; s++) {
            assertEq(
                _tryDeclareDefault(_mkLeaseAtStatus(statuses[s])), expectDeclareDefault[s], "matriz: declareDefault"
            );
        }

        for (uint256 s = 0; s < statuses.length; s++) {
            IFinancialLease.LeaseStatus st = statuses[s];

            assertEq(_tryPay(_mkLeaseAtStatus(st)), expectPay[s], "matriz: pay");
            assertEq(_tryAssignLessee(_mkLeaseAtStatus(st)), expectAssignLessee[s], "matriz: assignLessee");
            assertEq(
                _tryProposeTermination(_mkLeaseAtStatus(st)),
                expectProposeTermination[s],
                "matriz: proposeTermination"
            );

            bool statusAllowsPropose = st == IFinancialLease.LeaseStatus.Active
                || st == IFinancialLease.LeaseStatus.InArrears || st == IFinancialLease.LeaseStatus.InDefault;
            assertEq(
                _tryAcceptTermination(_mkLeaseAtStatus(st), statusAllowsPropose),
                expectAcceptTermination[s],
                "matriz: acceptTermination"
            );

            assertEq(
                _tryTerminateForDefault(_mkLeaseAtStatus(st)),
                expectTerminateForDefault[s],
                "matriz: terminateForDefault"
            );
            assertEq(
                _tryExercisePurchaseOption(_mkLeaseAtStatus(st)),
                expectExercisePurchaseOption[s],
                "matriz: exercisePurchaseOption"
            );
            assertEq(_tryUpdateServicing(_mkLeaseAtStatus(st)), expectUpdateServicing[s], "matriz: updateServicing");
        }
    }

    // ─── T70: BUG CRITICO (revision externa) — underflow en _penaltyOwed
    //          por fraccionar un pago en el mismo block.timestamp ────────

    /// @dev floor(a*r) + floor(b*r) <= floor((a+b)*r): cristalizar el
    ///      punitorio de a y b por separado (dos pagos que parten el mismo
    ///      tramo vencido) pierde hasta 1 unidad contra cristalizar de una
    ///      sola vez. penaltyPaidUnits no compensaba esa perdida, asi que
    ///      suficientes fracciones underfloweaban
    ///      crystallizedPenaltyUnits + penaltyGrossNow - penaltyPaidUnits
    ///      en _penaltyOwed (panic 0x11) — reproducido con esta secuencia
    ///      exacta antes del fix de _applyToPrincipal (cristalizar la
    ///      diferencia de grosses en vez del floor de lo aplicado). Post
    ///      fix, ademas de no revertir, fraccionar no debe cambiar
    ///      arrears() (MUST NOT de S3-01).
    function test_T70_regressionUnderflowPorFraccionarPago() public {
        (uint64[] memory dueDatesA, uint256[] memory unitAmountsA) = _schedule(12, 1e23);
        uint256 idA = _createLease(address(oracle), 0, dueDatesA, unitAmountsA);
        (uint64[] memory dueDatesB, uint256[] memory unitAmountsB) = _schedule(12, 1e23);
        uint256 idB = _createLease(address(oracle), 0, dueDatesB, unitAmountsB);

        vm.warp(block.timestamp + 200 days);
        assertEq(lease.arrears(idA), 657_000 * UNIT, "precondicion");
        assertEq(lease.arrears(idB), 657_000 * UNIT, "precondicion");

        uint256 p1 = 42844390007361274575661;
        uint256 p2 = 42844390007361274575660;
        uint256 p3 = 42844390007361274575660;

        // idA: el mismo total, de una sola vez.
        _pay(idA, p1 + p2 + p3);

        // idB: EXACTAMENTE la secuencia que underfloweaba pre-fix. Post
        // fix, el tercer pago ya no debe revertir.
        _pay(idB, p1);
        _pay(idB, p2);
        _pay(idB, p3);

        assertEq(lease.arrears(idA), lease.arrears(idB), "fraccionar en el mismo timestamp no debe cambiar arrears()");
    }

    /// @dev Fix permanente: pagar N unidades en una sola tx vs. en k
    ///      fracciones dentro del MISMO block.timestamp debe dar arrears()
    ///      identico. Fuzzea sobre k (cantidad de fracciones) y sobre el
    ///      total pagado.
    function testFuzz_T71_INV_fractioningSameTimestampDoesNotChangeArrears(uint8 kRaw, uint96 totalRaw) public {
        // Se paga `total` dos veces (una vez por lease) en el mismo test;
        // el balance de setUp (1_000_000e18) no alcanza para eso mas el
        // total del cronograma (1.2e24). Fondeo extra solo para este test.
        token.mint(lessee, 10_000_000 * UNIT);

        uint256 k = bound(uint256(kRaw), 1, 12);
        (uint64[] memory dueDatesA, uint256[] memory unitAmountsA) = _schedule(12, 1e23);
        uint256 idA = _createLease(address(oracle), 0, dueDatesA, unitAmountsA);
        (uint64[] memory dueDatesB, uint256[] memory unitAmountsB) = _schedule(12, 1e23);
        uint256 idB = _createLease(address(oracle), 0, dueDatesB, unitAmountsB);

        vm.warp(block.timestamp + 200 days);
        oracle.set(1e18);

        uint256 owed = lease.arrears(idA);
        uint256 total = bound(uint256(totalRaw), 1, owed);

        // idA: un unico pago de `total`.
        _pay(idA, total);

        // idB: el MISMO `total`, fraccionado en k pagos (mismo timestamp).
        uint256 base = total / k;
        uint256 rem = total - base * k;
        for (uint256 i = 0; i < k; i++) {
            uint256 amt = base + (i == k - 1 ? rem : 0);
            if (amt == 0) continue;
            _pay(idB, amt);
        }

        assertEq(lease.arrears(idA), lease.arrears(idB), "fraccionar un pago en el mismo timestamp no debe cambiar arrears()");
    }
}
