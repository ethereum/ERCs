// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ISettlementDeductions — a deduction policy for a task escrow.
/// @notice An escrow that pays for work (a task market, a job escrow) names one deduction
///         policy for its whole lifetime. It tells the policy about each new task, so the
///         policy can lock per-task terms, and asks it before every payout how much of the
///         payment it takes. The escrow pays the payee the rest and credits the deducted
///         amount to the policy, which withdraws it per task (ISettlementCredit). The
///         escrow never calls a deduction's final recipient.
///
///         Escrow obligations (normative in the ERC text, summarised here):
///         - call `deductions` on every path that pays a payee, and on no refund path;
///         - call it with a fixed gas budget, and refuse to settle if the caller left less
///           than that budget (so the policy cannot be starved on purpose);
///         - if the call fails, or returns anything but one word no larger than `amount`,
///           settle with no deduction and say so; settlement never stalls on the policy;
///         - fix each payout's payee before the payout; the payout never takes it as input.
interface ISettlementDeductions {
    /// @notice Called by the escrow when a task is created. Reverting makes creation revert.
    /// @param amountPerSettlement Expected size of one payout, or zero if unknown.
    function onTaskCreated(uint256 taskId, address asset, uint256 amountPerSettlement) external;

    /// @notice Called by the escrow before every payout to `payee` on `taskId`.
    /// @dev Runs on the escrow's fixed gas budget: makes no external calls, and should
    ///      create no storage. Never answers more than `amount`.
    /// @return total The amount taken out of `amount`; the escrow pays `payee` the rest.
    function deductions(uint256 taskId, uint256 settlementId, address payee, uint256 amount)
        external returns (uint256 total);
}

/// @title  ISettlementCredit — the escrow side.
/// @notice The escrow holds what the policy takes as credit, per task, until withdrawn.
///         Only deductions add to the policy's credit, so the events account for every
///         unit deducted, from the payout to its withdrawal.
interface ISettlementCredit {
    /// Emitted on every payout of an escrow with a policy: `deducted` of `amount` is
    /// credited to the policy, and the payee is paid the rest. `deducted` is zero when nothing was taken or the answer was
    /// invalid.
    event PayoutSettled(uint256 indexed taskId, uint256 indexed settlementId,
                        address indexed payee, uint256 amount, uint256 deducted);
    /// Also emitted when the policy failed or answered invalidly and the payout was made in full.
    event DeductionsSkipped(uint256 indexed taskId, uint256 indexed settlementId);
    /// Emitted when the payee could not receive its payout and `amount` was credited to it.
    event PayoutCredited(uint256 indexed taskId, uint256 indexed settlementId,
                         address indexed payee, uint256 amount);
    /// Emitted when the credit of `account` on `taskId` is withdrawn.
    event PayoutWithdrawn(uint256 indexed taskId, address indexed account, uint256 amount);

    /// @notice The amount held for `account` on `taskId`.
    function creditOf(uint256 taskId, address account) external view returns (uint256);

    /// @notice Transfers the whole credit of `account` on `taskId` to `account`.
    ///         Callable by anyone; pays only `account`. May revert when there is none.
    function withdrawCredit(uint256 taskId, address account) external;

    /// @notice The policy this escrow names for its lifetime, or zero if it has none.
    function deductionPolicy() external view returns (address);

    /// @notice The fixed gas budget G with which the escrow calls the policy.
    function deductionGas() external view returns (uint256);
}
