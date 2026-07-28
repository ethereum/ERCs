// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLease.sol
pragma solidity ^0.8.24;

// Identificadores base de servicing input, en un dominio bytes32 separado
// (keccak256 de un string namespaced) en vez de un enum cerrado. Declarados
// a nivel de archivo porque las interfaces de Solidity no pueden declarar
// variables (ni siquiera `constant`): viven junto a IFinancialLease para
// que el conjunto base sea parte del estándar y no se fragmente entre
// deployments. Implementaciones pueden definir inputs propios con su
// propio namespace (ej. keccak256("miorg.input.loQueSea")) sin tocar esta
// interfaz.
bytes32 constant INPUT_INDEX_OBSERVATION = keccak256("erc8348.input.indexObservation");
bytes32 constant INPUT_COLLECTIONS = keccak256("erc8348.input.collections");
bytes32 constant INPUT_ARREARS_RECORD = keccak256("erc8348.input.arrearsRecord");
bytes32 constant INPUT_INSURANCE_STATUS = keccak256("erc8348.input.insuranceStatus");
bytes32 constant INPUT_ASSET_CONDITION = keccak256("erc8348.input.assetCondition");
bytes32 constant INPUT_RESIDUAL_APPRAISAL = keccak256("erc8348.input.residualAppraisal");

// Causales de terminación anticipada (fix S6-01), mismo criterio de
// dominio bytes32 separado que los INPUT_* de arriba. Solo estas dos
// viven en el núcleo: son transiciones contractuales bilaterales o
// gatilladas por incumplimiento, aplicables a cualquier leasing
// financiero sin importar la jurisdicción o el tipo de activo. Otras
// causales (ej. pérdida total del bien) son un hecho sobre el activo,
// no una transición contractual — quedan a extensión con su propio
// namespace.
bytes32 constant TERMINATION_MUTUAL_AGREEMENT = keccak256("erc8348.termination.mutualAgreement");
bytes32 constant TERMINATION_DEFAULT = keccak256("erc8348.termination.default");

/// @notice Core interface of ERC-8348 (Financial Lease). Implementations
///         MUST also implement ERC-165 and ERC-721 with tokenId == leaseId.
interface IFinancialLease {
    enum LeaseStatus {
        Active,
        InArrears,
        InDefault,
        Terminated,
        Completed,
        PurchaseExercised
    }

    // ─── Legal layer ────────────────────────────────────────────
    function jurisdiction(uint256 leaseId) external view returns (bytes2);
    function governingLaw(uint256 leaseId) external view returns (string memory);
    function agreementHash(uint256 leaseId) external view returns (bytes32);
    function assetReference(uint256 leaseId) external view returns (string memory);

    // ─── Parties ────────────────────────────────────────────────
    function lessor(uint256 leaseId) external view returns (address);
    function lessee(uint256 leaseId) external view returns (address);

    // ─── Denomination and conversion ───────────────────────────
    function paymentAsset(uint256 leaseId) external view returns (address);
    function denomination(uint256 leaseId) external view returns (string memory symbol, address oracle);
    function convertToAssets(uint256 leaseId, uint256 units) external view returns (uint256 assets);
    function convertToUnits(uint256 leaseId, uint256 assets) external view returns (uint256 units);
    function conversionRateAsOf(uint256 leaseId) external view returns (uint256 rate, uint64 asOf);

    // ─── Schedule (immutable, in units) ────────────────────────
    function paymentCount(uint256 leaseId) external view returns (uint256);
    function paymentAt(uint256 leaseId, uint256 index) external view returns (uint256 units, uint64 dueDate, bool paid);

    // ─── Live economics ─────────────────────────────────────────
    function outstandingUnits(uint256 leaseId) external view returns (uint256);
    function outstandingBalance(uint256 leaseId) external view returns (uint256);
    function nextPayment(uint256 leaseId) external view returns (uint256 assets, uint64 dueDate);
    function arrears(uint256 leaseId) external view returns (uint256);
    function status(uint256 leaseId) external view returns (LeaseStatus);

    // ─── Servicing (reporte paralelo, no enforcado) ─────────────
    // `input` es un identificador bytes32 (ver constantes INPUT_* de este
    // archivo). El estándar solo EXPONE observedAt/reportedAt/maxStaleness;
    // el consumidor decide qué hacer con la divergencia entre ambos.
    function inputFreshness(uint256 leaseId, bytes32 input)
        external
        view
        returns (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness);
    function updateServicing(uint256 leaseId, bytes32 input, uint64 observedAt) external;

    // ─── Actions ────────────────────────────────────────────────
    function pay(uint256 leaseId, uint256 assets) external;
    function purchaseOption(uint256 leaseId) external view returns (uint256 priceInAssets, bool exercisable);
    function exercisePurchaseOption(uint256 leaseId) external;

    // ─── Events ─────────────────────────────────────────────────
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
    event ServicingUpdated(uint256 indexed leaseId, bytes32 indexed input, uint64 observedAt, uint64 reportedAt);
}
