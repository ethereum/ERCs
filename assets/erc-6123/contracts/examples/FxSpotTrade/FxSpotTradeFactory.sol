// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ERC20PvPSettlementRouter.sol";
import "./FxSpotTrade.sol";

/**
 * @title FX Spot Trade Factory
 * @notice Creates single-use trades and registers them with one shared router.
 * @dev Parties approve `settlementRouter`, not each individual trade.
 */
contract FxSpotTradeFactory {
    error CreatorNotParty();

    ERC20PvPSettlementRouter public immutable settlementRouter;

    event TradeCreated(
        address indexed trade,
        address indexed creator,
        address indexed baseToken,
        address quoteToken,
        address partyA,
        address partyB
    );

    /**
     * @notice Deploys the common settlement router controlled by this factory.
     */
    constructor() {
        settlementRouter = new ERC20PvPSettlementRouter(address(this));
    }

    /**
     * @notice Creates and registers one single-use FX spot trade.
     * @dev Only a named party may request creation. Deployment and registration
     *      occur in one transaction, so the trade cannot be used in between.
     * @param baseToken ERC-20 token represented by the signed position.
     * @param quoteToken ERC-20 token represented by the signed payment amount.
     * @param partyA First eligible counterparty.
     * @param partyB Second eligible counterparty.
     * @return trade Address of the newly created trade.
     */
    function createTrade(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address partyA,
        address partyB
    ) external returns (address trade) {
        if (msg.sender != partyA && msg.sender != partyB) {
            revert CreatorNotParty();
        }

        trade = address(
            new FxSpotTrade(
                baseToken,
                quoteToken,
                partyA,
                partyB,
                settlementRouter
            )
        );

        settlementRouter.registerTrade(trade);

        emit TradeCreated(
            trade,
            msg.sender,
            address(baseToken),
            address(quoteToken),
            partyA,
            partyB
        );
    }
}
