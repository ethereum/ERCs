// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC6150.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ERC7891 is ERC6150 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint8) public share;

    construct() ERC6150("ERC7891", "NFT") {}

    function mintParent(string memory tokenURI) external returns (uint256) {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMintWithParent(msg.sender, 0, tokenId);
        share[tokenId] = 100;
        _tokenURIs[tokenId] = tokenURI;
        return tokenId;
    }

    function mintSplit(uint256 parentId, uint8 _share) external returns (uint256) {
        require(share[parentId] >= _share, "Insufficient parent share");
        _tokenIds.increment();
        uint256 childId = _tokenIds.current();
        _safeMintWithParent(msg.sender, parentId, childId);
        share[parentId] -= _share;
        share[childId] = _share;
        _tokenURIs[childId] = _tokenURIs[parentId];
        emit NFTSplit(parentId, childId, _share);
        return childId;
    }

    function mintMerge(uint256 parentId, uint256[] memory tokenIds) external returns (uint256) {
        uint8 totalShare = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(parentOf(tokenIds[i]) == parentId, "Not a child of the same parent");
            totalShare += share[tokenIds[i]];
            _burn(tokenIds[i]);
        }
        _tokenIds.increment();
        uint256 newParentId = _tokenIds.current();
        _safeMintWithParent(msg.sender, parentId, newParentId);
        share[newParentId] = totalShare;
        emit NFTMerged(newParentId, tokenIds);
        return newParentId;
    }

    function sharePass(uint256 from,  uint256 to, uint8 _share) public  {
        share[from] += _share;
        share[to] -= _share ;
    }

    function burn(uint256 _tid) public {        
        uint256 pid = parentOf(_tid);
        if (pid == 0) share[_tid] = 0 ;
        else          sharePass( _pid, tid, share[_tid]);
        
        _safeBurn(_tid);

    }
  }
    

  

    

