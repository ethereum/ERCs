// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal ERC-721 control token for the conformance fixture.
/// The issuer (owner) grants a role by minting and revokes it by burning
/// without the holder's cooperation — the issuer-side kill switch described
/// in the ERC's Security Considerations.
contract ERC721ControlToken is ERC721, Ownable {
    uint256 private _nextId;

    constructor() ERC721("FixtureControl721", "FC721") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = ++_nextId;
        _safeMint(to, tokenId);
    }

    function burnByIssuer(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}
