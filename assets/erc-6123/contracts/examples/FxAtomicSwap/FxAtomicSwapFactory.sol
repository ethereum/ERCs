// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ERC20SettlementRouter.sol";
import "./FxAtomicSwap.sol";

/**
 * @title FX Atomic Swap Factory
 * @notice Creates single-use swaps and registers them with one shared router.
 * @dev Parties approve `settlementRouter`, not each individual swap.
 */
contract FxAtomicSwapFactory {
    error CreatorNotParty();

    ERC20SettlementRouter public immutable settlementRouter;

    event SwapCreated(
        address indexed swap,
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
        settlementRouter = new ERC20SettlementRouter(address(this));
    }

    /**
     * @notice Creates and registers one single-use FX atomic swap.
     * @dev Only a named party may request creation. Deployment and registration
     *      occur in one transaction, so the swap cannot be used in between.
     * @param baseToken ERC-20 token represented by the signed position.
     * @param quoteToken ERC-20 token represented by the signed payment amount.
     * @param partyA First eligible counterparty.
     * @param partyB Second eligible counterparty.
     * @return swap Address of the newly created swap.
     */
    function createSwap(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address partyA,
        address partyB
    ) external returns (address swap) {
        if (msg.sender != partyA && msg.sender != partyB) {
            revert CreatorNotParty();
        }

        swap = address(
            new FxAtomicSwap(
                baseToken,
                quoteToken,
                partyA,
                partyB,
                settlementRouter
            )
        );

        settlementRouter.registerSwap(swap);

        emit SwapCreated(
            swap,
            msg.sender,
            address(baseToken),
            address(quoteToken),
            partyA,
            partyB
        );
    }
}
