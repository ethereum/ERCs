// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @notice Minimal ERC-20 interface used by the settlement router.
 */
interface IERC20RouterToken {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @notice Common settlement interface called by factory-created FX trades.
 */
interface IPvPSettlement {
    function settlePvP(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address inceptor,
        address counterparty,
        int256 position,
        int256 paymentAmount
    ) external;
}

/**
 * @title ERC-20 PvP Settlement Router
 * @notice Common ERC-20 spender for all trades created by one factory.
 * @dev Token holders approve this router once. The router stores only whether a
 *      factory-created trade still has an unused settlement authorization. The
 *      immutable trade itself is the source of its tokens, parties, and amounts.
 */
contract ERC20PvPSettlementRouter is IPvPSettlement {
    error InvalidFactory();
    error InvalidTrade();
    error NotFactory();
    error InactiveTrade();
    error TransferFromFailed(address token);

    address public immutable factory;
    mapping(address trade => bool active) public activeTrade;

    /**
     * @notice Creates a settlement router controlled by one immutable factory.
     * @param factory_ Factory allowed to register newly created trades.
     */
    constructor(address factory_) {
        if (factory_ == address(0)) revert InvalidFactory();
        factory = factory_;
    }

    /**
     * @notice Gives one factory-created trade a single settlement authorization.
     * @dev The factory deploys the exact trusted trade implementation and calls this method in the same transaction.
     * @param trade Newly deployed trade contract.
     */
    function registerTrade(address trade) external {
        if (msg.sender != factory) revert NotFactory();
        if (trade.code.length == 0 || activeTrade[trade]) revert InvalidTrade();

        activeTrade[trade] = true;
    }

    /**
     * @notice Transfers both token legs for one authorized single-use trade.
     * @dev `msg.sender` must be a trade registered by the immutable factory. Its
     *      authorization is consumed before either external token call. This is
     *      the per-trade reentrancy guard: a callback cannot reuse the same trade;
     *      independent trades do not need a global lock. Any failure reverts both
     *      transfers and restores the authorization atomically.
     *
     *      Signed amounts are viewed from `inceptor`: positive means receive the
     *      token and negative means deliver it. The trusted trade has already
     *      validated that both legs are nonzero, opposite in sign, and not
     *      `type(int256).min`.
     * @param baseToken ERC-20 token represented by `position`.
     * @param quoteToken ERC-20 token represented by `paymentAmount`.
     * @param inceptor Party from whose perspective both amounts are signed.
     * @param counterparty Opposite fixed party.
     * @param position Signed base-token amount.
     * @param paymentAmount Signed quote-token amount.
     */
    function settlePvP(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address inceptor,
        address counterparty,
        int256 position,
        int256 paymentAmount
    ) external override {
        if (!activeTrade[msg.sender]) revert InactiveTrade();

        // Consume the authorization before calling either ERC-20 contract.
        activeTrade[msg.sender] = false;

        _move(baseToken, inceptor, counterparty, position);
        _move(quoteToken, inceptor, counterparty, paymentAmount);
    }

    /**
     * @notice Executes one signed token leg from `viewParty`'s perspective.
     * @param token ERC-20 token of the leg.
     * @param viewParty Party from whose perspective `signedAmount` is stated.
     * @param otherParty Opposite party.
     * @param signedAmount Positive to receive, negative to deliver.
     */
    function _move(
        IERC20RouterToken token,
        address viewParty,
        address otherParty,
        int256 signedAmount
    ) private {
        if (signedAmount > 0) {
            // This branch proves the value is positive and therefore representable as uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            _safeTransferFrom(token, otherParty, viewParty, uint256(signedAmount));
        } else {
            // The trusted trade rejects zero and type(int256).min, so negation is positive and safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            _safeTransferFrom(token, viewParty, otherParty, uint256(-signedAmount));
        }
    }

    /**
     * @notice Calls `transferFrom` while supporting ERC-20 tokens that do not revert, but return `false` or no data.
     * @param token ERC-20 token to call.
     * @param from Token owner that approved this router.
     * @param to Token recipient.
     * @param value Amount in the token's smallest unit.
     */
    function _safeTransferFrom(
        IERC20RouterToken token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeCall(IERC20RouterToken.transferFrom, (from, to, value))
        );

        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))
        ) {
            revert TransferFromFailed(address(token));
        }
    }
}
