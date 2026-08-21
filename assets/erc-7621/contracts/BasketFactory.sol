// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {BasketToken} from "./BasketToken.sol";

/**
 * @title BasketFactory
 * @notice Factory for deploying ERC-7621 BasketToken instances.
 */
contract BasketFactory {

    event BasketCreated(
        address indexed basket,
        address indexed creator,
        address[] tokens,
        uint256[] weights
    );

    address[] private _baskets;

    function createBasket(
        string calldata name,
        string calldata symbol,
        address[] calldata tokens,
        uint256[] calldata weights
    ) external returns (address basket) {
        BasketToken b = new BasketToken(name, symbol, msg.sender, tokens, weights);
        basket = address(b);
        _baskets.push(basket);
        emit BasketCreated(basket, msg.sender, tokens, weights);
    }

    function totalBaskets() external view returns (uint256) {
        return _baskets.length;
    }

    function getBasket(uint256 index) external view returns (address) {
        return _baskets[index];
    }
}
