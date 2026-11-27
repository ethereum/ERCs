// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IPuller} from "../interfaces/IPuller.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BasePuller
 * @notice Abstract base contract implementing the approval, allowance delegation,
 * permit, and event emission logic of ERC-8187.
 *
 * @dev Subclasses must implement `_sourceTokens` (the custom sourcing logic)
 * and `maxPullable` (the sourcing-aware pullability check).
 *
 * ## EIP-712 Permit
 *
 * The struct signed in permits is defined as:
 * ```
 * PullPermit(address token,address owner,address spender,uint256 limit,uint256 nonce,uint256 deadline)
 * ```
 *
 * The typehash is:
 * ```
 * keccak256("PullPermit(address token,address owner,address spender,uint256 limit,uint256 nonce,uint256 deadline)")
 * ```
 *
 * @custom:specification https://eips.ethereum.org/ERCS/erc-8187
 */
abstract contract BasePuller is IPuller, EIP712 {
    using SafeERC20 for IERC20;

    // =============================================================
    // Constants
    // =============================================================

    bytes32 private constant _PULL_PERMIT_TYPEHASH =
        keccak256("PullPermit(address token,address owner,address spender,uint256 limit,uint256 nonce,uint256 deadline)");

    // =============================================================
    // State
    // =============================================================

    mapping(address token => mapping(address owner => mapping(address spender => uint256))) private _pullAllowances;

    mapping(address owner => uint256) private _nonces;

    // =============================================================
    // Errors
    // =============================================================

    error InsufficientAllowance(uint256 available, uint256 required);
    error PermitExpired(uint256 deadline, uint256 currentTimestamp);
    error InvalidSignature(address expected, address recovered);
    error PermitFailedAndInsufficientAllowance(uint256 available, uint256 required);
    error TransferToSelf();

    // =============================================================
    // Constructor
    // =============================================================

    constructor() EIP712("TokenPuller", "1") {}

    // =============================================================
    // Core functions
    // =============================================================

    function approvePull(address token, address spender, uint256 limit) external {
        _pullAllowances[token][msg.sender][spender] = limit;
        emit PullApproval(token, msg.sender, spender, limit);
    }

    function pullFrom(address token, address owner, address to, uint256 amount) external {
        _executePull(token, owner, to, amount);
    }

    function pullAllowance(address token, address owner, address spender) external view returns (uint256) {
        return _pullAllowances[token][owner][spender];
    }

    function maxPullable(address token, address owner, uint256 upTo) external view virtual returns (uint256);

    // =============================================================
    // Allowance delegation
    // =============================================================

    function transferPullAllowance(address token, address owner, address toSpender, uint256 amount) external {
        if (toSpender == msg.sender) {
            revert TransferToSelf();
        }

        uint256 currentAllowance = _pullAllowances[token][owner][msg.sender];

        if (amount == type(uint256).max && currentAllowance == type(uint256).max) {
            _pullAllowances[token][owner][msg.sender] = 0;
            if (toSpender != address(0)) {
                _pullAllowances[token][owner][toSpender] = type(uint256).max;
            }
        } else {
            if (amount > currentAllowance) {
                revert InsufficientAllowance(currentAllowance, amount);
            }

            if (currentAllowance != type(uint256).max) {
                _pullAllowances[token][owner][msg.sender] = currentAllowance - amount;
            }

            if (toSpender != address(0)) {
                _pullAllowances[token][owner][toSpender] += amount;
            }
        }

        emit TransferPullAllowance(token, owner, msg.sender, toSpender, amount);
    }

    // =============================================================
    // Permits
    // =============================================================

    function permitPull(
        address token,
        address owner,
        address spender,
        uint256 limit,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) {
            revert PermitExpired(deadline, block.timestamp);
        }

        uint256 nonce = _nonces[owner];

        bytes32 structHash = keccak256(abi.encode(_PULL_PERMIT_TYPEHASH, token, owner, spender, limit, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        address recovered = ECDSA.recoverCalldata(digest, signature);
        if (recovered != owner) {
            revert InvalidSignature(owner, recovered);
        }

        _nonces[owner] = nonce + 1;
        _pullAllowances[token][owner][spender] = limit;

        emit PullApproval(token, owner, spender, limit);
    }

    function pullFromWithPermit(
        address token,
        address owner,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external {
        uint256 allowanceBefore = _pullAllowances[token][owner][msg.sender];

        if (allowanceBefore < amount) {
            try this.permitPull(token, owner, msg.sender, amount, deadline, signature) {
            } catch {
                uint256 allowanceAfter = _pullAllowances[token][owner][msg.sender];
                if (allowanceAfter < amount) {
                    revert PermitFailedAndInsufficientAllowance(allowanceAfter, amount);
                }
            }
        }

        _executePull(token, owner, to, amount);
    }

    // =============================================================
    // EIP-5267 / EIP-2612 helpers
    // =============================================================

    function eip712Domain()
        public
        view
        override(IPuller, EIP712)
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (hex"0f", _EIP712Name(), _EIP712Version(), block.chainid, address(this), bytes32(0), new uint256[](0));
    }

    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    // =============================================================
    // Internal: sourcing logic (abstract)
    // =============================================================

    function _sourceTokens(address token, address owner, address to, uint256 amount) internal virtual;

    // =============================================================
    // Internal: pull execution
    // =============================================================

    function _executePull(address token, address owner, address to, uint256 amount) internal {
        _consumeAllowance(token, owner, msg.sender, amount);

        _sourceTokens(token, owner, to, amount);

        emit TokensPulled(token, owner, msg.sender, to, amount);
    }

    // =============================================================
    // Internal: allowance management
    // =============================================================

    function _consumeAllowance(address token, address owner, address spender, uint256 amount) internal {
        if (spender == owner) {
            return;
        }

        uint256 currentAllowance = _pullAllowances[token][owner][spender];

        if (currentAllowance < amount) {
            revert InsufficientAllowance(currentAllowance, amount);
        }

        if (currentAllowance != type(uint256).max) {
            unchecked {
                _pullAllowances[token][owner][spender] = currentAllowance - amount;
            }
        }
    }

}
