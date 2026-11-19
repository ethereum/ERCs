// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ISettlementDeductions} from "./ISettlementDeductions.sol";
import {ITaxSchedule} from "./ITaxSchedule.sol";

/// @title  ISettlementDeductionPolicy — the optional reference-policy profile.
/// @notice A deduction policy with a public tax schedule locked per task, payee-made
///         assignments (fees as a rate, repayments as a fixed sum) that only their
///         recipient can release, one cap on all deductions together, and permissionless
///         claims.
interface ISettlementDeductionPolicy is ISettlementDeductions {
    /// Either a rate (`bps` > 0, applied to every payout) or a fixed sum (`remaining` > 0,
    /// repaid across payouts until exhausted). Both zero once exhausted or released.
    struct Assignment {
        address recipient;
        uint16 bps;
        uint256 remaining;
    }

    event TaxLocked(uint256 indexed taskId, address indexed treasury, uint16 bps);
    event PaymentAssigned(uint256 indexed taskId, address indexed payee,
                          address indexed recipient, uint16 bps, uint256 amount);
    event PaymentReleased(uint256 indexed taskId, address indexed payee, address indexed recipient);
    event Deducted(uint256 indexed taskId, uint256 indexed settlementId,
                   address indexed recipient, uint256 amount);
    event Claimed(uint256 indexed taskId, address indexed recipient, uint256 amount);

    /// @notice The only address allowed to call the hooks.
    function escrow() external view returns (address);

    /// @notice The schedule read at task creation; zero for no tax.
    function taxSchedule() external view returns (ITaxSchedule);

    /// @notice Cap on all deductions from one payout, in basis points.
    function maxDeductionBps() external view returns (uint16);

    /// @notice The tax locked for `taskId` at its creation.
    function lockedTaxOf(uint256 taskId) external view returns (address treasury, uint16 bps);

    /// @notice The payee's assignments on `taskId`, in the order they are served.
    function assignmentsOf(uint256 taskId, address payee) external view returns (Assignment[] memory);

    /// @notice Assign part of the caller's payouts on `taskId` to `recipient`: a share of
    ///         every payout (`bps`) or a fixed sum (`amount`). Exactly one is nonzero.
    ///         The payee cannot revoke or reduce it.
    function assignPayment(uint256 taskId, address recipient, uint16 bps, uint256 amount) external;

    /// @notice Release every assignment to the caller on `payee`'s payouts on `taskId`.
    ///         Only the recipient can release.
    function release(uint256 taskId, address payee) external;

    /// @notice Deducted for `recipient` on `taskId` and not yet claimed.
    function owedOf(uint256 taskId, address recipient) external view returns (uint256);

    /// @notice Pay `recipient` what it is owed on `taskId`. Callable by anyone.
    function claim(uint256 taskId, address recipient) external;
}
