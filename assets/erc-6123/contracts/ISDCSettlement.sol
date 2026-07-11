// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract - Settlement Events and Settlement Functions.
 * @dev Interface specification for a Smart Derivative Contract - Settlement Specific Part.
 *   See ISDC interface documentation for a more detailed description.
 */
interface ISDCSettlement {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /* Events related to the settlement process */

    /**
     * @dev Emitted when all pre-conditions of a settlement are met and the contracts waits for initateSettlement.
     * @param settlementSpec Optional information on the next settlement.
     */
    event SettlementAwaitingInitiation(string settlementSpec);

    /**
     * @dev Emitted when a settlement gets requested
     *     The argument `lastSettlementData` is the one that was passed to {performSettlement} after a previous settlement.
     *     It may/should contain the market information associated with the previous settlment to calculate the margin (difference).
     *     It may be used to pass updated settlement specific information, e.g. updated margin buffer (determined in the previous settlement).
     *     These parameters may be determined by an external oracle (e.g. the valuation oracle).
     *     In that case the external oracle can pass the `settlementData` via {performSettlement} of the previous settlement
     *     and pick it up in the {SettlementRequested} event (allows for stateless external oracles).
     * @param initiator the address of the requesting party
     * @param tradeData holding the stored trade data
     * @param lastSettlementData holding the settlementData from the previous settlement (next settlement will be the increment of next valuation compared to former valuation).
     *     May also hold additional specification for the settlement (e.g., updated margin buffer values)
     */
    event SettlementRequested(address initiator, string tradeData, string lastSettlementData);

    /**
     * @dev Emitted when Settlement has been valued and settlement phase is initiated.
     *    Depending on the implementation, the observation of the `settlementData` can influence required actions
     *    (e.g., pre-funding of margin buffers), that are verified upon a call to {afterSettlement}.
     * @param initiator the address of the requesting party
     * @param settlementAmount the settlement amount. If settlementAmount > 0 then receivingParty receives this amount from other party. If settlementAmount < 0 then other party receives -settlementAmount from receivingParty.
     * @param settlementData the tripple (product, previousSettlementData, settlementData) determines the settlementAmount.
     *     May also hold additional specification of the next settlement phase (e.g. updates to the margin buffers).
     *     Determines the value of lastSettlementData in the next emittance of {SettlementRequested}.
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
     *     May also contrain updates to the settlement specification of the next settlement phase.
     *     Determines the value of settlementDate in the next emittance of {SettlementDetermined}
     *     Determines the value of lastSettlementData in the next emittance of {SettlementRequested}.
     */
    function performSettlement(int256 settlementAmount, string memory settlementData) external;

    /**
     * @notice Called to prepare the next settlement and move to that phase. May trigger optional checks (e.g. pre-funding check).
     * @dev Depending on the implementation, this method may be called automatically at the end of performSettlement or called externally.
     *   An implementation that uses adjusting of pre-funding can check the pre-funding within this method.this.
     *   An implementation that uses a static pre-funding upon confirmation of the trade might not require this step.
     *   In any case, the method may trigger termination if the settlement failed.
     *   emits a {SettlementTransferred} or a {SettlementFailed} event. May emit a {TradeTerminated} event.
     */
    function afterSettlement() external;
}
