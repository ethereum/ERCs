// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
