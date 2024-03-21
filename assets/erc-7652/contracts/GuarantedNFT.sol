// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol"; 
//import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";  
//import "@openzeppelin/contracts/utils/introspection/ERC165.sol";  
//import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "./Base/IEIP721Guarantee.sol"; 
//

// CDaoIdeal 中存储的是所有值，
// 此处保存的是有效值；所有有效的担保都在这里存储；
// 每个用户只能设置一个担保值；
// 但是每个值可以被担保多次；
contract ERC721Guaranteeable is ERC721,IEIP721Guarantee
{

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns(bool) 
    {
          return ((interfaceId == type(IEIP721Guarantee).interfaceId) || 
              super.supportsInterface(interfaceId));
     }

    constructor(string memory name_, string memory symbol_) ERC721(name_,symbol_)
    { 

    }
  
    /// @notice   A user's evaluation for an NFT (token ID)
    /// @dev      Set the guarantee information for one guarantor,
    /// Throws if `_tokenId` is not a valid NFT
    /// @param value  user's evaluation for  an NFT
    /// @param user   address of guarantor
    /// @param weight guarantee weight for guarantor
    /// @param tokenId The NFT
    /// @return the error status of function execution
    function setNFTGuarantedInfo(
        uint256 value,
        address user,
        uint256 weight,
        uint256 tokenId
    ) public view returns (uint256)
    {
        require (!(ownerOf(tokenId) == address(0))," ERC721Guaranteeable: setNFTGuarantedInfo for non-existent tokenId" );
        
          if(user ==address(0)){
            return value;
        }
      return tokenId+weight;    
    }

    /// @notice   Establish guarantee sequence for an NFT (token ID) and split the commission
    /// @dev      Each NFT(token ID) retains a current guarantee sequence,
    ///           and expired guarantee sequences are no longer valid,
    ///           Throws if `_tokenId` is not a valid NFT
    /// @param valueCommission Commission for a transactions
    /// @param userGuaranteed   address of guaranteed
    /// @param number  block.number of transaction,
    ///              and all DAOs established before this point will enter the guarantee sequence
    /// @param tokenId The NFT
    /// @return the error status of function execution
    function establishNFTGuarantee(
        uint256 valueCommission,
        address userGuaranteed,
        uint256 number,
        uint256 tokenId
    ) public view returns (uint256)
    {
       require (!(ownerOf(tokenId) == address(0))," ERC721Guaranteeable: establishNFTGuarantee for non-existent tokenId" );
       
         if(userGuaranteed ==address(0)){
            return valueCommission;
        }
      return tokenId+number;  
    }

    /// @notice   Transactions that fulfill the guarantee responsibility
    /// @dev      The new accountability transaction also requires
    ///           the construction of a new guarantee sequence
    ///           Throws if `_tokenId` is not a valid NFT or userGuaranteed is not right

    /// @param  userGuaranteed   address of guaranteed
    /// @param  tokenId The NFT
    /// @return the error status of function execution
    function FulfillGuaranteeTransfer(address userGuaranteed, uint256 tokenId)
        public view
        returns (uint256)
    {
       require (!(ownerOf(tokenId) == address(0))," ERC721Guaranteeable: FulfillGuaranteeTransfer for non-existent tokenId" );
       
        if(userGuaranteed ==address(0)){
            return 0;
        }
      return tokenId;  
    }

}
