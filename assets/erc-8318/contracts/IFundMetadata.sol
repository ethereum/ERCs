// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ERC-8318: Tokenized fund lifecycle metadata
/// @notice Interfaces, enums, structs and events exactly as specified in ERC-8318.
/// @dev This file must stay byte-for-byte aligned with the Solidity blocks in
/// `ERCS/erc-8318.md`. Interface names do not affect ERC-165 identifiers; only
/// function names and parameter types do.

/*//////////////////////////////////////////////////////////////
                         ENUMS AND STRUCTS
//////////////////////////////////////////////////////////////*/

/// @notice Lifecycle states of a tokenized fund.
/// @dev Paused is modelled as a distinct state rather than an orthogonal flag so
/// that integrators can read a single field to decide whether to act.
/// Implementations MUST record the previous state when entering Paused and MUST
/// exit Paused only to that previous state or to a legal successor of it.
enum LifecycleState {
    Pending,
    SubscriptionOpen,
    SubscriptionClosed,
    Operating,
    RedemptionOnly,
    WindingDown,
    Closed,
    Paused
}

enum DistributionType {
    Dividend,
    Coupon,
    ReturnOfCapital,
    Other
}

enum DistributionStatus {
    Declared,
    ExDate,
    Paid,
    Cancelled
}

struct DistributionInfo {
    uint256 id;
    uint256 declaredAt;
    uint256 exDate;
    uint256 recordDate;
    uint256 paymentDate;
    uint256 amountPerShare;
    uint8 amountDecimals;
    bytes3 currency;
    DistributionType distributionType;
    DistributionStatus status;
}

struct ShareClassInfo {
    bytes32 id;
    string name;
    string symbol;
    uint256 minInvestment;
    uint8 minInvestmentDecimals;
    bytes eligibility;
}

struct AttestationInfo {
    bytes32 attestationHash;
    string attestationURI;
    uint256 attestedAt;
    address[] attestors;
    uint16 reservesToSupplyBps;
    string methodologyURI;
}

/*//////////////////////////////////////////////////////////////
                          CORE INTERFACE
//////////////////////////////////////////////////////////////*/

interface IFundMetadata is IERC165 {
    /* ----------------------------- NAV reads ----------------------------- */

    /// @notice Current NAV per share of the default share class.
    /// @return nav NAV per share, scaled by `navDecimals`.
    /// @return navDecimals Decimal precision of `nav`.
    /// @dev MUST NOT revert. MUST return the last known value even when stale.
    function navPerShare() external view returns (uint256 nav, uint8 navDecimals);

    /// @notice NAV per share at or immediately before `timestamp`, default class.
    /// @dev MAY revert with a clear reason if historical NAV is not stored.
    function navAsOf(uint256 timestamp) external view returns (uint256 nav, uint8 navDecimals);

    /// @notice Unix timestamp at which the current NAV was last set.
    function navUpdatedAt() external view returns (uint256 timestamp);

    /// @notice True if the current NAV is older than `navStalenessThreshold()`.
    function navStale() external view returns (bool);

    /// @notice Maximum age in seconds before NAV is considered stale.
    function navStalenessThreshold() external view returns (uint256);

    /// @notice ISO 4217 alpha-3 valuation currency code, e.g. 0x555344 for USD.
    function valuationCurrency() external view returns (bytes3);

    /* -------------------------- Lifecycle state -------------------------- */

    function lifecycleState() external view returns (LifecycleState);
    function lifecycleStateUpdatedAt() external view returns (uint256);

    /* --------------------- Corporate actions / distributions ------------- */

    /// @notice Total number of distributions known to the implementation.
    /// @dev Distribution IDs SHOULD start at 1. ID 0 SHOULD indicate "none".
    function distributionCount() external view returns (uint256);

    /// @notice Distribution details by ID.
    /// @dev MAY revert if `id` is unknown.
    function distributionById(uint256 id) external view returns (DistributionInfo memory);

    /// @notice Pending distribution IDs. SHOULD be bounded to currently pending items.
    function pendingDistributionIds() external view returns (uint256[] memory);

    /// @notice Most recent paid distribution ID, or 0 if none has been paid.
    function lastDistributionId() external view returns (uint256);

    /// @notice Next scheduled distribution date, or 0 if not known or not applicable.
    function nextDistributionDate() external view returns (uint256);

    /* ---------------------------- Fund params ---------------------------- */

    function managementFeeBps() external view returns (uint16);
    function performanceFeeBps() external view returns (uint16);
    function subscriptionFeeBps() external view returns (uint16);
    function redemptionFeeBps() external view returns (uint16);
    function minInvestment() external view returns (uint256 amount, uint8 decimals);
    function subscriptionWindow() external view returns (uint256 opensAt, uint256 closesAt);
    function redemptionWindow() external view returns (uint256 opensAt, uint256 closesAt);
    function maturityDate() external view returns (uint256);

    /* --------------------------- Required events -------------------------- */

