// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLease.sol
pragma solidity ^0.8.24;

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
}
