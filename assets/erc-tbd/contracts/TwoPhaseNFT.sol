// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721TwoPhase } from "./ERC721TwoPhase.sol";

/// @title TwoPhaseNFT — concrete mintable ERC-721 with the two-phase extension.
/// @dev Test/demo mock only. Public `mint` is intentionally unrestricted.
contract TwoPhaseNFT is ERC721TwoPhase {
    constructor() ERC721("TwoPhaseNFT", "2PN") { }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
