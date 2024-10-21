// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0 <0.9.0;



import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------
 * @title ERC6123 - Settlement Token Interface
 * @dev Settlement Token Interface enhances the ERC20 Token by introducing so called checked transfer functionality which can be used to directly interact with an SDC.
 * Checked transfers can be conducted for single or multiple transactions where SDC will receive a success message whether the transfer was executed successfully or not.
 */


interface IERC20Settlement is IERC20 {

    /**
     * @dev Emitted during Settlement phase in case an offchain settlement is needed
     * @param _hash - checksum
     * @param sdcAddress - address of the sdc trade
     * @param _fromId - payer ID for offchain system
     * @param _toId - receiver ID for offchain system
     * @param _amount - payment amount
     * @param _fromAddress - payer onchain address
     * @param _toAddress - receiver onchain address
     * @param correlationId - id for an external system
     */
    event PaymentTriggered(string _hash, address sdcAddress, string _fromId, string _toId, uint256 _amount, address _fromAddress, address _toAddress, string correlationId);

    /*
     * @dev Performs a single transfer from msg.sender balance and checks whether this transfer can be conducted
     * @param to - receiver
     * @param value - transfer amount
     * @param transactionID
     */
    function checkedTransfer(address to, uint256 value, uint256 transactionID) external;

    /*
     * @dev Performs a single transfer to a single addresss and checks whether this transfer can be conducted
     * @param from - payer
     * @param to - receiver
     * @param value - transfer amount
     * @param transactionID
     */
    function checkedTransferFrom(address from, address to, uint256 value, uint256 transactionID) external ;


    /*
     * @dev Performs a multiple transfers from msg.sender balance and checks whether these transfers can be conducted
     * @param to - receivers
     * @param values - transfer amounts
     * @param transactionID
     */
    function checkedBatchTransfer(address[] memory to, uint256[] memory values, uint256 transactionID ) external;

    /*
     * @dev Performs a multiple transfers between multiple addresses and checks whether these transfers can be conducted
     * @param from - payers
     * @param to - receivers
     * @param value - transfer amounts
     * @param transactionID
     */
    function checkedBatchTransferFrom(address[] memory from, address[] memory to, uint256[] memory values, uint256 transactionID ) external;

    /*
     * @dev Inits an SDC for which it conducts the settlement
     * @param address - address of sdc contract
     */
    function initSDC(address sdcAddress) external;

    /**
     * @dev Performs the initialization of a party, stores an onchain address associated with an offchain ID
     * @param partyAddress - onchain address
     * @param partyId - ID for offchain system
     */
    function initParty(address partyAddress, string memory partyId) external;
}
