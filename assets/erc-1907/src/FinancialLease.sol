// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "./IConversionOracle.sol";

/// @title FinancialLease — implementación de referencia del ERC de leasing
/// @dev Posición del lessor = NFT (tokenId == leaseId). Cronograma inmutable
///      en unidades de cuenta; conversión a payment asset vía oráculo.
contract FinancialLease is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    enum LeaseStatus {
        Active, // 0
        InArrears, // 1
        InDefault, // 2
        Terminated, // 3
        Completed, // 4
        PurchaseExercised // 5
    }

    struct Lease {
        // Partes y capa legal
        address lessee;
        bytes2 jurisdiction;
        string governingLaw;
        bytes32 agreementHash;
        string assetRef;
        // Denominación
        address paymentAsset;
        string denomSymbol;
        address oracle; // address(0) = denominación fija
        uint64 maxOracleStaleness; // segundos; 0 = sin límite
        // Cronograma (inmutable, en unidades)
        uint64[] dueDates;
        uint256[] unitAmounts;
        uint256 scheduleTotalUnits; // suma total del cronograma
        // Estado vivo
        uint256 nextIndex; // puntero de DEVENGAMIENTO (no de pago)
        uint256 unitsPaidCurrent; // pago parcial de la cuota corriente
        uint256 settledUnits; // unidades del cronograma efectivamente pagadas
        uint256 arrearsPrincipalUnits; // capital vencido impago
        uint256 arrearsPenaltyUnits; // punitorios acumulados
        uint64 lastAccrual;
        LeaseStatus status;
        // Gobernanza de mora
        address defaultDeclarer;
        // Opción de compra
        uint256 purchasePriceUnits;
        // Punitorio: bps diarios sobre el stock vencido
        uint16 penaltyBpsPerDay;
    }

    uint256 public nextLeaseId = 1;
    mapping(uint256 => Lease) internal _leases;

    // ─── Eventos del estándar ─────────────────────────────────
    event LeaseCreated(
        uint256 indexed leaseId,
        address indexed lessor,
        address indexed lessee,
        bytes2 jurisdiction,
        address paymentAsset
    );
    event PaymentReceived(
        uint256 indexed leaseId,
        address indexed payer,
        uint256 assets,
        uint256 unitsSettled,
        uint256 conversionRate,
        uint256 newOutstandingUnits
    );
    event ArrearsAccrued(uint256 indexed leaseId, uint256 totalArrearsUnits);
    event DefaultDeclared(uint256 indexed leaseId, address indexed declarer);
    event DefaultCured(uint256 indexed leaseId);
    event PurchaseOptionExercised(uint256 indexed leaseId, uint256 priceInAssets);
    event LeaseTerminated(uint256 indexed leaseId, LeaseStatus finalStatus);
    event LesseeAssigned(uint256 indexed leaseId, address indexed oldLessee, address indexed newLessee);

    error StaleOracle();
    error NotAuthorized();
    error WrongStatus();
    error NothingDue();

    constructor() ERC721("Financial Lease Position", "LEASE") {}

    // ─── Originación ──────────────────────────────────────────

    /// @dev Agrupado en struct para evitar "stack too deep": createLease
    ///      tenía 14 parámetros sueltos (varios calldata/arrays), lo cual
    ///      excede el límite de stack incluso con via-ir. Los campos y su
    ///      semántica son idénticos a la firma original.
    struct CreateLeaseParams {
        address lessee;
        bytes2 jurisdiction;
        string governingLaw;
        bytes32 agreementHash;
        string assetRef;
        address paymentAsset;
        string denomSymbol;
        address oracle;
        uint64 maxStaleness;
        uint64[] dueDates;
        uint256[] unitAmounts;
        uint256 purchasePriceUnits;
        uint16 penaltyBpsPerDay;
        address defaultDeclarer;
    }

    function createLease(CreateLeaseParams calldata p) external returns (uint256 leaseId) {
        require(p.dueDates.length == p.unitAmounts.length && p.dueDates.length > 0, "bad schedule");
        for (uint256 i = 1; i < p.dueDates.length; i++) {
            require(p.dueDates[i] > p.dueDates[i - 1], "unsorted schedule");
        }

        leaseId = nextLeaseId++;
        Lease storage l = _leases[leaseId];
        l.lessee = p.lessee;
        l.jurisdiction = p.jurisdiction;
        l.governingLaw = p.governingLaw;
        l.agreementHash = p.agreementHash;
        l.assetRef = p.assetRef;
        l.paymentAsset = p.paymentAsset;
        l.denomSymbol = p.denomSymbol;
        l.oracle = p.oracle;
        l.maxOracleStaleness = p.maxStaleness;
        l.dueDates = p.dueDates;
        l.unitAmounts = p.unitAmounts;
        l.purchasePriceUnits = p.purchasePriceUnits;
        l.penaltyBpsPerDay = p.penaltyBpsPerDay;
        l.defaultDeclarer = p.defaultDeclarer == address(0) ? msg.sender : p.defaultDeclarer;
        l.lastAccrual = uint64(block.timestamp);
        l.status = LeaseStatus.Active;

        uint256 total;
        for (uint256 i = 0; i < p.unitAmounts.length; i++) {
            total += p.unitAmounts[i];
        }
        l.scheduleTotalUnits = total;

        _mint(msg.sender, leaseId); // lessor = dueño del NFT
        emit LeaseCreated(leaseId, msg.sender, p.lessee, p.jurisdiction, p.paymentAsset);
    }

    // ─── Conversión ───────────────────────────────────────────

    function conversionRateAsOf(uint256 leaseId) public view returns (uint256 rate, uint64 asOf) {
        Lease storage l = _leases[leaseId];
        if (l.oracle == address(0)) return (1e18, uint64(block.timestamp));
        (rate, asOf) = IConversionOracle(l.oracle).latestRate();
    }

    function _freshRate(uint256 leaseId) internal view returns (uint256 rate) {
        Lease storage l = _leases[leaseId];
        uint64 asOf;
        (rate, asOf) = conversionRateAsOf(leaseId);
        if (l.maxOracleStaleness != 0 && block.timestamp - asOf > l.maxOracleStaleness) {
            revert StaleOracle();
        }
    }

    /// @dev Cobros: redondeo hacia ARRIBA (contra el pagador)
    function convertToAssets(uint256 leaseId, uint256 units) public view returns (uint256) {
        (uint256 rate,) = conversionRateAsOf(leaseId);
        return units.mulDiv(rate, 1e18, Math.Rounding.Ceil);
    }

    /// @dev Acreditación de pagos: redondeo hacia ABAJO (contra el pagador)
    function convertToUnits(uint256 leaseId, uint256 assets) public view returns (uint256) {
        (uint256 rate,) = conversionRateAsOf(leaseId);
        return assets.mulDiv(1e18, rate, Math.Rounding.Floor);
    }

    // ─── Devengamiento (lazy) ─────────────────────────────────

    function _accrue(uint256 leaseId) internal {
        Lease storage l = _leases[leaseId];
        if (uint8(l.status) > uint8(LeaseStatus.InDefault)) return; // estados terminales

        // Fix (c): avanzar lastAccrual solo días enteros, conservando el resto
        uint256 daysElapsed = (block.timestamp - l.lastAccrual) / 1 days;
        if (daysElapsed > 0) {
            uint256 overdue = l.arrearsPrincipalUnits + l.arrearsPenaltyUnits;
            if (overdue > 0 && l.penaltyBpsPerDay > 0) {
                l.arrearsPenaltyUnits += overdue.mulDiv(uint256(l.penaltyBpsPerDay) * daysElapsed, 10_000);
            }
            l.lastAccrual += uint64(daysElapsed * 1 days);
        }

        // Cuotas vencidas pasan al stock de mora (capital)
        while (l.nextIndex < l.dueDates.length && block.timestamp > l.dueDates[l.nextIndex]) {
            l.arrearsPrincipalUnits += l.unitAmounts[l.nextIndex] - l.unitsPaidCurrent;
            l.unitsPaidCurrent = 0;
            l.nextIndex++; // puntero de devengamiento, NO implica pago
        }

        if (l.arrearsPrincipalUnits + l.arrearsPenaltyUnits > 0 && l.status == LeaseStatus.Active) {
            l.status = LeaseStatus.InArrears;
            emit ArrearsAccrued(leaseId, l.arrearsPrincipalUnits + l.arrearsPenaltyUnits);
        }
    }

    // ─── Pago ─────────────────────────────────────────────────

    /// @dev Imputación de referencia: punitorios → capital vencido → cuotas.
    function pay(uint256 leaseId, uint256 assets) external nonReentrant {
        Lease storage l = _leases[leaseId];
        _accrue(leaseId);
        if (uint8(l.status) > uint8(LeaseStatus.InDefault)) revert WrongStatus();

        uint256 rate = _freshRate(leaseId);

        // Fix (d): capar a lo adeudado y transferir solo lo necesario
        uint256 owedUnits = l.arrearsPenaltyUnits + (l.scheduleTotalUnits - l.settledUnits);
        uint256 units = Math.min(assets.mulDiv(1e18, rate, Math.Rounding.Floor), owedUnits);
        if (units == 0) revert NothingDue();
        uint256 pulled = units.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        // ── Efectos ──
        uint256 remaining = units;

        // 1) Punitorios — fix (b): NO tocan settledUnits ni el capital
        uint256 toPenalty = Math.min(remaining, l.arrearsPenaltyUnits);
        l.arrearsPenaltyUnits -= toPenalty;
        remaining -= toPenalty;

        // 2) Capital vencido — SÍ es cronograma
        uint256 toArrears = Math.min(remaining, l.arrearsPrincipalUnits);
        l.arrearsPrincipalUnits -= toArrears;
        l.settledUnits += toArrears;
        remaining -= toArrears;

        // 3) Cuotas corrientes en orden
        while (remaining > 0 && l.nextIndex < l.unitAmounts.length) {
            uint256 due = l.unitAmounts[l.nextIndex] - l.unitsPaidCurrent;
            uint256 applied = Math.min(remaining, due);
            l.unitsPaidCurrent += applied;
            l.settledUnits += applied;
            remaining -= applied;
            if (l.unitsPaidCurrent == l.unitAmounts[l.nextIndex]) {
                l.unitsPaidCurrent = 0;
                l.nextIndex++;
            }
        }

        if (l.arrearsPrincipalUnits + l.arrearsPenaltyUnits == 0) {
            if (l.status == LeaseStatus.InDefault) emit DefaultCured(leaseId);
            l.status = l.settledUnits == l.scheduleTotalUnits ? LeaseStatus.Completed : LeaseStatus.Active;
            if (l.status == LeaseStatus.Completed) {
                emit LeaseTerminated(leaseId, LeaseStatus.Completed);
            }
        }

        // ── Interacción al final — fix (e) ──
        IERC20(l.paymentAsset).safeTransferFrom(msg.sender, ownerOf(leaseId), pulled);

        emit PaymentReceived(leaseId, msg.sender, pulled, units, rate, l.scheduleTotalUnits - l.settledUnits);
    }

    // ─── Mora formal ──────────────────────────────────────────

    function declareDefault(uint256 leaseId) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != l.defaultDeclarer) revert NotAuthorized();
        _accrue(leaseId);
        if (l.status != LeaseStatus.InArrears) revert WrongStatus();
        l.status = LeaseStatus.InDefault;
        emit DefaultDeclared(leaseId, msg.sender);
    }

    // ─── Opción de compra ─────────────────────────────────────

    function purchaseOption(uint256 leaseId) public view returns (uint256 priceInAssets, bool exercisable) {
        Lease storage l = _leases[leaseId];
        priceInAssets = convertToAssets(leaseId, l.purchasePriceUnits);
        exercisable = l.status == LeaseStatus.Completed;
    }

    function exercisePurchaseOption(uint256 leaseId) external nonReentrant {
        Lease storage l = _leases[leaseId];
        _accrue(leaseId);
        if (msg.sender != l.lessee) revert NotAuthorized();
        (, bool ok) = purchaseOption(leaseId);
        if (!ok) revert WrongStatus();

        uint256 rate = _freshRate(leaseId);
        uint256 price = l.purchasePriceUnits.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        l.status = LeaseStatus.PurchaseExercised;

        IERC20(l.paymentAsset).safeTransferFrom(msg.sender, ownerOf(leaseId), price);

        emit PurchaseOptionExercised(leaseId, price);
        emit LeaseTerminated(leaseId, LeaseStatus.PurchaseExercised);
        // Extensión asset-bound: acá iría el settlement atómico del bien
    }

    // ─── Cesión del tomador ───────────────────────────────────

    /// @dev Simplificación de referencia: en producción, consentimiento
    ///      de ambas partes + hook de compliance (3643/7943).
    function assignLessee(uint256 leaseId, address newLessee) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != l.lessee && msg.sender != l.defaultDeclarer) {
            revert NotAuthorized();
        }
        address old = l.lessee;
        l.lessee = newLessee;
        emit LesseeAssigned(leaseId, old, newLessee);
    }

    // ─── Views del estándar ───────────────────────────────────

    function lessor(uint256 id) external view returns (address) {
        return ownerOf(id);
    }

    function lessee(uint256 id) external view returns (address) {
        return _leases[id].lessee;
    }

    function jurisdiction(uint256 id) external view returns (bytes2) {
        return _leases[id].jurisdiction;
    }

    function governingLaw(uint256 id) external view returns (string memory) {
        return _leases[id].governingLaw;
    }

    function agreementHash(uint256 id) external view returns (bytes32) {
        return _leases[id].agreementHash;
    }

    function assetReference(uint256 id) external view returns (string memory) {
        return _leases[id].assetRef;
    }

    function paymentAsset(uint256 id) external view returns (address) {
        return _leases[id].paymentAsset;
    }

    function denomination(uint256 id) external view returns (string memory, address) {
        return (_leases[id].denomSymbol, _leases[id].oracle);
    }

    function paymentCount(uint256 id) external view returns (uint256) {
        return _leases[id].dueDates.length;
    }

    /// @dev Fix (a): `paid` se deriva del acumulado saldado, no del
    ///      puntero de devengamiento. Loop aceptable en referencia;
    ///      producción usaría prefix sums.
    function paymentAt(uint256 id, uint256 i) external view returns (uint256 units, uint64 dueDate, bool paid) {
        Lease storage l = _leases[id];
        units = l.unitAmounts[i];
        dueDate = l.dueDates[i];
        uint256 cum;
        for (uint256 k = 0; k <= i; k++) {
            cum += l.unitAmounts[k];
        }
        paid = l.settledUnits >= cum;
    }

    function outstandingUnits(uint256 id) public view returns (uint256) {
        Lease storage l = _leases[id];
        return l.scheduleTotalUnits - l.settledUnits;
    }

    function outstandingBalance(uint256 id) external view returns (uint256) {
        return convertToAssets(id, outstandingUnits(id));
    }

    function arrears(uint256 id) external view returns (uint256) {
        Lease storage l = _leases[id];
        return convertToAssets(id, l.arrearsPrincipalUnits + l.arrearsPenaltyUnits);
    }

    function nextPayment(uint256 id) external view returns (uint256 assets, uint64 dueDate) {
        Lease storage l = _leases[id];
        if (l.nextIndex >= l.dueDates.length) return (0, 0);
        uint256 due = l.unitAmounts[l.nextIndex] - l.unitsPaidCurrent;
        return (convertToAssets(id, due), l.dueDates[l.nextIndex]);
    }

    function status(uint256 id) external view returns (LeaseStatus) {
        return _leases[id].status;
    }
}
