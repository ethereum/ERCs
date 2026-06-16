// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERCVersion} from "../ERCVersion.sol";

contract ERC721VersionedExample is ERC721URIStorage, ERCVersion {
    uint256 private _nextTokenId;

    constructor() ERC721("Versioned ERC721", "VER721") {}

    function mint(address to, string memory tokenURI) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721URIStorage, ERCVersion)
        returns (bool)
    {
        return ERCVersion.supportsInterface(interfaceId) || ERC721URIStorage.supportsInterface(interfaceId);
    }
}
