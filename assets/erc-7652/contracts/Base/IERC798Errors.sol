// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

/**
 * @dev Standard ERC798 Errors
 */
 
 
// 定义枚举类型 DAO_STATE
enum IEC798_DAO_RETURN_VALUE {
    SUCCESS, // 成功
    SUC_DAO_CLOSE, //成功执行且DAO已经关闭
    ERR_, // 保证状态
    ERR_PROCESS // 投票状态
} 


interface IERC798Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in EIP-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC798InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC798NonexistentToken(uint256 tokenId);

    
}
