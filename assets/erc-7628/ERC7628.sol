// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC7628 is ERC721, Ownable, ReentrancyGuard {
    mapping(uint256 => uint256) private _shareBalances;
    mapping(uint256 => mapping(address => uint256)) private _shareAllowances;
    uint256 private _totalShares;
    uint256 private _nextTokenId;

    constructor(address initialOwner)
        ERC721("MyToken", "MTK")
        Ownable(initialOwner)
    {}

    function addSharesToToken(uint256 tokenId, uint256 shares) public override onlyOwner {
        require(tokenId > 0, "ERC7628: tokenId cannot be zero");
        _shareBalances[tokenId] += shares;
        _totalShares += shares;
        emit SharesAdded(tokenId, shares);
    }

    function shareDecimals() external pure override returns (uint8) {
        return 18;
    }

    function totalShares() external view override returns (uint256) {
        return _totalShares;
    }

    function shareOf(uint256 tokenId) external view override returns (uint256) {
        return _shareBalances[tokenId];
    }

    function shareAllowance(uint256 tokenId, address spender) external view override returns (uint256) {
        return _shareAllowances[tokenId][spender];
    }

    function approveShare(uint256 tokenId, address spender, uint256 shares) external override {
        require(spender != ownerOf(tokenId), "ERC7628: approval to current owner");
        require(msg.sender == ownerOf(tokenId), "ERC7628: approve caller is not owner");

        _shareAllowances[tokenId][spender] = shares;
        emit SharesApproved(tokenId, spender, shares);
    }

    function transferShares(uint256 fromTokenId, uint256 toTokenId, uint256 shares) external override nonReentrant {
        require(_shareBalances[fromTokenId] >= shares, "ERC7628: insufficient shares for transfer");
        require(_isApprovedOrOwner(msg.sender, fromTokenId), "ERC7628: transfer caller is not owner nor approved");

        _shareBalances[fromTokenId] -= shares;
        _shareBalances[toTokenId] += shares;
        emit SharesTransfered(fromTokenId, toTokenId, shares);
    }

    function transferSharesToAddress(uint256 fromTokenId, address to, uint256 shares) external override nonReentrant {
        require(_shareBalances[fromTokenId] >= shares, "ERC7628: insufficient shares for transfer");
        require(_isApprovedOrOwner(msg.sender, fromTokenId), "ERC7628: transfer caller is not owner nor approved");

        _nextTokenId++;
        _safeMint(to, _nextTokenId);
        _shareBalances[_nextTokenId] = shares;
        emit SharesTransfered(fromTokenId, _nextTokenId, shares);
    }

    // Helper function to check if an address is the owner or approved
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        return (spender == ownerOf(tokenId) || getApproved(tokenId) == spender || isApprovedForAll(ownerOf(tokenId), spender));
    }

    // Make sure to declare all events as they are in IERC7628
    event SharesAdded(uint256 indexed tokenId, uint256 shares);
    event SharesTransfered(uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 amount);
    event SharesApproved(uint256 indexed tokenId, address indexed spender, uint256 amount);
}