    event NavUpdated(uint256 previousNav, uint256 newNav, uint8 navDecimals, uint256 effectiveAt);

    event LifecycleStateChanged(
        LifecycleState indexed previousState, LifecycleState indexed newState, uint256 timestamp
    );

    event DistributionDeclared(
        uint256 indexed id,
        DistributionType indexed distributionType,
        uint256 exDate,
        uint256 recordDate,
        uint256 paymentDate,
        uint256 amountPerShare,
        uint8 amountDecimals,
        bytes3 currency
    );

    event DistributionPaid(
        uint256 indexed id, uint256 totalAmount, uint8 amountDecimals, bytes3 currency, uint256 paidAt
    );

    event DistributionCancelled(uint256 indexed id, string reason);
}

/*//////////////////////////////////////////////////////////////
                        OPTIONAL EXTENSIONS
//////////////////////////////////////////////////////////////*/

interface IFundMetadataAUM is IFundMetadata {
    function aum() external view returns (uint256 amount, uint8 decimals);
    function aumUpdatedAt() external view returns (uint256 timestamp);

    event AUMUpdated(uint256 previousAum, uint256 newAum, uint8 decimals, uint256 effectiveAt);
}

interface IFundMetadataLockup is IFundMetadata {
    function lockupExpires(address account) external view returns (uint256);
}

interface IFundMetadataYield is IFundMetadata {
    function accruedYield(address account) external view returns (uint256);
}

interface IFundMetadataMultiClass is IFundMetadata {
    function shareClasses() external view returns (bytes32[] memory);
    function defaultShareClass() external view returns (bytes32);
    function shareClassInfo(bytes32 shareClassId) external view returns (ShareClassInfo memory);

    function navPerShare(bytes32 shareClassId) external view returns (uint256 nav, uint8 navDecimals);
    function navAsOf(bytes32 shareClassId, uint256 timestamp) external view returns (uint256 nav, uint8 navDecimals);
    function navUpdatedAt(bytes32 shareClassId) external view returns (uint256 timestamp);
    function navStale(bytes32 shareClassId) external view returns (bool);
    function valuationCurrency(bytes32 shareClassId) external view returns (bytes3);
    function lifecycleState(bytes32 shareClassId) external view returns (LifecycleState);
    function lifecycleStateUpdatedAt(bytes32 shareClassId) external view returns (uint256);
    function distributionCount(bytes32 shareClassId) external view returns (uint256);
    function distributionById(bytes32 shareClassId, uint256 id) external view returns (DistributionInfo memory);
    function pendingDistributionIds(bytes32 shareClassId) external view returns (uint256[] memory);
    function lastDistributionId(bytes32 shareClassId) external view returns (uint256);
    function nextDistributionDate(bytes32 shareClassId) external view returns (uint256);
    function managementFeeBps(bytes32 shareClassId) external view returns (uint16);
    function performanceFeeBps(bytes32 shareClassId) external view returns (uint16);
    function subscriptionFeeBps(bytes32 shareClassId) external view returns (uint16);
    function redemptionFeeBps(bytes32 shareClassId) external view returns (uint16);
    function minInvestment(bytes32 shareClassId) external view returns (uint256 amount, uint8 decimals);
    function subscriptionWindow(bytes32 shareClassId) external view returns (uint256 opensAt, uint256 closesAt);
    function redemptionWindow(bytes32 shareClassId) external view returns (uint256 opensAt, uint256 closesAt);
    function maturityDate(bytes32 shareClassId) external view returns (uint256);

    event ShareClassAdded(bytes32 indexed id, string name, string symbol);

    event ClassNavUpdated(
        bytes32 indexed shareClassId, uint256 previousNav, uint256 newNav, uint8 navDecimals, uint256 effectiveAt
    );

    event ClassLifecycleStateChanged(
        bytes32 indexed shareClassId,
        LifecycleState indexed previousState,
        LifecycleState indexed newState,
        uint256 timestamp
    );

    event ClassDistributionDeclared(
        bytes32 indexed shareClassId,
        uint256 indexed id,
        DistributionType indexed distributionType,
        uint256 exDate,
        uint256 recordDate,
        uint256 paymentDate,
        uint256 amountPerShare,
        uint8 amountDecimals,
        bytes3 currency
    );

    event ClassDistributionPaid(
        bytes32 indexed shareClassId,
        uint256 indexed id,
        uint256 totalAmount,
        uint8 amountDecimals,
        bytes3 currency,
        uint256 paidAt
    );

    event ClassDistributionCancelled(bytes32 indexed shareClassId, uint256 indexed id, string reason);
}

interface IFundMetadataProofOfReserves is IFundMetadata {
    function latestAttestation() external view returns (AttestationInfo memory);
    function attestationHistory(uint256 fromTimestamp) external view returns (AttestationInfo[] memory);

    event AttestationPublished(
        bytes32 indexed attestationHash, uint256 attestedAt, uint16 reservesToSupplyBps, string attestationURI
    );
}
