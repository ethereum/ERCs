// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1643} from "./erc-1643/ERC1643.sol";

/// @title ERC20DocumentToken
/// @notice ERC-20 reference implementation with attached ERC-1643 module.
contract ERC20DocumentToken is ERC20, ERC1643 {
    /**
     * @notice Deploys the token and assigns ownership of the document module.
     * @param name_ ERC-20 token name.
     * @param symbol_ ERC-20 token symbol.
     * @param initialOwner Account allowed to mint and to manage documents.
     */
    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC20(name_, symbol_)
        ERC1643(initialOwner)
    {}

    /**
     * @notice Mints new tokens to an account.
     * @dev Restricted to the owner. Provided so the example token is usable; not part of ERC-1643.
     * @param to Recipient of the minted tokens.
     * @param amount Quantity of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
