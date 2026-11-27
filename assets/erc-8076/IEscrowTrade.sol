// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Interface for an escrowed exchange of two ERC-20 tokens.
interface IEscrowTrade {
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed payer,
        address indexed to,
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        uint256 deadline
    );
    event OrderCompleted(bytes32 indexed orderId);
    event OrderCancelled(bytes32 indexed orderId);

    /// @notice Deposit the payer's input tokens into a new escrow order.
    /// @param to The recipient of the output tokens.
    /// @param tokenFrom The input token contract.
    /// @param tokenTo The output token contract.
    /// @param amountFrom The input amount in the token's smallest units.
    /// @param amountTo The output amount in the token's smallest units.
    /// @param deadline The last Unix timestamp in seconds at which the order can be filled.
    /// @return orderId The order identifier within this escrow contract.
    function createOrder(
        address to,
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 amountTo,
        uint256 deadline
    ) external returns (bytes32 orderId);

    /// @notice Deliver the output tokens to the recipient and receive the escrowed input tokens.
    /// @param orderId The identifier of the open order to fill.
    function completeOrder(bytes32 orderId) external;

    /// @notice Return the escrowed input tokens to the payer after the order expires.
    /// @param orderId The identifier of the open order to cancel.
    function cancelOrder(bytes32 orderId) external;
}
