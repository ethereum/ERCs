// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

import "./SDC.sol";
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

contract SDCPledgedBalance is SDC {


    struct MarginRequirement {
        uint256 buffer;
        uint256 terminationFee;
    }

    int256[] private settlementAmounts;
    string[] private settlementData;



    mapping(address => MarginRequirement) private marginRequirements; // Storage of M and P per counterparty address

    constructor(
        address _party1,
        address _party2,
        address _settlementToken,
        uint256 _initialBuffer, // m
        uint256 _initalTerminationFee // p
    ) SDC(_party1,_party2,_settlementToken) {
        marginRequirements[party1] = MarginRequirement(_initialBuffer, _initalTerminationFee);
        marginRequirements[party2] = MarginRequirement(_initialBuffer, _initalTerminationFee);
    }


    function processTradeAfterConfirmation(address upfrontPayer, uint256 upfrontPayment, string memory initialSettlementData) override internal{
        settlementAmounts.push(0);
        settlementData.push(initialSettlementData);
        //uint256 requiredBalanceParty1 = marginRequirementParty1 + (upfrontPayer==party1 ? upfrontPayment : 0);
        //uint256 requiredBalanceParty2 = marginRequirementParty2 + (upfrontPayer==party2 ? upfrontPayment : 0);
        //bool isAvailableParty1 = (settlementToken.balanceOf(party1) >= requiredBalanceParty1) && (settlementToken.allowance(party1, address(this)) >= requiredBalanceParty1);
        //bool isAvailableParty2 = (settlementToken.balanceOf(party2) >= requiredBalanceParty2) && (settlementToken.allowance(party2, address(this)) >= requiredBalanceParty2);
        //if (isAvailableParty1 && isAvailableParty2){       // Pre-Conditions: M + P needs to be locked (i.e. pledged)
        address[] memory from = new address[](3);
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        from[0] = party1;       to[0] = address(this);              amounts[0] = uint(marginRequirements[party1].buffer + marginRequirements[party1].terminationFee );
        from[1] = party2;       to[1] = address(this);              amounts[1] = uint(marginRequirements[party2].buffer + marginRequirements[party2].terminationFee );
        from[2] = upfrontPayer; to[2] = otherParty(upfrontPayer);   amounts[2] = upfrontPayment;
        uint256 transactionID = uint256(keccak256(abi.encodePacked(from,to,amounts)));
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);             // Atomic Transfer
    }

    function processTradeAfterMutualTermination(address terminationFeePayer, uint256 terminationAmount, string memory terminationData) override internal{
        address[] memory from = new address[](3);
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        from[0] = address(this);       to[0] = party1;              amounts[0] = uint(marginRequirements[party1].buffer + marginRequirements[party1].terminationFee );  // Release buffers
        from[1] = address(this);       to[1] = party2;              amounts[1] = uint(marginRequirements[party2].buffer + marginRequirements[party2].terminationFee );  // Release buffers
        from[2] = terminationFeePayer; to[2] = otherParty(terminationFeePayer);   amounts[2] = terminationAmount;
        uint256 transactionID = uint256(keccak256(abi.encodePacked(from,to,amounts)));
        setTradeState(TradeState.InTermination);
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);

    }

    /*
     * Settlement can be initiated when margin accounts are locked, a valuation request event is emitted containing tradeData and valuationViewParty
     * Changes Process State to Valuation&Settlement
     * can be called only when ProcessState = Rebalanced and TradeState = Active
     */
    function initiateSettlement() external override onlyCounterparty onlyWhenSettled {
        address initiator = msg.sender;
        setTradeState(TradeState.Valuation);
        emit TradeSettlementRequest(initiator, tradeData, settlementData[settlementData.length - 1]);
    }

    /*
     * Performs a settelement only when processState is ValuationAndSettlement
     * Puts process state to "inTransfer"
     * Checks Settlement amount according to valuationViewParty: If SettlementAmount is > 0, valuationViewParty receives
     * can be called only when ProcessState = ValuationAndSettlement
     */

    function performSettlement(int256 settlementAmount, string memory _settlementData) onlyWhenValuation external override {

        settlementData.push(_settlementData);
        settlementAmounts.push(settlementAmount);

        uint256 transferAmount;
        address settlementPayer;
        (settlementPayer, transferAmount) = determineTransferAmountAndPayerAddress(settlementAmount);

        //if (settlementToken.balanceOf(settlementPayer) >= transferAmount ) { /* Good case: Balances are sufficient and token has enough approval */
        uint256 transactionID = uint256(keccak256(abi.encodePacked(settlementPayer,otherParty(settlementPayer), transferAmount)));
        address[] memory from = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        from[0] = settlementPayer; to[0] = otherParty(settlementPayer); amounts[0] = transferAmount;
        emit TradeSettlementPhase();
        setTradeState(TradeState.InTransfer);
        settlementToken.checkedBatchTransferFrom(from,to,amounts,transactionID);
    }

    function determineTransferAmountAndPayerAddress(int256 settlementAmount) internal view returns(address, uint256)  {
        address settlementReceiver = settlementAmount > 0 ? receivingParty : otherParty(receivingParty);
        address settlementPayer = otherParty(settlementReceiver);

        uint256 transferAmount;
        if (settlementAmount > 0)
            transferAmount = uint256(abs(min( settlementAmount, int(marginRequirements[settlementPayer].buffer))));
        else
            transferAmount = uint256(abs(max( settlementAmount, -int(marginRequirements[settlementReceiver].buffer))));

        return (settlementPayer,transferAmount);
    }

    function afterTransfer(uint256 /* transactionHash */, bool success) external override  {
        require(getTradeState() == TradeState.InTransfer || getTradeState() == TradeState.Confirmed || getTradeState() == TradeState.InTermination, "Wrong TradeState");
        if ( getTradeState() == TradeState.Confirmed){
            if (success){
                setTradeState(TradeState.Settled);
                emit TradeActivated(getTradeID());
            }
            else{
                setTradeState(TradeState.Terminated);
                emit TradeTerminated("Upfront Transfer Failure");
            }
        }
        if ( getTradeState() == TradeState.InTransfer){
            if (success){
                setTradeState(TradeState.Settled);
                emit TradeSettled();
            }
            else{  // Settlement & Pledge Case: transferAmount is transferred from SDC balance (i.e. pledged balance).
                int256 settlementAmount = settlementAmounts[settlementAmounts.length-1];
                uint256 transferAmount;
                address settlementPayer;
                (settlementPayer, transferAmount)  = determineTransferAmountAndPayerAddress(settlementAmount);
                address settlementReceiver = otherParty(settlementPayer);
                address[] memory to = new address[](2);
                uint256[] memory amounts = new uint256[](2);
                to[0] = settlementReceiver; amounts[0] = uint256(transferAmount);
                to[1] = settlementReceiver; amounts[1] = uint256(marginRequirements[settlementPayer].terminationFee);
                uint256 transactionID = uint256(keccak256(abi.encodePacked(to,amounts)));
                setTradeState( TradeState.InTermination );
                settlementToken.checkedBatchTransfer(to,amounts,transactionID);
            }
        }
        if( getTradeState() == TradeState.InTermination){
            setTradeState(TradeState.Terminated);
            if (success)
                emit TradeTerminated("Trade terminated sucessfully");
            else
                emit TradeTerminated("Trade terminated with failure");
        }
    }
}
