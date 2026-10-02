// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC1643} from "./erc-1643/ERC1643.sol";

/// @title ERC721DocumentToken
/// @notice ERC-721 reference implementation with attached ERC-1643 module.
contract ERC721DocumentToken is ERC1643, ERC721 {
    /**
     * @notice Deploys the token and assigns ownership of the document module.
     * @param name_ ERC-721 collection name.
     * @param symbol_ ERC-721 collection symbol.
     * @param initialOwner Account allowed to mint and to manage documents.
     */
    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC721(name_, symbol_)
        ERC1643(initialOwner)
    {}

    /**
     * @notice Mints a new token to an account.
     * @dev Restricted to the owner. Provided so the example token is usable; not part of ERC-1643.
     * @param to Recipient of the minted token.
     * @param tokenId Identifier of the token to mint.
     */
    function mint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }

    /**
     * @notice Reports whether this contract implements a given interface.
     * @dev Resolves the ERC-165 implementations inherited from both `ERC1643` and `ERC721`.
     * @param interfaceId ERC-165 identifier to query.
     * @return True when either base supports `interfaceId`.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1643, ERC721) returns (bool) {
        return ERC1643.supportsInterface(interfaceId) || ERC721.supportsInterface(interfaceId);
    }
}
