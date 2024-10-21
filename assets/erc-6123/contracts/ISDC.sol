// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0 <0.9.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC6123 Smart Derivative Contract
 * @dev Interface specification for a Smart Derivative Contract, which specifies the post-trade live cycle of an OTC financial derivative in a completely deterministic way.
 *
 * A Smart Derivative Contract (SDC) is a deterministic settlement protocol which aims is to remove many inefficiencies in (collateralized) financial transactions.
 * Settlement (Delivery versus payment) and Counterparty Credit Risk are removed by construction.
 *
 * Special Case OTC-Derivatives: In case of a collateralized OTC derivative the SDC nets contract-based and collateral flows . As result, the SDC generates a stream of
 * reflecting the settlement of a referenced underlying. The settlement cash flows may be daily (which is the standard frequency in traditional markets)
 * or at higher frequencies.
 * With each settlement flow the change is the (discounting adjusted) net present value of the underlying contract is exchanged and the value of the contract is reset to zero.
 *
 * To automatically process settlement, parties need to provide sufficient initial funding and termination fees at the
 * beginning of each settlement cycle. Through a settlement cycle the margin amounts are locked. Simplified, the contract reverts the classical scheme of
 * 1) underlying valuation, then 2) funding of a margin call to
 * 1) pre-funding of a margin buffer (a token), then 2) settlement.
 *
 * A SDC may automatically terminates the financial contract if there is insufficient pre-funding or if the settlement amount exceeds a
 * prefunded margin balance. Beyond mutual termination is also intended by the function specification.
 *
 * Events and Functionality specify the entire live cycle: TradeInception, TradeConfirmation, TradeTermination, Margin-Account-Mechanics, Valuation and Settlement.
 *
 * The process can be described by time points and time-intervals which are associated with well defined states:
 * <ol>
 *  <li>t < T* (befrore incept).
 *  </li>
 *  <li>
 *      The process runs in cycles. Let i = 0,1,2,... denote the index of the cycle. Within each cycle there are times
 *      T_{i,0}, T_{i,1}, T_{i,2}, T_{i,3} with T_{i,1} = The Activation of the Trade (initial funding provided), T_{i,1} = request valuation from oracle, T_{i,2} = perform settlement on given valuation, T_{i+1,0} = T_{i,3}.
 *  </li>
 *  <li>
 *      Given this time discretization the states are assigned to time points and time intervalls:
 *      <dl>
 *          <dt>Idle</dt>
 *          <dd>Before incept or after terminate</dd>
 *
 *          <dt>Initiation</dt>
 *          <dd>T* < t < T_{0}, where T* is time of incept and T_{0} = T_{0,0}</dd>
 *
 *          <dt>InTransfer (Initiation Phase)</dt>
 *          <dd>T_{i,0} < t < T_{i,1}</dd>
 *
 *          <dt>Settled</dt>
 *          <dd>t = T_{i,1}</dd>
 *
 *          <dt>ValuationAndSettlement</dt>
 *          <dd>T_{i,1} < t < T_{i,2}</dd>
 *
 *          <dt>InTransfer (Settlement Phase)</dt>
 *          <dd>T_{i,2} < t < T_{i,3}</dd>
 *
 *          <dt>Settled</dt>
 *          <dd>t = T_{i,3}</dd>
 *      </dl>
 *  </li>
 * </ol>
 */

interface ISDC {

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
    event SettlementEvaluated(address initiator, int256 settlementAmount, string settlementData);

    /**
     * @dev Emitted when settlement process has been finished
     */
    event SettlementTransferred(string transactionData);

    /**
     * @dev Emitted when settlement process has been finished
     */
    event SettlementFailed(string transactionData);

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

    /// Settlement Cycle: Settlement

    /**
     * @notice Called to trigger a (maybe external) valuation of the underlying contract and afterwards the according settlement process
     * @dev emits a {SettlementRequested}
     */
    function initiateSettlement() external;

    /**
     * @notice Called to trigger according settlement on chain-balances callback for initiateSettlement() event handler
     * @dev perform settlement checks, may initiate transfers and emits {SettlementEvaluated}
     * @param settlementAmount the settlement amount. If settlementAmount > 0 then receivingParty receives this amount from other party. If settlementAmount < 0 then other party receives -settlementAmount from receivingParty.
     * @param settlementData. the tripple (product, previousSettlementData, settlementData) determines the settlementAmount.
     */
    function performSettlement(int256 settlementAmount, string memory settlementData) external;


    /**
     * @notice May get called from outside to to finish a transfer (callback). The trade decides on how to proceed based on success flag
     * @param success tells the protocol whether transfer was successful
     * @param transactionData data associtated with the transfer, will be emitted via the events.
     * @dev emit a {SettlementTransferred} or a {SettlementFailed} event. May emit a {TradeTerminated} event.
     */
    function afterTransfer(bool success, string memory transactionData) external;

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
