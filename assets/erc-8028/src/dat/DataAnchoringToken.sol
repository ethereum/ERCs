// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DataAnchoringToken is ERC1155Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string public constant name = "LazAI";
    string public constant symbol = "LAZAI";

    event TokenMinted(address indexed to, uint256 indexed tokenId, string fileUrl);

    // Token ID => file url
    mapping(uint256 => string) private _fileUrls;
    // Token ID => verified status
    mapping(uint256 => bool) private _tokenVerified;

    uint256 private _tokenIdCounter;

    modifier onlyRoleOr(bytes32 role1, bytes32 role2) {
        require(hasRole(role1, _msgSender()) || hasRole(role2, _msgSender()), "Must have one of the specified roles");
        _;
    }

    function initialize(address admin_, string memory uri_) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _setURI(uri_);

        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function mint(address to, uint256 amount, string memory fileUrl_, bool verified_) public onlyRole(MINTER_ROLE) {
        uint256 tokenId = ++_tokenIdCounter;
        _mint(to, tokenId, amount, "");
        _setFileUrl(tokenId, fileUrl_);
        setTokenVerified(tokenId, verified_);
        emit TokenMinted(to, tokenId, fileUrl_);
    }

    function fileUrl(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "DataAnchoringToken: non-existent token");
        return _fileUrls[tokenId];
    }

    function verified(uint256 tokenId) public view returns (bool) {
        require(_exists(tokenId), "DataAnchoringToken: non-existent token");
        return _tokenVerified[tokenId];
    }

    function _setFileUrl(uint256 tokenId, string memory fileUrl_) internal {
        _fileUrls[tokenId] = fileUrl_;
    }

    function setTokenVerified(uint256 tokenId, bool verified_) public onlyRole(MINTER_ROLE) {
        require(_exists(tokenId), "DataAnchoringToken: non-existent token");
        _tokenVerified[tokenId] = verified_;
    }

    function setURI(string memory uri_) public onlyRoleOr(MINTER_ROLE, DEFAULT_ADMIN_ROLE) {
        _setURI(uri_);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return bytes(_fileUrls[tokenId]).length > 0;
    }

    function batchMint(address to, uint256[] memory ids, uint256[] memory amounts, string[] memory fileUrls)
        public
        onlyRole(MINTER_ROLE)
    {
        require(ids.length == amounts.length, "DataAnchoringToken: arrays length mismatch");
        require(ids.length == fileUrls.length, "DataAnchoringToken: arrays length mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            _mint(to, tokenId, amounts[i], "");
            _setFileUrl(tokenId, fileUrls[i]);
        }
    }

    function currentTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            ERC1155Upgradeable.supportsInterface(interfaceId) || AccessControlUpgradeable.supportsInterface(interfaceId);
    }
}
