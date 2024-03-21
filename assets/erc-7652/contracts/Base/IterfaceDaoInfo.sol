// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

//import {IERC721Receiver} from "./IERC721Receiver.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// 定义枚举类型 DAO_STATE
enum DAO_STATE {
    Hold, // 持有状态
    Split, // 分裂状态
    Guaranteed, // 保证状态
    Vote // 投票状态
} 

/*
一个用户的组织也DAO，方便转让部分权重，
*/

interface  IterfaceDaoInfo {  
 
     /// @notice           DAO筹资完成，达到目标值
    /// @param DaoAdd      address of DAO
    /// @param objValue    objValue organization providing guarantee 
    event DaoFundraisingEnd(address DaoAdd,uint256 objValue); 
   
    //一旦基金关闭，份额只能向第三人整体转让，不能退出；
    function setInfo(address addr, uint256 weight)
        external 
        returns (uint256 errInfo);

    //一旦基金关闭，份额只能向第三人整体转让，不能退出；
    // 关闭前也可以转让；
    function transferWeight(
        address from,
        address to,
        uint256 weight
    ) external  returns (uint256 errInfo);

    function resetDivision(uint256 shareValue)
        external
        returns (uint256 errInfo); 
}
