// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IERCXXXX.sol";

contract ERCXXXX is ERC721, IERCXXXX {

    constructor(
        string memory name_, 
        string memory symbol_) 
    ERC721(name_,symbol_) {}

    // mapping variable
    mapping(uint256 => uint256) internal _startBlock;
    mapping(uint256 => uint256) internal _endBlock;

    // functional
    function _mint(address to, uint256 tokenId, uint256 startBlock, uint256 endBlock) internal {
        _mint(to, tokenId);
        // store data to mapping
        _startBlock[tokenId] = startBlock;
        _endBlock[tokenId] = endBlock;
        
        emit ExpirationUpdated(tokenId, startBlock, endBlock);
    }
    
    function startTime(uint256 tokenId) public view returns (uint256) {
        return _startBlock[tokenId];
    }

    function endTime(uint256 tokenId) public view returns (uint256) {
        return _endBlock[tokenId];
    }

    function expiryType() external pure returns (EXPIRY_TYPE) {
        return IERCXXXX.EXPIRY_TYPE.BLOCK_BASED;
    }

    function isTokenExpired(uint256 tokenId) external view returns (bool) {
        uint256 startTimeCache = startTime(tokenId);
        uint256 endTimeCache = endTime(tokenId);
        if (startTimeCache == 0 && endTimeCache == 0) {
            return false;
        } else {
            return block.number > endTime(tokenId);
        }
    }

    function mint(address to, uint256 tokenId, uint256 startBlock, uint256 endBlock) public {
        if (endBlock < startBlock) {
            revert ();
        }
        _mint(to, tokenId,startBlock,endBlock);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IERCXXXX).interfaceId || super.supportsInterface(interfaceId);
    }
}