// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract - Transfer Events and Transfer Functions.
 * @dev Interface specification for a Smart Derivative Contract - Transfer Specific Part. See ISDC interface documentation for a more detailed description.
 */

interface IAsyncTransferCallback {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /* Events related to the settlement process */

    /**
     * @dev Emitted when settlement process has been finished
     * @param transactionID a transaction id
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     */
    event TransferSucceeded(uint256 transactionID, string transactionData);

    /**
     * @dev Emitted when transfer process has been finished
     * @param transactionID a transaction id
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     */
    event TransferFailed(uint256 transactionID, string transactionData);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice May get called from outside to to finish a transfer (callback). The trade decides on how to proceed based on success flag
     * @param success tells the protocol whether transfer was successful
     * @param transactionID a transaction id
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     * @dev emits a {TransferSucceeded} or a {TransferFailed} event.
     */
    function afterTransfer(bool success, uint256 transactionID, string memory transactionData) external;
}
