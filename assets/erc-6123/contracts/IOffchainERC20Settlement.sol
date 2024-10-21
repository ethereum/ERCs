// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0 <0.9.0;

import "./IERC20Settlement.sol";

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------
 * @title ERC6123 - Settlement Token Interface
 * @dev Settlement Token Interface enhances the ERC20 Token by introducing so called checked transfer functionality which can be used to directly interact with an SDC.
 * Checked transfers can be conducted for single or multiple transactions where SDC will receive a success message whether the transfer was executed successfully or not.
 */


interface IOffchainERC20Settlement is IERC20Settlement {

    /**
     * @dev Performs the initialization of a party, stores an onchain address associated with an offchain ID
     * @param partyAddress - onchain address
     * @param partyId - ID for offchain system
     */
    function initParty(address partyAddress, string memory partyId) external;

    /**
     * @dev Emitted during Settlement phase in case an offchain settlement is needed
     * @param _hash - checksum
     * @param sdcAddress - address of the sdc trade
     * @param _fromId - payer ID for offchain system
     * @param _toId - receiver ID for offchain system
     * @param _amount - payment amount
     * @param _fromAddress - payer onchain address
     * @param _toAddress - receiver onchain address
     */
    event PaymentTriggered(string _hash, address sdcAddress, string _fromId, string _toId, uint256 _amount, address _fromAddress, address _toAddress);
}
