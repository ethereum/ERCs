// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC6150.sol";
import "./IERC7891.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ERC7891 is ERC6150, IERC7891 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint8) public share;

    constructor() ERC6150("ERC7891", "NFT") {}

    function mintParent(string memory tokenURI) external payable override returns (uint256) {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMintWithParent(msg.sender, 0, tokenId);
        share[tokenId] = 100;
        _tokenURIs[tokenId] = tokenURI;
        return tokenId;
    }

    function mintSplit(uint256 parentId, uint8 _share) public payable override returns (uint256) {
        require(share[parentId] >= _share, "Insufficient parent share");
        _tokenIds.increment();
        uint256 childId = _tokenIds.current();
        _safeMintWithParent(msg.sender, parentId, childId);
        sharePass(parentId, childId, _share);
        _tokenURIs[childId] = _tokenURIs[parentId];
        emit Split(parentId, childId, _share);
        return childId;
    }

    function mintMerge(uint256 parentId, uint256[] memory tokenIds) public payable override returns (uint256) {
        require(tokenIds.length > 1, "At least two tokens are required for merging.");
        uint8 totalShare = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(parentOf(tokenIds[i]) == parentId, "Not a child of the same parent");
            totalShare += share[tokenIds[i]];
            burn(tokenId);
        }

        uint256 newTokenId = mintSplit(parentId, totalShare);
        emit Merged(newTokenId, tokenIds);
        return newTokenId;
    }

    function sharePass(uint256 from,  uint256 to, uint8 _share) public  {
        require(_exists(from), "Source token does not exist");
        require(_exists(to), "Target token does not exist");
        share[from] -= _share;
        share[to] += _share ;
    }

    function burn(uint256 _tid) public {        
        uint256 pid = parentOf(_tid);
        if (pid == 0) share[_tid] = 0 ;
        else          sharePass( _tid, pid, share[_tid]);
        
        _safeBurn(_tid);

    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
     return 
     interfaceId == type(IERC7891).interfaceId || super.supportsInterface(interfaceId);
     }

    function getInterfaceID() external pure returns (bytes4) {
        return type(IERC7891).interfaceId;
     }
  }
    

  

    

