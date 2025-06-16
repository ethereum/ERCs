// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract - Settlement Events and Settlement Functions.
 * @dev Interface specification for a Smart Derivative Contract - Settlement Specific Part. See ISDC interface documentation for a more detailed description.
 */

interface ISDCSettlement {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /* Events related to the settlement process */

    /**
     * @dev Emitted when a settlement gets requested
     * @param initiator the address of the requesting party
     * @param tradeData holding the stored trade data
     * @param lastSettlementData holding the settlementdata from previous settlement (next settlement will be the increment of next valuation compared to former valuation)
     */
    event SettlementRequested(address initiator, string tradeData, string lastSettlementData);

    /**
     * @dev Emitted when Settlement has been valued and settlement phase is initiated
     * @param initiator the address of the requesting party
     * @param settlementAmount the settlement amount. If settlementAmount > 0 then receivingParty receives this amount from other party. If settlementAmount < 0 then other party receives -settlementAmount from receivingParty.
     * @param settlementData. the tripple (product, previousSettlementData, settlementData) determines the settlementAmount.
     */
    event SettlementDetermined(address initiator, int256 settlementAmount, string settlementData);

    /**
     * @dev Emitted when settlement process has been finished
     * @param transactionID a transaction id
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     */
    event SettlementTransferred(uint256 transactionID, string transactionData);

    /**
     * @dev Emitted when settlement process has been finished
     * @param transactionID a transaction id
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     */
    event SettlementFailed(uint256 transactionID, string transactionData);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /// Settlement Cycle: Settlement

    /**
     * @notice Called to trigger a (maybe external) valuation of the underlying contract and afterwards the according settlement process
     * @dev emits a {SettlementRequested}
     */
    function initiateSettlement() external;

    /**
     * @notice Called to trigger according settlement on chain-balances callback for initiateSettlement() event handler
     * @dev perform settlement checks, may initiate transfers and emits {SettlementDetermined}
     * @param settlementAmount the settlement amount. If settlementAmount > 0 then receivingParty receives this amount from other party. If settlementAmount < 0 then other party receives -settlementAmount from receivingParty.
     * @param settlementData. the tripple (product, previousSettlementData, settlementData) determines the settlementAmount.
     */
    function performSettlement(int256 settlementAmount, string memory settlementData) external;
}
