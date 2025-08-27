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
     * @dev Emitted when a settlement gets requested
     *     The argument `settlementSpec` is the one that was passed after a previous settlement
     *     in `afterSettlement`. It may be used to pass updated settlement specific information
     *     to the valuation oracle, e.g., when margin buffer amounts are a function of market
     *     parameters and are determined by an external oracle (e.g. the valuation oracle).
     *     In that case the external oracle can pass the `settlementSpec` via `afterSettlement`
     *     and pick it up in the `SettlementRequested` event (allows for stateless external oracles).
     *     For the initial settlement such data should be part of `tradeData`.
     * @param initiator the address of the requesting party
     * @param tradeData holding the stored trade data
     * @param settlementSpec holding additional specification for the settlement (e.g., updated margin buffer values)
     * @param lastSettlementData holding the settlementdata from previous settlement (next settlement will be the increment of next valuation compared to former valuation)
     */
    event SettlementRequested(address initiator, string tradeData, string settlementSpec, string lastSettlementData);

    /**
     * @dev Emitted when Settlement has been valued and settlement phase is initiated.
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

    /**
     * @notice Called to prepare the next settlement and move to that phase. May trigger optional checks (e.g. pre-funding check).
     * @dev Depending on the implementation, this method may be called automatically at the end of performSettlement or called externally.
     *   An implementation that used adjusting of pre-funding can check the pre-funding within this method.this.
     *   An implementation that checked a static pre-funding upon confirmation of the trade might not require this step.
     *   In any case, the method may trigger termination if the settlement failed.
     *   emits a {SettlementTransferred} or a {SettlementFailed} event. May emit a {TradeTerminated} event.
     * @param success may be used, in case an external oracle performs checks required for the next settlement phase.
     * @param nextSettlementSpec may be used to update settlement specification that is passed with the next {SettlementRequested} event.
     */
    function afterSettlement(bool success, string memory nextSettlementSpec) external;
}
