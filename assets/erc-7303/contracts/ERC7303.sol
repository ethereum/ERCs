// SPDX-License-Identifier: CC0-1.0
// Reference implementation of ERC-7303, identical to the one in the ERC text.

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./IERC7303.sol";

abstract contract ERC7303 is IERC7303 {
    struct ERC721Token {
        address contractId;
    }

    struct ERC1155Token {
        address contractId;
        uint256 typeId;
    }

    mapping (bytes32 => ERC721Token[]) private _ERC721_Contracts;
    mapping (bytes32 => ERC1155Token[]) private _ERC1155_Contracts;

    modifier onlyHasToken(bytes32 role, address account) {
        require(_checkHasToken(role, account), "ERC7303: not has a required token");
        _;
    }

    /**
     * @notice Check whether `account` currently holds `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _checkHasToken(role, account);
    }

    /**
     * @notice Enumerate the ERC-721 control tokens associated with `role`.
     */
    function getERC721ControlTokens(bytes32 role) public view returns (address[] memory contractIds) {
        ERC721Token[] memory tokens = _ERC721_Contracts[role];
        contractIds = new address[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            contractIds[i] = tokens[i].contractId;
        }
    }

    /**
     * @notice Enumerate the ERC-1155 control tokens associated with `role`.
     */
    function getERC1155ControlTokens(bytes32 role) public view returns (address[] memory contractIds, uint256[] memory typeIds) {
        ERC1155Token[] memory tokens = _ERC1155_Contracts[role];
        contractIds = new address[](tokens.length);
        typeIds = new uint256[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            contractIds[i] = tokens[i].contractId;
            typeIds[i] = tokens[i].typeId;
        }
    }

    /**
     * @notice Grant a role to user who owns a control token specified by the ERC-721 contractId.
     * Multiple calls are allowed, in this case the user must own at least one of the specified token.
     * @param role byte32 The role which you want to grant.
     * @param contractId address The address of contractId of which token the user required to own.
     */
    function _grantRoleByERC721(bytes32 role, address contractId) internal {
        require(
            IERC165(contractId).supportsInterface(type(IERC721).interfaceId),
            "ERC7303: provided contract does not support ERC721 interface"
        );
        _ERC721_Contracts[role].push(ERC721Token(contractId));
        emit ERC721ControlTokenAdded(role, contractId);
    }

    /**
     * @notice Grant a role to user who owns a control token specified by the ERC-1155 contractId.
     * Multiple calls are allowed, in this case the user must own at least one of the specified token.
     * @param role byte32 The role which you want to grant.
     * @param contractId address The address of contractId of which token the user required to own.
     * @param typeId uint256 The token type id that the user required to own.
     */
    function _grantRoleByERC1155(bytes32 role, address contractId, uint256 typeId) internal {
        require(
            IERC165(contractId).supportsInterface(type(IERC1155).interfaceId),
            "ERC7303: provided contract does not support ERC1155 interface"
        );
        _ERC1155_Contracts[role].push(ERC1155Token(contractId, typeId));
        emit ERC1155ControlTokenAdded(role, contractId, typeId);
    }

    function _checkHasToken(bytes32 role, address account) internal view returns (bool) {
        ERC721Token[] memory ERC721Tokens = _ERC721_Contracts[role];
        for (uint i = 0; i < ERC721Tokens.length; i++) {
            if (IERC721(ERC721Tokens[i].contractId).balanceOf(account) > 0) return true;
        }

        ERC1155Token[] memory ERC1155Tokens = _ERC1155_Contracts[role];
        for (uint i = 0; i < ERC1155Tokens.length; i++) {
            if (IERC1155(ERC1155Tokens[i].contractId).balanceOf(account, ERC1155Tokens[i].typeId) > 0) return true;
        }

        return false;
    }
}
