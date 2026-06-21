// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @notice Minimal ERC-20 interface used by the settlement router.
 */
interface IERC20RouterToken {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @notice Interface called by a registered single-use atomic swap.
 * @dev Parties approve the implementation of this interface once, rather than
 *      approving every individual swap contract.
 */
interface IAtomicSwapSettlement {
    function settleAtomicSwap(
        address inceptor,
        int256 position,
        int256 paymentAmount
    ) external;
}

/**
 * @title ERC-20 Settlement Router
 * @notice Common ERC-20 spender for factory-created, single-use FX swaps.
 * @dev The underlying ERC-20 sees this router as `msg.sender` when
 *      `transferFrom` is called. Consequently, token holders approve this
 *      router, not each individual swap.
 *
 *      The immutable factory may register swaps together with their fixed
 *      parties and token pair. A registered swap can settle exactly once and
 *      can transfer only between its two registered parties using its two
 *      registered tokens.
 *
 *      This contract is a transfer router/operator, not an ERC-20 token.
 */
contract ERC20SettlementRouter is IAtomicSwapSettlement {
    /**
     * @notice Immutable metadata and one-time status of a registered swap.
     */
    struct SwapAuthorization {
        address baseToken;
        address quoteToken;
        address partyA;
        address partyB;
        bool registered;
        bool settled;
    }

    address public immutable factory;
    mapping(address swap => SwapAuthorization authorization) public swaps;

    bool private locked;

    /**
     * @notice Emitted when the factory authorizes a newly created swap.
     * @param swap Address of the authorized swap.
     * @param baseToken Base-token address fixed for the swap.
     * @param quoteToken Quote-token address fixed for the swap.
     * @param partyA First fixed counterparty.
     * @param partyB Second fixed counterparty.
     */
    event SwapRegistered(
        address indexed swap,
        address indexed baseToken,
        address indexed quoteToken,
        address partyA,
        address partyB
    );

    /**
     * @notice Emitted after both legs requested by a registered swap succeed.
     * @param swap Swap that requested settlement.
     * @param inceptor Party from whose perspective the signed amounts are given.
     * @param counterparty Opposite registered party.
     * @param position Signed base-token amount from the inceptor's perspective.
     * @param paymentAmount Signed quote-token amount from the inceptor's perspective.
     */
    event AtomicSwapSettled(
        address indexed swap,
        address indexed inceptor,
        address indexed counterparty,
        int256 position,
        int256 paymentAmount
    );

    /**
     * @notice Restricts swap registration to the immutable factory.
     */
    modifier onlyFactory() {
        require(msg.sender == factory, "not factory");
        _;
    }

    /**
     * @notice Prevents nested settlement calls while ERC-20 code is executing.
     * @dev There is no check/set race: the EVM executes these instructions
     *      sequentially and no external call occurs between the check and the
     *      assignment. Re-entry becomes possible only later, during `_`, when
     *      `locked` is already `true`.
     */
    modifier nonReentrant() {
        require(!locked, "reentrant");
        locked = true;
        _;
        locked = false;
    }

    /**
     * @notice Creates a common settlement router controlled by one factory.
     * @param factory_ Factory allowed to register its newly deployed swaps.
     */
    constructor(address factory_) {
        require(factory_ != address(0), "zero factory");
        factory = factory_;
    }

    /**
     * @notice Registers the fixed token pair and counterparties of one swap.
     * @dev The factory should call this immediately after deploying the swap.
     *      Registration is permanent; the swap can consume it only once.
     * @param swap Newly deployed swap contract.
     * @param baseToken Base-token address used by the swap.
     * @param quoteToken Quote-token address used by the swap.
     * @param partyA First eligible counterparty.
     * @param partyB Second eligible counterparty.
     */
    function registerSwap(
        address swap,
        address baseToken,
        address quoteToken,
        address partyA,
        address partyB
    ) external onlyFactory {
        require(swap != address(0) && swap.code.length > 0, "bad swap");
        require(baseToken != address(0), "zero base token");
        require(quoteToken != address(0), "zero quote token");
        require(baseToken.code.length > 0, "base token has no code");
        require(quoteToken.code.length > 0, "quote token has no code");
        require(baseToken != quoteToken, "same token");
        require(partyA != address(0) && partyB != address(0), "zero party");
        require(partyA != partyB, "same party");
        require(!swaps[swap].registered, "already registered");

        swaps[swap] = SwapAuthorization({
            baseToken: baseToken,
            quoteToken: quoteToken,
            partyA: partyA,
            partyB: partyB,
            registered: true,
            settled: false
        });

        emit SwapRegistered(swap, baseToken, quoteToken, partyA, partyB);
    }

    /**
     * @notice Executes both legs of one registered single-use FX swap.
     * @dev `msg.sender` must be a registered swap. The router marks that swap as
     *      settled before calling either token, so re-entry cannot consume the
     *      same authorization twice. If either token transfer fails, the whole
     *      transaction reverts, including the first transfer and the `settled`
     *      flag.
     *
     *      The signed amounts follow this convention from `inceptor`'s view:
     *      positive means receive that token; negative means deliver it. Hence
     *      the base and quote amounts must be nonzero and have opposite signs.
     * @param inceptor One of the two registered parties.
     * @param position Signed base-token amount from the inceptor's perspective.
     * @param paymentAmount Signed quote-token amount from the inceptor's perspective.
     */
    function settleAtomicSwap(
        address inceptor,
        int256 position,
        int256 paymentAmount
    ) external override nonReentrant {
        SwapAuthorization storage authorization = swaps[msg.sender];

        require(authorization.registered, "unregistered swap");
        require(!authorization.settled, "already settled");
        require(
            inceptor == authorization.partyA || inceptor == authorization.partyB,
            "bad inceptor"
        );
        require(position != 0 && paymentAmount != 0, "zero leg");
        require(
            position != type(int256).min && paymentAmount != type(int256).min,
            "int min"
        );
        require((position > 0) != (paymentAmount > 0), "same sign");

        address counterparty = inceptor == authorization.partyA
            ? authorization.partyB
            : authorization.partyA;

        // Effects before interactions. A revert restores this flag.
        authorization.settled = true;

        _move(
            IERC20RouterToken(authorization.baseToken),
            inceptor,
            counterparty,
            position
        );
        _move(
            IERC20RouterToken(authorization.quoteToken),
            inceptor,
            counterparty,
            paymentAmount
        );

        emit AtomicSwapSettled(
            msg.sender,
            inceptor,
            counterparty,
            position,
            paymentAmount
        );
    }

    /**
     * @notice Executes one signed token leg from `viewParty`'s perspective.
     * @dev Positive means that `viewParty` receives; negative means that
     *      `viewParty` delivers.
     * @param token ERC-20 token of the leg.
     * @param viewParty Party from whose perspective the amount is signed.
     * @param otherParty Opposite party.
     * @param signedAmount Signed token amount.
     */
    function _move(
        IERC20RouterToken token,
        address viewParty,
        address otherParty,
        int256 signedAmount
    ) private {
        if (signedAmount > 0) {
            _safeTransferFrom(token, otherParty, viewParty, uint256(signedAmount));
        } else {
            _safeTransferFrom(token, viewParty, otherParty, uint256(_neg(signedAmount)));
        }
    }

    /**
     * @notice Calls an ERC-20 `transferFrom` safely across common return styles.
     * @param token ERC-20 token to call.
     * @param from Token owner, who must have approved this router.
     * @param to Token recipient.
     * @param value Amount in the token's smallest units.
     */
    function _safeTransferFrom(
        IERC20RouterToken token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20RouterToken.transferFrom.selector, from, to, value)
        );

        require(
            ok && (data.length == 0 || abi.decode(data, (bool))),
            "transferFrom failed"
        );
    }

    /**
     * @notice Safely negates a signed token amount.
     * @param x Signed amount.
     * @return Negated amount.
     */
    function _neg(int256 x) private pure returns (int256) {
        require(x != type(int256).min, "int min");
        return -x;
    }
}
