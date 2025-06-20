// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import "./IAsyncTransferCallback.sol";

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------
 * @title ERC6123 - Settlement Token Interface.
 * @dev Settlement Token Interface introduces an asynchronous (checked) transfer functionality which can be used to directly interact with an SDC.
 * Transfers can be conducted for single or multiple transactions where SDC will receive a success message whether the transfer was executed successfully or not (via ISDCTransferCallback).
 * The IAsyncTransferCallback (usually the SDC) needs to implement a function afterTransfer(bool success, uint256 transactionID, string memory transactionData)
 */
interface IAsyncTransfer {

    /**
     * @dev Emitted when a transfer gets requested
     * @param from the address from which to transfer
     * @param to the address to which to transfer
     * @param value the value to transfer
     * @param transactionID a transaction ID that may serve as correlation ID, will be passed to the callback.
     * @param callbackContract a contract implementing afterTransfer
     */
    event TransferRequested(address from, address to, uint256 value, uint256 transactionID, IAsyncTransferCallback callbackContract);

    /**
     * @dev Emitted when a batch transfer gets requested
     * @param from the addresses from which to transfer
     * @param to the addresses to which to transfer
     * @param value the values to transfer
     * @param transactionID a transaction ID that may serve as correlation ID, will be passed to the callback.
     * @param callbackContract a contract implementing afterTransfer
     */
    event TransferBatchRequested(address[] from, address[] to, uint256[] value, uint256 transactionID, IAsyncTransferCallback callbackContract);

    /*
     * @dev Performs a single transfer from msg.sender balance and checks whether this transfer can be conducted
     * @param to - receiver
     * @param value - transfer amount
     * @param transactionID - an id that will be passed back to the callback
     * @param callbackContract - a contract implementing the method afterTransfer(bool success, uint256 transactionID, string memory transactionData)
     */
    function transferAndCallback(address to, uint256 value, uint256 transactionID, IAsyncTransferCallback callbackContract) external;

    /*
     * @dev Performs a single transfer to a single addresss and checks whether this transfer can be conducted
     * @param from - payer
     * @param to - receiver
     * @param value - transfer amount
     * @param transactionID - an id that will be passed back to the callback
     * @param callbackContract - a contract implementing the method afterTransfer(bool success, uint256 transactionID, string memory transactionData)
     */
    function transferFromAndCallback(address from, address to, uint256 value, uint256 transactionID, IAsyncTransferCallback callbackContract) external ;

    /*
     * @dev Performs a multiple transfers from msg.sender balance and checks whether these transfers can be conducted
     * @param to - receivers
     * @param values - transfer amounts
     * @param transactionID - an id that will be passed back to the callback
     * @param callbackContract - a contract implementing the method afterTransfer(bool success, uint256 transactionID, string memory transactionData)
     */
    function transferBatchAndCallback(address[] memory to, uint256[] memory values, uint256 transactionID, IAsyncTransferCallback callbackContract) external;

    /*
     * @dev Performs a multiple transfers between multiple addresses and checks whether these transfers can be conducted
     * @param from - payers
     * @param to - receivers
     * @param values - transfer amounts
     * @param transactionID - an id that will be passed back to the callback
     * @param callbackContract - a contract implementing the method afterTransfer(bool success, uint256 transactionID, string memory transactionData)
     */
    function transferBatchFromAndCallback(address[] memory from, address[] memory to, uint256[] memory values, uint256 transactionID, IAsyncTransferCallback callbackContract) external;
}
