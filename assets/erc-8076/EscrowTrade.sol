// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEscrowTrade} from "./IEscrowTrade.sol";

/// @notice ERC-8076 reference implementation for ERC-20 tokens with exact transfers and stable balances.
contract EscrowTrade is IEscrowTrade, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        None,
        Open,
        Completed,
        Cancelled
    }

    struct Order {
        address payer;
        address recipient;
        IERC20 tokenFrom;
        IERC20 tokenTo;
        uint256 amountFrom;
        uint256 amountTo;
        uint256 deadline;
        Status status;
    }

    mapping(bytes32 => Order) private _orders;
    uint256 private _lastOrderId;

    error InvalidOrderParameters();
    error OrderNotOpen(bytes32 orderId);
    error OrderExpired(bytes32 orderId);
    error OrderNotExpired(bytes32 orderId);
    error UnauthorizedPayer(bytes32 orderId);
    error RecipientCannotFill(bytes32 orderId);
    error InexactTransfer(address token, address from, address to, uint256 amount);

    /// @inheritdoc IEscrowTrade
    function createOrder(
        address to,
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        uint256 deadline
    ) external override nonReentrant returns (bytes32 orderId) {
        if (
            to == address(0) || to == address(this) || tokenFrom == tokenTo || tokenFrom.code.length == 0
                || tokenTo.code.length == 0 || amountFrom == 0 || amountTo == 0 || deadline <= block.timestamp
        ) revert InvalidOrderParameters();

        orderId = bytes32(++_lastOrderId);
        _orders[orderId] = Order({
            payer: msg.sender,
            recipient: to,
            tokenFrom: IERC20(tokenFrom),
            tokenTo: IERC20(tokenTo),
            amountFrom: amountFrom,
            amountTo: amountTo,
            deadline: deadline,
            status: Status.Open
        });

        _transferExact(IERC20(tokenFrom), msg.sender, address(this), amountFrom);
        emit OrderCreated(orderId, msg.sender, to, tokenFrom, tokenTo, amountFrom, amountTo, deadline);
    }

    /// @inheritdoc IEscrowTrade
    function completeOrder(bytes32 orderId) external override nonReentrant {
        Order storage order = _orders[orderId];
        if (order.status != Status.Open) revert OrderNotOpen(orderId);
        if (block.timestamp > order.deadline) revert OrderExpired(orderId);
        if (msg.sender == order.recipient) revert RecipientCannotFill(orderId);

        order.status = Status.Completed;
        _transferExact(order.tokenTo, msg.sender, order.recipient, order.amountTo);
        _transferExact(order.tokenFrom, address(this), msg.sender, order.amountFrom);
        emit OrderCompleted(orderId);
    }

    /// @inheritdoc IEscrowTrade
    function cancelOrder(bytes32 orderId) external override nonReentrant {
        Order storage order = _orders[orderId];
        if (order.status != Status.Open) revert OrderNotOpen(orderId);
        if (msg.sender != order.payer) revert UnauthorizedPayer(orderId);
        if (block.timestamp <= order.deadline) revert OrderNotExpired(orderId);

        order.status = Status.Cancelled;
        _transferExact(order.tokenFrom, address(this), order.payer, order.amountFrom);
        emit OrderCancelled(orderId);
    }

    function _transferExact(IERC20 token, address from, address to, uint256 amount) private {
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        if (from == address(this)) {
            token.safeTransfer(to, amount);
        } else {
            token.safeTransferFrom(from, to, amount);
        }

        uint256 fromAfter = token.balanceOf(from);
        uint256 toAfter = token.balanceOf(to);
        if (fromAfter > fromBefore || toAfter < toBefore || fromBefore - fromAfter != amount || toAfter - toBefore != amount) {
            revert InexactTransfer(address(token), from, to, amount);
        }
    }
}
