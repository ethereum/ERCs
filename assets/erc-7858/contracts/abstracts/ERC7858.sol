// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../interfaces/IERC7858.sol";

contract ERC7858 is ERC721, IERC7858 {
    constructor(
        string memory name_, 
        string memory symbol_) 
    ERC721(name_,symbol_) {}

    // mapping variable
    mapping(uint256 => uint256) internal _startBlock;
    mapping(uint256 => uint256) internal _endBlock;

    // not allowing to passing {0, 0} use _mint instead.
    function _updateTokenTimeStamp(uint256 tokenId, uint256 startBlock, uint256 endBlock) internal {
        if (startBlock >= endBlock) {
            revert ERC7858InvalidTimeStamp(startBlock, endBlock);
        }
        // store data to mapping
        _startBlock[tokenId] = startBlock;
        _endBlock[tokenId] = endBlock;

        emit TokenExpiryUpdated(tokenId, startBlock, endBlock);
    }

    function _burnAndClearTimeStamp(uint256 tokenId) internal {
        _burn(tokenId);
        // clear data from mapping
        delete _startBlock[tokenId];
        delete _endBlock[tokenId];
    }
    
    function startTime(uint256 tokenId) public view returns (uint256) {
        return _startBlock[tokenId];
    }

    function endTime(uint256 tokenId) public view returns (uint256) {
        return _endBlock[tokenId];
    }

    function expiryType() external pure returns (EXPIRY_TYPE) {
        return IERC7858.EXPIRY_TYPE.BLOCK_BASED;
    }

    function isTokenExpired(uint256 tokenId) external view returns (bool) {
        if (ownerOf(tokenId) == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        uint256 startTimeCache = startTime(tokenId);
        uint256 endTimeCache = endTime(tokenId);
        // if start and end is {0, 0} mean token non-expirable and return false.
        if (startTimeCache == 0 && endTimeCache == 0) {
            return false;
        } else {
            return block.number >= endTimeCache;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IERC7858).interfaceId || super.supportsInterface(interfaceId);
    }
}
