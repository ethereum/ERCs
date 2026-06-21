// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ERC20SettlementRouter.sol";
import "./FxAtomicSwapRouted.sol";

/**
 * @title FX Atomic Swap Factory
 * @notice Deploys routed single-use swaps and registers them with one shared
 *         ERC-20 settlement router.
 * @dev Parties approve `address(settlementRouter)`, not each deployed swap.
 */
contract FxAtomicSwapFactory {
    ERC20SettlementRouter public immutable settlementRouter;
    mapping(address swap => bool createdByFactory) public isSwap;

    /**
     * @notice Emitted after a swap has been deployed and registered.
     * @param swap Newly deployed swap.
     * @param creator Address that requested creation.
     * @param baseToken Base-token address.
     * @param quoteToken Quote-token address.
     * @param partyA First counterparty.
     * @param partyB Second counterparty.
     */
    event SwapCreated(
        address indexed swap,
        address indexed creator,
        address indexed baseToken,
        address quoteToken,
        address partyA,
        address partyB
    );

    /**
     * @notice Deploys the immutable settlement router controlled by this factory.
     */
    constructor() {
        settlementRouter = new ERC20SettlementRouter(address(this));
    }

    /**
     * @notice Creates and registers one single-use FX atomic swap.
     * @dev Only one of the two named parties may request creation. Deployment and
     *      router registration occur in the same transaction, so no external
     *      caller can interact with the swap between those steps.
     * @param baseToken ERC-20 token represented by the signed position.
     * @param quoteToken ERC-20 token represented by the signed payment amount.
     * @param partyA First eligible counterparty.
     * @param partyB Second eligible counterparty.
     * @return swap Address of the deployed swap.
     */
    function createSwap(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address partyA,
        address partyB
    ) external returns (address swap) {
        require(msg.sender == partyA || msg.sender == partyB, "creator not party");

        FxAtomicSwapRouted deployedSwap = new FxAtomicSwapRouted(
            baseToken,
            quoteToken,
            partyA,
            partyB,
            settlementRouter
        );

        swap = address(deployedSwap);
        isSwap[swap] = true;

        settlementRouter.registerSwap(
            swap,
            address(baseToken),
            address(quoteToken),
            partyA,
            partyB
        );

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
