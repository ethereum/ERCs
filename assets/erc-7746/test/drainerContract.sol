// SPDX-License-Identifier: CC0-1.0
import "./MockERC20.sol";
pragma solidity =0.8.20;

contract Drainer {
    constructor() {}

    function drain(address payable victim, uint256 cycles) public {
        for (uint256 i = 0; i < cycles; i++) {
            MockERC20(victim).mint(address(this), 1);
        }
    }
}
