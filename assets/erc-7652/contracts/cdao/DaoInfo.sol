// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

//import {IERC721Receiver} from "./IERC721Receiver.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./Division/FaiDivision.sol";
import "../Base/IterfaceDaoInfo.sol";

/*
一个用户的组织也DAO，方便装让部分权重，
*/
contract DaoInfo is IterfaceDaoInfo, IERC721Receiver {
    using FairDivision for infoFairDivision[];

    uint256 public objValue;
    uint256 public CloseTime;
    bool public bClose; // 是否完成筹资，如果完成，则close为true

    infoFairDivision[] public users; // 所有用户的股份信息以及利益最终分配价格信息

    uint256 public totalWeight;

    // event DaoFundraisingEnd(uint256 objValue); // DAO筹资完成，达到目标值

    // FairDivision division;
    bool private setInfoLock; // 设置锁

    DAO_STATE public dao_state; // 声明一个 DAO_STATE 类型的状态变量

    constructor(uint256 _objValue) {
        objValue = _objValue;
        totalWeight = 0;
        bClose = false;
        setInfoLock = false;
        dao_state = DAO_STATE.Hold;
    }

    /**
     ** @dev 防止函数被重入的修饰器。
     **/
    modifier nonSetInfo() {
        // 在函数执行前检查是否已经进入
        require(!setInfoLock, "Waiting for other users to set parameters");

        // 设置状态为已进入,上锁
        setInfoLock = true;

        // _; 是被修饰函数的占位符
        _;

        // 函数执行完毕后，恢复状态为未进入
        setInfoLock = false;
    }

    //一旦基金关闭，份额只能向第三人整体转让，不能退出；
    function setInfo(address addr, uint256 weight)
        public
        nonSetInfo
        returns (uint256 errInfo)
    {
        if (bClose) {
            // 一旦关闭，只能转让，不能增加修改；
            return 1111;
        }

        uint256 len = users.length;
        uint256 index = len;

        for (uint256 i = 0; i < len; i++) {
            if (addr == users[i].coOwner) {
                index = i;
                // no break;s
            }
        }

        //新增加的用户信息；
        if (index == len) {
            // 可以增加
            infoFairDivision memory infoT;
            infoT.coOwner = addr; // 共同权利人
            infoT.weight = weight; //  比例权重

            if ((totalWeight + weight) < objValue) {
                //尚未投资完成；
                users.push(infoT);
                totalWeight += weight;
                return 0;
            } else if ((totalWeight + weight) == objValue) {
                //正好投资完成；
                users.push(infoT);
                totalWeight += weight;
                bClose = true;
                CloseTime = block.timestamp;

                //  emit DaoFundraisingEnd(objValue);

                return 0;
            } else {
                // 投资额溢出，不能投资
                return 11;
            }
        } else {
            // 原先就存在的用户，需要修改信息
            infoFairDivision storage userInfo = users[index];
            uint256 oldWeight = userInfo.weight;
            if (oldWeight == weight) {
                // 时间不需要修改；保持第一次更新的时间
                return 0;
            } else if (oldWeight < weight) {
                // 属于增加投资，此时未关闭，一定可以增加投资
                uint256 diff = weight - oldWeight;
                if ((totalWeight + diff) < objValue) {
                    //尚未投资完成；
                    users[index].weight = weight;
                    totalWeight += diff;
                    // bClose = false; 不需要修改
                    return 0;
                } else if ((totalWeight + diff) == objValue) {
                    //正好投资完成；
                    users[index].weight = weight;
                    totalWeight += diff;
                    bClose = true;
                    CloseTime = block.timestamp;
                    //                emit DaoFundraisingEnd(objValue);
                    return 0;
                } else {
                    // 投资额溢出，不能投资
                    return 11;
                }
            } else {
                // 减少投资
                uint256 diff = oldWeight - weight;
                users[index].weight = weight;
                totalWeight -= diff;
                // bClose = false;  不需要修改
                return 113;
            }
        }
    }

    //一旦基金关闭，份额只能向第三人整体转让，不能退出；
    // 关闭前也可以转让；
    function transferWeight(
        address from,
        address to,
        uint256 weight
    ) public nonSetInfo returns (uint256 errInfo) {
        if (to == address(0)) {
            return 1111; // 不能转移到0地址；
        }

        if (from == to) {
            // 自己转移给自己；直接返回
            return 0;
        }

        //查找对应的add
        uint256 len = users.length;
        uint256 indexFrom = len;
        uint256 indexTo = len;

        for (uint256 i = 0; i < len; i++) {
            if (from == users[i].coOwner) {
                indexFrom = i;
            } else if (to == users[i].coOwner) {
                indexTo = i;
            }
        }

        if (indexFrom == len) {
            // // 转移人没有份额
            return 11111;
        } else if (users[indexFrom].weight < weight) {
            // 转移份额超过自己的份额
            return 111111;
        } else {
            if (indexTo == len) {
                // 新成员；增加即可
                infoFairDivision memory infoT;
                infoT.coOwner = to; // 共同权利人
                infoT.weight = weight; //  比例权重从0变为weight
                users[indexFrom].weight -= weight;
                users.push(infoT);
                return 0;
            } else {
                // 可以转移：
                users[indexFrom].weight -= weight;
                users[indexTo].weight += weight;
                return 0;
            }
        }
    }

    function resetDivision(uint256 shareValue)
        public
        returns (uint256 errInfo)
    {
        //DAO只有筹资完成才能承担担保义务，享受担保权益；
        require(bClose, "Only the closed DAO has a rigth ");
        // close,这个属于应用层逻辑，
        FairDivision.Division(shareValue, objValue, users);
        return 0;
    }

    /// @notice           接收NFT721之后的处理
    /// @dev              基本上属于担保责任的处理函数，接收到NFT，支付对应的担保佣金；
    ///                  by `operator` from `from`, this function is called.
    ///     sfrom
    ///      Guaranteed NFT (token ID),
    /// @param data            traansfer data
    /// It must return its Solidity selector to confirm the token transfer.
    ///If any other value is returned or the interface is not implemented by the recipient, the transfer will be
    /// reverted.
    ///The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
    function onERC721Received(
        address ,
        address ,
        uint256 ,
        bytes calldata data
    ) public view returns (bytes4) {
        if (dao_state == DAO_STATE.Hold) {
            //  继续持有
            return IERC721Receiver.onERC721Received.selector;
        } else if (dao_state == DAO_STATE.Split) {
            // 内部转移；
            return IERC721Receiver.onERC721Received.selector;
        } else if (dao_state == DAO_STATE.Guaranteed) {
            // 寻找后续的的担保人；
            return IERC721Receiver.onERC721Received.selector;
        } else if (dao_state == DAO_STATE.Vote) {
            // 投票抉择
            //  如果 有人願意拿NFT,則可以把NFT轉移到個人名下，
            //  否則，可以進一步的尋找後序的的擔保人
            //  因为所有人对NFT的估价一致，大家也可以统统运营NFT，
            //  或者参加拍卖会
            return IERC721Receiver.onERC721Received.selector;
        } else {
            // not process ;error
            return IERC721Receiver.onERC721Received.selector;
        }
    }

    error CustomError(uint256 arg1, uint256 arg2);

    function test() public pure {
        uint256 arg1 = 2;
        uint256 arg2 = 8;

        if ((arg1 + arg2 == 10)) {
            revert CustomError(arg1, arg2);
        } //这个函数会返回用户什么消息
    }
}
