// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBNPL} from "./interfaces/IBNPL.sol";
import {IPaymentAuth} from "./interfaces/IPaymentAuth.sol";
import {IOperatorManager} from "./interfaces/IOperatorManager.sol";

/**
 * @title BNPLManager
 * @notice Reference implementation of IBNPL and IOperatorManager.
 *
 * @dev Implements the full IBNPL state machine with:
 *   - EIP-712 customer consent verification (EIP-1271 smart wallet support)
 *   - Pluggable split authorization strategies for down payment and installments
 *   - Per-merchant operator authorization
 *   - Spec-faithful checks-effects-interactions ordering throughout
 *   - mulDiv for overflow-safe basis point calculations
 *
 * Refund policy (RECOMMENDED behavior per spec):
 *   - Customer-initiated cancellation: down payment forfeit; any collected
 *     installments beyond the down payment are refunded.
 *   - Merchant-initiated cancellation: all collected amounts refunded.
 */
contract BNPLManager is IBNPL, IOperatorManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ ERC-165 interface ID ============

    bytes4 public constant IBNPL_INTERFACE_ID =
        IBNPL.createOrder.selector
        ^ IBNPL.collectInstallment.selector
        ^ IBNPL.payOffEarly.selector
        ^ IBNPL.markDefaulted.selector
        ^ IBNPL.cancelOrder.selector
        ^ IBNPL.getOrder.selector
        ^ IBNPL.getNextInstallment.selector
        ^ IBNPL.getSchedule.selector
        ^ IBNPL.getRemainingBalance.selector
        ^ IBNPL.isOrderPastDue.selector
        ^ IBNPL.authorizationNonce.selector;

    // ============ EIP-712 constants ============

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /// @dev keccak256("OrderAuthorization(address merchant,address token,uint256 totalAmount,uint8 installments,uint256 downPaymentBps,uint256 installmentPeriod,uint256 gracePeriod,uint256 lateFeeBps,address downPaymentAuthStrategy,address installmentAuthStrategy,uint256 nonce,uint256 deadline)")
    bytes32 private constant ORDER_AUTHORIZATION_TYPEHASH =
        0x68c5443e5040df5f1ed96a455ea7294876fb94e43e188f9c3a81b67c21a9be41;

    // ============ Storage ============

    /// @notice All orders keyed by orderId.
    mapping(bytes32 => Order) private _orders;

    /// @notice Per-customer authorization nonce.
    mapping(address => uint256) private _nonces;

    /// @notice Operator authorization: merchant => operator => authorized.
    mapping(address => mapping(address => bool)) private _operators;

    /// @notice Records the creation timestamp of each order for getSchedule.
    /// @dev Needed to reconstruct due dates off the stored installmentPeriod.
    mapping(bytes32 => uint256) private _orderCreatedAt;

    // ============ Constructor ============

    constructor() {}

    // ============ Domain separator ============

    /**
     * @notice Computes the EIP-712 domain separator.
     * @dev Recomputed on each call — NOT cached — so it correctly handles
     *      chain forks and is always consistent with block.chainid.
     */
    function _domainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("BNPL")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

    // ============ Internal helpers ============

    /**
     * @notice Compute the installment amount for a given installment index.
     * @dev Dust (remainder from integer division) is added to the FINAL
     *      installment only. Index is 0-based.
     */
    function _installmentAmount(
        uint256 totalAmount,
        uint256 downPaymentBps,
        uint8   installments,
        uint8   installmentIndex    // 0-based; final installment = installments - 1
    ) private pure returns (uint256 amount) {
        uint256 downPayment  = Math.mulDiv(totalAmount, downPaymentBps, 10000);
        uint256 remaining    = totalAmount - downPayment;
        uint256 baseAmount   = remaining / installments;
        uint256 dust         = remaining % installments;

        // Dust is applied to the last installment (index = installments - 1)
        bool isFinal = (installmentIndex == installments - 1);
        amount = isFinal ? baseAmount + dust : baseAmount;
    }

    /**
     * @notice Verify an EIP-712 customer signature (ECDSA or EIP-1271).
     */
    function _verifyCustomerSig(
        address customer,
        bytes32 digest,
        bytes calldata sig
    ) private view {
        if (customer.code.length > 0) {
            // EIP-1271 — smart contract wallet
            (bool ok, bytes memory result) = customer.staticcall(
                abi.encodeWithSignature(
                    "isValidSignature(bytes32,bytes)",
                    digest,
                    sig
                )
            );
            require(
                ok &&
                result.length >= 32 &&
                abi.decode(result, (bytes4)) == bytes4(0x1626ba7e),
                "BNPL: invalid contract signature"
            );
        } else {
            // ECDSA — EOA wallet
            address recovered = ECDSA.recover(digest, sig);
            require(recovered == customer, "BNPL: invalid signature");
        }
    }

    /**
     * @notice Check whether caller is authorized to trigger collection for an order.
     */
    function _isAuthorizedCollector(bytes32 orderId) private view returns (bool) {
        Order storage o = _orders[orderId];
        return (
            msg.sender == o.customer ||
            msg.sender == o.merchant ||
            _operators[o.merchant][msg.sender]
        );
    }

    // ============ IBNPL — createOrder ============

    /**
     * @inheritdoc IBNPL
     *
     * @dev Execution order per spec:
     *   Step 1: Validate parameters
     *   Step 2: Validate auth strategy addresses via ERC-165
     *   Step 3: Verify customer EIP-712 consent signature
     *   Step 4: Effects — consume nonce, store order
     *   Step 5: Interaction — collect down payment
     *   Step 6: Emit OrderCreated
     */
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
    ) external override nonReentrant returns (bytes32 orderId) {

        // ---- Step 1: Parameter validation ----
        require(installments >= 2 && installments <= 12,
            "BNPL: installments out of range [2,12]");
        require(downPaymentBps >= 1000 && downPaymentBps <= 5000,
            "BNPL: downPaymentBps out of range [1000,5000]");
        require(lateFeeBps <= 1500,
            "BNPL: lateFeeBps exceeds max 1500");
        require(gracePeriod <= 2592000,
            "BNPL: gracePeriod exceeds max 30 days");
        require(totalAmount > 0,
            "BNPL: totalAmount must be non-zero");
        require(block.timestamp <= deadline,
            "BNPL: authorization expired");
        require(customer != address(0),
            "BNPL: zero customer address");

        // ---- Step 2: ERC-165 strategy validation ----
        require(
            _supportsPaymentAuth(downPaymentAuthStrategy),
            "BNPL: downPaymentAuthStrategy does not implement IPaymentAuth"
        );
        require(
            _supportsPaymentAuth(installmentAuthStrategy),
            "BNPL: installmentAuthStrategy does not implement IPaymentAuth"
        );

        // ---- Step 3: Verify customer EIP-712 consent ----
        uint256 currentNonce = _nonces[customer];
        bytes32 structHash = keccak256(abi.encode(
            ORDER_AUTHORIZATION_TYPEHASH,
            msg.sender,         // merchant = caller
            token,
            totalAmount,
            installments,
            downPaymentBps,
            installmentPeriod,
            gracePeriod,
            lateFeeBps,
            downPaymentAuthStrategy,
            installmentAuthStrategy,
            currentNonce,
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            _domainSeparator(),
            structHash
        ));
        _verifyCustomerSig(customer, digest, customerSig);

        // ---- Step 4: Effects ----
        // Derive orderId — complete fingerprint of order terms
        orderId = keccak256(abi.encode(
            customer,
            msg.sender,     // merchant
            token,
            totalAmount,
            installments,
            downPaymentBps,
            installmentPeriod,
            block.timestamp,
            currentNonce
        ));

        // Consume nonce atomically with order creation
        _nonces[customer] = currentNonce + 1;
        emit AuthorizationNonceConsumed(customer, currentNonce);

        // Store order — paidAmount set to 0 here, updated after pullPayment
        _orders[orderId] = Order({
            customer:                  customer,
            merchant:                  msg.sender,
            token:                     token,
            downPaymentAuthStrategy:   downPaymentAuthStrategy,
            installmentAuthStrategy:   installmentAuthStrategy,
            totalAmount:               totalAmount,
            paidAmount:                0,
            downPaymentBps:            downPaymentBps,
            installments:              installments,
            paidInstallments:          0,
            installmentPeriod:         installmentPeriod,
            nextPaymentDue:            block.timestamp + installmentPeriod,
            gracePeriod:               gracePeriod,
            lateFeeBps:                lateFeeBps,
            status:                    OrderStatus.Active
        });

        // Record creation timestamp for getSchedule due date derivation
        _orderCreatedAt[orderId] = block.timestamp;

        // ---- Step 5: Collect down payment ----
        uint256 downPayment = Math.mulDiv(totalAmount, downPaymentBps, 10000);
        bool ok = IPaymentAuth(downPaymentAuthStrategy).pullPayment(
            customer,
            msg.sender,   // merchant receives tokens directly
            token,
            downPayment,
            downPaymentAuthData
        );
        require(ok, "BNPL: down payment failed");

        // Update paidAmount after successful pull
        _orders[orderId].paidAmount = downPayment;

        // ---- Step 6: Emit ----
        emit OrderCreated(
            orderId,
            customer,
            msg.sender,
            token,
            totalAmount,
            installments,
            downPayment,
            downPaymentAuthStrategy,
            installmentAuthStrategy
        );
    }

    // ============ IBNPL — collectInstallment ============

    /// @dev MerkleScheduleAuth type identifier
    bytes4 private constant MERKLE_AUTH_TYPE =
        bytes4(keccak256("MerkleScheduleAuth"));

    /**
     * @inheritdoc IBNPL
     *
     * @dev Execution order per spec:
     *   Step 1: Validate
     *   Step 2: Calculate amounts (shared helper, same as getNextInstallment)
     *   Step 3: Effects
     *   Step 4: Collect via installmentAuthStrategy
     *   Step 5: Emit
     *
     *   For MerkleScheduleAuth orders, the amount is determined by the merkle
     *   leaf rather than uniform calculation. This contract passes 0 and the
     *   strategy enforces the leaf amount.
     */
    function collectInstallment(
        bytes32 orderId,
        bytes calldata installmentAuthData
    ) external override nonReentrant {
        Order storage o = _orders[orderId];

        // ---- Step 1: Validate ----
        require(o.status == OrderStatus.Active, "BNPL: order not active");
        require(block.timestamp >= o.nextPaymentDue, "BNPL: payment not yet due");
        require(_isAuthorizedCollector(orderId), "BNPL: caller not authorized");

        // ---- Step 2: Calculate amounts ----
        // For MerkleScheduleAuth, the actual amount comes from the leaf
        bool isMerkleSchedule = IPaymentAuth(o.installmentAuthStrategy).authType() == MERKLE_AUTH_TYPE;

        uint256 principal;
        uint256 lateFee;
        uint256 amountToCollect;

        if (isMerkleSchedule) {
            // Decode leaf amount from authData: (orderId, installmentIndex, leafAmount, dueDate, proof)
            (, , uint256 leafAmount, , ) = abi.decode(
                installmentAuthData, (bytes32, uint256, uint256, uint256, bytes32[])
            );
            principal = leafAmount;
            lateFee = 0; // Late fees not applied to merkle schedule orders
            amountToCollect = 0; // Strategy uses leaf amount
        } else {
            (principal, lateFee) = _calculateNextInstallment(o);
            amountToCollect = principal + lateFee;
        }

        // ---- Step 3: Effects ----
        uint8 installmentNumber = o.paidInstallments + 1; // 1-indexed for event
        o.paidInstallments += 1;
        o.paidAmount       += principal + lateFee;
        o.nextPaymentDue   += o.installmentPeriod;

        bool completed = (o.paidInstallments == o.installments);
        if (completed) {
            o.status = OrderStatus.Completed;
        }

        // ---- Step 4: Collect ----
        bool ok = IPaymentAuth(o.installmentAuthStrategy).pullPayment(
            o.customer,
            o.merchant,
            o.token,
            amountToCollect,
            installmentAuthData
        );
        require(ok, "BNPL: installment payment failed");

        // ---- Step 5: Emit ----
        emit InstallmentCollected(orderId, installmentNumber, principal, lateFee, msg.sender);
        if (completed) emit OrderCompleted(orderId);
    }

    // ============ IBNPL — payOffEarly ============

    /// @inheritdoc IBNPL
    function payOffEarly(
        bytes32 orderId,
        bytes calldata authData
    ) external override nonReentrant {
        Order storage o = _orders[orderId];

        require(o.status == OrderStatus.Active,  "BNPL: order not active");
        require(msg.sender == o.customer,         "BNPL: only customer can pay off early");

        uint256 remaining = o.totalAmount - o.paidAmount;
        require(remaining > 0, "BNPL: nothing remaining");

        // Effects before interaction
        o.paidAmount = o.totalAmount;
        o.paidInstallments = o.installments;
        o.status = OrderStatus.Completed;

        // No late fee on early payoff
        bool ok = IPaymentAuth(o.installmentAuthStrategy).pullPayment(
            o.customer,
            o.merchant,
            o.token,
            remaining,
            authData
        );
        require(ok, "BNPL: early payoff failed");

        emit OrderCompleted(orderId);
    }

    // ============ IBNPL — markDefaulted ============

    /// @inheritdoc IBNPL
    function markDefaulted(bytes32 orderId) external override {
        Order storage o = _orders[orderId];

        require(o.status == OrderStatus.Active, "BNPL: order not active");
        require(
            msg.sender == o.merchant || _operators[o.merchant][msg.sender],
            "BNPL: only merchant or operator"
        );
        require(
            block.timestamp > o.nextPaymentDue + o.gracePeriod,
            "BNPL: grace period not elapsed"
        );

        uint256 outstanding = o.totalAmount - o.paidAmount;
        o.status = OrderStatus.Defaulted;

        emit OrderDefaulted(orderId, outstanding);
    }

    // ============ IBNPL — cancelOrder ============

    /**
     * @inheritdoc IBNPL
     *
     * @dev Implements RECOMMENDED refund behavior per spec:
     *   - Customer cancels: down payment forfeit; collected installments refunded.
     *   - Merchant cancels: all collected amounts refunded.
     *
     * Refund is executed in the same transaction before OrderCancelled is emitted.
     */
    function cancelOrder(bytes32 orderId) external override nonReentrant {
        Order storage o = _orders[orderId];

        require(o.status == OrderStatus.Active, "BNPL: order not active");
        require(
            msg.sender == o.customer || msg.sender == o.merchant,
            "BNPL: only customer or merchant"
        );

        uint256 downPayment = Math.mulDiv(o.totalAmount, o.downPaymentBps, 10000);
        uint256 refundAmount;

        if (msg.sender == o.customer) {
            // Customer cancels: down payment forfeit, installments refunded
            refundAmount = o.paidAmount > downPayment
                ? o.paidAmount - downPayment
                : 0;
        } else {
            // Merchant cancels: full refund
            refundAmount = o.paidAmount;
        }

        // Effects before interaction
        o.status = OrderStatus.Cancelled;

        // Execute refund in same transaction if applicable
        if (refundAmount > 0) {
            IERC20(o.token).safeTransferFrom(o.merchant, o.customer, refundAmount);
        }

        emit OrderCancelled(orderId, msg.sender, refundAmount);
    }

    // ============ IBNPL — View functions ============

    /// @inheritdoc IBNPL
    function getOrder(bytes32 orderId)
        external view override returns (Order memory)
    {
        require(_orders[orderId].customer != address(0), "BNPL: order not found");
        return _orders[orderId];
    }

    /// @inheritdoc IBNPL
    function getNextInstallment(bytes32 orderId)
        external view override returns (uint256 principal, uint256 lateFee)
    {
        Order storage o = _orders[orderId];
        require(o.status == OrderStatus.Active, "BNPL: order not active");
        return _calculateNextInstallment(o);
    }

    /**
     * @inheritdoc IBNPL
     *
     * @dev Returns empty arrays for MerkleScheduleAuth orders since the
     *      schedule is off-chain. Callers should read scheduleDataCIDs from
     *      the MerkleScheduleAuth contract for merkle-based orders.
     */
    function getSchedule(bytes32 orderId)
        external view override
        returns (uint256[] memory amounts, uint256[] memory dueDates)
    {
        Order storage o = _orders[orderId];
        require(o.customer != address(0), "BNPL: order not found");

        // Return empty arrays for MerkleScheduleAuth — schedule is off-chain
        bytes4 merkleId = bytes4(keccak256("MerkleScheduleAuth"));
        if (IPaymentAuth(o.installmentAuthStrategy).authType() == merkleId) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256 n = o.installments;
        amounts  = new uint256[](n);
        dueDates = new uint256[](n);

        uint256 downPayment = Math.mulDiv(o.totalAmount, o.downPaymentBps, 10000);
        uint256 remaining   = o.totalAmount - downPayment;
        uint256 baseAmt     = remaining / n;
        uint256 dust        = remaining % n;
        uint256 createdAt   = _orderCreatedAt[orderId];

        for (uint256 i = 0; i < n; i++) {
            amounts[i]  = (i == n - 1) ? baseAmt + dust : baseAmt;
            dueDates[i] = createdAt + o.installmentPeriod * (i + 1);
        }
    }

    /// @inheritdoc IBNPL
    function getRemainingBalance(bytes32 orderId)
        external view override returns (uint256)
    {
        Order storage o = _orders[orderId];
        require(o.customer != address(0), "BNPL: order not found");
        if (o.status == OrderStatus.Completed) return 0;
        return o.totalAmount - o.paidAmount;
    }

    /// @inheritdoc IBNPL
    function isOrderPastDue(bytes32 orderId)
        external view override returns (bool pastDue, bool pastGrace)
    {
        Order storage o = _orders[orderId];
        require(o.customer != address(0), "BNPL: order not found");
        pastDue   = block.timestamp > o.nextPaymentDue;
        pastGrace = block.timestamp > o.nextPaymentDue + o.gracePeriod;
    }

    /// @inheritdoc IBNPL
    function authorizationNonce(address customer)
        external view override returns (uint256)
    {
        return _nonces[customer];
    }

    // ============ IOperatorManager ============

    /// @inheritdoc IOperatorManager
    function authorizeOperator(address operator) external override {
        require(operator != address(0), "BNPL: zero operator address");
        require(!_operators[msg.sender][operator], "BNPL: already authorized");
        _operators[msg.sender][operator] = true;
        emit OperatorAuthorized(operator, msg.sender);
    }

    /// @inheritdoc IOperatorManager
    function revokeOperator(address operator) external override {
        require(_operators[msg.sender][operator], "BNPL: not authorized");
        _operators[msg.sender][operator] = false;
        emit OperatorRevoked(operator, msg.sender);
    }

    /// @inheritdoc IOperatorManager
    function isOperator(address operator, address merchant)
        external view override returns (bool)
    {
        return _operators[merchant][operator];
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == IBNPL_INTERFACE_ID
            || interfaceId == type(IOperatorManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ============ Private helpers ============

    /**
     * @notice Check that an address implements IPaymentAuth via ERC-165.
     */
    function _supportsPaymentAuth(address strategy) private view returns (bool) {
        (bool ok, bytes memory data) = strategy.staticcall(
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IPaymentAuth).interfaceId)
        );
        return ok && data.length >= 32 && abi.decode(data, (bool));
    }

    /**
     * @notice Shared installment amount + late fee calculation.
     * @dev Used by both collectInstallment and getNextInstallment to guarantee
     *      that displayed amounts always match collected amounts.
     */
    function _calculateNextInstallment(Order storage o)
        private view
        returns (uint256 principal, uint256 lateFee)
    {
        // Dust-aware installment amount
        principal = _installmentAmount(
            o.totalAmount,
            o.downPaymentBps,
            o.installments,
            o.paidInstallments   // 0-based index of the installment being collected
        );

        // Late fee applies if past due but still within grace period
        lateFee = 0;
        if (
            block.timestamp > o.nextPaymentDue &&
            block.timestamp <= o.nextPaymentDue + o.gracePeriod
        ) {
            lateFee = Math.mulDiv(principal, o.lateFeeBps, 10000);
        }
    }
}
