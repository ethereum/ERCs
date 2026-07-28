// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "./IConversionOracle.sol";
import {IFinancialLease, INPUT_INDEX_OBSERVATION, TERMINATION_DEFAULT} from "./IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "./IFinancialLeaseAnchored.sol";

/// @title FinancialLease — implementación de referencia del ERC de leasing
/// @dev Posición del lessor = NFT (tokenId == leaseId). Cronograma inmutable
///      en unidades de cuenta; conversión a payment asset vía oráculo.
contract FinancialLease is ERC721, ReentrancyGuard, IFinancialLease, IFinancialLeaseAnchored {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @dev observedAt: cuando el servicer dice que observo el dato
    ///      off-chain. reportedAt: cuando quedo persistido on-chain
    ///      (siempre block.timestamp de la tx de updateServicing). Los dos
    ///      pueden divergir (ver inputFreshness) — maxStaleness NO vive
    ///      aca: la fija la configuracion del lease (ver
    ///      Lease.maxStalenessByInput), no el servicer.
    struct ServicingAttestation {
        uint64 observedAt;
        uint64 reportedAt;
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
        // Estado vivo — devengamiento closed-form (fix S3-01, ver
        // audit/s3-01-diseno.md y audit/s3-01-fix.md). Nada de esto se
        // "proyecta": arrears()/status()/nextPayment() son funciones puras
        // de estos campos + block.timestamp, sin ningun paso de
        // persistencia intermedio.
        uint256 settledUnits; // unidades del cronograma efectivamente pagadas (capital, FIFO)
        // Punitorio: "bruto acumulado" (crystallizedPenaltyUnits + dinamico
        // sobre lo actualmente impago, ver _computeState) MENOS lo
        // efectivamente pagado (penaltyPaidUnits). crystallizedPenaltyUnits
        // solo crece cuando un pago reduce montoImpago(i) de un tramo
        // vencido — nunca por el mero paso del tiempo ni por relectura.
        uint256 crystallizedPenaltyUnits;
        uint256 penaltyPaidUnits;
        // Cache de gas (NO fuente de verdad): primer tramo del cronograma
        // con saldo impago, y la suma acumulada de unitAmounts ANTES de
        // ese indice. Se mantiene al dia en cada pay(); si por algun motivo
        // quedara atras, los loops que lo usan son defensivos (ver
        // _computeState) y el resultado sigue siendo correcto, solo menos
        // optimo en gas.
        uint256 firstUnsettledIndex;
        uint256 cumBeforeFirstUnsettled;
        LeaseStatus status;
        // Gobernanza de mora (fix S4-01): 0 = sin override, el poder de
        // declarar default sigue DINAMICAMENTE a ownerOf(leaseId) (ver
        // _declarer()) — sobrevive a transferencias del NFT sin quedar
        // nunca en manos de un lessor que ya se desprendio de la
        // posicion. Un lessor puede delegar a una address fija via
        // assignDefaultDeclarer, gateado por ser el ownerOf actual.
        address defaultDeclarer;
        // Timestamp de la ultima transicion exitosa a InDefault (0 = nunca).
        // Usado como ancla del timelock de terminateForDefault.
        uint64 defaultDeclaredAt;
        // Terminación anticipada (fix S6-01): ver _terminate(),
        // proposeTermination(), acceptTermination(), terminateForDefault().
        // terminationTimestamp == 0 significa "no terminado" — una vez
        // seteado, _effectiveNow() lo usa para congelar toda magnitud
        // economica derivada de _computeState en ese instante para
        // siempre, sin importar cuanto tiempo pase despues.
        uint64 terminationTimestamp;
        uint64 terminationDelay; // fijado al originar; MUST ser > 0
        bytes32 terminationReason;
        address terminationProposedBy;
        bytes32 terminationProposedReason;
        // Opción de compra
        uint256 purchasePriceUnits;
        // Punitorio: bps diarios sobre el stock vencido
        uint16 penaltyBpsPerDay;
        // Ancla a activo titulado en un registro ERC-8325 (opcional)
        uint256 anchorChainId;
        address anchorRegistry;
        bytes32 anchorId;
        // Servicing paralelo: atestaciones de frescura por input (bytes32)
        address servicer;
        mapping(bytes32 => ServicingAttestation) servicingAttestations;
        // maxStaleness declarado por input, fijado al originar el lease
        // (change 3): el servicer ya NO puede autoevaluarse su propia
        // tolerancia via updateServicing.
        mapping(bytes32 => uint64) maxStalenessByInput;
    }

    uint256 public nextLeaseId = 1;
    mapping(uint256 => Lease) internal _leases;

    error StaleOracle();
    error NotAuthorized();
    error WrongStatus();
    error NothingDue();
    error DerivedInput();
    error InvalidAnchor();
    error FutureObservation();
    error InvalidTerminationDelay();
    error TimelockNotElapsed();

    /// @dev No forma parte de IFinancialLease: es especifico de como esta
    ///      implementacion resuelve el rol de defaultDeclarer (fix S4-01).
    event DefaultDeclarerAssigned(uint256 indexed leaseId, address indexed oldDeclarer, address indexed newDeclarer);

    /// @dev No forma parte de IFinancialLease: la interfaz solo exige
    ///      LeaseTerminated(leaseId, finalStatus) — ya declarado ahi y
    ///      reusado para el status Terminated. Estos dos eventos agregan
    ///      la causal y quien propuso, que LeaseTerminated no carga.
    event TerminationProposed(uint256 indexed leaseId, address indexed proposedBy, bytes32 reason);
    event TerminationRecorded(uint256 indexed leaseId, bytes32 indexed reason);

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
        // Timelock entre declareDefault y terminateForDefault. MUST > 0:
        // cero admite tres lecturas razonables (sin timelock / usar un
        // default implicito / configuracion invalida) y ese patron ya
        // costo un hallazgo (S2-05, sentinel de staleness con semantica
        // ambigua entre capas) — createLease revierte explicito en vez
        // de dejarlo ambiguo.
        uint64 terminationDelay;
        uint256 anchorChainId;
        address anchorRegistry;
        bytes32 anchorId;
        address servicer;
        // Tolerancia de staleness por servicing input (change 3): arrays
        // paralelos porque los structs calldata no admiten mappings.
        // IndexObservation ignora esta config: usa maxOracleStaleness.
        bytes32[] servicingInputs;
        uint64[] servicingMaxStaleness;
    }

    function createLease(CreateLeaseParams calldata p) external returns (uint256 leaseId) {
        require(p.dueDates.length == p.unitAmounts.length && p.dueDates.length > 0, "bad schedule");
        for (uint256 i = 1; i < p.dueDates.length; i++) {
            require(p.dueDates[i] > p.dueDates[i - 1], "unsorted schedule");
        }
        require(p.servicingInputs.length == p.servicingMaxStaleness.length, "bad servicing config");
        if (p.terminationDelay == 0) revert InvalidTerminationDelay();

        // Change 1: la tupla de anclaje es o toda-cero (no anclado) o
        // toda-seteada. Tuplas parciales quedan invalidas.
        bool anyAnchorField = p.anchorChainId != 0 || p.anchorRegistry != address(0) || p.anchorId != bytes32(0);
        bool allAnchorFields = p.anchorChainId != 0 && p.anchorRegistry != address(0) && p.anchorId != bytes32(0);
        if (anyAnchorField && !allAnchorFields) revert InvalidAnchor();

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
        // Fix S4-01: ya NO se sustituye address(0) por msg.sender. Dejarlo
        // en 0 significa "sin override" -> _declarer() lo resuelve
        // dinamicamente contra ownerOf(leaseId) en cada llamada, asi que
        // sigue al NFT si se transfiere. Pasar una address explicita
        // fija ese declarer desde el origen (delegacion inicial).
        l.defaultDeclarer = p.defaultDeclarer;
        l.terminationDelay = p.terminationDelay;
        l.status = LeaseStatus.Active;
        l.anchorChainId = p.anchorChainId;
        l.anchorRegistry = p.anchorRegistry;
        l.anchorId = p.anchorId;
        l.servicer = p.servicer == address(0) ? msg.sender : p.servicer;

        for (uint256 i = 0; i < p.servicingInputs.length; i++) {
            l.maxStalenessByInput[p.servicingInputs[i]] = p.servicingMaxStaleness[i];
        }

        uint256 total;
        for (uint256 i = 0; i < p.unitAmounts.length; i++) {
            total += p.unitAmounts[i];
        }
        l.scheduleTotalUnits = total;
        // firstUnsettledIndex / cumBeforeFirstUnsettled quedan en su
        // default (0, 0) — correcto: apuntan al primer tramo del
        // cronograma, sin nada acumulado antes.

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
        // S2-01: un oraculo con asOf futuro underfloweria `block.timestamp
        // - asOf` -> Panic -> DoS de pay()/exercisePurchaseOption(). La
        // capa de servicing ya exige esto (ver FutureObservation en
        // updateServicing); reusa el mismo error para la capa de oraculo,
        // sin importar si el oraculo especifico en uso es confiable.
        if (asOf > block.timestamp) revert FutureObservation();
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

    // ─── Terminalidad y congelamiento ───────────────────────────

    /// @dev Unica fuente de verdad de "¿es un status terminal?". Por
    ///      valor exacto, no por orden del enum — un `uint8(status) >
    ///      uint8(X)` se rompe en silencio si algun dia se inserta un
    ///      miembro nuevo en medio del enum; esto no.
    function _isTerminal(LeaseStatus s) internal pure returns (bool) {
        return s == LeaseStatus.Completed || s == LeaseStatus.PurchaseExercised || s == LeaseStatus.Terminated;
    }

    /// @dev "Ahora", a los efectos de cualquier calculo economico. Antes
    ///      de terminar: block.timestamp real. Despues de terminar:
    ///      congelado para siempre en el instante de la terminacion — asi
    ///      arrears()/status()/nextPayment() (todo lo que pasa por
    ///      _computeState) dejan de moverse apenas el lease es Terminated,
    ///      sin importar cuanto tiempo transcurra despues.
    function _effectiveNow(Lease storage l) internal view returns (uint64) {
        return l.terminationTimestamp == 0 ? uint64(block.timestamp) : l.terminationTimestamp;
    }

    // ─── Devengamiento (closed-form, sin estado intermedio) ────

    /// @dev Fuente única de verdad de la mora, en unidades de cuenta.
    ///      Recorre el cronograma desde el cache (firstUnsettledIndex /
    ///      cumBeforeFirstUnsettled) hasta el primer tramo NO vencido
    ///      (dueDates ascendente => ahi se puede cortar, todo lo que sigue
    ///      tambien esta por vencer). Es pura: ninguna llamada externa
    ///      puede alterar su resultado salvo un pago real (que muta
    ///      settledUnits/crystallizedPenaltyUnits/penaltyPaidUnits) — por
    ///      eso arrears()/status()/nextPayment()/pay() dan siempre el
    ///      mismo valor sin importar cuantas veces se llamo antes (fix
    ///      S3-01). Devuelve ademas nextIdx/cumAtNextIdx: el primer tramo
    ///      con dueDate >= ahora (o length si no queda ninguno) y la suma
    ///      acumulada hasta ahi — reutilizado por nextPayment() para no
    ///      pagar un segundo recorrido ni una busqueda binaria aparte.
    function _computeState(Lease storage l)
        internal
        view
        returns (uint256 principalArrears, uint256 penaltyGrossNow, uint256 nextIdx, uint256 cumAtNextIdx)
    {
        uint256 n = l.dueDates.length;
        uint256 i = l.firstUnsettledIndex;
        uint256 cum = l.cumBeforeFirstUnsettled;
        uint256 settled = l.settledUnits;
        uint16 bps = l.penaltyBpsPerDay;
        uint64 nowEff = _effectiveNow(l); // congela post-terminacion

        for (; i < n; i++) {
            cum += l.unitAmounts[i];
            if (cum <= settled) continue; // saldado (cache defensivamente atrasado); seguir
            if (l.dueDates[i] >= nowEff) break; // primer tramo aun no vencido: cortar aca
            uint256 unpaid = cum - settled;
            if (unpaid > l.unitAmounts[i]) unpaid = l.unitAmounts[i]; // clamp defensivo
            principalArrears += unpaid;
            if (bps > 0) {
                uint256 daysLate = (nowEff - l.dueDates[i]) / 1 days;
                penaltyGrossNow += unpaid.mulDiv(uint256(bps) * daysLate, 10_000, Math.Rounding.Floor);
            }
        }
        nextIdx = i;
        cumAtNextIdx = cum;
    }

    /// @dev penaltyOwed = (crystallizedPenaltyUnits + dinamico-de-ahora) −
    ///      penaltyPaidUnits. Nunca negativo por construccion: solo se
    ///      permite pagar hasta min(remaining, penaltyOwed) en cada pago
    ///      (ver pay()), y el numerador es monotono no-decreciente, asi
    ///      que penaltyPaidUnits jamas puede superarlo.
    function _penaltyOwed(Lease storage l, uint256 penaltyGrossNow) internal view returns (uint256) {
        return l.crystallizedPenaltyUnits + penaltyGrossNow - l.penaltyPaidUnits;
    }

    function _statusView(Lease storage l) internal view returns (LeaseStatus) {
        if (l.status != LeaseStatus.Active) return l.status;
        (uint256 principalArrears,,,) = _computeState(l);
        return principalArrears > 0 ? LeaseStatus.InArrears : LeaseStatus.Active;
    }

    /// @dev Aplica `remaining` unidades a capital, FIFO desde el cache,
    ///      cristalizando por tramo con SU PROPIA fecha de vencimiento
    ///      (no una fecha comun para todo el pago — ver T48). Cubre tanto
    ///      capital vencido (cristaliza) como cuotas futuras (no
    ///      cristaliza, `dueDates[i] >= block.timestamp`) en un unico
    ///      recorrido: son la misma cola FIFO, solo difieren en si
    ///      generan punitorio.
    function _applyToPrincipal(Lease storage l, uint256 remaining) internal {
        uint256 i = l.firstUnsettledIndex;
        uint256 cumBefore = l.cumBeforeFirstUnsettled; // suma de unitAmounts[0..i-1]
        uint256 settledSoFar = l.settledUnits;
        uint256 crystallizedNow;
        uint256 n = l.dueDates.length;
        uint16 bps = l.penaltyBpsPerDay;
        // Inalcanzable con un lease Terminated (pay() ya revierte antes
        // de llegar aca), pero _effectiveNow() de todos modos por
        // consistencia: ningun calculo economico de este contrato debe
        // depender de block.timestamp directo, ni siquiera en un camino
        // hoy inalcanzable.
        uint64 nowEff = _effectiveNow(l);

        while (remaining > 0 && i < n) {
            uint256 cumThroughI = cumBefore + l.unitAmounts[i];
            uint256 unpaid = cumThroughI > settledSoFar ? cumThroughI - settledSoFar : 0;
            if (unpaid == 0) {
                cumBefore = cumThroughI;
                i++;
                continue;
            }
            uint256 applied = Math.min(remaining, unpaid);

            if (bps > 0 && l.dueDates[i] < nowEff) {
                uint256 daysLate = (nowEff - l.dueDates[i]) / 1 days;
                crystallizedNow += applied.mulDiv(uint256(bps) * daysLate, 10_000, Math.Rounding.Floor);
            }

            settledSoFar += applied;
            remaining -= applied;

            if (applied == unpaid) {
                cumBefore = cumThroughI;
                i++;
            }
        }

        l.firstUnsettledIndex = i;
        l.cumBeforeFirstUnsettled = cumBefore;
        l.settledUnits = settledSoFar;
        if (crystallizedNow > 0) l.crystallizedPenaltyUnits += crystallizedNow;
    }

    // ─── Pago ─────────────────────────────────────────────────

    /// @dev Imputación de referencia: punitorios → capital vencido → cuotas.
    ///      Punitorios (cristalizado + dinamico neteado contra lo pagado)
    ///      se pueden pagar de forma independiente del capital que los
    ///      generó (ver T7/Scenario2) — pagar solo el punitorio NO reduce
    ///      outstandingUnits.
    function pay(uint256 leaseId, uint256 assets) external nonReentrant {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();

        uint256 rate = _freshRate(leaseId);

        LeaseStatus statusBefore = l.status;
        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        uint256 penaltyOwed = _penaltyOwed(l, penaltyGrossNow);

        if (statusBefore == LeaseStatus.Active && principalArrears > 0) {
            emit ArrearsAccrued(leaseId, principalArrears + penaltyOwed);
        }

        // Fix (d): capar a lo adeudado y transferir solo lo necesario
        uint256 remainingPrincipal = l.scheduleTotalUnits - l.settledUnits;
        uint256 owedUnits = penaltyOwed + remainingPrincipal;
        uint256 units = Math.min(assets.mulDiv(1e18, rate, Math.Rounding.Floor), owedUnits);
        if (units == 0) revert NothingDue();
        uint256 pulled = units.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        // ── Efectos ──
        uint256 remaining = units;

        // 1) Punitorios — fix (b): NO tocan settledUnits ni el capital
        uint256 toPenalty = Math.min(remaining, penaltyOwed);
        l.penaltyPaidUnits += toPenalty;
        remaining -= toPenalty;

        // 2) Capital (vencido primero por el orden FIFO del cache, luego
        //    cuotas futuras) — cristaliza punitorio por tramo al pasar
        if (remaining > 0) {
            _applyToPrincipal(l, remaining);
        }

        bool stillOverdue =
            l.firstUnsettledIndex < l.dueDates.length && l.dueDates[l.firstUnsettledIndex] < _effectiveNow(l);
        bool stillOwesPenalty = l.crystallizedPenaltyUnits != l.penaltyPaidUnits;

        if (!stillOverdue && !stillOwesPenalty) {
            if (statusBefore == LeaseStatus.InDefault) emit DefaultCured(leaseId);
            l.status = l.settledUnits == l.scheduleTotalUnits ? LeaseStatus.Completed : LeaseStatus.Active;
            if (l.status == LeaseStatus.Completed) {
                emit LeaseTerminated(leaseId, LeaseStatus.Completed);
            }
        } else if (statusBefore == LeaseStatus.Active) {
            // La mora persiste y todavia no se habia marcado — queda
            // registrada para que un pago posterior no vuelva a emitir
            // ArrearsAccrued por la misma mora.
            l.status = LeaseStatus.InArrears;
        }

        // ── Interacción al final — fix (e) ──
        IERC20(l.paymentAsset).safeTransferFrom(msg.sender, ownerOf(leaseId), pulled);

        emit PaymentReceived(leaseId, msg.sender, pulled, units, rate, l.scheduleTotalUnits - l.settledUnits);
    }

    // ─── Mora formal ──────────────────────────────────────────

    /// @dev Fix S4-01: si nunca se delego explicitamente (defaultDeclarer
    ///      == 0), el poder de declarar default es del ownerOf(leaseId)
    ///      ACTUAL — sigue al NFT en cada transferencia, nunca se queda
    ///      congelado en un lessor que ya vendio su posicion.
    function _declarer(Lease storage l, uint256 leaseId) internal view returns (address) {
        return l.defaultDeclarer == address(0) ? ownerOf(leaseId) : l.defaultDeclarer;
    }

    /// @dev Delegacion explicita del rol de defaultDeclarer, gateada por
    ///      quien sea el dueño ACTUAL del NFT (nunca por quien lo era al
    ///      originar el lease). `newDeclarer == address(0)` limpia la
    ///      delegacion y vuelve a la resolucion dinamica via ownerOf.
    function assignDefaultDeclarer(uint256 leaseId, address newDeclarer) external {
        if (msg.sender != ownerOf(leaseId)) revert NotAuthorized();
        Lease storage l = _leases[leaseId];
        address old = l.defaultDeclarer;
        l.defaultDeclarer = newDeclarer;
        emit DefaultDeclarerAssigned(leaseId, old, newDeclarer);
    }

    function declareDefault(uint256 leaseId) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != _declarer(l, leaseId)) revert NotAuthorized();
        // Active: mora nunca "notada" por un pay() previo. InArrears: ya
        // notada (persistida por pay(), ver epilogo de pay()). Ambas son
        // validas — la unica diferencia es si ArrearsAccrued ya se emitio.
        LeaseStatus statusBefore = l.status;
        if (statusBefore != LeaseStatus.Active && statusBefore != LeaseStatus.InArrears) revert WrongStatus();

        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        if (principalArrears == 0) revert WrongStatus();

        if (statusBefore == LeaseStatus.Active) {
            emit ArrearsAccrued(leaseId, principalArrears + _penaltyOwed(l, penaltyGrossNow));
        }

        l.status = LeaseStatus.InDefault;
        l.defaultDeclaredAt = uint64(block.timestamp);
        emit DefaultDeclared(leaseId, msg.sender);
    }

    // ─── Terminación anticipada (fix S6-01) ─────────────────────

    /// @dev Congela el lease para siempre: persiste el instante y la
    ///      causal, y pasa a Terminated. A partir de aca, _effectiveNow()
    ///      deja de avanzar para este lease — ninguna magnitud economica
    ///      derivada de _computeState vuelve a cambiar.
    function _terminate(uint256 leaseId, Lease storage l, bytes32 reason) internal {
        l.terminationTimestamp = uint64(block.timestamp);
        l.status = LeaseStatus.Terminated;
        l.terminationReason = reason;
        emit LeaseTerminated(leaseId, LeaseStatus.Terminated);
        emit TerminationRecorded(leaseId, reason);
    }

    /// @dev Paso 1 de la terminación por acuerdo mutuo. Llamable por el
    ///      lessee o por el ownerOf(leaseId) actual, en cualquier status
    ///      no terminal (Active, InArrears o InDefault). Una propuesta
    ///      nueva SIEMPRE sobrescribe la anterior — sin importar quién la
    ///      hizo ni si ya había una pendiente sin aceptar.
    function proposeTermination(uint256 leaseId, bytes32 reason) external {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();
        if (msg.sender != l.lessee && msg.sender != ownerOf(leaseId)) revert NotAuthorized();

        l.terminationProposedBy = msg.sender;
        l.terminationProposedReason = reason;
        emit TerminationProposed(leaseId, msg.sender, reason);
    }

    /// @dev Paso 2. Solo la CONTRAPARTE del último `proposeTermination`
    ///      puede aceptar: si propuso el lessee, acepta el ownerOf
    ///      actual, y viceversa (evaluado con las identidades VIGENTES al
    ///      momento de aceptar, no las que tenían al proponer — si
    ///      `lessee`/el dueño del NFT cambiaron en el medio,
    ///      assignLessee/transferFrom siguen permitidos mientras no haya
    ///      terminado, ver matriz de operaciones).
    function acceptTermination(uint256 leaseId) external {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();

        address proposer = l.terminationProposedBy;
        if (proposer == address(0)) revert NotAuthorized(); // nada propuesto todavia
        address expectedAccepter = proposer == l.lessee ? ownerOf(leaseId) : l.lessee;
        if (msg.sender != expectedAccepter) revert NotAuthorized();

        bytes32 reason = l.terminationProposedReason;
        l.terminationProposedBy = address(0);
        l.terminationProposedReason = bytes32(0);

        _terminate(leaseId, l, reason);
    }

    /// @dev Terminación por incumplimiento. Solo el ownerOf(leaseId)
    ///      actual (nunca el defaultDeclarer per se, aunque en general
    ///      coincidan salvo delegación explícita — ver S4-01/S4-02:
    ///      declarar default y decidir terminar son facultades
    ///      distintas, la primera puede delegarse sin delegar la
    ///      segunda). Requiere status == InDefault (estricto, no
    ///      InArrears ni Active) Y que haya pasado el timelock desde
    ///      defaultDeclaredAt.
    function terminateForDefault(uint256 leaseId) external {
        if (msg.sender != ownerOf(leaseId)) revert NotAuthorized();
        Lease storage l = _leases[leaseId];
        if (l.status != LeaseStatus.InDefault) revert WrongStatus();
        if (block.timestamp < uint256(l.defaultDeclaredAt) + uint256(l.terminationDelay)) {
            revert TimelockNotElapsed();
        }

        _terminate(leaseId, l, TERMINATION_DEFAULT);
    }

    // ─── Opción de compra ─────────────────────────────────────

    function purchaseOption(uint256 leaseId) public view returns (uint256 priceInAssets, bool exercisable) {
        Lease storage l = _leases[leaseId];
        priceInAssets = convertToAssets(leaseId, l.purchasePriceUnits);
        exercisable = _statusView(l) == LeaseStatus.Completed;
    }

    function exercisePurchaseOption(uint256 leaseId) external nonReentrant {
        Lease storage l = _leases[leaseId];
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

    /// @dev Fix S4-02: solo el lessee SALIENTE puede reasignarse a si
    ///      mismo. La version anterior tambien aceptaba a
    ///      `defaultDeclarer` (que por default terminaba siendo el
    ///      lessor) sin gate de status ni consentimiento del lessee —
    ///      permitia robar la opcion de compra a costo cero (ver
    ///      audit/s4-02-fix.md). Simplificación de referencia: en
    ///      producción, además consentimiento explícito (firma/two-step)
    ///      + hook de compliance (3643/7943). Reasignación iniciada por
    ///      un tercero (ej. repossession post-default) requeriría un rol
    ///      separado, explícitamente delegado — nunca el mismo que
    ///      declara default ni el lessor.
    /// @dev Permitido en Active/InArrears/InDefault, bloqueado en
    ///      terminales (fix S6-01, matriz de operaciones): es política
    ///      comercial, no una cuestión de autorización — el estándar deja
    ///      esta elección a la implementación; esta referencia elige
    ///      permitirlo incluso en mora porque no hay ninguna razón
    ///      económica para impedirle al tomador ceder su posición
    ///      mientras el lease siga vivo.
    function assignLessee(uint256 leaseId, address newLessee) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != l.lessee) revert NotAuthorized();
        if (_isTerminal(l.status)) revert WrongStatus();
        address old = l.lessee;
        l.lessee = newLessee;
        emit LesseeAssigned(leaseId, old, newLessee);
    }

    // ─── Anclaje a registro ERC-8325 ───────────────────────────

    function assetAnchor(uint256 leaseId) external view returns (uint256 chainId, address registry, bytes32 anchorId) {
        Lease storage l = _leases[leaseId];
        return (l.anchorChainId, l.anchorRegistry, l.anchorId);
    }

    // ─── Servicing (reporte paralelo, no enforcado) ────────────

    /// @dev IndexObservation se deriva de conversionRateAsOf (observedAt ==
    ///      reportedAt: el oraculo no distingue los dos momentos) y nunca
    ///      se atesta manualmente (ver DerivedInput en updateServicing).
    ///      Las demas categorias son atestaciones que el servicer
    ///      actualiza. Puro reporte: no participa de pay() ni del estado
    ///      del lease. Un input bytes32 nunca atestado y no derivado
    ///      devuelve (0,0,0) — informacion valida ("nunca se reporto"), no
    ///      un caso de error.
    function inputFreshness(uint256 leaseId, bytes32 input)
        external
        view
        returns (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness)
    {
        Lease storage l = _leases[leaseId];
        if (input == INPUT_INDEX_OBSERVATION) {
            (, uint64 asOf) = conversionRateAsOf(leaseId);
            return (asOf, asOf, l.maxOracleStaleness);
        }
        ServicingAttestation storage a = l.servicingAttestations[input];
        return (a.observedAt, a.reportedAt, l.maxStalenessByInput[input]);
    }

    function updateServicing(uint256 leaseId, bytes32 input, uint64 observedAt) external {
        Lease storage l = _leases[leaseId];
        if (input == INPUT_INDEX_OBSERVATION) revert DerivedInput();
        if (msg.sender != l.servicer) revert NotAuthorized();
        if (observedAt > block.timestamp) revert FutureObservation();

        uint64 reportedAt = uint64(block.timestamp);
        l.servicingAttestations[input] = ServicingAttestation({observedAt: observedAt, reportedAt: reportedAt});
        emit ServicingUpdated(leaseId, input, observedAt, reportedAt);
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
    /// @dev No necesita _computeState: `paid` depende solo de
    ///      settledUnits (que pay() muta directamente) y del cronograma
    ///      inmutable — ninguno de los dos lo toca el paso del tiempo,
    ///      así que ya es preciso en cualquier momento entre tx.
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

    /// @dev settledUnits solo lo muta pay() — el mero paso del tiempo
    ///      nunca lo toca, así que esta view ya es precisa en cualquier
    ///      momento entre tx sin necesitar _computeState.
    function outstandingUnits(uint256 id) public view returns (uint256) {
        Lease storage l = _leases[id];
        return l.scheduleTotalUnits - l.settledUnits;
    }

    function outstandingBalance(uint256 id) external view returns (uint256) {
        return convertToAssets(id, outstandingUnits(id));
    }

    /// @dev Frequency-independent por construccion (fix S3-01): función
    ///      pura de (cronograma, settledUnits, crystallizedPenaltyUnits,
    ///      penaltyPaidUnits, block.timestamp). Ningún poke (llamada sin
    ///      pago real) puede alterar ninguno de esos campos.
    function arrears(uint256 id) external view returns (uint256) {
        Lease storage l = _leases[id];
        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        return convertToAssets(id, principalArrears + _penaltyOwed(l, penaltyGrossNow));
    }

    /// @dev Próxima cuota del calendario cuya fecha de vencimiento AÚN NO
    ///      pasó (independiente de si hay mora en cuotas anteriores — la
    ///      mora se consulta vía arrears()/status()). Si el cronograma ya
    ///      está totalmente saldado (incluso si fue prepago antes de
    ///      vencer), no queda "próxima" que reportar: (0, 0).
    function nextPayment(uint256 id) external view returns (uint256 assets, uint64 dueDate) {
        Lease storage l = _leases[id];
        if (l.settledUnits >= l.scheduleTotalUnits) return (0, 0);
        (,, uint256 nextIdx, uint256 cumAtNextIdx) = _computeState(l);
        if (nextIdx >= l.dueDates.length) return (0, 0);
        uint256 unpaid = cumAtNextIdx > l.settledUnits ? cumAtNextIdx - l.settledUnits : 0;
        if (unpaid > l.unitAmounts[nextIdx]) unpaid = l.unitAmounts[nextIdx];
        return (convertToAssets(id, unpaid), l.dueDates[nextIdx]);
    }

    function status(uint256 id) external view returns (LeaseStatus) {
        return _statusView(_leases[id]);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IFinancialLease).interfaceId
            || interfaceId == type(IFinancialLeaseAnchored).interfaceId || super.supportsInterface(interfaceId);
    }
}
