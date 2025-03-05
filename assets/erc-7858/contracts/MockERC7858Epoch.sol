// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ERC7858Epoch} from "./abstracts/ERC7858Epoch.sol";

contract MockERC7858Epoch is ERC7858Epoch {
    // assume configuration
    constructor(string memory _name, string memory _symbol) ERC7858Epoch(_name, _symbol, 1200, 4) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }
}
