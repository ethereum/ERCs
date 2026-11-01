// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLease.sol
pragma solidity ^0.8.24;

// Base servicing-input identifiers, in a separate bytes32 domain
// (keccak256 of a namespaced string) instead of a closed enum. Declared
// at file level because Solidity interfaces cannot declare
// variables (not even `constant`): they live next to IFinancialLease so
// that the base set is part of the standard and does not fragment across
// deployments. Implementations may define their own inputs under their
// own namespace (e.g. keccak256("myorg.input.whatever")) without touching this
// interface.
bytes32 constant INPUT_INDEX_OBSERVATION = keccak256("erc8348.input.indexObservation");
bytes32 constant INPUT_COLLECTIONS = keccak256("erc8348.input.collections");
bytes32 constant INPUT_ARREARS_RECORD = keccak256("erc8348.input.arrearsRecord");
bytes32 constant INPUT_INSURANCE_STATUS = keccak256("erc8348.input.insuranceStatus");
bytes32 constant INPUT_ASSET_CONDITION = keccak256("erc8348.input.assetCondition");
bytes32 constant INPUT_RESIDUAL_APPRAISAL = keccak256("erc8348.input.residualAppraisal");

// Early-termination causes (fix S6-01), same separate bytes32 domain
// approach as the INPUT_* above. Only these two
// live in the core: they are bilateral contractual transitions or
// transitions triggered by breach, applicable to any financial
// lease regardless of jurisdiction or asset type. Other
// causes (e.g. total loss of the asset) are a fact about the asset,
// not a contractual transition — they are left to an extension with its own
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

    // ─── Input freshness (parallel reporting, not enforced) ─────
    // `input` is a bytes32 identifier (see the INPUT_* constants in this
    // file). The standard only EXPOSES observedAt/reportedAt/maxStaleness;
    // the consumer decides what to do with any divergence between them.
    // Recording a servicing attestation is an implementation-defined entry
    // point (FinancialLease.updateServicing in this implementation); the
    // standard constrains its effects, not its signature, so it is not part
    // of this interface or of its ERC-165 identifier.
    function inputFreshness(uint256 leaseId, bytes32 input)
        external
        view
        returns (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness);

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
    /// @dev Emitted alongside LeaseTerminated when a lease reaches Terminated,
    ///      carrying the domain-separated reason (TERMINATION_* or an
    ///      implementation-defined one).
    event TerminationRecorded(uint256 indexed leaseId, bytes32 indexed reason);
    event ServicingUpdated(uint256 indexed leaseId, bytes32 indexed input, uint64 observedAt, uint64 reportedAt);
}
