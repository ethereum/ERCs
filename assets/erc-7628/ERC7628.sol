// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC7628 is ERC721, Ownable {
    mapping(uint256 => uint256) private _balances;
    mapping(uint256 => mapping(address => uint256)) private _allowances;
    uint256 private _totalBalance;
    uint256 private _nextTokenId;

    constructor(address initialOwner)
        ERC721("MyToken", "MTK")
        Ownable(initialOwner)
    {}

    function addBalance(uint256 tokenId, uint256 amount) public onlyOwner {
        require(tokenId>0, "ERC7628: cannot be zero");
        _balances[tokenId] += amount;
        _totalBalance += amount;
        emit Transfer(0, tokenId, amount);
    }

    function balanceDecimals() external pure returns (uint8) {
        return 18;
    }

    function totalBalances() external view returns (uint256) {
        return _totalBalance;
    }

    function balanceOf(uint256 tokenId) external view returns (uint256) {
        return _balances[tokenId];
    }

    function allowance(uint256 tokenId, address spender) external view returns (uint256) {
        return _allowances[tokenId][spender];
    }

    function approve(uint256 tokenId, address to, uint256 amount) external {
        require(to != _ownerOf(tokenId), "ERC7628: approval to current owner");
        require(msg.sender == _ownerOf(tokenId), "ERC7628: approve caller is not owner");

        _allowances[tokenId][to] = amount;
        emit Approval(tokenId, to, amount);
    }

    function transferFrom(uint256 _fromTokenId, uint256 _toTokenId, uint256 amount) external {
        require(msg.sender == _ownerOf(_fromTokenId), "ERC7628: caller is not owner");
        _transfer(_fromTokenId, _toTokenId, amount);
    }

    function transferFrom(uint256 _fromTokenId, address _to, uint256 amount) external {
        require(msg.sender == _ownerOf(_fromTokenId), "ERC7628: caller is not owner");
        _nextTokenId++;
        _safeMint(_to, _nextTokenId);
        _transfer(_fromTokenId, _nextTokenId, amount);
    }

    function _transfer(uint256 fromTokenId, uint256 toTokenId, uint256 amount) internal {
        require(_balances[fromTokenId] >= amount, "ERC7628: transfer amount exceeds balance");

        _balances[fromTokenId] -= amount;
        _balances[toTokenId] += amount;

        emit Transfer(fromTokenId, toTokenId, amount);
    }

    event Transfer(uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 value);
    event Approval(uint256 indexed tokenId, address indexed spender, uint256 value);
}
