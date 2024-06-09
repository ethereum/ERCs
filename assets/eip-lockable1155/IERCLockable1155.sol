// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

/// @title Lockable Extension for ERC721
/// @dev Interface for ERC7066
/// @author StreamNFT 
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IERCLocakable1155 is IERC1155{

    /**
     * @dev Emitted when tokenId is locked
     */
    event Lock(uint256 indexed tokenId, address account, address _locker, uint256 amount);

    /**
     * @dev Emitted when tokenId is unlocked
     */
    event Unlock (uint256 indexed tokenId, address account, address _locker, uint256 amount);

    /**
     * @dev Lock the tokenId if msg.sender is owner or approved and set locker to msg.sender
     */
    function lock(uint256 tokenId, address account, uint256 amount) external;

    /**
     * @dev Lock the tokenId if msg.sender is owner and set locker to _locker
     */
    function lock(uint256 tokenId, address account, address _locker, uint256 amount) external;

    /**
     * @dev Unlocks the tokenId if msg.sender is locker
     */
    function unlock(uint256 tokenId, address account, uint256 amount) external;

    /**
     * @dev Tranfer and lock the token if the msg.sender is owner or approved. 
     *      Lock the token and set locker to caller
     *      Optionally approve caller if bool setApprove flag is true
     */
    function transferAndLock(address from, address to, uint256 tokenId, uint256 amount, bool setApprove) external;

    /**
     * @dev Returns the wallet, that is stated as unlocking wallet for the tokenId.
     *      If (0) returned, that means token is not locked. Any other result means token is locked.
     */
    function getLocked(uint256 tokenId, address account, address operator) external view returns (uint256);

    function setApprovalForId(uint256 tokenId, address operator, uint256 amount) external;
}