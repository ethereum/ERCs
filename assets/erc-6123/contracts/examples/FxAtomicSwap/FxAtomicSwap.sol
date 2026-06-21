// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ISDCTrade.sol";
import "./ERC20SettlementRouter.sol";

/**
 * @notice Interface for exposing an ERC-8100-style XML state template.
 */
interface IXMLRepresentableState {
    function stateXmlTemplate() external view returns (string memory);
}

/**
 * @title FX Atomic Swap
 * @notice Single-use payment-versus-payment exchange of two ERC-20 tokens.
 * @dev Parties approve the shared settlement router, not this individual swap.
 *      The factory creates and registers the swap atomically.
 */
contract FxAtomicSwap is ISDCTrade, IXMLRepresentableState {
    enum Phase {
        Created,
        Incepted,
        Settled,
        Canceled
    }

    error InvalidPhase();
    error InvalidToken();
    error InvalidParty();
    error InvalidRouter();
    error InvalidLegs();
    error TermsMismatch();
    error TerminationNotSupported();

    IERC20RouterToken public immutable baseToken;
    IERC20RouterToken public immutable quoteToken;
    address public immutable partyA;
    address public immutable partyB;
    IAtomicSwapSettlement public immutable settlementRouter;

    // `phase` and `inceptor` are packed into one storage slot.
    Phase public phase;
    address public inceptor;

    // Economic terms are stored from the inceptor's perspective.
    int256 public position;
    int256 public paymentAmount;
    string public tradeData;
    string public initialSettlementData;

    /**
     * @notice Creates one swap for fixed tokens, counterparties, and router.
     * @param baseToken_ ERC-20 token represented by `position`.
     * @param quoteToken_ ERC-20 token represented by `paymentAmount`.
     * @param partyA_ First eligible counterparty.
     * @param partyB_ Second eligible counterparty.
     * @param settlementRouter_ Common spender authorized by both parties.
     */
    constructor(
        IERC20RouterToken baseToken_,
        IERC20RouterToken quoteToken_,
        address partyA_,
        address partyB_,
        IAtomicSwapSettlement settlementRouter_
    ) {
        if (
            address(baseToken_) == address(0)
                || address(quoteToken_) == address(0)
                || address(baseToken_) == address(quoteToken_)
                || address(baseToken_).code.length == 0
                || address(quoteToken_).code.length == 0
        ) revert InvalidToken();

        if (
            partyA_ == address(0)
                || partyB_ == address(0)
                || partyA_ == partyB_
        ) revert InvalidParty();

        if (
            address(settlementRouter_) == address(0)
                || address(settlementRouter_).code.length == 0
        ) revert InvalidRouter();

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
     * @notice Incepts the swap and stores its economic and textual terms.
     * @dev Sign convention from the inceptor's perspective:
     *
     *      - `position > 0`, `paymentAmount < 0`: receive base and pay quote;
     *      - `position < 0`, `paymentAmount > 0`: pay base and receive quote.
     *
     *      Both legs must therefore be nonzero and have opposite signs. Their
     *      absolute amounts jointly define the implied FX rate.
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
        if (phase != Phase.Created) revert InvalidPhase();
        if (withParty != _other(msg.sender)) revert InvalidParty();
        _checkLegs(position_, paymentAmount_);

        inceptor = msg.sender;
        position = position_;
        paymentAmount = paymentAmount_;
        tradeData = tradeData_;
        initialSettlementData = initialSettlementData_;
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
     * @notice Confirms matching terms and atomically settles both token legs.
     * @dev The confirmer supplies the exact negatives of the inceptor's signed
     *      amounts. `phase` is changed before the external router call; a failure
     *      in the router or either token reverts the entire transaction.
     * @param withParty Must be the original inceptor.
     * @param tradeData_ Trade description, which must match inception.
     * @param position_ Negated base-token amount from the confirmer's perspective.
     * @param paymentAmount_ Negated quote-token amount from the confirmer's perspective.
     * @param initialSettlementData_ Settlement data, which must match inception.
     */
    function confirmTrade(
        address withParty,
        string calldata tradeData_,
        int256 position_,
        int256 paymentAmount_,
        string calldata initialSettlementData_
    ) external override {
        if (phase != Phase.Incepted) revert InvalidPhase();
        if (msg.sender != _other(inceptor) || withParty != inceptor) {
            revert InvalidParty();
        }
        if (position_ != -position || paymentAmount_ != -paymentAmount) {
            revert TermsMismatch();
        }
        if (
            _hashTerms(tradeData_, initialSettlementData_)
                != _hashTerms(tradeData, initialSettlementData)
        ) {
            revert TermsMismatch();
        }

        // Checks-effects-interactions. A revert restores this assignment.
        phase = Phase.Settled;

        settlementRouter.settleAtomicSwap(
            baseToken,
            quoteToken,
            inceptor,
            msg.sender,
            position,
            paymentAmount
        );

        string memory id = tradeId();
        emit TradeConfirmed(msg.sender, id);
        emit TradeTerminated(id, "atomic settlement completed");
    }

    /**
     * @notice Cancels an incepted swap before confirmation.
     * @dev Only the inceptor may cancel and all supplied terms must match.
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
        if (phase != Phase.Incepted) revert InvalidPhase();
        if (msg.sender != inceptor || withParty != _other(inceptor)) {
            revert InvalidParty();
        }
        if (position_ != position || paymentAmount_ != paymentAmount) {
            revert TermsMismatch();
        }
        if (
            _hashTerms(tradeData_, initialSettlementData_)
                != _hashTerms(tradeData, initialSettlementData)
        ) {
            revert TermsMismatch();
        }

        phase = Phase.Canceled;
        emit TradeCanceled(msg.sender, tradeId());
    }

    /**
     * @notice Rejects early termination because an unconfirmed swap is canceled
     *         through `cancelTrade` and a confirmed swap is already final.
     */
    function requestTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert TerminationNotSupported();
    }

    /**
     * @notice Rejects confirmation of an unsupported termination request.
     */
    function confirmTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert TerminationNotSupported();
    }

    /**
     * @notice Rejects cancellation of an unsupported termination request.
     */
    function cancelTradeTermination(
        string memory,
        int256,
        string memory
    ) external pure override {
        revert TerminationNotSupported();
    }

    /**
     * @notice Returns the static XML template used to render the contract state.
     * @return XML template with bindings to the semantically relevant state.
     */
    function stateXmlTemplate() external pure override returns (string memory) {
        return string.concat(
            "<FxAtomicSwap xmlns='urn:example:fx-atomic-swap' ",
            "xmlns:evmstate='urn:evm:state:1.0' ",
            "evmstate:chain-id='' evmstate:contract-address='' evmstate:block-number=''>",
            "<Lifecycle>",
            "<TradeId>1</TradeId>",
            "<Phase evmstate:call='phase()(uint8)' evmstate:format='decimal'/>",
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
            "<SettlementRouter evmstate:call='settlementRouter()(address)' evmstate:format='address'/>",
            "<Terms view='inceptor'>",
            "<Position token='base' unit='smallest-token-unit' ",
            "evmstate:call='position()(int256)' evmstate:format='decimal'/>",
            "<PaymentAmount token='quote' unit='smallest-token-unit' ",
            "evmstate:call='paymentAmount()(int256)' evmstate:format='decimal'/>",
            "<TradeData evmstate:call='tradeData()(string)' evmstate:format='string'/>",
            "<InitialSettlementData evmstate:call='initialSettlementData()(string)' ",
            "evmstate:format='string'/>",
            "</Terms>",
            "</FxAtomicSwap>"
        );
    }

    /**
     * @notice Checks that both signed legs are valid for payment-versus-payment.
     * @param position_ Signed base-token amount.
     * @param paymentAmount_ Signed quote-token amount.
     */
    function _checkLegs(int256 position_, int256 paymentAmount_) private pure {
        if (
            position_ == 0
                || paymentAmount_ == 0
                || position_ == type(int256).min
                || paymentAmount_ == type(int256).min
                || (position_ > 0) == (paymentAmount_ > 0)
        ) revert InvalidLegs();
    }

    /**
     * @notice Returns the fixed counterparty opposite `party`.
     * @param party One of the two fixed counterparties.
     * @return Opposite counterparty.
     */
    function _other(address party) private view returns (address) {
        if (party == partyA) return partyB;
        if (party == partyB) return partyA;
        revert InvalidParty();
    }

    /**
     * @notice Hashes the two textual fields used for confirmation matching.
     * @param tradeData_ Trade description.
     * @param initialSettlementData_ Initial settlement data.
     * @return Keccak-256 commitment to both strings.
     */
    function _hashTerms(
        string memory tradeData_,
        string memory initialSettlementData_
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(tradeData_, initialSettlementData_));
    }
}
