// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC6150.sol";

/**
 * @title IERC7891: Hierarchical NFTs with Splitting, Merging, and Share Management
 * @dev This interface extends ERC-6150 for share-based hierarchical NFTs.
 * It includes mechanisms for minting parent and child NFTs, merging, share transfer, and burning.
 * Note: The ERC-165 identifier for this interface is 0x43cb816b
 */
interface IERC7891 is IERC6150  {

    /**
     * @notice Emitted when a child token is minted under a parent with an assigned share.
     * @param parentId The ID of the parent token
     * @param childId The ID of the newly minted child token
     * @param share Share percentage assigned to the child token
     */
    event Split(uint256 indexed parentId, uint256 indexed childId, uint8 share);

    /**
     * @notice Emitted when multiple child tokens are merged into a new token.
     * @param newTokenId The ID of the newly minted merged token
     * @param mergedTokenIds Array of token IDs that were merged
     */
    event Merged(uint256 indexed newTokenId, uint256[] mergedTokenIds);

    /**
     * @notice Mints a new root-level parent NFT.
     * @param _tokenURI URI string pointing to token metadata
     * @return tokenId The ID of the newly minted parent token
     */
    function mintParent(string memory _tokenURI) external payable returns (uint256 tokenId);

    /**
     * @notice Mints a child NFT under a given parent with a specific share allocation.
     * @param parentId ID of the parent token
     * @param _share Share percentage assigned to the child token
     * @return tokenId The ID of the newly minted child token
     */
    function mintSplit(uint256 parentId, uint8 _share) external payable returns (uint256 tokenId);

    /**
     * @notice Merges multiple child NFTs into a new token under the same parent.
     * @param parentId ID of the parent token
     * @param _tokenIds Array of child token IDs to be merged
     * @return newTokenId The ID of the newly minted merged token
     */
    function mintMerge(uint256 parentId, uint256[] memory _tokenIds) external payable returns (uint256 newTokenId);

    /**
     * @notice Transfers share ownership from one NFT to another.
     * @param to Token ID receiving the share
     * @param from Token ID sending the share
     * @param _share Share percentage to transfer
     */
    function sharePass(uint256 to, uint256 from, uint8 _share) external;

    /**
     * @notice Burns an NFT and transfers its share back to the parent NFT.
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) external;
}
