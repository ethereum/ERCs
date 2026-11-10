// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ISettlementDeductions, ISettlementCredit} from "./interfaces/ISettlementDeductions.sol";
import {ISettlementDeductionPolicy} from "./interfaces/ISettlementDeductionPolicy.sol";
import {ITaxSchedule} from "./interfaces/ITaxSchedule.sol";

/// @title  SettlementDeductionPolicy — reference policy: tax, referral fees, repayments.
/// @notice Divides each payout before the payee is paid:
///
///           payout 100
///            ├─ tax        (public schedule, locked at task creation) → treasury
///            ├─ fee        (payee's own assignment, a rate)           → referrer
///            ├─ repayment  (payee's own assignment, a sum)            → lender
///            └─ remainder                                             → payee
///
///         Two sources, two consents. The tax belongs to the escrow's deployment: its
///         schedule is fixed here for life and snapshotted per task, so every task on that
///         escrow carries it and nobody can create a task around it. Fees and
///         repayments belong to the payee: only the payee can assign part of its own
///         payouts on a task, and only the recipient can release an assignment, which is
///         what lets a lender advance money against a task already won.
///
///         All deductions together are capped at maxDeductionBps of the payout; a
///         repayment cut by the cap carries over to the payee's next payout on the task.
///
///         The escrow credits this policy one total per payout. The policy records each
///         recipient's share and pays it on claim, for each task only out of what has been
///         withdrawn from the escrow for that task (by this policy or by anyone else).
///         Assets that deliver less than the amount transferred are not supported.
contract SettlementDeductionPolicy is ISettlementDeductionPolicy {
    uint16 public constant BPS = 10_000;
    /// Bounds the work done at settlement, which runs on the escrow's fixed gas budget.
    uint256 public constant MAX_ASSIGNMENTS = 4;

    /// @inheritdoc ISettlementDeductionPolicy
    address public immutable escrow;
    /// @inheritdoc ISettlementDeductionPolicy
    ITaxSchedule public immutable taxSchedule;
    /// @inheritdoc ISettlementDeductionPolicy
    uint16 public immutable maxDeductionBps;

    struct Tax {
        address treasury;
        uint16 bps;
    }

    mapping(uint256 => Tax) private _tax;
    mapping(uint256 => address) private _asset; // payout asset, recorded at creation
    mapping(uint256 => mapping(address => Assignment[])) private _assignments;
    mapping(uint256 => mapping(address => uint256)) private _owed;
    mapping(uint256 => uint256) private _deducted; // total credited to this policy, per task
    mapping(uint256 => uint256) private _paid;     // total paid out on claims, per task
    bool private _claiming;

    modifier onlyEscrow() {
        require(msg.sender == escrow, "Deductions: not escrow");
        _;
    }

    constructor(address escrow_, ITaxSchedule schedule, uint16 maxDeductionBps_) {
        require(escrow_ != address(0), "Deductions: zero escrow");
        require(maxDeductionBps_ <= BPS, "Deductions: cap above 100%");
        escrow = escrow_;
        taxSchedule = schedule;
        maxDeductionBps = maxDeductionBps_;
    }

    // ------------------------------------------------------------------ views
    /// @inheritdoc ISettlementDeductionPolicy
    function lockedTaxOf(uint256 taskId) external view returns (address treasury, uint16 bps) {
        Tax memory t = _tax[taskId];
        return (t.treasury, t.bps);
    }

    /// @inheritdoc ISettlementDeductionPolicy
    function assignmentsOf(uint256 taskId, address payee) external view returns (Assignment[] memory) {
        return _assignments[taskId][payee];
    }

    /// @inheritdoc ISettlementDeductionPolicy
    function owedOf(uint256 taskId, address recipient) external view returns (uint256) {
        return _owed[taskId][recipient];
    }

    // ------------------------------------------------------------ assignments
    /// @inheritdoc ISettlementDeductionPolicy
    function assignPayment(uint256 taskId, address recipient, uint16 bps, uint256 amount) external {
        require(recipient != address(0) && recipient != msg.sender, "Deductions: bad recipient");
        require((bps == 0) != (amount == 0), "Deductions: rate xor amount");
        require(bps <= maxDeductionBps, "Deductions: rate above cap");
        Assignment[] storage list = _assignments[taskId][msg.sender];
        if (list.length == MAX_ASSIGNMENTS) _compact(list);
        require(list.length < MAX_ASSIGNMENTS, "Deductions: too many assignments");
        list.push(Assignment(recipient, bps, amount));
        emit PaymentAssigned(taskId, msg.sender, recipient, bps, amount);
    }

    /// @inheritdoc ISettlementDeductionPolicy
    function release(uint256 taskId, address payee) external {
        Assignment[] storage list = _assignments[taskId][payee];
        bool released;
        for (uint256 k = 0; k < list.length; k++) {
            Assignment storage a = list[k];
            if (a.recipient == msg.sender && (a.bps > 0 || a.remaining > 0)) {
                a.bps = 0;
                a.remaining = 0;
                released = true;
            }
        }
        require(released, "Deductions: nothing to release");
        emit PaymentReleased(taskId, payee, msg.sender);
    }

    /// Drops exhausted and released assignments, keeping the order of the rest.
    function _compact(Assignment[] storage list) private {
        uint256 n;
        for (uint256 k = 0; k < list.length; k++) {
            if (list[k].bps > 0 || list[k].remaining > 0) {
                if (n != k) list[n] = list[k];
                n++;
            }
        }
        while (list.length > n) list.pop();
    }

    // ------------------------------------------------------------------ claim
    /// @inheritdoc ISettlementDeductionPolicy
    function claim(uint256 taskId, address recipient) external {
        require(!_claiming, "Deductions: reentrant");
        _claiming = true;
        ISettlementCredit e = ISettlementCredit(escrow);
        if (e.creditOf(taskId, address(this)) > 0) e.withdrawCredit(taskId, address(this));
        uint256 amount = _owed[taskId][recipient];
        require(amount > 0, "Deductions: nothing owed");
        // What has left the escrow for this task, whoever triggered the withdrawal.
        uint256 credit = e.creditOf(taskId, address(this));
        uint256 received = credit < _deducted[taskId] ? _deducted[taskId] - credit : 0;
        require(_paid[taskId] + amount <= received, "Deductions: not received");
        _paid[taskId] += amount;
        _owed[taskId][recipient] = 0;
        emit Claimed(taskId, recipient, amount);
        _send(_asset[taskId], recipient, amount);
        _claiming = false;
    }

    /// Native-currency credit arrives here through the escrow's withdrawal.
    receive() external payable {}

    function _send(address asset, address to, uint256 amount) private {
        bool ok;
        if (asset == address(0)) {
            (ok, ) = payable(to).call{value: amount}("");
        } else {
            bytes memory ret;
            (ok, ret) = asset.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
            ok = ok && (ret.length == 0 || (ret.length >= 32 && abi.decode(ret, (uint256)) != 0));
        }
        require(ok, "Deductions: transfer failed");
    }

    // ------------------------------------------------------------------ hooks
    /// @inheritdoc ISettlementDeductions
    function onTaskCreated(uint256 taskId, address asset, uint256) external onlyEscrow {
        _asset[taskId] = asset;
        if (address(taxSchedule) == address(0)) return;
        (address treasury, uint16 bps) = taxSchedule.taxOf(asset);
        if (bps == 0) return;
        require(treasury != address(0), "Deductions: tax to zero");
        require(bps <= maxDeductionBps, "Deductions: tax above cap");
        _tax[taskId] = Tax(treasury, bps);
        emit TaxLocked(taskId, treasury, bps);
    }

    /// @inheritdoc ISettlementDeductions
    /// @dev Tax first, then the payee's assignments in the order made, all within one
    ///      budget of maxDeductionBps. Makes no external calls.
    function deductions(uint256 taskId, uint256 settlementId, address payee, uint256 amount)
        external onlyEscrow returns (uint256 total)
    {
        uint256 budget = amount * maxDeductionBps / BPS;
        Tax memory tax = _tax[taskId];
        if (tax.bps > 0) {
            uint256 a = amount * tax.bps / BPS; // <= budget: tax.bps <= cap at creation
            budget -= a;
            total += _record(taskId, settlementId, tax.treasury, a);
        }
        Assignment[] storage list = _assignments[taskId][payee];
        for (uint256 k = 0; k < list.length; k++) {
            Assignment storage as_ = list[k];
            uint256 want = as_.bps > 0 ? amount * as_.bps / BPS : as_.remaining;
            uint256 take = want > budget ? budget : want;
            if (as_.bps == 0) as_.remaining -= take;
            budget -= take;
            total += _record(taskId, settlementId, as_.recipient, take);
        }
        _deducted[taskId] += total;
    }

    function _record(uint256 taskId, uint256 settlementId, address to, uint256 amount)
        private returns (uint256)
    {
        if (amount == 0) return 0;
        _owed[taskId][to] += amount;
        emit Deducted(taskId, settlementId, to, amount);
        return amount;
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}
