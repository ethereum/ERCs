// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Minimal mintable ERC-721 for TwoPhaseEscrow tests.
contract MockERC721 is ERC721 {
    constructor() ERC721("Mock", "MOCK") { }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
