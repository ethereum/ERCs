// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBequeathable.sol";

// import "hardhat/console.sol"; //only used for debugging

/**
 * @title   A DeedRegistry
 * @author  Wamith Mockbill
 * @notice  An example contract that allows a token to be 'bequeathed' to another wallet upon the original owner's demise
 *
 * For a detailed write up see the scansanproperties blog
 * https://scansanproperties.com/f/xxxxx
 */ 

contract DeedRegistry is ERC721Enumerable, Bequeathable {

   mapping (address => Will ) wills;

   // Event emitted upon the minting of a new token.
   event TokenMinted(address indexed to, uint256 indexed tokenId); 

   function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
      return super.supportsInterface(interfaceId);
   }

   constructor() ERC721("MyDeeds", "MYD") {
      // console.log("Deed registry deployed by:", msg.sender);
   }

   function safeMint(address to, uint256 tokenId) public  {
      _safeMint(to, tokenId);
      emit TokenMinted(to, tokenId); // Emitting the token minted event.
   }

   /**
    * @dev                    A token owner can set a will that allows an executor to transfer their tokens after their death
    *                         Although more than one executor address can be set, only one is required to go through the process
    * @param  _executors      An array of executors eg legal council, spouse, child 1, child 2 etc..
    * @param  _moratoriumTTL  The time that must pass (in seconds) from when the obituary starts to when the inheritance can take place
    * @dev                    This is a safety buffer time frame that allows for any intervention before the tokens get transferred
    */
   function setWill(address[] memory _executors, uint256 _moratoriumTTL) public  {
      // make sure this person is an owner of at least one token/deed
      require(balanceOf(msg.sender)>0, "sender does not own any contracts");

      // safety check that we actually have an array and that the first one is not the zero address
      require(_executors.length>0 && _executors[0]!=address(0), "bad executor list");
      // in the interest of gas efficiency, limit the number of executors
      require(_executors.length < 9, "Too many executors");

      // create a new will, even if one already exists
      Will memory newWill =  Will({
         executors: _executors,
         moratoriumTTL: _moratoriumTTL,
         inheritor: address(0),
         obituaryStart: 0
      });

      wills[msg.sender]=newWill;        // record this will
   }

   /** 
    * @dev get the contents of the will. Can only be called by the owner
    */
   function getWill(address owner) public view returns (address[] memory executors, uint256 moratoriumTTL){
      require(owner==msg.sender, "only owner");

      Will memory myWill = wills[owner];

      return (myWill.executors, myWill.moratoriumTTL);
   }

   /**
    * @dev internal helper function to return if this address is a named executor
    */ 
   function _isExecutor(address _owner) internal view returns(bool){
      bool found = false;
      // get the will for the owner
      Will memory will = wills[_owner];  //how do i check it's not null?
      for (uint256 i =0; i < will.executors.length; i++) {
         if(will.executors[i] == msg.sender) {
            found = true;
            break;
         }
      }
      return found;
   }

   /** 
    * @dev start the Obituary process and declare who is the intended inheritor
    */ 
   function announceObit(address owner, address _inheritor) public {
      require(_isExecutor(owner),"only owner or executor");

      // check the obit has not been previously set
      require(wills[owner].obituaryStart==0, "obituary has already been set");
      // check the inheritor is not the zero address
      require(_inheritor != address(0), "zero address cannot inherit");

      wills[owner].inheritor = _inheritor;
      wills[owner].obituaryStart = block.timestamp;
      emit ObituaryStarted(owner, _inheritor);
   }

   /** 
    * @dev any of the executors (or the owner) may cancel an obituary
    */
   function cancelObit(address owner) public{
      require(owner==msg.sender || _isExecutor(owner), "only owner or executor");

      Will memory will = wills[owner];
      require(will.obituaryStart>0);

      // reset the obituray
      wills[owner].inheritor = address(0);
      wills[owner].obituaryStart = 0;

      emit ObituaryCancelled(owner, msg.sender);
   }


   /** 
    * @dev get the inheritor and how much time is left before the moratoriumTTL is satisfied
    */
   function getObit(address owner) public view returns (address, int256){
      require(owner==msg.sender || _isExecutor(owner), "only owner or executor");
      Will memory will = wills[owner];
      int256 ttl = int256(will.moratoriumTTL);

      if (will.obituaryStart>0 ){
         // work out the time left on the obit - a minus figure indicates it can be bequeathed
         ttl = int256(will.moratoriumTTL) -  int256(block.timestamp - will.obituaryStart) ;
      }

      return (will.inheritor, ttl);
   }

   /** 
    * @dev transfer, aka 'bequeath` the tokens to the previously declared inheritor
    */
   function bequeath(address owner) public{
      require(_isExecutor(owner),"only an executor may bequeath a token");

      Will memory will = wills[owner];
      require(will.obituaryStart>0, "obituary has not started");
      require(will.inheritor!=address(0), "inheritor has not been set") ;

      if(block.timestamp - will.obituaryStart > will.moratoriumTTL ) {
         // console.log("transferring this contract to the inheritor", will.inheritor);
      }else{
         revert("Not enough time has passed yet to allow transfer of token");
      }

      // loop through the owner's tokens and transfer them
      uint256 tokenCount = balanceOf(owner);
      uint256 tokenId;

      // temporarily set the executor as an approved address for all
      super._setApprovalForAll(owner, msg.sender, true);
      for (uint256 i = 0; i < tokenCount; i++) {
         tokenId = tokenOfOwnerByIndex(owner, 0);   // always pick the zero index as it will get updated on transfer

         // transfer the token to the inheritor
         super.transferFrom(owner, will.inheritor, tokenId); // Standard ERC721 transfer.
      }

      // remove the approver once all is done - as a precaution
      super._setApprovalForAll(owner, msg.sender, false);
   }

}
