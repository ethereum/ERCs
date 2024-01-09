// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./AbstractERC7590.sol";


error OnlyNFTOwnerCanTransferTokensFromIt();

/**
 * @title ERC7590Mock
 * @author RMRK team
 * @notice Mock implementation of and ERC-721 with ERC-7590 extension
 */
contract ERC7590Mock is AbstractERC7590, ERC721 {
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AbstractERC7590, ERC721) returns (bool) {
        return
            AbstractERC7590.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IERC7590
     */
    function transferHeldERC20FromToken(
        address erc20Contract,
        uint256 tokenHolderId,
        address to,
        uint256 amount,
        bytes memory data
    ) external {
        if (msg.sender != ownerOf(tokenHolderId)) {
            revert OnlyNFTOwnerCanTransferTokensFromIt();
        }
        _transferHeldERC20FromToken(
            erc20Contract,
            tokenHolderId,
            to,
            amount,
            data
        );
    }
}
