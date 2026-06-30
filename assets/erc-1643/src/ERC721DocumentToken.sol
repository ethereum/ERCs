// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC1643} from "./erc-1643/ERC1643.sol";

/// @notice ERC-721 reference implementation with attached ERC-1643 module.
contract ERC721DocumentToken is ERC1643, ERC721 {
    constructor(string memory name_, string memory symbol_, address initialOwner) ERC721(name_, symbol_) ERC1643(initialOwner) {}

    function mint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1643, ERC721) returns (bool) {
        return ERC1643.supportsInterface(interfaceId) || ERC721.supportsInterface(interfaceId);
    }
}
