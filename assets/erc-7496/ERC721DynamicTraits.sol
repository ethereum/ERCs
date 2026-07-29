// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {DynamicTraits} from "src/dynamic-traits/DynamicTraits.sol";

contract ERC721DynamicTraits is DynamicTraits, Ownable, ERC721 {
    constructor() Ownable(msg.sender) ERC721("ERC721DynamicTraits", "ERC721DT") {
        _setTraitMetadataURI("https://example.com");
    }

    function setTrait(uint256 tokenId, bytes32 traitKey, bytes32 value) public virtual override onlyOwner {
        // Revert if the token doesn't exist.
        _requireOwned(tokenId);

        // Call the internal function to set the trait.
        DynamicTraits.setTrait(tokenId, traitKey, value);
    }

    function getTraitValue(uint256 tokenId, bytes32 traitKey)
        public
        view
        virtual
        override
        returns (bytes32 traitValue)
    {
        // Revert if the token doesn't exist.
        _requireOwned(tokenId);

        // Call the internal function to get the trait value.
        return DynamicTraits.getTraitValue(tokenId, traitKey);
    }

    function getTraitValues(uint256 tokenId, bytes32[] calldata traitKeys)
        public
        view
        virtual
        override
        returns (bytes32[] memory traitValues)
    {
        // Revert if the token doesn't exist.
        _requireOwned(tokenId);

        // Call the internal function to get the trait values.
        return DynamicTraits.getTraitValues(tokenId, traitKeys);
    }

    function setTraitMetadataURI(string calldata uri) external onlyOwner {
        // Set the new metadata URI.
        _setTraitMetadataURI(uri);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, DynamicTraits) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || DynamicTraits.supportsInterface(interfaceId);
    }
}
