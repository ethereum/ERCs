// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1643} from "./erc-1643/ERC1643.sol";

/// @notice ERC-20 reference implementation with attached ERC-1643 module.
contract ERC20DocumentToken is ERC20, ERC1643 {
    constructor(string memory name_, string memory symbol_, address initialOwner) ERC20(name_, symbol_) ERC1643(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
