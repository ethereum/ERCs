// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/**
 * @title IBNPL
 * @notice Standard interface for Buy Now Pay Later installment orders.
 *
 * @dev Flow overview:
 *
 *   1. At checkout the merchant presents an OrderAuthorization EIP-712
 *      struct to the customer's wallet. The customer signs it.
 *
 *   2. The merchant calls createOrder() providing order parameters,
 *      the customer's signature, and authData for the down payment.
 *      The contract verifies consent, consumes the nonce, and collects
 *      the down payment atomically.
 *
 *   3. Subsequent installments are collected via collectInstallment().
 *      Callable by the merchant, customer, or any authorized operator.
 *      Tokens always flow customer → merchant; operators never receive funds.
 *
 *   4. The customer may pay off the remaining balance early via payOffEarly().
 *
 *   5. If payment is not made within gracePeriod seconds of nextPaymentDue,
 *      the merchant or operator may call markDefaulted(). The OrderDefaulted
 *      event carries the outstanding balance for off-chain recovery.
 *
 * ERC-165 interface ID:
 *   IBNPL.createOrder.selector
 *   ^ IBNPL.collectInstallment.selector
 *   ^ IBNPL.payOffEarly.selector
 *   ^ IBNPL.markDefaulted.selector
 *   ^ IBNPL.cancelOrder.selector
 *   ^ IBNPL.getOrder.selector
 *   ^ IBNPL.getNextInstallment.selector
 *   ^ IBNPL.getSchedule.selector
 *   ^ IBNPL.getRemainingBalance.selector
 *   ^ IBNPL.isOrderPastDue.selector
 *   ^ IBNPL.authorizationNonce.selector
 */
interface IBNPL {

    // ============ Enums ============

    enum OrderStatus {
        Active,     // Order is open; installments are being collected
        Completed,  // All installments have been paid
        Defaulted,  // Customer failed to pay within the grace period
        Cancelled   // Order was cancelled before completion
    }

    // ============ Structs ============

    struct Order {
        address     customer;
        address     merchant;
        address     token;
        address     downPaymentAuthStrategy;
        address     installmentAuthStrategy;
        uint256     totalAmount;
        uint256     paidAmount;
        uint256     downPaymentBps;
        uint8       installments;
        uint8       paidInstallments;
        uint256     installmentPeriod;
        uint256     nextPaymentDue;
        uint256     gracePeriod;
        uint256     lateFeeBps;
        OrderStatus status;
    }

    // ============ Events ============

    event OrderCreated(
        bytes32 indexed orderId,
        address indexed customer,
        address indexed merchant,
        address  token,
        uint256  totalAmount,
        uint8    installments,
        uint256  downPayment,
        address  downPaymentAuthStrategy,
        address  installmentAuthStrategy
    );

    event InstallmentCollected(
        bytes32 indexed orderId,
        uint8   indexed installmentNumber,
        uint256 principal,
        uint256 lateFee,
        address collector
    );

    event OrderCompleted(bytes32 indexed orderId);

    event OrderDefaulted(
        bytes32 indexed orderId,
        uint256 outstandingAmount
    );

    event OrderCancelled(
        bytes32 indexed orderId,
        address cancelledBy,
        uint256 refundAmount
    );

    event AuthorizationNonceConsumed(
        address indexed customer,
        uint256 nonce
    );

    // ============ Core Functions ============

    function createOrder(
        address customer,
        address token,
        uint256 totalAmount,
        uint8   installments,
        uint256 downPaymentBps,
        uint256 installmentPeriod,
        uint256 gracePeriod,
        uint256 lateFeeBps,
        address downPaymentAuthStrategy,
        address installmentAuthStrategy,
        uint256 deadline,
        bytes   calldata customerSig,
        bytes   calldata downPaymentAuthData
    ) external returns (bytes32 orderId);

    function collectInstallment(
        bytes32 orderId,
        bytes calldata installmentAuthData
    ) external;

    function payOffEarly(
        bytes32 orderId,
        bytes calldata authData
    ) external;

    function markDefaulted(bytes32 orderId) external;

    function cancelOrder(bytes32 orderId) external;

    // ============ View Functions ============

    function getOrder(bytes32 orderId) external view returns (Order memory);

    function getNextInstallment(bytes32 orderId)
        external view returns (uint256 principal, uint256 lateFee);

    function getSchedule(bytes32 orderId)
        external view returns (uint256[] memory amounts, uint256[] memory dueDates);

    function getRemainingBalance(bytes32 orderId)
        external view returns (uint256);

    function isOrderPastDue(bytes32 orderId)
        external view returns (bool pastDue, bool pastGrace);

    function authorizationNonce(address customer)
        external view returns (uint256);
}
