// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "./interfaces/IERC7721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title ERC7066: Lockable Extension for ERC721
/// @dev Implementation for the Lockable extension ERC7066 for ERC721
/// @author StreamNFT 

abstract contract ERC7721 is ERC1155,IERC7721{

    /*///////////////////////////////////////////////////////////////
                            ERC7066 EXTENSION STORAGE                        
    //////////////////////////////////////////////////////////////*/

    //Mapping from tokenId to user address for locker
    mapping(uint256 tokenId => mapping(address account => mapping(address operator => uint256))) private locker;
    mapping(uint256 tokenId => mapping(address account => mapping(address operator => uint256))) private nftApproval;
    mapping(uint256 tokenId => mapping(address account => uint256)) private lockedAmount;


    /*///////////////////////////////////////////////////////////////
                              ERC7066 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the locked amount for the tokenId on account by operator
     */
    function getLocked(uint256 tokenId, address account, address operator) public virtual view override returns(uint256){
        return locker[tokenId][account][operator];
    }

    /**
     * @dev Public function to lock the amount of token and set locker to msg.sender. Verifies if the msg.sender is owner or approved
     *      reverts otherwise
     */
    // lock: is locked true or false:  
    function lock(uint256 tokenId, address account, uint256 amount) public virtual override{
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()) || getApprovalForId(tokenId,account,_msgSender())>=amount,
            "ERC1155: caller is not token owner or approved"
        );
        _lock(tokenId, account, _msgSender(), amount);
    }

    /**
     * @dev Public function to lock the amount of token and set locker to _locker. Verifies if the msg.sender is owner
     *      reverts otherwise
     */
    // lock: is locked true or false:
    function lock(uint256 tokenId, address account, address _locker, uint256 amount) public virtual override{
        require(
            account == _msgSender() || isApprovedForAll(account, _locker) || getApprovalForId(tokenId,account,_locker)>=amount,
            "ERC1155: caller is not token owner or approved"
        );
        _lock(tokenId, account,_locker, amount);
    }

    /**
     * @dev Internal function to lock the token.
     */
    function _lock(uint256 tokenId, address account, address _locker, uint256 amount) internal {
        require(balanceOf(account, tokenId)>=amount,"ERC1155: Insufficient Balance");
        locker[tokenId][account][_msgSender()]=locker[tokenId][account][_msgSender()]+amount;
        lockedAmount[tokenId][account]=lockedAmount[tokenId][account]+amount;
        emit Lock(tokenId, account, _locker,amount);
    }

    /**
     * @dev Public function to unlock the token. Verifies the msg.sender is locker
     *      reverts otherwise
     */
    function unlock(uint256 tokenId, address account, uint256 amount) public virtual override{
        require(locker[tokenId][account][_msgSender()]>=amount,"ERC1155: Insufficient Locked Amount");
        _unlock(tokenId,account,_msgSender(),amount);
    }

    /**
     * @dev Internal function to unlock the token. 
     */
    function _unlock(uint256 tokenId, address account, address _locker, uint256 amount) internal{
        locker[tokenId][account][_msgSender()]=locker[tokenId][account][_msgSender()]-amount;
        lockedAmount[tokenId][account]=lockedAmount[tokenId][account]-amount;
        emit Unlock(tokenId, account, _locker,amount);
    }

   /**
     * @dev Public function to tranfer and lock the token. Reverts if caller is not owner or approved.
     *      Lock the token and set locker to caller
     *.     Optionally approve caller if bool setApprove flag is true
     */
    function transferAndLock(address from, address to, uint256 tokenId, uint256 amount, bool setApprove) public virtual {
        _transferAndLock(tokenId,from,to,amount,setApprove);
    }

    /**
     * @dev Internal function to tranfer, update locker/approve and lock the token.
     */
    function _transferAndLock(uint256 tokenId, address from, address to, uint256 amount, bool setApprove) internal {
        safeTransferFrom(from, to, tokenId, amount, "" ); 
        if(setApprove){
            nftApproval[tokenId][to][from]=nftApproval[tokenId][to][from]+amount;
        }
        _lock(tokenId,to,msg.sender,amount);
    }

    /**
     * @dev Set approval on specific tokenId for token approved and operator on account
     */
    function setApprovalForId(uint256 tokenId, address operator, uint256 amount) public virtual {
        require (amount>locker[tokenId][_msgSender()][operator], "ERC1155: Insufficient Locked Amount");
        nftApproval[tokenId][_msgSender()][operator]=amount;
    }

    /**
     * @dev Get amount for token approved and operator on account
     */
    function getApprovalForId(uint256 tokenId, address account, address operator) public virtual returns(uint256) {
        return nftApproval[tokenId][account][operator];
    }
    
    /*///////////////////////////////////////////////////////////////
                              OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override(ERC1155,IERC1155) {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()) ||  getApprovalForId(id,from,_msgSender()) >= amount,
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev Override _beforeTokenTransfer to make sure token is unlocked or msg.sender is approved if 
     * token is lockApproved
     */
    function _beforeTokenTransfer( 
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        // if it is a Transfer or Burn, we always deal with one token, that is startTokenId
        if (from != address(0)) { 
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenId = ids[i];
                uint256 amount = amounts[i];
                if(locker[tokenId][from][operator]>0){
                    require( getApprovalForId(tokenId,from,operator) >= amount,"ERC7066: Locked");
                } else{
                    require(balanceOf(from, tokenId)-amount >= lockedAmount[tokenId][from],"ERC7066: Can't Spend Locked");
                }
            }
        }
        super._beforeTokenTransfer(operator,from,to,ids,amounts,data);
    }

    /**
     * @dev Override _afterTokenTransfer to make locker is purged
     */
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        // if it is a Transfer or Burn, we always deal with one token, that is startTokenId
        if (from != address(0)) { 
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenId=ids[i];
                uint256 amount = amounts[i];
                if(getApprovalForId(tokenId,from,operator)>=amount){
                    nftApproval[tokenId][from][operator]=getApprovalForId(tokenId,from,operator)-amount;
                    if(locker[tokenId][from][operator]>0){
                        if(amount>=locker[tokenId][from][operator]){
                            lockedAmount[tokenId][from]=lockedAmount[tokenId][from]-locker[tokenId][from][operator];         
                            locker[tokenId][from][operator]=0;
                        } else{
                            lockedAmount[tokenId][from]=lockedAmount[tokenId][from]-amount;         
                            locker[tokenId][from][operator]=locker[tokenId][from][operator]-amount;
                        }
                    }
                }
            }  
        }
        super._afterTokenTransfer(operator,from,to,ids,amounts,data);
    }

     /*///////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC1155) returns (bool) {
         return
            interfaceId == type(IERC7066SFT).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}