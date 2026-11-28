// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymentAuth} from "../interfaces/IPaymentAuth.sol";

/**
 * @title MerkleScheduleAuth
 * @notice IPaymentAuth strategy for variable-amount installment schedules
 *         committed via a merkle root at order creation time.
 *
 * @dev Use this strategy only when installment amounts genuinely vary across
 *      payments. For uniform schedules, AllowanceAuth or Permit2Auth are
 *      simpler and correct.
 *
 *      Usage pattern:
 *        1. Merchant pre-computes orderId (deterministic — see BNPLManager).
 *        2. In the same transaction as BNPLManager.createOrder(), merchant
 *           calls registerSchedule(orderId, merkleRoot, dataCID) via multicall.
 *        3. For each installment, caller provides authData encoding
 *           (orderId, installmentIndex, leafAmount, dueDate, proof[]).
 *        4. pullPayment verifies the proof, enforces dueDate, marks the leaf
 *           consumed, and pulls the exact leaf amount.
 *
 *      Amount authority: this strategy uses the leaf amount, not the amount
 *      parameter passed by the caller. Callers MUST pass amount = 0 as a
 *      sentinel, or pass the exact leaf amount. Passing a non-zero amount
 *      that does not match the leaf amount causes a revert.
 *
 *      Payer prerequisite: standing ERC-20 allowance on the BNPL contract
 *      covering the full remaining installment balance (same as AllowanceAuth).
 *
 *      Uses SafeERC20.safeTransferFrom for non-bool-returning token safety.
 *
 *      Leaf construction:
 *        leaf = keccak256(abi.encode(installmentIndex, leafAmount, dueDate))
 *      where all three fields are uint256. abi.encode (not abi.encodePacked)
 *      is used to prevent variable-length encoding ambiguities.
 *
 *      Tree construction: binary tree with sorted siblings before hashing to
 *      prevent second-preimage attacks. Compatible with OZ MerkleProof library.
 *
 *      authData: abi.encode(
 *          bytes32 orderId,
 *          uint256 installmentIndex,
 *          uint256 leafAmount,
 *          uint256 dueDate,
 *          bytes32[] proof
 *      )
 */
