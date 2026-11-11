// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ISettlementDeductions, ISettlementCredit} from "../interfaces/ISettlementDeductions.sol";

/// @title  ExampleEscrow — the smallest escrow that meets the settlement-deduction
///         obligations. Illustration only: the creator pays the task out, in one or
///         several payouts, and may refund what is left.
/// @notice What any escrow has to do to take a deduction policy:
///         1. name the policy for life and tell it about each new task;
///         2. on every payment, ask it with a fixed gas budget, after checking the caller
///            left that budget (no starving the policy into failure);
///         3. if it fails, answers with anything but one word, or answers more than the
///            payment, pay in full and say so;
///         4. credit what it takes to the policy and let the policy withdraw it;
///         5. never ask on a refund;
///         6. fix each payout's payee before the payout; a payout never takes it as input.
contract ExampleEscrow is ISettlementCredit {
    uint256 public constant DEDUCTION_GAS = 300_000;
    /// Gas for pushing native currency to a payee. A payee that refuses, or needs more,
    /// is credited instead (since EIP-7702 any address can refuse).
    uint256 public constant PUSH_GAS = 100_000;

    ISettlementDeductions public immutable policy; // zero = no deductions

    struct Task {
        address creator;
        address payee;     // fixed at creation: the creator cannot pay someone else instead
        address asset;
        uint256 remaining; // still escrowed
        uint256 payouts;   // payouts made so far; the next settlement id is payouts + 1
    }

    Task[] private _tasks;
    mapping(uint256 => mapping(address => uint256)) private _credit;

    event TaskCreated(uint256 indexed taskId, address indexed creator, address indexed payee,
                      address asset, uint256 amount);
    event Paid(uint256 indexed taskId, uint256 indexed settlementId, address indexed payee, uint256 amount);
    event Refunded(uint256 indexed taskId, uint256 amount);
    /// The payout could not be delivered; the payee withdraws it with `withdrawCredit`.
    event PayoutCredited(uint256 indexed taskId, uint256 indexed settlementId, address indexed payee, uint256 amount);

    constructor(ISettlementDeductions policy_) {
        // The policy's code must be in place, and must not be an EIP-7702 delegation: an
        // account whose code its key holder can set or change later would make "one
        // policy for life" meaningless.
        address p = address(policy_);
        require(p == address(0) || p.code.length != 0, "Escrow: policy without code");
        require(!_delegated(p), "Escrow: delegated policy");
        policy = policy_;
    }

    function _delegated(address a) private view returns (bool) {
        bytes memory c = a.code;
        return c.length == 23 && c[0] == 0xef && c[1] == 0x01 && c[2] == 0x00;
    }

    /// Escrows `amount` of `asset` for `payee`. The payee is fixed here, before any work, so
    /// that what the payee assigns to others cannot be skipped by paying another address.
    function createTask(address asset, uint256 amount, address payee) external payable returns (uint256 taskId) {
        require(amount > 0, "Escrow: zero amount");
        require(payee != address(0) && payee != address(this) && payee != address(policy), "Escrow: bad payee");
        if (asset == address(0)) {
            require(msg.value == amount, "Escrow: value");
        } else {
            require(msg.value == 0, "Escrow: value");
            (bool ok, bytes memory ret) =
                asset.call(abi.encodeCall(IERC20.transferFrom, (msg.sender, address(this), amount)));
            _checked(asset, ok, ret);
        }
        taskId = _tasks.length;
        _tasks.push(Task(msg.sender, payee, asset, amount, 0));
        if (address(policy) != address(0)) policy.onTaskCreated(taskId, asset, amount);
        emit TaskCreated(taskId, msg.sender, payee, asset, amount);
    }

    /// Pays the task's payee everything still escrowed.
    function pay(uint256 taskId) external {
        payPart(taskId, _tasks[taskId].remaining);
    }

    /// Pays the task's payee part of what is escrowed: one payout, one settlement id.
    function payPart(uint256 taskId, uint256 amount) public {
        Task storage t = _tasks[taskId];
        address payee = t.payee;
        require(msg.sender == t.creator, "Escrow: not creator");
        require(amount > 0 && amount <= t.remaining, "Escrow: bad amount");
        t.remaining -= amount;
        uint256 settlementId = ++t.payouts;
        uint256 net = amount - _deduct(taskId, settlementId, payee, amount);
        emit Paid(taskId, settlementId, payee, net);
        // A payee that refuses the transfer cannot block the payout, and so cannot push
        // the creator into a refund that skips the deductions: it is credited instead.
        if (net > 0 && !_trySend(t.asset, payee, net)) {
            _credit[taskId][payee] += net;
            emit PayoutCredited(taskId, settlementId, payee, net);
        }
    }

    /// Returns what is left to the creator. Never asks the policy.
    function refund(uint256 taskId) external {
        Task storage t = _tasks[taskId];
        require(msg.sender == t.creator, "Escrow: not creator");
        uint256 amount = t.remaining;
        require(amount > 0, "Escrow: nothing to refund");
        t.remaining = 0;
        emit Refunded(taskId, amount);
        _send(t.asset, t.creator, amount);
    }

    function _deduct(uint256 taskId, uint256 settlementId, address payee, uint256 amount)
        private returns (uint256 d)
    {
        if (address(policy) == address(0)) return 0;
        address p = address(policy);
        d = type(uint256).max; // anything but one word reads as invalid
        // Reading the code size also warms the policy's account before the gas check, so
        // the 10,000 margin covers the call whatever cold account access costs. A policy
        // without code could not answer anyway.
        if (p.code.length != 0) {
            require(gasleft() > DEDUCTION_GAS * 64 / 63 + 10_000, "Escrow: gas");
            bytes memory data =
                abi.encodeCall(ISettlementDeductions.deductions, (taskId, settlementId, payee, amount));
            assembly ("memory-safe") {
                // Copy at most 32 bytes back, so a policy cannot make the caller pay for
                // large return data.
                if call(DEDUCTION_GAS, p, 0, add(data, 32), mload(data), 0, 32) {
                    if eq(returndatasize(), 32) { d := mload(0) }
                }
            }
        }
        if (d > amount) {
            emit DeductionsSkipped(taskId, settlementId);
            return 0;
        }
        if (d > 0) {
            _credit[taskId][address(policy)] += d;
            emit SettlementDeducted(taskId, settlementId, address(policy), d);
        }
    }

    // --------------------------------------------------------- ISettlementCredit
    function creditOf(uint256 taskId, address account) external view returns (uint256) {
        return _credit[taskId][account];
    }

    function deductionPolicy() external view returns (address) {
        return address(policy);
    }

    function deductionGas() external pure returns (uint256) {
        return DEDUCTION_GAS;
    }

    /// ERC-165.
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == type(ISettlementCredit).interfaceId;
    }

    function withdrawCredit(uint256 taskId, address account) external {
        uint256 a = _credit[taskId][account];
        require(a > 0, "Escrow: nothing credited");
        _credit[taskId][account] = 0;
        _send(_tasks[taskId].asset, account, a);
    }

    function _send(address asset, address to, uint256 amount) private {
        if (amount == 0) return;
        if (asset == address(0)) {
            (bool ok, ) = payable(to).call{value: amount}("");
            require(ok, "Escrow: transfer failed");
        } else {
            (bool ok, bytes memory ret) = asset.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            _checked(asset, ok, ret);
        }
    }

    /// Like `_send`, but reports a failed transfer instead of reverting.
    function _trySend(address asset, address to, uint256 amount) private returns (bool ok) {
        if (asset == address(0)) {
            (ok, ) = payable(to).call{value: amount, gas: PUSH_GAS}("");
        } else {
            bytes memory ret;
            (ok, ret) = asset.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            ok = ok && (ret.length == 0 ? asset.code.length > 0 : ret.length >= 32 && abi.decode(ret, (uint256)) != 0);
        }
    }

    /// Accepts tokens that return true and tokens that return nothing. No return data is
    /// success only for a contract: a call to an address without code also returns nothing.
    function _checked(address asset, bool ok, bytes memory ret) private view {
        require(ok && (ret.length == 0 ? asset.code.length > 0 : ret.length >= 32 && abi.decode(ret, (uint256)) != 0),
                "Escrow: transfer failed");
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
