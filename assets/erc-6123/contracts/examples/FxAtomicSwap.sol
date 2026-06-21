// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ISDCTrade.sol";

/**
 * @notice Minimal ERC-20 interface used by the swap.
 * @dev The implementation deliberately supports both ERC-20 tokens that return
 *      `true` and older tokens that return no data from `transferFrom`.
 */
interface IERC20Like {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @notice Interface for exposing an XML template of the contract state.
 */
interface IXMLRepresentableState {
    function stateXmlTemplate() external view returns (string memory);
}

/**
 * @title FX Atomic Swap
 * @notice Single-use payment-versus-payment exchange of two ERC-20 tokens.
 * @dev The two signed amounts are specified at inception and matched from the
 *      opposite perspective at confirmation. Confirmation transfers both legs
 *      in one EVM transaction. If either transfer fails, the entire transaction,
 *      including the first transfer and all state changes, is reverted.
 *
 *      This direct-transfer variant requires each party to approve this swap
 *      contract for the token that the party may have to deliver.
 */
contract FxAtomicSwap is ISDCTrade, IXMLRepresentableState {
    /**
     * @notice Lifecycle of this single-use swap.
     */
    enum Phase {
        Created,
        Incepted,
        Settled,
        Canceled
    }

    IERC20Like public immutable baseToken;
    IERC20Like public immutable quoteToken;
    address public immutable partyA;
    address public immutable partyB;

    Phase public phase;
    address public inceptor;

    // The economic terms are stored from the inceptor's perspective.
    int256 public position;          // Signed base-token amount.
    int256 public paymentAmount;     // Signed quote-token amount.

    string public tradeData;
    string public initialSettlementData;
    bytes32 public termsHash;

    /**
     * @notice Emitted after both ERC-20 transfers have completed successfully.
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
     * @notice Creates one swap for two fixed tokens and two fixed counterparties.
     * @param baseToken_ ERC-20 token represented by `position`.
     * @param quoteToken_ ERC-20 token represented by `paymentAmount`.
     * @param partyA_ First eligible counterparty.
     * @param partyB_ Second eligible counterparty.
     */
    constructor(
        IERC20Like baseToken_,
        IERC20Like quoteToken_,
        address partyA_,
        address partyB_
    ) {
        require(address(baseToken_) != address(0), "zero base token");
        require(address(quoteToken_) != address(0), "zero quote token");
        require(address(baseToken_).code.length > 0, "base token has no code");
        require(address(quoteToken_).code.length > 0, "quote token has no code");
        require(address(baseToken_) != address(quoteToken_), "same token");
        require(partyA_ != address(0) && partyB_ != address(0), "zero party");
        require(partyA_ != partyB_, "same party");

        baseToken = baseToken_;
        quoteToken = quoteToken_;
        partyA = partyA_;
        partyB = partyB_;
    }

    /**
     * @notice Returns the trade identifier within this single-trade contract.
     * @dev The pair `(address(this), tradeId())` uniquely identifies the trade,
     *      so the local identifier can be the constant string `"1"`.
     * @return Local trade identifier.
     */
    function tradeId() public pure returns (string memory) {
        return "1";
    }

    /**
     * @notice Incepts the swap and stores its complete economic terms.
     * @dev `position_` and `paymentAmount_` must have opposite signs because,
     *      from one party's perspective, an FX exchange always consists of one
     *      receivable and one payable:
     *
     *      - `position_ > 0`: receive base token; therefore `paymentAmount_ < 0`
     *        means pay quote token.
     *      - `position_ < 0`: pay base token; therefore `paymentAmount_ > 0`
     *        means receive quote token.
     *
     *      The two absolute amounts jointly define the implied FX rate. No
     *      separate constructor FX rate is required.
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
     * @notice Confirms the stored terms from the counterparty's perspective and
     *         atomically settles both ERC-20 legs.
     * @dev The confirmer must provide the exact negatives of the inceptor's
     *      signed amounts. The phase is changed to `Settled` before either token
     *      is called. Consequently, a token callback cannot re-enter
     *      `confirmTrade`, `cancelTrade`, or `inceptTrade` successfully. There is
     *      therefore no separate reentrancy lock in this contract.
     *
     *      The state change and both token transfers remain atomic: a revert in
     *      either transfer rolls back the phase change and every earlier call in
     *      this transaction.
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

        // Checks-effects-interactions: close the lifecycle before external calls.
        phase = Phase.Settled;

        _move(baseToken, inceptor, msg.sender, position);
        _move(quoteToken, inceptor, msg.sender, paymentAmount);

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

        // This spot swap is final immediately after confirmation and settlement;
        // it does not remain active as a long-lived derivative contract.
        emit TradeTerminated(id, "atomic settlement completed");
    }

    /**
     * @notice Cancels an incepted but not yet confirmed swap.
     * @dev Only the original inceptor can cancel, and all supplied terms must
     *      match the stored inception terms.
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
     * @dev A spot atomic swap is already final immediately after confirmation;
     *      before confirmation, `cancelTrade` is the applicable withdrawal path.
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
     * @notice Returns an XML template mapping contract getters to trade state.
     * @dev The FX rate is represented by the two stored signed leg amounts rather
     *      than by a redundant constructor rate.
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
     * @notice Executes one signed token leg from `viewParty`'s perspective.
     * @dev A positive signed amount is a receivable of `viewParty`, so tokens
     *      move from `otherParty_` to `viewParty`. A negative signed amount is a
     *      payable of `viewParty`, so tokens move in the opposite direction.
     * @param token ERC-20 token of this leg.
     * @param viewParty Party from whose perspective the amount is signed.
     * @param otherParty_ Opposite counterparty.
     * @param amountFromViewParty Signed amount from `viewParty`'s perspective.
     */
    function _move(
        IERC20Like token,
        address viewParty,
        address otherParty_,
        int256 amountFromViewParty
    ) private {
        if (amountFromViewParty > 0) {
            _safeTransferFrom(token, otherParty_, viewParty, uint256(amountFromViewParty));
        } else {
            _safeTransferFrom(token, viewParty, otherParty_, uint256(_neg(amountFromViewParty)));
        }
    }

    /**
     * @notice Calls `transferFrom` and accepts either `true` or empty return data.
     * @dev Reverts when the token call itself fails, returns `false`, or returns
     *      malformed data.
     * @param token ERC-20 token to call.
     * @param from Token owner.
     * @param to Token recipient.
     * @param value Unsigned token amount in smallest units.
     */
    function _safeTransferFrom(
        IERC20Like token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, value)
        );