contract MerkleScheduleAuth is IPaymentAuth, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 public constant AUTH_TYPE_ID = bytes4(keccak256("MerkleScheduleAuth"));

    // ============ Storage ============

    /// @notice Merkle root committed for each order.
    /// @dev orderId => merkleRoot. Zero means no schedule registered.
    mapping(bytes32 => bytes32) public scheduleRoots;

    /// @notice Content-addressed reference to the full leaf set.
    /// @dev orderId => CID bytes. Data availability commitment.
    mapping(bytes32 => bytes) public scheduleDataCIDs;

    /// @notice Tracks consumed leaves to prevent replay.
    /// @dev orderId => leafHash => consumed.
    mapping(bytes32 => mapping(bytes32 => bool)) public consumed;

    // ============ Events ============

    event ScheduleRegistered(
        bytes32 indexed orderId,
        bytes32 merkleRoot,
        bytes   dataCID
    );

    event LeafConsumed(
        bytes32 indexed orderId,
        uint256 installmentIndex,
        bytes32 leafHash
    );

    // ============ Registration ============

    /**
     * @notice Register a variable payment schedule for an order.
     *
     * @dev MUST be called by the merchant in the same transaction as
     *      BNPLManager.createOrder() — use a multicall wrapper.
     *      The orderId is deterministic and can be pre-computed before
     *      createOrder is submitted.
     *
     *      Reverts if:
     *        - A schedule is already registered for this orderId
     *        - merkleRoot is bytes32(0)
     *        - dataCID is empty
     *
     *      Publishing the leaf set to the referenced dataCID location
     *      is the merchant's responsibility.
     *
     * @param orderId     The IBNPL order identifier (pre-computable).
     * @param merkleRoot  Root of the (installmentIndex, amount, dueDate) tree.
     * @param dataCID     IPFS CID or other content-addressed reference to the
     *                    full leaf set. MUST be non-empty.
     */
    function registerSchedule(
        bytes32 orderId,
        bytes32 merkleRoot,
        bytes calldata dataCID
    ) external {
        require(
            scheduleRoots[orderId] == bytes32(0),
            "MerkleScheduleAuth: schedule already registered"
        );
        require(merkleRoot != bytes32(0),  "MerkleScheduleAuth: empty root");
        require(dataCID.length > 0,        "MerkleScheduleAuth: empty dataCID");

        scheduleRoots[orderId]    = merkleRoot;
        scheduleDataCIDs[orderId] = dataCID;

        emit ScheduleRegistered(orderId, merkleRoot, dataCID);
    }

    // ============ IPaymentAuth ============

    function authType() external pure override returns (bytes4) {
        return AUTH_TYPE_ID;
    }

    /**
     * @notice Pull an installment amount verified against the committed schedule.
     *
     * @dev The `amount` parameter supplied by the caller is validated against
     *      the leaf amount. Callers SHOULD pass amount = 0 as a sentinel.
     *      A non-zero amount that differs from the leaf amount causes a revert.
     *
     *      authData MUST be abi.encode(
     *          bytes32 orderId,
     *          uint256 installmentIndex,
     *          uint256 leafAmount,
     *          uint256 dueDate,
     *          bytes32[] proof
     *      )
     */
    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata authData
    ) external override nonReentrant returns (bool) {
        (
            bytes32 orderId,
            uint256 installmentIndex,
            uint256 leafAmount,
            uint256 dueDate,
            bytes32[] memory proof
        ) = abi.decode(authData, (bytes32, uint256, uint256, uint256, bytes32[]));

        // Validate caller-supplied amount matches leaf (or is sentinel 0)
        require(
            amount == 0 || amount == leafAmount,
            "MerkleScheduleAuth: amount mismatch"
        );

        // Schedule must exist for this order
        bytes32 root = scheduleRoots[orderId];
        require(root != bytes32(0), "MerkleScheduleAuth: no schedule registered");

        // Reconstruct leaf and verify not already consumed
        bytes32 leaf = keccak256(abi.encode(installmentIndex, leafAmount, dueDate));
        require(
            !consumed[orderId][leaf],
            "MerkleScheduleAuth: leaf already consumed"
        );

        // Verify proof against committed root
        require(
            MerkleProof.verify(proof, root, leaf),
            "MerkleScheduleAuth: invalid proof"
        );

        // Enforce due date
        require(
            block.timestamp >= dueDate,
            "MerkleScheduleAuth: payment not yet due"
        );

        // Effects before interaction (CEI pattern)
        consumed[orderId][leaf] = true;
        emit LeafConsumed(orderId, installmentIndex, leaf);

        // Pull tokens using SafeERC20
        IERC20(token).safeTransferFrom(payer, recipient, leafAmount);
        return true;
    }

    // ============ View Functions ============

    /**
     * @notice Check whether a specific leaf has been consumed.
     */
    function isLeafConsumed(
        bytes32 orderId,
        uint256 installmentIndex,
        uint256 leafAmount,
        uint256 dueDate
    ) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encode(installmentIndex, leafAmount, dueDate));
        return consumed[orderId][leaf];
    }

    /**
     * @notice Verify a proof without consuming the leaf.
     * @return valid True if the proof is valid against the registered root.
     */
    function verifyInstallment(
        bytes32 orderId,
        uint256 installmentIndex,
        uint256 leafAmount,
        uint256 dueDate,
        bytes32[] calldata proof
    ) external view returns (bool valid) {
        bytes32 root = scheduleRoots[orderId];
        if (root == bytes32(0)) return false;
        bytes32 leaf = keccak256(abi.encode(installmentIndex, leafAmount, dueDate));
        return MerkleProof.verify(proof, root, leaf);
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId)
        external pure override returns (bool)
    {
        return interfaceId == type(IPaymentAuth).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
