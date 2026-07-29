// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title Fraction Transfer Event Emitter interface
 * @notice Interface defines functions to emit events when fractions are transferred
 */
interface IFractionTransferEventEmitter {
    /// @dev Emitted when caller is not one of expected addresses
    error WrongTransferNotificationSource();

    /**
     * @notice Notifies about a fraction transfer
     * @param from Address from which the fraction is transferred
     * @param to Address to which the fraction is transferred
     * @param value Amount of the fraction transferred
     * @dev Should emit an event with the information about the transfer
     */
    function fractionTransferredNotify(address from, address to, uint256 value) external;
}