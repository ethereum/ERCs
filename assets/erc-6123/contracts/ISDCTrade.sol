// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract - Trade Events and Trade Functions.
 * @dev Interface specification for a Smart Derivative Contract - Trade Specific Part. See ISDC interface documentation for a more detailed description.
 */

interface ISDCTrade {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /* Events related to trade inception */

    /**
     * @dev Emitted  when a new trade is incepted from a eligible counterparty
     * @param initiator is the address from which trade was incepted
     * @param withParty is the party the inceptor wants to trade with
     * @param tradeId is the trade ID (e.g. generated internally)
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
    event TradeIncepted(address initiator, address withParty, string tradeId, string tradeData, int position, int256 paymentAmount, string initialSettlementData);

    /**
     * @dev Emitted when an incepted trade is confirmed by the opposite counterparty
     * @param confirmer the confirming party
     * @param tradeId the trade identifier
     */
    event TradeConfirmed(address confirmer, string tradeId);

    /**
     * @dev Emitted when an incepted trade is canceled by the incepting counterparty
     * @param initiator is the address from which trade was canceled
     * @param tradeId the trade identifier
     */
    event TradeCanceled(address initiator, string tradeId);

    /* Events related to activation and termination */

    /**
     * @dev Emitted when a confirmed trade is set to active - e.g. when termination fee amounts are provided
     * @param tradeId the trade identifier of the activated trade
     */
    event TradeActivated(string tradeId);

    /**
     * @dev Emitted when an active trade is terminated
     * @param tradeId the trade identifier of the activated trade
     * @param cause string holding data associated with the termination, e.g. transactionData upon a failed transaction
     */
    event TradeTerminated(string tradeId, string cause);

    /* Events related to trade termination */

    /**
     * @dev Emitted when a counterparty proactively requests an early termination of the underlying trade
     * @param initiator the address of the requesting party
     * @param terminationPayment an agreed termination amount (viewed from the requester)
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationTerms termination terms
     */
    event TradeTerminationRequest(address initiator, string tradeId, int256 terminationPayment, string terminationTerms);

    /**
     * @dev Emitted when early termination request is confirmed by the opposite party
     * @param confirmer the party which confirms the trade termination
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationPayment an agreed termination amount (viewed from the confirmer, negative of the value provided by the requester)
     * @param terminationTerms termination terms
     */
    event TradeTerminationConfirmed(address confirmer, string tradeId, int256 terminationPayment, string terminationTerms);

    /**
     * @dev Emitted when a counterparty cancels its requests an early termination of the underlying trade
     * @param initiator the address of the requesting party
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationTerms termination terms
     */
    event TradeTerminationCanceled(address initiator, string tradeId, string terminationTerms);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /// Trade Inception

    /**
     * @notice Incepts a trade, stores trade data
     * @dev emits a {TradeIncepted} event
     * @param withParty is the party the inceptor wants to trade with
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     * @return the tradeId uniquely determining this trade.
     */
    function inceptTrade(address withParty, string memory tradeData, int position, int256 paymentAmount, string memory initialSettlementData) external returns (string memory);

    /**
     * @notice Performs a matching of provided trade data and settlement data of a previous trade inception
     * @dev emits a {TradeConfirmed} event if trade data match and emits a {TradeActivated} if trade becomes active or {TradeTerminated} if not
     * @param withParty is the party the confirmer wants to trade with
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the confirmer has in that trade (negative of the position the inceptor has in the trade)
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the confirmer, negative of the inceptor's view)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
     function confirmTrade(address withParty, string memory tradeData, int position, int256 paymentAmount, string memory initialSettlementData) external;

    /**
     * @notice Performs a matching of provided trade data and settlement data of a previous trade inception. Required to be called by inceptor.
     * @dev emits a {TradeCanceled} event if trade data match and msg.sender agrees with the party that incepted the trade.
     * @param withParty is the party the inceptor wants to trade with
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
    function cancelTrade(address withParty, string memory tradeData, int position, int256 paymentAmount, string memory initialSettlementData) external;

    /// Trade termination

    /**
     * @notice Called from a counterparty to request a mutual termination
     * @dev emits a {TradeTerminationRequest}
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationPayment an agreed termination amount (viewed from the requester)
     * @param terminationTerms the termination terms to be stored on chain.
     */
    function requestTradeTermination(string memory tradeId, int256 terminationPayment, string memory terminationTerms) external;

    /**
     * @notice Called from a party to confirm an incepted termination, which might trigger a final settlement before trade gets closed
     * @dev emits a {TradeTerminationConfirmed}
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationPayment an agreed termination amount (viewed from the confirmer, negative of the value provided by the requester)
     * @param terminationTerms the termination terms to be stored on chain.
     */
    function confirmTradeTermination(string memory tradeId, int256 terminationPayment, string memory terminationTerms) external;

    /**
     * @notice Called from a party to confirm an incepted termination, which might trigger a final settlement before trade gets closed
     * @dev emits a {TradeTerminationCanceled}
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param terminationPayment an agreed termination amount (viewed from the requester)
     * @param terminationTerms the termination terms
     */
    function cancelTradeTermination(string memory tradeId, int256 terminationPayment, string memory terminationTerms) external;
}
