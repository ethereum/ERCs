// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @notice Negative fixture. Functionally identical balance gating to
/// `FixtureTarget` (same roles, same control tokens, same revert string),
/// but written in the pre-IERC7303 style: no introspection interface and no
/// ERC-165 registration of the IERC7303 identifier, so
/// `supportsInterface(0x4ee69337)` answers `false`. Discovery tooling
/// encountering this contract must classify it as NOT implementing this ERC,
/// even though its gating behaves identically on-chain.
contract LegacyTarget is ERC721 {
    IERC721 private immutable _ct721;
    IERC1155 private immutable _ct1155;

    constructor(address ct721, address ct1155) ERC721("LegacyTarget", "LT") {
        _ct721 = IERC721(ct721);
        _ct1155 = IERC1155(ct1155);
    }

    function safeMint(address to, uint256 tokenId) public {
        require(
            _ct721.balanceOf(msg.sender) > 0 || _ct1155.balanceOf(msg.sender, 1) > 0,
            "ERC7303: not has a required token"
        );
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) public {
        require(
            _ct1155.balanceOf(msg.sender, 2) > 0,
            "ERC7303: not has a required token"
        );
        _burn(tokenId);
    }
}
