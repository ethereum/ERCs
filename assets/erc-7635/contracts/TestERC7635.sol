// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.6;

import "./ERC7635.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract TestERC7635 is ERC7635, Ownable {

    uint256 public count;

    // Maximum circulation
    uint256 public maxSupply;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC7635(name_, symbol_)  {
    }

    /**
     * @dev Set maximum circulation
     * @param maxSupply_ Maximum circulation
     */
    function setMaxSupply(uint256 maxSupply_) external onlyOwner {
        maxSupply = maxSupply_;
    }


    /**
    * @dev Update or add slot information
    * @param slotIndex_ Slot Index
    * @param update_ true for update
    * @param transferable_ true indicates transferable
    * @param isToken_ True indicates  token
    * @param isNft_ True indicates  NFT
    * @param tokenAddress_ ERC20 or ERC721 Token Address
    * @param name_ Slot Name
    */
    function updateSlot(
        uint256 slotIndex_,
        bool update_,
        bool transferable_,
        bool isToken_,
        bool isNft_,
        address tokenAddress_,
        string memory name_
    ) external payable onlyOwner {
        _updateSlot(slotIndex_, update_, transferable_, isToken_, isNft_, tokenAddress_, name_);
    }


    /**
     * @dev mint MFT
     * @param to_ Receiver's address
     * @param tokenLevel_ token level
     * @param tokenType_ token type
     * @param transferable_ true indicates transferable
     */
    function mint(
        address to_,
        uint32 tokenLevel_,
        uint8 tokenType_,
        bool transferable_
    ) external payable onlyOwner {
        require(count < maxSupply, "MFT: max supply reached");

        _mint(to_, ++count, tokenLevel_, tokenType_, transferable_);
    }

}