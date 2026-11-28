// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymentAuth} from "../interfaces/IPaymentAuth.sol";

/**
 * @title AllowanceAuth
 * @notice IPaymentAuth strategy using standard ERC-20 approve/transferFrom.
 *
 * @dev Setup: the payer calls token.approve(bnplContract, amount) before
 *      this strategy can pull. authData is unused and MUST be empty (0x).
 *
 *      Uses SafeERC20.safeTransferFrom to handle tokens that do not return
 *      a bool from transferFrom (e.g. USDT on Ethereum mainnet).
 *
 *      Security: persistent allowance. Payers SHOULD set allowance equal to
 *      the remaining installment balance (totalAmount - downPayment), not
 *      type(uint256).max. The BNPL contract enforces per-installment amounts.
 *
 *      Typical use: installmentAuthStrategy — automatic collection after a
 *      signature-based checkout.
 *
 *      authData: empty (0x)
 */
contract AllowanceAuth is IPaymentAuth, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 public constant AUTH_TYPE_ID = bytes4(keccak256("AllowanceAuth"));

    // ============ IPaymentAuth ============

    function authType() external pure override returns (bytes4) {
        return AUTH_TYPE_ID;
    }

    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata /* authData */
    ) external override nonReentrant returns (bool) {
        IERC20(token).safeTransferFrom(payer, recipient, amount);
        return true;
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId)
        external pure override returns (bool)
    {
        return interfaceId == type(IPaymentAuth).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
