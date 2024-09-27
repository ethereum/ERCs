// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

/// @title Lockable Extension for ERC721
/// @dev Interface for ERC7066
/// @author StreamNFT 
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IERC7721 is IERC1155{

    /**
     * @dev Emitted when tokenId is locked
     */
    event Lock(uint256 indexed tokenId, address account, address _locker, uint256 amount);

    /**
     * @dev Emitted when tokenId is unlocked
     */
    event Unlock (uint256 indexed tokenId, address account, address _locker, uint256 amount);

    /**
     * @dev lock the amount of token and set locker to msg.sender. Verifies if the msg.sender is owner or approved
     *      reverts otherwise
     */
    function lock(uint256 tokenId, address account, uint256 amount) external;

    /**
     * @dev lock the amount of token and set locker to _locker. Verifies if the msg.sender is owner
     *      reverts otherwise
     */
    function lock(uint256 tokenId, address account, address _locker, uint256 amount) external;

    /**
     * @dev unlock the token. Verifies the msg.sender is locker
     *      reverts otherwise
     */
    function unlock(uint256 tokenId, address account, uint256 amount) external;

    /**
     * @dev Tranfer and lock the token if the msg.sender is owner or approved. 
     *      Lock the token and set locker to caller
     *      Optionally approve caller if bool setApprove flag is true
     */
    function transferAndLock(address from, address to, uint256 tokenId, uint256 amount, bool setApprove) external;

    /**
     * @dev Returns the locked amount for the tokenId on account by operator
     */
    function getLocked(uint256 tokenId, address account, address operator) external view returns (uint256);

    /**
     * @dev Set approval on specific tokenId for token approved and operator on account
     */
    function setApprovalForId(uint256 tokenId, address operator, uint256 amount) external;

    /**
     * @dev Get amount for token approved and operator on account
     */
    function getApprovalForId(uint256 tokenId, address account, address operator) external;

}