        require(
            ok && (data.length == 0 || abi.decode(data, (bool))),
            "transferFrom failed"
        );
    }

    /**
     * @notice Checks that the caller and `withParty` are the fixed opposite parties.
     * @param caller Caller to validate.
     * @param withParty Claimed counterparty.
     */
    function _checkParties(address caller, address withParty) private view {
        require(caller == partyA || caller == partyB, "not party");
        require(withParty == _other(caller), "bad withParty");
    }

    /**
     * @notice Checks the economic sign convention of the two FX legs.
     * @dev Both legs must be nonzero and have opposite signs because one party
     *      cannot receive both currencies or pay both currencies in a bilateral
     *      payment-versus-payment exchange.
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
     * @return Keccak-256 hash of both strings with unambiguous ABI encoding.
     */
    function _hashTerms(
        string calldata tradeData_,
        string calldata initialSettlementData_
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(tradeData_, initialSettlementData_));
    }

    /**
     * @notice Safely negates a signed 256-bit amount.
     * @dev `type(int256).min` has no positive counterpart and is therefore
     *      rejected explicitly.
     * @param x Signed amount.
     * @return Negated amount.
     */
    function _neg(int256 x) private pure returns (int256) {
        require(x != type(int256).min, "int min");
        return -x;
    }
}
