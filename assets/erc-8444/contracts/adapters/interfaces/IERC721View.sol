// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC721View {
    /// @dev ERC-721 ownerOf; MUST revert for a nonexistent token.
    function ownerOf(uint256 tokenId) external view returns (address);
}
