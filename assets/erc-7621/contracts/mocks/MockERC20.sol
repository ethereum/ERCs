// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Simple mock ERC20 token for testing purposes.
 */
contract MockERC20 is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Mints tokens to an address (for testing).
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
