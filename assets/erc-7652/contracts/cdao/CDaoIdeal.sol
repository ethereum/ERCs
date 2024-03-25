// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

import "./CDaoDivision.sol";
import "./DaoInfo.sol";
import "./Division/superFairDivision.sol";

/// 该合约适应于理想的DAO运行中治理及分割问题,
/// 成员之间估价相对全部公开，随时可以加入，随时可以退出；
/// 不需要设置私密保护，公开出价且担保筹资完成就可以获得收益。
/// 以服务器接收到的请求时间作为数组成员之间的排队顺序
/// 不参与也不设置对应的惩罚措施，但是应用层可以作出对应的权限处理。
contract CDaoIdeal {
    // 每个值可以建立一个股份型MAP结构,
    mapping(uint256 => DaoInfo) cdao;
    CDaoDivisionErrorinfo private errorInfo; // 错误信息处理
    infoDivision[] public info; // 全体价格评价评估信息以及最终分配价格信息

    event SetDivisionInfoEnd(); // 设置估价结束；可以公开披露报价了
    event RerealEnd(); // 披露价格结束；准备分割；
    event DivisionEnd(); // 分割结束，可以查询了；

    bool private setInfoLock; // 设置锁

    constructor() {
        setInfoLock = false; // 设置锁
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

    function setInfo(
        uint256 value,
        address user,
        uint256 weight
    ) external nonSetInfo returns (uint256 errInfo) {
        uint256 index = info.length;
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].valuation == value) {
                //值存在
                index = i;
            }
        }

        if (index == info.length) {
            //新增加的评估值
            DaoInfo newDaoInfo = new DaoInfo(value);
            newDaoInfo.setInfo(user, weight);
            cdao[value] = newDaoInfo;

            infoDivision memory infoT;
            infoT.coOwner == (address)(newDaoInfo);

            infoT.valuation = value; //初始化设置，如果没有正确公开披露出价，则以该数值为准
            infoT.resDivision = 0; //分配结果值;
            infoT.onlyOwner = false; //最终权利所有人
            info.push(infoT);
            return 0;
        }
        else
        {//该价格已经有人出了，参与该dao合伙出价；
            return cdao[value].setInfo(user,weight); 
        } 
    }
 
    function Division() private returns (uint256 errInfo) {
        // address ad = division.supperDivision(info);
        //  onlyOwner.transfer(highestBid);
        for (uint256 i = 0; i < info.length; i++) {
            if (!info[i].onlyOwner) {
                // 不是最终权利人的
                //  transfrom(payable(ad),info[i].coOwner,info[i].resDivision);
            }
        }
 
        emit DivisionEnd(); //
        return 0;
    }

    // 返回一个结构体的函数
    function getDivisionInfo() public view returns (infoDivision[] memory) {
        return info;
    }
}
