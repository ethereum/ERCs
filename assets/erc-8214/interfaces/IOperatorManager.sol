// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IOperatorManager
 * @notice Manages addresses authorized to trigger payment collection
 *         on behalf of a merchant.
 * @dev Authorization is scoped per merchant. An address authorized by
 *      merchant A has no authority over merchant B's orders.
 *      Operators MUST NOT receive collected funds — all tokens flow
 *      directly from customer to merchant.
 */
interface IOperatorManager is IERC165 {

    event OperatorAuthorized(
        address indexed operator,
        address indexed merchant
    );

    event OperatorRevoked(
        address indexed operator,
        address indexed merchant
    );

    /**
     * @notice Authorize an operator to collect on behalf of the caller.
     * @dev MUST revert if operator is the zero address.
     *      MUST revert if operator is already authorized.
     */
    function authorizeOperator(address operator) external;

    /**
     * @notice Revoke a previously authorized operator.
     * @dev MUST revert if operator is not currently authorized for the caller.
     */
    function revokeOperator(address operator) external;

    /**
     * @notice Check whether an address is an authorized operator for a merchant.
     */
    function isOperator(
        address operator,
        address merchant
    ) external view returns (bool);
}
