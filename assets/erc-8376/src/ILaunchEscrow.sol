// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {LaunchState} from "./LaunchAbuseTypes.sol";

/// @title Venue-held escrow of launch proceeds.
/// @notice Proceeds vest to the deployer on a schedule instead of settling at
///         purchase, so that funds remain reachable during the window in which
///         launch abuse typically occurs.
interface ILaunchEscrow {
    event LaunchRegistered(
        bytes32 indexed launchId,
        address indexed token,
        address indexed deployer,
        uint256 bond,
        uint64  releaseStart,
        uint64  releaseEnd
    );
    event PurchaseRecorded(bytes32 indexed launchId, address indexed buyer, uint256 paid, uint256 tokens);
    event SaleRecorded(bytes32 indexed launchId, address indexed buyer, uint256 realised);
    event ProceedsReleased(bytes32 indexed launchId, uint256 amount);
    event LaunchFrozen(bytes32 indexed launchId, bytes32 reportId, uint64 frozenUntil);
    event LaunchSettled(bytes32 indexed launchId);
    event RefundOpened(bytes32 indexed launchId, uint256 pool, uint256 totalNetPaid);
    event RefundClaimed(bytes32 indexed launchId, address indexed buyer, uint256 amount);
    event LinkedAddressExcluded(bytes32 indexed launchId, address indexed account, uint256 removed);
    event RefundSwept(bytes32 indexed launchId, address indexed to, uint256 amount);

    /// @notice Register a launch. The deployer MUST have posted `requiredBond`.
    /// @param asset settlement asset for both proceeds and bond, or address(0)
    ///        for native value. Venues that price in a project token cannot use
    ///        native settlement, so this MUST be supported.
    function registerLaunch(
        address token,
        address deployer,
        address asset,
        uint256 bondAmount,
        uint64  releaseStart,
        uint64  releaseEnd
    ) external payable returns (bytes32 launchId);

    /// @notice Convenience form for native settlement, passing `msg.value` as
    ///         the bond.
    function registerLaunchNative(
        address token,
        address deployer,
        uint64  releaseStart,
        uint64  releaseEnd
    ) external payable returns (bytes32 launchId);

    /// @notice Exclude a deployer-linked buyer from the refund pool.
    /// @dev The excluded address leaves the denominator as well as the payout,
    ///      so remaining buyers are restored to their proper share.
    function markLinked(bytes32 launchId, address account) external;

    /// @notice Record a purchase and deposit its proceeds. Caller MUST be the venue.
    /// @dev Payable, and `msg.value` MUST equal `paid`. Recording an amount the
    ///      escrow does not hold would make refunds unpayable.
    function recordPurchase(bytes32 launchId, address buyer, uint256 paid, uint256 tokens)
        external
        payable;

    /// @notice Record value a buyer realised by selling purchased tokens.
    /// @dev Required so `netContributionOf` can discount buyers who already
    ///      exited. Without it a profitable seller would draw on a pool shared
    ///      with buyers still holding.
    function recordSale(bytes32 launchId, address buyer, uint256 realised) external;

    /// @notice Amount paid less value already realised, floored at zero.
    function netContributionOf(bytes32 launchId, address buyer) external view returns (uint256);

    /// @notice Release the vested portion of proceeds to the deployer.
    function releaseProceeds(bytes32 launchId) external returns (uint256 amount);

    /// @notice Halt release pending adjudication.
    function freezeLaunch(bytes32 launchId, bytes32 reportId) external;

    /// @notice Buyer pulls their pro-rata share of an opened refund pool.
    function claimRefund(bytes32 launchId) external returns (uint256 amount);

    function stateOf(bytes32 launchId) external view returns (LaunchState);
    function escrowedProceeds(bytes32 launchId) external view returns (uint256);
    function maxFreezeDuration() external view returns (uint64);
}
