// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ISDCTrade.sol";
import "./ERC20SettlementRouter.sol";

/**
 * @notice Interface for exposing an XML template of the contract state.
 */
interface IXMLRepresentableRoutedState {
    function stateXmlTemplate() external view returns (string memory);
}

/**
 * @title FX Atomic Swap Using a Shared Settlement Router
 * @notice Single-use payment-versus-payment exchange of two ERC-20 tokens.
 * @dev Parties approve the shared `settlementRouter`, not this individual swap.
 *      The factory must register this swap with the router immediately after
 *      deployment using the same fixed token and party configuration.
 */
contract FxAtomicSwapRouted is ISDCTrade, IXMLRepresentableRoutedState {
    /**
     * @notice Lifecycle of this single-use swap.
     */
    enum Phase {
        Created,
        Incepted,
        Settled,
        Canceled
    }

    IERC20RouterToken public immutable baseToken;
    IERC20RouterToken public immutable quoteToken;
    address public immutable partyA;
    address public immutable partyB;
    IAtomicSwapSettlement public immutable settlementRouter;

    Phase public phase;
    address public inceptor;

    // The economic terms are stored from the inceptor's perspective.
    int256 public position;          // Signed base-token amount.
    int256 public paymentAmount;     // Signed quote-token amount.

    string public tradeData;
    string public initialSettlementData;
    bytes32 public termsHash;

    /**
     * @notice Emitted after the shared router has transferred both legs.
     * @param inceptor_ Party that called `inceptTrade`.
     * @param counterparty Party that called `confirmTrade`.
     * @param baseToken_ Address of the base token.
     * @param quoteToken_ Address of the quote token.
     * @param position_ Signed base-token amount from the inceptor's perspective.
     * @param paymentAmount_ Signed quote-token amount from the inceptor's perspective.
     */
    event SwapSettled(
        address indexed inceptor_,
        address indexed counterparty,
        address baseToken_,
        address quoteToken_,
        int256 position_,
        int256 paymentAmount_
    );

    /**
     * @notice Creates one routed swap for fixed tokens and counterparties.
     * @param baseToken_ ERC-20 token represented by `position`.
     * @param quoteToken_ ERC-20 token represented by `paymentAmount`.
     * @param partyA_ First eligible counterparty.
     * @param partyB_ Second eligible counterparty.
     * @param settlementRouter_ Common spender authorized by the factory.
     */
    constructor(
        IERC20RouterToken baseToken_,
        IERC20RouterToken quoteToken_,
        address partyA_,
        address partyB_,
        IAtomicSwapSettlement settlementRouter_
    ) {
        require(address(baseToken_) != address(0), "zero base token");
        require(address(quoteToken_) != address(0), "zero quote token");
        require(address(baseToken_).code.length > 0, "base token has no code");
        require(address(quoteToken_).code.length > 0, "quote token has no code");
        require(address(baseToken_) != address(quoteToken_), "same token");
        require(partyA_ != address(0) && partyB_ != address(0), "zero party");
        require(partyA_ != partyB_, "same party");
        require(address(settlementRouter_) != address(0), "zero router");
        require(address(settlementRouter_).code.length > 0, "router has no code");

        baseToken = baseToken_;
        quoteToken = quoteToken_;
        partyA = partyA_;
        partyB = partyB_;
        settlementRouter = settlementRouter_;
    }

    /**
     * @notice Returns the local identifier of this contract's only trade.
     * @dev `(address(this), "1")` is globally unique.
     * @return Local trade identifier.
     */
    function tradeId() public pure returns (string memory) {
        return "1";
    }

    /**
     * @notice Incepts the swap and stores its complete economic terms.
     * @dev The sign condition expresses payment-versus-payment from the
     *      inceptor's perspective:
     *
     *      - positive `position_`: receive base; negative `paymentAmount_`: pay quote;
     *      - negative `position_`: pay base; positive `paymentAmount_`: receive quote.
     *
     *      Thus both legs must be nonzero and have opposite signs. Their two
     *      absolute amounts jointly determine the implied FX rate; no separate
     *      constructor rate is necessary.
     * @param withParty Counterparty to the inceptor.
     * @param tradeData_ Trade description, for example XML.
     * @param position_ Signed base-token amount from `msg.sender`'s perspective.
     * @param paymentAmount_ Signed quote-token amount from `msg.sender`'s perspective.
     * @param initialSettlementData_ Initial settlement or market data.
     * @return id Local trade identifier.
     */
    function inceptTrade(
        address withParty,
        string calldata tradeData_,
        int256 position_,
        int256 paymentAmount_,
        string calldata initialSettlementData_
    ) external override returns (string memory id) {
        require(phase == Phase.Created, "not created");
        _checkParties(msg.sender, withParty);
        _checkLegs(position_, paymentAmount_);

        inceptor = msg.sender;
        position = position_;
        paymentAmount = paymentAmount_;
        tradeData = tradeData_;
        initialSettlementData = initialSettlementData_;
        termsHash = _hashTerms(tradeData_, initialSettlementData_);
        phase = Phase.Incepted;

        id = tradeId();
        emit TradeIncepted(
            msg.sender,
            withParty,
            id,
            tradeData_,
            position_,
            paymentAmount_,
            initialSettlementData_
        );
    }

    /**
     * @notice Confirms matching terms and asks the common router to settle both legs.
     * @dev The confirmer supplies the exact negatives of the inceptor's signed
     *      amounts. The phase is set to `Settled` before the external router call,
     *      so a callback cannot successfully re-enter any lifecycle-changing
     *      method. A router or token failure reverts the whole transaction.
     * @param withParty Must be the original inceptor.
     * @param tradeData_ Trade description, which must match inception.
     * @param position_ Signed base-token amount from the confirmer's perspective.
     * @param paymentAmount_ Signed quote-token amount from the confirmer's perspective.
     * @param initialSettlementData_ Settlement data, which must match inception.
     */
    function confirmTrade(
        address withParty,
        string calldata tradeData_,
        int256 position_,
        int256 paymentAmount_,
        string calldata initialSettlementData_
    ) external override {
        require(phase == Phase.Incepted, "not incepted");
        require(msg.sender == _other(inceptor), "not confirmer");
        require(withParty == inceptor, "bad withParty");

        require(position_ == _neg(position), "position mismatch");
        require(paymentAmount_ == _neg(paymentAmount), "payment mismatch");
        require(
            termsHash == _hashTerms(tradeData_, initialSettlementData_),
            "terms mismatch"
        );

        // Checks-effects-interactions. Reverts restore this assignment.
        phase = Phase.Settled;

        settlementRouter.settleAtomicSwap(inceptor, position, paymentAmount);

        string memory id = tradeId();
        emit TradeConfirmed(msg.sender, id);
        emit SwapSettled(
            inceptor,
            msg.sender,
            address(baseToken),
            address(quoteToken),
            position,
            paymentAmount
        );
        emit TradeTerminated(id, "atomic settlement completed");
    }

    /**
     * @notice Cancels an incepted but not yet confirmed swap.
     * @dev Only the inceptor may cancel and all terms must match inception.
     * @param withParty Must be the other fixed counterparty.
     * @param tradeData_ Trade description, which must match inception.
     * @param position_ Signed base-token amount from the inceptor's perspective.
     * @param paymentAmount_ Signed quote-token amount from the inceptor's perspective.
     * @param initialSettlementData_ Settlement data, which must match inception.
     */
    function cancelTrade(
        address withParty,
        string calldata tradeData_,
        int256 position_,
        int256 paymentAmount_,
        string calldata initialSettlementData_
    ) external override {
        require(phase == Phase.Incepted, "not incepted");
        require(msg.sender == inceptor, "not inceptor");
        require(withParty == _other(inceptor), "bad withParty");

        require(position_ == position, "position mismatch");
        require(paymentAmount_ == paymentAmount, "payment mismatch");
        require(
            termsHash == _hashTerms(tradeData_, initialSettlementData_),
            "terms mismatch"
        );

        phase = Phase.Canceled;
        emit TradeCanceled(msg.sender, tradeId());
    }

    /**
     * @notice Rejects an early-termination request.
     * @dev Before confirmation the inceptor uses `cancelTrade`; after confirmation
     *      the one-shot swap is already settled and final.
     * @dev All interface arguments are intentionally ignored.
     */
    function requestTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert("termination not supported");
    }

    /**
     * @notice Rejects confirmation of an early-termination request.
     * @dev See `requestTradeTermination`.
     * @dev All interface arguments are intentionally ignored.
     */
    function confirmTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert("termination not supported");
    }

    /**
     * @notice Rejects cancellation of an early-termination request.
     * @dev See `requestTradeTermination`.
     * @dev All interface arguments are intentionally ignored.
     */
    function cancelTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert("termination not supported");
    }

    /**
     * @notice Returns an XML template mapping getters to contract state.
     * @dev The template exposes the common settlement router and represents the
     *      implied FX rate through the two matched signed amounts.
     * @return XML state template.
     */
    function stateXmlTemplate() external pure override returns (string memory) {
        return string.concat(
            "<FxAtomicSwap xmlns='urn:example:fx-atomic-swap' ",
            "xmlns:evmstate='urn:evm:state:1.0' ",
            "evmstate:chain-id='' evmstate:contract-address='' evmstate:block-number=''>",

            "<Lifecycle>",
            "<TradeId evmstate:call='tradeId()(string)' evmstate:format='string'/>",
            "<Phase evmstate:call='phase()(uint8)' evmstate:format='decimal'/>",
            "<PhaseMeaning>0=Created,1=Incepted,2=Settled,3=Canceled</PhaseMeaning>",
            "<Inceptor evmstate:call='inceptor()(address)' evmstate:format='address'/>",
            "</Lifecycle>",

            "<Parties>",
            "<Party role='A' evmstate:call='partyA()(address)' evmstate:format='address'/>",
            "<Party role='B' evmstate:call='partyB()(address)' evmstate:format='address'/>",
            "</Parties>",

            "<Tokens>",
            "<Token role='base' evmstate:call='baseToken()(address)' evmstate:format='address'/>",
            "<Token role='quote' evmstate:call='quoteToken()(address)' evmstate:format='address'/>",
            "</Tokens>",

            "<Settlement>",
            "<Router evmstate:call='settlementRouter()(address)' evmstate:format='address'/>",
            "</Settlement>",

            "<InceptedTerms view='inceptor'>",
            "<Position token='base' unit='smallest-token-unit' ",
            "evmstate:call='position()(int256)' evmstate:format='decimal'/>",
            "<PaymentAmount token='quote' unit='smallest-token-unit' ",
            "evmstate:call='paymentAmount()(int256)' evmstate:format='decimal'/>",
            "<TradeData evmstate:call='tradeData()(string)' evmstate:format='string'/>",
            "<InitialSettlementData ",
            "evmstate:call='initialSettlementData()(string)' ",
            "evmstate:format='string'/>",
            "<TermsHash evmstate:call='termsHash()(bytes32)' evmstate:format='hex'/>",
            "</InceptedTerms>",

            "</FxAtomicSwap>"
        );
    }

    /**
     * @notice Checks that caller and `withParty` are the fixed opposite parties.
     * @param caller Caller to validate.
     * @param withParty Claimed counterparty.
     */
    function _checkParties(address caller, address withParty) private view {
        require(caller == partyA || caller == partyB, "not party");
        require(withParty == _other(caller), "bad withParty");
    }

    /**
     * @notice Checks that the FX legs are nonzero and have opposite signs.
     * @param position_ Signed base-token amount.
     * @param paymentAmount_ Signed quote-token amount.
     */
    function _checkLegs(int256 position_, int256 paymentAmount_) private pure {
        require(position_ != 0 && paymentAmount_ != 0, "zero leg");
        require(
            position_ != type(int256).min && paymentAmount_ != type(int256).min,
            "int min"
        );
        require((position_ > 0) != (paymentAmount_ > 0), "same sign");
    }

    /**
     * @notice Returns the other fixed counterparty.
     * @param party One of the two fixed counterparties.
     * @return Opposite counterparty.
     */
    function _other(address party) private view returns (address) {
        if (party == partyA) return partyB;
        if (party == partyB) return partyA;
        revert("not party");
    }

    /**
     * @notice Hashes the non-amount trade terms used during matching.
     * @param tradeData_ Trade description.
     * @param initialSettlementData_ Initial settlement data.
     * @return Keccak-256 hash of both strings.
     */
    function _hashTerms(
        string calldata tradeData_,
        string calldata initialSettlementData_
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(tradeData_, initialSettlementData_));
    }

    /**
     * @notice Safely negates a signed 256-bit amount.
     * @param x Signed amount.
     * @return Negated amount.
     */
    function _neg(int256 x) private pure returns (int256) {
        require(x != type(int256).min, "int min");
        return -x;
    }
}
