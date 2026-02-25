// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import "../contracts/abstracts/ERC20Expirable.sol";

contract MockERC20Expirable is ERC20Expirable {
    constructor(
        string memory _name,
        string memory _symbol,
        uint16 blockTime_,
        uint8 windowSize_
    ) ERC20Expirable(_name, _symbol, block.number, blockTime_, windowSize_, false) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public {
        _burn(from, value);
    }
}
