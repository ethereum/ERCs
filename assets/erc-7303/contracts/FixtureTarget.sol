// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./ERC7303.sol";

/// @notice Canonical compliant fixture. Its role structure is fixed so that
/// the introspection getters have deterministic expected values relative to
/// the two control-token addresses supplied at deployment:
///
///   MINTER_ROLE = keccak256("MINTER_ROLE")
///     - ERC-721 control token  `ct721`
///     - ERC-1155 control token `ct1155`, typeId 1
///     (two entries: holding either one grants the role — OR semantics)
///   BURNER_ROLE = keccak256("BURNER_ROLE")
///     - ERC-1155 control token `ct1155`, typeId 2
///     (no ERC-721 entry: the ERC-721 getter answers an empty array)
contract FixtureTarget is ERC721, ERC7303 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(address ct721, address ct1155) ERC721("FixtureTarget", "FT") {
        _grantRoleByERC721(MINTER_ROLE, ct721);
        _grantRoleByERC1155(MINTER_ROLE, ct1155, 1);
        _grantRoleByERC1155(BURNER_ROLE, ct1155, 2);
    }

    function safeMint(address to, uint256 tokenId)
        public onlyHasToken(MINTER_ROLE, msg.sender)
    {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId)
        public onlyHasToken(BURNER_ROLE, msg.sender)
    {
        _burn(tokenId);
    }

    /// @notice Stacking the modifiers of two roles composes them with AND
    /// semantics: reissuing requires both the burn and the mint privilege.
    function reissue(uint256 tokenId, address to)
        public
        onlyHasToken(MINTER_ROLE, msg.sender)
        onlyHasToken(BURNER_ROLE, msg.sender)
    {
        _burn(tokenId);
        _safeMint(to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return interfaceId == type(IERC7303).interfaceId || super.supportsInterface(interfaceId);
    }
}
