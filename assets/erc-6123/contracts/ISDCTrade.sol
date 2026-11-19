// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract - Trade Events and Trade Functions.
 * @dev Interface specification for a Smart Derivative Contract - Trade Specific Part. See ISDC interface documentation for a more detailed description.
 * Trade participants are explicit, distinct and nonzero; they need not be the caller.
 * Implementations must authorize the caller for the relevant participant; the mechanism is implementation-specific.
 * Inception generates a nonempty tradeId that is never reused within this contract, including after cancellation or completion.
 * Confirmation and cancellation must match the ID and all inception terms and validate the lifecycle state.
 * Signed amounts retain the inceptor's perspective (positive: receive, negative: deliver); termination payments retain the requester's perspective.
 * Participant fields in events identify the economic parties, not necessarily the caller.
 */

interface ISDCTrade {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /* Events related to trade inception */

    /**
     * @dev Emitted  when a new trade is incepted from a eligible counterparty
     * @param initiator is the economic inceptor
     * @param withParty is the party the inceptor wants to trade with
     * @param tradeId is the trade ID (e.g. generated internally)
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade, may be negative (sell) or positive (buy)
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
    event TradeIncepted(address initiator, address withParty, string tradeId, string tradeData, int256 position, int256 paymentAmount, string initialSettlementData);

    /**
     * @dev Emitted when an incepted trade is confirmed by the opposite counterparty
     * @param confirmer the confirming party
     * @param tradeId the trade identifier
     */
    event TradeConfirmed(address confirmer, string tradeId);

    /**
     * @dev Emitted when an incepted trade is canceled by the incepting counterparty
     * @param initiator is the economic inceptor whose trade was canceled
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
     * @param terminationPayment an agreed termination amount (viewed from the original requester, with unchanged sign)
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
     * @dev Requires authority for the inceptor and emits a {TradeIncepted} event. An open inception must not be overwritten.
     * @param inceptor is the party proposing the trade
     * @param counterparty is the party the inceptor wants to trade with
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade, may be negative (sell) or positive (buy)
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     * @return tradeId the generated identifier, unique for the lifetime of this contract.
     */
    function inceptTrade(address inceptor, address counterparty, string memory tradeData, int256 position, int256 paymentAmount, string memory initialSettlementData) external returns (string memory tradeId);

    /**
     * @notice Performs a matching of provided trade data and settlement data of a previous trade inception
     * @dev Requires authority for the counterparty; emits a {TradeConfirmed} event if trade data match and emits a {TradeActivated} if trade becomes active or {TradeTerminated} if not
     * @param tradeId the identifier returned by inception
     * @param inceptor the original inceptor
     * @param counterparty the original counterparty
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the original position viewed from the inceptor, with unchanged sign
     * @param paymentAmount is the original payment amount viewed from the inceptor, with unchanged sign
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
     function confirmTrade(string memory tradeId, address inceptor, address counterparty, string memory tradeData, int256 position, int256 paymentAmount, string memory initialSettlementData) external;

    /**
     * @notice Performs a matching of provided trade data and settlement data of a previous trade inception.
     * @dev Requires authority for the inceptor and emits a {TradeCanceled} event if all inception terms match.
     * @param tradeId the identifier returned by inception
     * @param inceptor the original inceptor
     * @param counterparty the original counterparty
     * @param tradeData a description of the trade specification e.g. in xml format, suggested structure - see assets/eip-6123/doc/sample-tradedata-filestructure.xml
     * @param position is the position the inceptor has in that trade, may be negative (sell) or positive (buy)
     * @param paymentAmount is the payment amount which can be positive or negative (viewed from the inceptor)
     * @param initialSettlementData the initial settlement data (e.g. initial market data at which trade was incepted)
     */
    function cancelTrade(string memory tradeId, address inceptor, address counterparty, string memory tradeData, int256 position, int256 paymentAmount, string memory initialSettlementData) external;

    /// Trade termination

    /**
     * @notice Called from a counterparty to request a mutual termination
     * @dev Requires authority for the requesting party and emits a {TradeTerminationRequest}.
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param requestingParty the original participant requesting termination
     * @param terminationPayment an agreed termination amount (viewed from the requester)
     * @param terminationTerms the termination terms to be stored on chain.
     */
    function requestTradeTermination(string memory tradeId, address requestingParty, int256 terminationPayment, string memory terminationTerms) external;

    /**
     * @notice Called from a party to confirm an incepted termination, which might trigger a final settlement before trade gets closed
     * @dev Requires authority for the participant opposite the requesting party, matches the complete request and emits a {TradeTerminationConfirmed}.
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param requestingParty the original participant requesting termination
     * @param terminationPayment an agreed termination amount (viewed from the original requester, with unchanged sign)
     * @param terminationTerms the termination terms to be stored on chain.
     */
    function confirmTradeTermination(string memory tradeId, address requestingParty, int256 terminationPayment, string memory terminationTerms) external;

    /**
     * @notice Cancels a pending mutual termination request
     * @dev Requires authority for the requesting party, matches the complete request and emits a {TradeTerminationCanceled}.
     * @param tradeId the trade identifier which is supposed to be terminated
     * @param requestingParty the original participant requesting termination
     * @param terminationPayment an agreed termination amount (viewed from the requester)
     * @param terminationTerms the termination terms
     */
    function cancelTradeTermination(string memory tradeId, address requestingParty, int256 terminationPayment, string memory terminationTerms) external;
}
