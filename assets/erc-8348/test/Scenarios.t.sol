// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";
import {IFinancialLease} from "../src/IFinancialLease.sol";
import {ChainlinkConversionOracle} from "../src/oracles/ChainlinkConversionOracle.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";

/// @dev Stablecoin mock con decimales configurables (para simular una
///      ARS digital de 6 decimales, distinta del mUSD de 18 decimales
///      usado en FinancialLease.t.sol).
contract MockStable is ERC20 {
    uint8 private immutable _dec;

    constructor(uint8 dec_) ERC20("Mock Stable", "mSTB") {
        _dec = dec_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title Escenarios end-to-end para ERC-8348 (Financial Lease)
/// @dev Esta suite NO reemplaza FinancialLease.t.sol (25 tests unitarios):
///      es una capa adicional que simula contratos de leasing reales de
///      punta a punta, con invariantes verificados tras cada operacion.
contract ScenariosTest is Test {
    FinancialLease lease;

    // Token "actual" contra el cual se verifica el invariante I5 (balance
    // total recibido por el/los lessor(es) == suma de PaymentReceived).
    // Cada escenario usa un unico payment asset a lo largo de su ciclo de
    // vida, asi que alcanza con un puntero mutable seteado al comienzo.
    IERC20 internal _currentAssetToken;

    // ─── Registro de cronogramas (para reconstruir invariantes desde
    //     fuera del contrato sin tocar src/) ─────────────────────────
    mapping(uint256 => uint64[]) internal _schedDue;
    mapping(uint256 => uint256[]) internal _schedAmt;
    mapping(uint256 => uint256) internal _schedTotal;

    // ─── Contabilidad de pagos (I5), reconstruida via replay de logs ──
    mapping(uint256 => address) internal _ownerOfLease;
    mapping(address => uint256) internal _expectedFromPayments;
    mapping(address => uint256) internal _expectedFromPurchase;
    address[] internal _touchedAddresses;
    mapping(address => bool) internal _isTouched;

    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant PAYMENT_RECEIVED_TOPIC =
        keccak256("PaymentReceived(uint256,address,uint256,uint256,uint256,uint256)");
    bytes32 internal constant PURCHASE_TOPIC = keccak256("PurchaseOptionExercised(uint256,uint256)");

    function setUp() public {
        lease = new FinancialLease();
        vm.recordLogs();
    }

    // ════════════════════════════════════════════════════════════════
    // Helpers de originacion
    // ════════════════════════════════════════════════════════════════

    function _monthlySchedule(uint256 n, uint256 amountEach)
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

    function _registerSchedule(uint256 leaseId, uint64[] memory due, uint256[] memory amt) internal {
        uint256 total;
        for (uint256 i = 0; i < due.length; i++) {
            _schedDue[leaseId].push(due[i]);
            _schedAmt[leaseId].push(amt[i]);
            total += amt[i];
        }
        _schedTotal[leaseId] = total;
    }

    function _createLease(
        address lessorAddr,
        address lesseeAddr,
        address tokenAddr,
        address oracleAddr,
        uint64 staleness,
        uint64[] memory dueDates,
        uint256[] memory unitAmounts,
        uint256 purchasePriceUnits,
        uint16 penaltyBps,
        address declarer
    ) internal returns (uint256 leaseId) {
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lesseeAddr,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://machine/1",
            paymentAsset: tokenAddr,
            denomSymbol: "UVA",
            oracle: oracleAddr,
            maxStaleness: staleness,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: purchasePriceUnits,
            penaltyBpsPerDay: penaltyBps,
            defaultDeclarer: declarer,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessorAddr);
        leaseId = lease.createLease(p);
        _registerSchedule(leaseId, dueDates, unitAmounts);
        _assertInvariants(leaseId);
    }

    // ════════════════════════════════════════════════════════════════
    // Reconstruccion externa de arrearsPrincipalUnits
    // ════════════════════════════════════════════════════════════════

    /// @dev El contrato nunca expone arrearsPrincipalUnits ni
    ///      arrearsPenaltyUnits por separado (solo arrears(), que los
    ///      combina en assets). Pero como pay() SIEMPRE imputa en el
    ///      orden punitorios -> capital vencido -> cuotas futuras, el
    ///      capital vencido nunca puede "saltearse" cuotas: por lo tanto
    ///      arrearsPrincipalUnits == totalOverdueNominal - settledUnits
    ///      (nunca negativo), donde totalOverdueNominal es la suma de
    ///      unitAmounts cuyo dueDate ya paso. Ambos lados son
    ///      reconstruibles desde la interfaz publica.
    function _reconstructArrearsPrincipal(uint256 leaseId) internal view returns (uint256 principal) {
        uint256 outstanding = lease.outstandingUnits(leaseId);
        uint256 settled = _schedTotal[leaseId] - outstanding;

        uint64[] storage due = _schedDue[leaseId];
        uint256[] storage amt = _schedAmt[leaseId];
        uint256 totalOverdue;
        for (uint256 i = 0; i < due.length; i++) {
            if (due[i] < block.timestamp) totalOverdue += amt[i];
        }
        principal = totalOverdue > settled ? totalOverdue - settled : 0;
    }

    // ════════════════════════════════════════════════════════════════
    // Invariantes globales — llamar despues de CADA operacion
    // ════════════════════════════════════════════════════════════════

    function _assertInvariants(uint256 leaseId) internal {
        uint256 total = _schedTotal[leaseId];
        uint256 outstanding = lease.outstandingUnits(leaseId);

        // I1: settledUnits <= scheduleTotalUnits. outstandingUnits() se
        // calcula como total - settled: si settled > total, la resta
        // hubiese revertido por underflow. Chequeamos ademas el rango.
        assertLe(outstanding, total, "I1: outstandingUnits excede scheduleTotalUnits");

        // I2: outstandingUnits == scheduleTotalUnits - settledUnits es
        // verdadero por construccion en el contrato (es su formula
        // literal); no es falseable desde afuera. Lo que SI verificamos,
        // como chequeo de regresion mas fuerte, es que el campo
        // newOutstandingUnits emitido en cada PaymentReceived coincide
        // con el estado vivo leido inmediatamente despues (dentro de
        // _assertPaymentAccounting).

        // I6: la mora de capital reconstruida nunca debe exceder lo que
        // falta pagar del cronograma.
        uint256 principalRecon = _reconstructArrearsPrincipal(leaseId);
        assertLe(principalRecon, outstanding, "I6: mora de capital excede outstandingUnits");

        IFinancialLease.LeaseStatus st = lease.status(leaseId);
        uint256 arrearsAssets = lease.arrears(leaseId);

        // I3: Completed => outstanding == 0 && arrears == 0.
        // (arrears() == 0 en assets es equivalente exacto a "0 unidades"
        // porque convertToAssets(0) = 0 y cualquier valor positivo de
        // unidades redondea hacia arriba a un valor positivo de assets.)
        if (st == IFinancialLease.LeaseStatus.Completed) {
            assertEq(outstanding, 0, "I3: Completed con outstandingUnits != 0");
            assertEq(arrearsAssets, 0, "I3: Completed con arrears != 0");
        }

        // I4: Active => sin mora de capital ni punitorios.
        if (st == IFinancialLease.LeaseStatus.Active) {
            assertEq(arrearsAssets, 0, "I4: Active con mora pendiente");
        }

        _assertPaymentAccounting();
    }

    function _trackAddress(address a) internal {
        if (!_isTouched[a]) {
            _isTouched[a] = true;
            _touchedAddresses.push(a);
        }
    }

    /// @dev I5: replay de logs desde el ultimo drenaje. Reconstruye,
    ///      para cada direccion que alguna vez fue dueño del NFT de
    ///      alguna lease, cuanto deberia haber recibido via
    ///      PaymentReceived + PurchaseOptionExercised, y lo compara
    ///      contra su balance real del payment asset vigente.
    function _assertPaymentAccounting() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory logEntry = logs[i];
            if (logEntry.emitter != address(lease)) continue;
            if (logEntry.topics.length == 0) continue;
            bytes32 topic0 = logEntry.topics[0];

            if (topic0 == TRANSFER_TOPIC && logEntry.topics.length == 4) {
                uint256 tokenId = uint256(logEntry.topics[3]);
                address to = address(uint160(uint256(logEntry.topics[2])));
                _ownerOfLease[tokenId] = to;
                _trackAddress(to);
            } else if (topic0 == PAYMENT_RECEIVED_TOPIC && logEntry.topics.length == 3) {
                uint256 lid = uint256(logEntry.topics[1]);
                (uint256 assets,,, uint256 newOutstanding) =
                    abi.decode(logEntry.data, (uint256, uint256, uint256, uint256));
                address ownerAtPayment = _ownerOfLease[lid];
                _expectedFromPayments[ownerAtPayment] += assets;
                _trackAddress(ownerAtPayment);
                assertEq(
                    lease.outstandingUnits(lid),
                    newOutstanding,
                    "REGRESION: PaymentReceived.newOutstandingUnits no coincide con outstandingUnits() vivo"
                );
            } else if (topic0 == PURCHASE_TOPIC && logEntry.topics.length == 2) {
                uint256 lid = uint256(logEntry.topics[1]);
                uint256 price = abi.decode(logEntry.data, (uint256));
                address ownerAtPurchase = _ownerOfLease[lid];
                _expectedFromPurchase[ownerAtPurchase] += price;
                _trackAddress(ownerAtPurchase);
            }
        }

        for (uint256 i = 0; i < _touchedAddresses.length; i++) {
            address a = _touchedAddresses[i];
            assertEq(
                _currentAssetToken.balanceOf(a),
                _expectedFromPayments[a] + _expectedFromPurchase[a],
                "I5: balance del lessor no coincide con la suma de PaymentReceived + purchase"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 1 — leasing UVA argentino, ciclo completo y limpio
    // ════════════════════════════════════════════════════════════════

    function test_Scenario1_UVAFullCycle() public {
        address lessorAddr = makeAddr("s1_lessor");
        address lesseeAddr = makeAddr("s1_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 10_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle uvaOracle = new MockUVAOracle(1500e6);

        uint256 n = 36;
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(uvaOracle),
            10 days,
            dueDates,
            unitAmounts,
            1000e18,
            0,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 totalNominalConverted;
        uint256 rate = 1500e6;

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            rate = (rate * 104) / 100; // ~4% acumulativo mensual
            uvaOracle.set(rate);

            totalNominalConverted += lease.convertToAssets(id, unitAmounts[i]);

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        console2.log("Escenario 1 - rate final (x1e6 ARS/UVA):", rate / 1e6);
        console2.log("Escenario 1 - assets totales pagados por el tomador:", totalAssetsPaid);
        console2.log("Escenario 1 - suma nominal convertida al momento de cada pago:", totalNominalConverted);

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 1 - outstandingUnits final (esperado 0):", finalOutstanding);
        assertEq(finalOutstanding, 0, "ESCENARIO 1 CRITICO: queda dust tras pagar las 36 cuotas exactas");
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "debe estar Completed tras la 36a cuota"
        );

        (uint256 price, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable, "la opcion de compra debe ser ejercible tras Completed");

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.PurchaseOptionExercised(id, price);
        vm.prank(lesseeAddr);
        lease.exercisePurchaseOption(id);
        _assertInvariants(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 2 — mora, punitorios, cura y finalizacion
    // ════════════════════════════════════════════════════════════════

    function test_Scenario2_ArrearsPenaltyCureCompletion() public {
        address lessorAddr = makeAddr("s2_lessor");
        address lesseeAddr = makeAddr("s2_lessee");
        address declarer = makeAddr("s2_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        // Rate fijo en 1e18: convertToAssets/convertToUnits se vuelven
        // identidades exactas (sin redondeo), lo que permite aislar el
        // componente EXACTO de punitorios mas abajo.
        MockUVAOracle oracle_ = new MockUVAOracle(1e18);

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(12, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            30 days,
            dueDates,
            unitAmounts,
            5000e18,
            10,
            declarer
        );

        // Cuotas 1-3 puntuales
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        // Saltear cuotas 4 y 5: avanzar bien mas alla de su vencimiento
        vm.warp(uint256(dueDates[4]) + 5 days); // ~65 dias sin pagar desde la cuota 3
        oracle_.set(1e18);

        // status()/arrears() proyectan el devengo a block.timestamp: ya
        // reflejan la mora aca mismo, SIN mandar ninguna transaccion
        // (antes de la corrección de views obsoletas hacía falta un pago
        // minimo "poke" para forzar la persistencia; ya no es necesario).
        assertEq(
            uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears), "debe verse InArrears sin tx previa"
        );
        assertGt(lease.arrears(id), 0, "arrears() debe ser > 0 sin tx previa");

        (,, bool paid3) = lease.paymentAt(id, 3);
        (,, bool paid4) = lease.paymentAt(id, 4);
        assertFalse(paid3, "REGRESION: cuota 4 vencida impaga no debe figurar paid");
        assertFalse(paid4, "REGRESION: cuota 5 vencida impaga no debe figurar paid");

        // declareDefault es la primera tx real desde la cuota 3: establece
        // el primer checkpoint persistido de la mora (capital vencido,
        // sin punitorios todavia — devengan recien desde este checkpoint).
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.ArrearsAccrued(id, 0);
        vm.expectEmit(true, true, false, false);
        emit IFinancialLease.DefaultDeclared(id, declarer);
        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Dejar correr mas dias para que el stock ya reconocido devengue punitorios
        vm.warp(block.timestamp + 20 days);
        oracle_.set(1e18);

        // Componente EXACTO de punitorios (rate=1e18 => sin redondeo)
        uint256 principalUnits = _reconstructArrearsPrincipal(id);
        uint256 totalArrearsUnits = lease.arrears(id); // == unidades exactas porque rate == 1e18
        uint256 penaltyUnits = totalArrearsUnits - principalUnits;
        assertGt(penaltyUnits, 0, "debe haber punitorios devengados");

        uint256 outstandingBeforePenaltyPay = lease.outstandingUnits(id);
        oracle_.set(1e18);
        vm.prank(lesseeAddr);
        lease.pay(id, penaltyUnits);
        _assertInvariants(id);

        // REGRESION: pagar SOLO punitorios no debe reducir outstandingUnits
        assertEq(
            lease.outstandingUnits(id),
            outstandingBeforePenaltyPay,
            "REGRESION: los punitorios no deben tocar el capital/outstanding"
        );
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.InDefault),
            "sigue en default: el capital vencido sigue impago"
        );

        // Pagar el resto de la mora (capital vencido) -> cura
        oracle_.set(1e18);
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        vm.prank(lesseeAddr);
        lease.pay(id, principalUnits);
        _assertInvariants(id);

        assertEq(
            uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active), "debe curar a Active (quedan cuotas)"
        );
        assertEq(lease.arrears(id), 0, "toda la mora debe quedar saldada");

        // Completar las cuotas restantes (6 a 12) puntualmente
        for (uint256 i = 5; i < 12; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "debe llegar a Completed pese al historial de mora"
        );
        (, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable, "la opcion de compra debe quedar ejercible");
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 3 — securitizacion (cesion del lessor a mitad de vida)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario3_SecuritizationTransferMidLife() public {
        address lessorOriginal = makeAddr("s3_lessorOriginal");
        address fondoComprador = makeAddr("s3_fondoComprador");
        address tomador = makeAddr("s3_tomador");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(tomador, 1_000_000e18);
        vm.prank(tomador);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(24, 1000e18);
        uint256 id = _createLease(
            lessorOriginal,
            tomador,
            address(stable),
            address(oracle_),
            60 days,
            dueDates,
            unitAmounts,
            5000e18,
            10,
            address(0)
        );

        for (uint256 i = 0; i < 8; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorOriginal);
            vm.prank(tomador);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            assertEq(
                stable.balanceOf(lessorOriginal) - balBefore,
                assetsDue,
                "cuotas 1-8: los fondos deben ir a lessorOriginal"
            );
        }
        assertEq(stable.balanceOf(fondoComprador), 0, "fondoComprador no debe tener fondos todavia");

        uint256 outstandingBeforeTransfer = lease.outstandingUnits(id);
        IFinancialLease.LeaseStatus statusBeforeTransfer = lease.status(id);
        (uint256 nextAssetsBefore, uint64 nextDueBefore) = lease.nextPayment(id);

        vm.prank(lessorOriginal);
        lease.transferFrom(lessorOriginal, fondoComprador, id);
        _assertInvariants(id);

        assertEq(lease.lessor(id), fondoComprador, "el NFT debe pasar a fondoComprador");
        assertEq(
            lease.outstandingUnits(id), outstandingBeforeTransfer, "ASSERT: la cesion no debe alterar el outstanding"
        );
        assertEq(uint8(lease.status(id)), uint8(statusBeforeTransfer), "ASSERT: la cesion no debe alterar el status");
        (uint256 nextAssetsAfter, uint64 nextDueAfter) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "ASSERT: la cesion no debe alterar la proxima cuota");
        assertEq(nextDueAfter, nextDueBefore, "ASSERT: la cesion no debe alterar el vencimiento");

        for (uint256 i = 8; i < 24; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBeforeNew = stable.balanceOf(fondoComprador);
            uint256 balBeforeOld = stable.balanceOf(lessorOriginal);
            vm.prank(tomador);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            assertEq(
                stable.balanceOf(fondoComprador) - balBeforeNew,
                assetsDue,
                "cuotas 9-24: los fondos deben ir a fondoComprador"
            );
            assertEq(stable.balanceOf(lessorOriginal), balBeforeOld, "lessorOriginal no debe recibir nada mas");
        }

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    function test_Scenario3_TransferDuringDefault() public {
        address lessorA = makeAddr("s3b_lessorA");
        address lessorB = makeAddr("s3b_lessorB");
        address tomador = makeAddr("s3b_tomador");
        address declarer = makeAddr("s3b_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(tomador, 1_000_000e18);
        vm.prank(tomador);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(6, 1000e18);
        uint256 id = _createLease(
            lessorA, tomador, address(stable), address(oracle_), 60 days, dueDates, unitAmounts, 2000e18, 10, declarer
        );

        // Saltear la cuota 1 y dejarla devengar mora
        vm.warp(uint256(dueDates[0]) + 20 days);
        oracle_.set(1e18);

        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Cesion del NFT mientras la lease esta InDefault
        vm.prank(lessorA);
        lease.transferFrom(lessorA, lessorB, id);
        _assertInvariants(id);
        assertEq(lease.lessor(id), lessorB);

        uint256 curePrincipal = _reconstructArrearsPrincipal(id);
        uint256 curePenalty = lease.arrears(id) - curePrincipal; // rate=1e18: exacto
        uint256 balBeforeB = stable.balanceOf(lessorB);
        uint256 balBeforeA = stable.balanceOf(lessorA);

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        vm.prank(tomador);
        lease.pay(id, curePrincipal + curePenalty);
        _assertInvariants(id);

        assertEq(
            stable.balanceOf(lessorB) - balBeforeB,
            curePrincipal + curePenalty,
            "el pago de cura debe ir al nuevo dueno"
        );
        assertEq(stable.balanceOf(lessorA), balBeforeA, "el dueno anterior no debe recibir nada");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active));
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 4 — deflacion del indice
    // ════════════════════════════════════════════════════════════════

    function test_Scenario4_DeflationHealthyCycle() public {
        address lessorAddr = makeAddr("s4_lessor");
        address lesseeAddr = makeAddr("s4_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(2000e6);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(12, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            40 days,
            dueDates,
            unitAmounts,
            3000e18,
            10,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 projectedAtOriginalRate;
        uint256 rate = 2000e6;

        for (uint256 i = 0; i < 12; i++) {
            vm.warp(uint256(dueDates[i]));
            if (i == 3) {
                rate = (rate * 80) / 100; // el indice cae 20% entre la cuota 3 y la 4
            }
            oracle_.set(rate);

            projectedAtOriginalRate += (unitAmounts[i] * 2000e6) / 1e18;

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        console2.log("Escenario 4 - assets totales pagados (con deflacion):", totalAssetsPaid);
        console2.log("Escenario 4 - proyeccion ingenua al rate original:", projectedAtOriginalRate);
        assertLt(
            totalAssetsPaid,
            projectedAtOriginalRate,
            "con deflacion, lo realmente pagado debe ser menor a la proyeccion"
        );

        assertEq(lease.outstandingUnits(id), 0, "debe llegar a 0 unidades pendientes pese a la deflacion");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    function test_Scenario4_DangerousDeflationWithAccruedArrears() public {
        address lessorAddr = makeAddr("s4b_lessor");
        address lesseeAddr = makeAddr("s4b_lessee");
        address declarer = makeAddr("s4b_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(2000e6);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(6, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            60 days,
            dueDates,
            unitAmounts,
            2000e18,
            10,
            declarer
        );

        // Generar mora: saltear la cuota 1
        vm.warp(uint256(dueDates[0]) + 10 days);
        oracle_.set(2000e6);
        vm.prank(lesseeAddr);
        lease.pay(id, 1); // poke minimo: reconoce la mora, dispara InArrears
        _assertInvariants(id);

        // Dejar acumular punitorios en un segundo ciclo de accrual
        vm.warp(block.timestamp + 15 days);
        oracle_.set(2000e6);
        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        vm.warp(block.timestamp + 15 days);
        oracle_.set(2000e6);
        vm.prank(lesseeAddr);
        lease.pay(id, 1); // otro poke: mas punitorios sobre el stock vencido
        _assertInvariants(id);

        // Ahora, con punitorios ya devengados, el indice cae fuerte
        uint256 crashedRate = (2000e6 * 50) / 100; // -50%
        oracle_.set(crashedRate);
        _assertInvariants(id); // el solo movimiento del oraculo no debe corromper el estado

        // Pagar todo de una vez (capital vencido + punitorios + resto del
        // cronograma). pay() cappea a lo efectivamente adeudado, asi que
        // sobre-enviar es seguro y no debe haber underflow en ningun punto.
        uint256 hugeAmount = stable.balanceOf(lesseeAddr); // todo el balance disponible
        vm.prank(lesseeAddr);
        lease.pay(id, hugeAmount);
        _assertInvariants(id);

        assertEq(lease.outstandingUnits(id), 0, "no debe haber underflow ni estado corrupto tras la deflacion fuerte");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 5 — bordes de vencimiento y pagos parciales
    // ════════════════════════════════════════════════════════════════

    function test_Scenario5_PaymentTimingAndPartialEdges() public {
        address lessorAddr = makeAddr("s5_lessor");
        address lesseeAddr = makeAddr("s5_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(4, 500e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            30 days,
            dueDates,
            unitAmounts,
            1000e18,
            10,
            address(0)
        );

        // (a) Pagar EXACTAMENTE en dueDate: la condicion de mora en
        // _accrue usa `>` estricto, asi que vencer justo a tiempo NO
        // cuenta como mora. Comportamiento observado, documentado aqui.
        vm.warp(uint256(dueDates[0]));
        oracle_.set(1e18);
        (uint256 assetsDue0,) = lease.nextPayment(id);
        vm.prank(lesseeAddr);
        lease.pay(id, assetsDue0);
        _assertInvariants(id);
        console2.log("Escenario 5(a) - status tras pagar EXACTO en dueDate:", uint8(lease.status(id)));
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Active),
            "OBSERVADO: pagar exactamente en dueDate cuenta como al dia (sin mora), por el `>` estricto en _accrue"
        );
        assertEq(lease.arrears(id), 0);

        // (b) 1 segundo despues del vencimiento: SI se registra mora
        // (evento ArrearsAccrued), aunque se cure en la misma tx al pagar
        // el monto exacto adeudado.
        vm.warp(uint256(dueDates[1]) + 1);
        oracle_.set(1e18);
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.ArrearsAccrued(id, 0);
        (uint256 assetsDue1,) = lease.nextPayment(id);
        vm.prank(lesseeAddr);
        lease.pay(id, assetsDue1);
        _assertInvariants(id);
        assertEq(lease.arrears(id), 0, "se cura en la misma tx al pagar el monto exacto");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active));

        // (c) Pago parcial de la cuota 3
        vm.warp(uint256(dueDates[2]));
        oracle_.set(1e18);
        (uint256 assetsDue2,) = lease.nextPayment(id);
        uint256 half = assetsDue2 / 2;
        vm.prank(lesseeAddr);
        lease.pay(id, half);
        _assertInvariants(id);
        (,, bool paid2Partial) = lease.paymentAt(id, 2);
        assertFalse(paid2Partial, "un pago parcial no debe marcar la cuota como pagada");
        (uint256 remainingAssets,) = lease.nextPayment(id);
        assertGt(remainingAssets, 0, "nextPayment debe reflejar el saldo restante");
        assertLt(remainingAssets, assetsDue2, "el saldo restante debe ser menor al original");

        vm.prank(lesseeAddr);
        lease.pay(id, remainingAssets);
        _assertInvariants(id);
        (,, bool paid2Full) = lease.paymentAt(id, 2);
        assertTrue(paid2Full, "tras completar el saldo, la cuota debe quedar pagada");

        // (d) Sobrepago en la ultima cuota: solo se transfiere lo necesario
        uint256 outstandingBefore = lease.outstandingBalance(id);
        uint256 overpay = outstandingBefore * 10;
        uint256 lessorBalBefore = stable.balanceOf(lessorAddr);
        vm.prank(lesseeAddr);
        lease.pay(id, overpay);
        _assertInvariants(id);
        uint256 pulled = stable.balanceOf(lessorAddr) - lessorBalBefore;
        assertEq(pulled, outstandingBefore, "no debe transferirse mas de lo estrictamente adeudado");
        assertEq(lease.outstandingUnits(id), 0, "no debe acreditarse de mas");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        console2.log("Escenario 5(d) - assets enviados en el sobrepago:", overpay);
        console2.log("Escenario 5(d) - assets realmente transferidos:", pulled);
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 6 — cronograma largo, stress de redondeo (EL MAS IMPORTANTE)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario6_LongScheduleRoundingStress() public {
        address lessorAddr = makeAddr("s6_lessor");
        address lesseeAddr = makeAddr("s6_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 100_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1500e6);

        uint256 n = 60;
        uint256 amountEach = 833333333333333333; // no redondo
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, amountEach);

        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            10 days,
            dueDates,
            unitAmounts,
            amountEach,
            0,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 totalNominalConverted;
        uint256 rate = 1500e6;

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            rate = (rate * 1037) / 1000; // no redondo, ~3.7%/mes
            oracle_.set(rate);

            totalNominalConverted += lease.convertToAssets(id, amountEach);

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 6 - outstandingUnits final (esperado 0):", finalOutstanding);
        console2.log("Escenario 6 - assets totales pagados por el tomador:", totalAssetsPaid);
        console2.log("Escenario 6 - suma nominal convertida al momento de cada pago:", totalNominalConverted);

        if (finalOutstanding != 0) {
            console2.log(
                "HALLAZGO ESCENARIO 6: queda dust tras 60 pagos exactos, unidades residuales:", finalOutstanding
            );
        }
        assertEq(finalOutstanding, 0, "ESCENARIO 6 CRITICO: dust residual tras 60 cuotas con montos/rate no redondos");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    // ════════════════════════════════════════════════════════════════
    // ESCENARIO 7 — adaptador de oraculo real (Chainlink)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario7_ChainlinkOracleFullCycle() public {
        address lessorAddr = makeAddr("s7_lessor");
        address lesseeAddr = makeAddr("s7_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 10_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockAggregator feed = new MockAggregator(8);
        int256 answer = 1500e8;
        feed.setAnswer(answer);
        feed.setUpdatedAt(block.timestamp);
        ChainlinkConversionOracle clOracle = new ChainlinkConversionOracle(address(feed), 6);

        uint256 n = 36;
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(clOracle),
            10 days,
            dueDates,
            unitAmounts,
            1000e18,
            0,
            address(0)
        );

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            answer = (answer * 104) / 100;
            feed.setAnswer(answer);
            feed.setUpdatedAt(block.timestamp);

            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 7 - outstandingUnits final (esperado 0):", finalOutstanding);
        assertEq(finalOutstanding, 0, "ESCENARIO 7: dust residual con ChainlinkConversionOracle tras 36 pagos");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        (, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable);
        vm.prank(lesseeAddr);
        lease.exercisePurchaseOption(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }
}
