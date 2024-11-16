// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.9.0;

import "./ERC7818.sol";

contract MockERC7818 is ERC7818 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint16 blockTime_,
        uint8 frameSize_,
        uint8 slotSize_
    ) ERC7818(_name, _symbol, block.number, blockTime_, frameSize_, slotSize_) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public {
        _burn(from, value);
    }

    function badApprove(address owner, address spender, uint256 value) public returns (bool) {
        _approve(owner, spender, value);
        return true;
    }

    function badTransfer(address from, address to, uint256 value) public returns (bool) {
        _transfer(from, to, value);
        return true;
    }
}
