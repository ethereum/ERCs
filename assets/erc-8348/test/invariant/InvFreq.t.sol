// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {INPUT_COLLECTIONS, INPUT_ARREARS_RECORD} from "../../src/IFinancialLease.sol";
import {MockERC20} from "./Handler.sol";

/// @title STEP 6/fix — INV-FREQ (Fase 3, test de escenario dirigido)
/// @dev Confirma el fix de S3-01. Post-fix no existe ningun "_accrue"
///      interno que exponer via harness — arrears() es una view pura, asi
///      que se prueba contra FinancialLease directamente.
///
///      DEBE PASAR con el codigo actual (post-fix). Si falla, el fix esta
///      mal — no hay que tocar este test para que pase.
contract InvFreqTest is Test {
    FinancialLease internal lease;
    MockERC20 internal token;
    address internal lessee_ = makeAddr("lessee");
    address internal lessor_ = makeAddr("lessor");
    address internal declarer_ = makeAddr("declarer");
    address internal otherLessee = makeAddr("otherLessee");
    address internal otherLessor = makeAddr("otherLessor");

    uint256 internal constant UNIT = 1e18;
    uint256 internal constant PRINCIPAL = 1_000_000 * UNIT;
    uint16 internal constant PENALTY_BPS_PER_DAY = 10; // 0.10%/dia

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        token.mint(lessee_, 10_000_000 * UNIT);
        vm.prank(lessee_);
        token.approve(address(lease), type(uint256).max);

        token.mint(otherLessee, 10_000_000 * UNIT);
        vm.prank(otherLessee);
        token.approve(address(lease), type(uint256).max);
    }

    function _mkLease() internal returns (uint256 id) {
        uint64[] memory dueDates = new uint64[](1);
        uint256[] memory unitAmounts = new uint256[](1);
        dueDates[0] = uint64(block.timestamp) + 1;
        unitAmounts[0] = PRINCIPAL;

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee_,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "USD",
            oracle: address(0), // rate fijo 1:1, unidades == assets
            maxStaleness: 0,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 0,
            penaltyBpsPerDay: PENALTY_BPS_PER_DAY,
            defaultDeclarer: declarer_,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: lessor_,
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor_);
        id = lease.createLease(p);
    }

    /// @dev Version simple, view-only. Cierto por construccion (una view
    ///      nunca muta storage), la dejo como baseline barato pero
    ///      ACLARADO como trivial: no prueba nada sobre transacciones
    ///      reales, solo sobre relecturas. La prueba fuerte es
    ///      test_INV_FREQ_immuneToNonEconomicTransactions de abajo.
    function test_INV_FREQ_readsAloneCannotDiverge_trivialBaseline() public {
        uint256 idA = _mkLease();
        uint256 idB = _mkLease();
        vm.warp(block.timestamp + 2);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 90 days);
        uint256 arrearsA = lease.arrears(idA);

        for (uint256 i = 0; i < 90; i++) {
            vm.warp(t0 + i * 1 days);
            lease.arrears(idB); // descartado — una view no puede mutar nada
        }
        vm.warp(t0 + 90 days);
        uint256 arrearsB = lease.arrears(idB);

        assertEq(arrearsA, arrearsB, "trivial: las views nunca mutan storage");
    }

    /// @dev INV-FREQ fuerte — inmune a transacciones sin efecto economico.
    ///      Prueba lo que S3-01 realmente pedia: dos leases identicos, con
    ///      los MISMOS pagos en los MISMOS instantes, pero uno de ellos
    ///      ademas recibe cuanta transaccion real (no revertida, con
    ///      escritura de storage genuina) se pueda intercalar sin mover
    ///      dinero del lease — declareDefault, updateServicing,
    ///      assignLessee, transferencia del NFT de posicion del lessor, y
    ///      un intento de pago que revierte. arrears() debe coincidir
    ///      EXACTO al final en ambos.
    ///
    ///      ARGUMENTO (no solo empirico) de por que esto tiene que dar
    ///      igual, verificado por inspeccion exhaustiva de
    ///      src/FinancialLease.sol antes de escribir este test (todo
    ///      `l.<campo> = ...` del contrato, grep confirmado uno por uno):
    ///
    ///      arrears() depende UNICAMENTE de los campos que lee
    ///      _computeState()/_penaltyOwed(): dueDates, unitAmounts,
    ///      penaltyBpsPerDay (los tres fijados una unica vez en
    ///      createLease, nunca reescritos despues), settledUnits,
    ///      firstUnsettledIndex, cumBeforeFirstUnsettled,
    ///      crystallizedPenaltyUnits, penaltyPaidUnits.
    ///
    ///      De esos 5 campos "vivos", los UNICOS que se escriben en todo
    ///      el contrato fuera de createLease son los que muta
    ///      _applyToPrincipal() (settledUnits, firstUnsettledIndex,
    ///      cumBeforeFirstUnsettled, crystallizedPenaltyUnits) y
    ///      penaltyPaidUnits (mutado solo dentro de pay()). Ninguna otra
    ///      funcion del contrato — declareDefault, exercisePurchaseOption,
    ///      assignLessee, updateServicing, ni las transferencias ERC721
    ///      heredadas (que ademas viven en storage de OpenZeppelin,
    ///      totalmente separado del struct Lease) — escribe ninguno de
    ///      esos 5 campos. declareDefault/exercisePurchaseOption solo
    ///      escriben `status` (que _computeState ni siquiera lee);
    ///      assignLessee solo escribe `lessee`; updateServicing solo
    ///      escribe el mapping de servicing. Por lo tanto NINGUNA
    ///      transaccion sin pago puede alterar el resultado de arrears() —
    ///      es una garantia estructural del diseño (closed-form, sin
    ///      bucket agregado ni paso de persistencia intermedio), no una
    ///      coincidencia de este escenario particular.
    function test_INV_FREQ_immuneToNonEconomicTransactions() public {
        uint256 idA = _mkLease();
        uint256 idB = _mkLease();

        vm.warp(block.timestamp + 2); // cruzar el vencimiento en ambos
        uint256 t0 = block.timestamp;

        // Lease B: intercalar toda transaccion real sin efecto economico
        // que el contrato permite, ANTES del pago.
        vm.prank(lessor_);
        lease.updateServicing(idB, INPUT_COLLECTIONS, uint64(block.timestamp));

        vm.prank(declarer_);
        lease.declareDefault(idB); // valido: idB ya esta en mora (1,000,000 vencido)

        vm.prank(lessor_);
        lease.transferFrom(lessor_, otherLessor, idB); // el NFT de posicion cambia de dueño

        vm.prank(lessee_);
        lease.assignLessee(idB, otherLessee); // el lessee se reasigna

        vm.prank(otherLessor); // el nuevo servicer NO es otherLessor -> revierte
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.updateServicing(idB, INPUT_ARREARS_RECORD, uint64(block.timestamp));

        vm.prank(otherLessee); // pago de 0 -> revierte, no debe dejar rastro
        vm.expectRevert(FinancialLease.NothingDue.selector);
        lease.pay(idB, 0);

        // Avanzar 90 dias intercalando MAS transacciones sin pago en B
        // (lease A no recibe ninguna — solo el paso del tiempo).
        for (uint256 i = 0; i < 90; i++) {
            vm.warp(t0 + (i + 1) * 1 days);
            if (i % 10 == 0) {
                vm.prank(lessor_);
                lease.updateServicing(idB, INPUT_COLLECTIONS, uint64(block.timestamp));
            }
        }
        assertEq(block.timestamp, t0 + 90 days, "precondicion: mismo timestamp final");

        // El MISMO pago, en el MISMO instante, en ambos leases — este es
        // el unico tipo de transaccion que el diseño permite que altere
        // arrears(), y es identico en A y B.
        uint256 payment = 500_000 * UNIT;
        vm.prank(lessee_);
        lease.pay(idA, payment);
        vm.prank(otherLessee); // en B el lessee ya fue reasignado arriba
        lease.pay(idB, payment);

        assertEq(
            lease.arrears(idA),
            lease.arrears(idB),
            "INV-FREQ fuerte: arrears() debe coincidir aunque B haya recibido transacciones reales (declareDefault, updateServicing, assignLessee, transferencia del NFT, pagos revertidos) que A nunca recibio"
        );

        // Verificacion cuantitativa: interes SIMPLE por tramo (fix
        // S3-01), 1,000,000 UNIT en mora desde t0, penaltyBpsPerDay=10,
        // 90 dias, menos el pago de 500,000 UNIT aplicado en el mismo
        // instante en ambos. El punitorio antes del pago es identico al
        // "Caso A" historico del bug (90,000 UNIT) en los dos leases.
        assertEq(
            lease.arrears(idA), (PRINCIPAL + 90_000 * UNIT) - payment, "punitorio simple exacto, tras el pago"
        );
    }
}
