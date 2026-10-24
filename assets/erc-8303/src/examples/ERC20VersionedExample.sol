// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC8303} from "../ERC8303.sol";

contract ERC20VersionedExample is ERC20, ERC8303 {
    constructor(uint256 initialSupply) ERC20("Versioned ERC20", "VER20") {
        _mint(msg.sender, initialSupply);
    }
}
