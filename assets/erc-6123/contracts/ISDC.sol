// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import "./ISDCTrade.sol";
import "./ISDCSettlement.sol";
import "./IAsyncTransferCallback.sol";

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
 *
 * The ISDC interface is split into three parts: ISDCTrade, ISDCSettlement, IAsyncTransferCallback
 * <dl>
 *  <dd>ISDCTrade</dd>
 *  <dt>Functions related to trade inception, confirmation and termination.</dt>
 *
 *  <dd>ISDCSettlement</dd>
 *  <dt>Functions related to settlement process.</dt>
 *
 *  <dd>ISDCTransferCallback</dd>
 *  <dt>Function representing the callback upon successful (external) transfer (of the settlement amount(s)).</dt>
 * </dl>
 *
 * The IAsyncTransferCallback is associated with the IAsyncTransfer.
 * <dl>
 *  <dd>IAsyncTransferCallback</dd>
 *  <dt>Function representing netted batch transfers (with a callback) tok upon successful (external) transfer (of the settlement amount(s)).</dt>
 * </dl>
 */

interface ISDC is ISDCTrade, ISDCSettlement, IAsyncTransferCallback {

}
