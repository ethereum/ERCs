// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

import "./SDCSingleTrade.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ERC20Settlement.sol";


/**
 * @title Reference Implementation of ERC6123 - Smart Derivative Contract
 * @notice This reference implementation is based on a finite state machine with predefined trade and process states (see enums below)
 * Some comments on the implementation:
 * - trade and process states are used in modifiers to check which function is able to be called at which state
 * - trade data are stored in the contract
 * - trade data matching is done in incept and confirm routine (comparing the hash of the provided data)
 * - ERC-20 token is used for three participants: counterparty1 and counterparty2 and sdc
 * - when prefunding is done sdc contract will hold agreed amounts and perform settlement on those
 * - sdc also keeps track on internal balances for each counterparty
 * - during prefunding sdc will transfer required amounts to its own balance - therefore sufficient approval is needed
 * - upon termination all remaining 'locked' amounts will be transferred back to the counterparties
 *------------------------------------*
     * Setup with Pledge Account
     *
     *  Settlement:
     *  _bookSettlement
     *      Update internal balances
     *      Message
     *  Rebalance:
     *      Book Party2 -> Party1:   X
     *      Rebalance Check
     *          Failed
     *              Book SDC -> Party1:   X
     *              Terminate
 *-------------------------------------*
*/

contract SDCSingleTradePledgedBalance is SDCSingleTrade {

    struct MarginRequirement {
        uint256 buffer;
        uint256 terminationFee;
    }

    mapping(address => MarginRequirement) private marginRequirements; // Storage of M and P per counterparty address

    int256[] private settlementAmounts;
    string[] private settlementData;

    constructor(
        address _party1,
        address _party2,
        address _settlementToken,
        uint256 _initialBuffer,         // m
        uint256 _initalTerminationFee   // p
    ) SDCSingleTrade(_party1,_party2,_settlementToken) {
        marginRequirements[party1] = MarginRequirement(_initialBuffer, _initalTerminationFee);
        marginRequirements[party2] = MarginRequirement(_initialBuffer, _initalTerminationFee);
    }


    /*
     * Settlement can be initiated when margin accounts are locked, a valuation request event is emitted containing tradeData and valuationViewParty
     * Changes Process State to Valuation&Settlement
     * can be called only when ProcessState = Rebalanced and TradeState = Active
     */
    function initiateSettlement() external override onlyCounterparty onlyWhenSettled {
        address initiator = msg.sender;
        setTradeState(TradeState.Valuation);
        emit SettlementRequested(initiator, tradeData, settlementData[settlementData.length - 1]);
    }

    /*
     * Performs a settelement only when processState is ValuationAndSettlement
     * Puts process state to "inTransfer"
     * Checks Settlement amount according to valuationViewParty: If SettlementAmount is > 0, valuationViewParty receives
     * can be called only when ProcessState = ValuationAndSettlement
     */
    function performSettlement(int256 settlementAmount, string memory _settlementData) onlyWhenValuation external override {
        (address settlementPayer,uint256 transferAmount) = determineTransferAmountAndPayerAddress(settlementAmount);
        int cappedSettlementAmount = settlementPayer == receivingParty ? -int256(transferAmount) : int256(transferAmount);
        settlementData.push(_settlementData);
        settlementAmounts.push(cappedSettlementAmount); // save the capped settlement amount
        uint256 transactionID = uint256(keccak256(abi.encodePacked(settlementPayer,otherParty(settlementPayer), transferAmount, block.timestamp)));
        address[] memory from = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        from[0] = settlementPayer; to[0] = otherParty(settlementPayer); amounts[0] = transferAmount;
        emit SettlementEvaluated(msg.sender, settlementAmount, _settlementData);
        setTradeState(TradeState.InTransfer);
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);
    }

    /*
    * afterTransfer processes SDC depending on success of the respective payment and depending on the current trade state
    * Good Case: state will be settled, failed settlement will trigger the pledge balance transfer and termination
    */
    function afterTransfer(bool success, string memory transactionHash) external override  {
        if ( inStateConfirmed()){
            if (success){
                setTradeState(TradeState.Settled);
                emit TradeActivated(getTradeID());
            }
            else{
                setTradeState(TradeState.Terminated);
                emit TradeTerminated(tradeID, "Upfront Transfer Failure");
            }
        }
        else if ( inStateTransfer() ){
            if (success){
                setTradeState(TradeState.Settled);
                emit SettlementTransferred("Settlement Settled - Pledge Transfer");
            }
            else{  // Settlement & Pledge Case: transferAmount is transferred from SDC balance (i.e. pledged balance).
                int256 settlementAmount = settlementAmounts[settlementAmounts.length-1];
                setTradeState(TradeState.InTermination);
                processTerminationWithPledge(settlementAmount);
                emit TradeTerminated(tradeID, "Settlement Failed - Pledge Transfer");
            }
        }
        else if( inStateTermination() ){
            if (success){
                setTradeState(TradeState.Terminated);
                emit TradeTerminated(tradeID, "Trade terminated sucessfully");
            }
            else{
                emit TradeTerminated(tradeID, "Mutual Termination failed - Pledge Transfer");
                processTerminationWithPledge(getTerminationPayment());
            }
        }
        else
            revert("Trade State does not allow to call 'afterTransfer'");
    }

    /*
    * internal function which determines the capped settlement amount and poyer address
    */
    function determineTransferAmountAndPayerAddress(int256 settlementAmount) internal view returns(address, uint256)  {
        address settlementReceiver = settlementAmount > 0 ? receivingParty : otherParty(receivingParty);
        address settlementPayer = otherParty(settlementReceiver);

        uint256 transferAmount;
        if (settlementAmount > 0)
            transferAmount = uint256(abs(min( settlementAmount, int256(marginRequirements[settlementPayer].buffer))));
        else
            transferAmount = uint256(abs(max( settlementAmount, -int256(marginRequirements[settlementReceiver].buffer))));

        return (settlementPayer,transferAmount);
    }

    /*
     * internal function which pepares the settlement tranfer after confirmation.
     * Batched Transfer consists of Upfront Payment and Initial Prefunding to SDC Address
     */

    function processTradeAfterConfirmation(address upfrontPayer, uint256 upfrontPayment, string memory initialSettlementData) override internal{
        settlementAmounts.push(0);
        settlementData.push(initialSettlementData);
        address[] memory from = new address[](3);
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        from[0] = party1;       to[0] = address(this);              amounts[0] = uint(marginRequirements[party1].buffer + marginRequirements[party1].terminationFee );
        from[1] = party2;       to[1] = address(this);              amounts[1] = uint(marginRequirements[party2].buffer + marginRequirements[party2].terminationFee );
        from[2] = upfrontPayer; to[2] = otherParty(upfrontPayer);   amounts[2] = upfrontPayment;
        uint256 transactionID = uint256(keccak256(abi.encodePacked(from,to,amounts)));
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);      // Batched Transfer
    }

    /*
     * internal function which processes mutual termination, transfers termination payment and releases pledged balances from sdc address
     */
    function processTradeAfterMutualTermination(address terminationFeePayer, uint256 terminationAmount, string memory terminationData) override internal{
        settlementAmounts.push(0); // termination payment is saved separately
        settlementData.push(terminationData);
        address[] memory from = new address[](3);
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        from[0] = address(this);       to[0] = party1;              amounts[0] = uint(marginRequirements[party1].buffer + marginRequirements[party1].terminationFee );  // Release buffers
        from[1] = address(this);       to[1] = party2;              amounts[1] = uint(marginRequirements[party2].buffer + marginRequirements[party2].terminationFee );  // Release buffers
        from[2] = terminationFeePayer; to[2] = otherParty(terminationFeePayer);   amounts[2] = terminationAmount;
        uint256 transactionID = uint256(keccak256(abi.encodePacked(from,to,amounts)));
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);    // Batched Transfer
    }

    /* function which perfoms the "Pledged Booking" in case of failed settlement, transferring open settlement amount as well as termination fee from sdc's own balance
    */
    function processTerminationWithPledge(int256 settlementAmount) internal{
        (address settlementPayer, uint256 transferAmount)  = determineTransferAmountAndPayerAddress(settlementAmount);
        address settlementReceiver = otherParty(settlementPayer);
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        to[0] = settlementReceiver; amounts[0] = transferAmount+marginRequirements[settlementPayer].terminationFee; // Settlement from Own Balance
        to[1] = settlementReceiver; amounts[1] = marginRequirements[settlementReceiver].terminationFee + marginRequirements[settlementReceiver].buffer; // Release
        to[2] = settlementPayer; amounts[2] = marginRequirements[settlementPayer].buffer-transferAmount; // Release of Buffer
        uint256 transactionID = uint256(keccak256(abi.encodePacked(to,amounts)));
        settlementToken.checkedBatchTransfer(to,amounts,transactionID);
    }

}
