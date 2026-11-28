// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymentAuth} from "../interfaces/IPaymentAuth.sol";

/**
 * @title PermitAuth
 * @notice IPaymentAuth strategy using ERC-2612 permit signatures.
 *
 * @dev The token MUST implement IERC20Permit. If permit() reverts (e.g.
 *      unsupported token, expired deadline, invalid signature), pullPayment
 *      reverts and no tokens are moved.
 *
 *      No standing allowance required — each pull consumes a fresh permit
 *      signature with a deadline. The payer must produce a new signature
 *      before each collection, or pre-sign all permits at checkout.
 *
 *      Uses SafeERC20.safeTransferFrom after permit to handle tokens that
 *      do not return a bool from transferFrom.
 *
 *      Typical use: downPaymentAuthStrategy for ERC-2612 tokens.
 *
 *      authData: abi.encode(uint256 deadline, uint8 v, bytes32 r, bytes32 s)
 */
contract PermitAuth is IPaymentAuth, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 public constant AUTH_TYPE_ID = bytes4(keccak256("PermitAuth"));

    // ============ IPaymentAuth ============

    function authType() external pure override returns (bytes4) {
        return AUTH_TYPE_ID;
    }

    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata authData
    ) external override nonReentrant returns (bool) {
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(authData, (uint256, uint8, bytes32, bytes32));

        // Permit sets the allowance for this contract to exactly `amount`
        IERC20Permit(token).permit(
            payer,
            address(this),
            amount,
            deadline,
            v, r, s
        );

        // Transfer using SafeERC20 to handle non-bool-returning tokens
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
