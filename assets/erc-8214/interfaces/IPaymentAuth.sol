// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IPaymentAuth
 * @notice Pluggable interface for pulling ERC-20 tokens from a payer.
 * @dev Each implementation encapsulates one authorization model.
 *      The authData parameter carries strategy-specific data
 *      (signatures, proofs, empty bytes) and is opaque to IBNPL callers.
 */
interface IPaymentAuth is IERC165 {

    /**
     * @notice Pull `amount` of `token` from `payer` to `recipient`.
     * @param payer      Address whose tokens are pulled.
     * @param recipient  Address that receives the tokens.
     * @param token      ERC-20 token address.
     * @param amount     Exact amount to pull in token base units.
     * @param authData   Strategy-specific authorization data.
     * @return success   True if tokens were transferred successfully.
     */
    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata authData
    ) external returns (bool success);

    /**
     * @notice Returns a unique identifier for this authorization strategy type.
     * @dev SHOULD return bytes4(keccak256("StrategyName")).
     */
    function authType() external pure returns (bytes4);
}
