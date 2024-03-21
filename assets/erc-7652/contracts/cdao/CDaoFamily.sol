// SPDX-License-Identifier: Apache License 2.0 

pragma solidity ^0.8.20;
 
 import "./Division/superFairDivision.sol"; 
 import "./CDaoDivision.sol"; 


/// 该合约适应于小规模,成员之间相对熟悉的DAO系统使用，
/// 不需要设置时间限制，所有人参与之后，自动进入下一个状态；
/// 以服务器接收到的请求时间作为数组成员之间的排队顺序
/// 不参与也不设置对应的惩罚措施，但是应用层可以作出对应的权限处理。
contract CDaoFamily {
    using superFairDivision for infoDivision[];

    infoDivision[] public info; // 权利人主观价格评估信息以及最终分配价格信息

    using superFairDivision for infoDivision[];
    // superFairDivision private division; // 分割合约
    CDaoDivisionErrorinfo private errorInfo; // 错误信息处理

    uint256 private coOwnerNum; // 权利人总数

    /// uint               private  curSetIndex;      //下一个设置预估价格的权利人索引
    ///  uint               private  curRevealIndex;   // 下一个公开披露价格的权利人索引

    uint256 private stateProcess;
    // 0:   初始状态，尚未开始估价
    // 1：  设置估价值；
    // 2：  披露价格阶段(所有人都出价完毕，自动进入披露本阶段)；
    // 3:   披露价格结束，分配阶段；
    //  4:   分配结束，数据仅供查询

    bool private setDivisionLock; // 设置价格锁
    bool private revealLock; // 披露价格函数锁

    event SetDivisionInfoEnd(); // 设置估价结束；可以公开披露报价了
    event RerealEnd(); // 披露价格结束；准备分割；
    event DivisionEnd(); // 分割结束，可以查询了；


   // bool bReveal; //是否公开披露出价，也属于应用逻辑，转移到map
   // bytes32 blindedValue; //保密存储值，应用逻辑，转移到map
    mapping(address=>bool)   private mapReveal;
    mapping(address=>bytes32) private mapBlindedValue;

   // bool bReveal; //是否公开披露出价，也属于应用逻辑，转移到map
   // bytes32 blindedValue; //保密存储值，应用逻辑，转移到map
    ///  unint coOwnerNum ， 权利共有人的数量；
    constructor(uint256 _coOwnerNum) {
        require(
            _coOwnerNum > 1,
            "The division requires a minimum of two participants."
        );

        coOwnerNum = _coOwnerNum;

        //division = new superFairDivision();
        errorInfo = new CDaoDivisionErrorinfo();

        // info            = new infoDivision[](coOwnerNum);
        // curSetIndex     = 0;
        // curRevealIndex  = 0;
        stateProcess = 1;
           
        setDivisionLock = false;
        revealLock = false;
    }

    /**
     ** @dev 防止函数被重入的修饰器。
     **/
    modifier nonSetDivision() {
        // 在函数执行前检查是否已经进入
        require(!setDivisionLock, "Waiting for other users to set parameters");

        // 设置状态为已进入,上锁
        setDivisionLock = true;

        // _; 是被修饰函数的占位符
        _;

        // 函数执行完毕后，恢复状态为未进入
        setDivisionLock = false;
    }

    /**
     ** @dev 防止函数被重入的修饰器。
     **/
    modifier nonReveal() {
        // 在函数执行前检查是否已经进入
        require(
            !revealLock,
            "Waiting for other users to reveal price parameters"
        );

        // 设置状态为已进入,上锁
        revealLock = true;

        // _; 是被修饰函数的占位符
        _;

        // 函数执行完毕后，恢复状态为未进入
        revealLock = false;
    }

    /// 期待每个权利人都设置一次，但是，如果多次设置，以最后一次设置为准；
    /// 可以通过 `blindedValue` = keccak256(valuation, limitValue, address) 设置一个加密评价值。
    /// 该函数同一时间只能被一个用户调用
    function setDivisionInfo(bytes32 blindedValue, uint256 limitValue)
        external
        nonSetDivision
        returns (uint256 errInfo)
    {
        if (stateProcess != 1) {
            // 不是评估值阶段
            if (stateProcess < 1) {
                return 1;
            } else {
                return 2;
            }
        }

        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].coOwner == msg.sender) {
                //重复出价；覆盖上一次的数值
                info[i].valuation = limitValue; //初始化设置，如果没有正确公开披露出价，则以该数值为准
                //info[i].resDivision = 0; //分配结果值;
                //info[i].onlyOwner = false; //最终权利所有人
                mapBlindedValue[msg.sender]= blindedValue; //私密数值
                return 0; //退出设置
            }
        }

        // 没有找到，新增加一个
        if (info.length < coOwnerNum) {
            infoDivision memory infoT;
            infoT.coOwner == msg.sender;
            infoT.valuation = limitValue; //初始化设置，如果没有正确公开披露出价，则以该数值为准
            infoT.resDivision = 0; //分配结果值;
            infoT.onlyOwner = false; //最终权利所有人
           // infoT.bReveal = false; //尚未公开披露价格
           // infoT.blindedValue = blindedValue; //私密数值
           mapReveal[msg.sender]= false; //尚未公开披露价格
           mapBlindedValue[msg.sender]= blindedValue; //私密数值

           info.push(infoT);
        }

        // 根据插入数据之后的新状态判断
        if (info.length == coOwnerNum) {
            // 所有人都设置完毕，自动进入公开出价阶段
            stateProcess = 2;
            emit SetDivisionInfoEnd(); // 设置估价结束
        }

        return 0; //退出设置
    }

    /// 只有在出价披露阶段被正确披露，设置的价格才会生效
    /// 这是一个 "internal" 函数，
    ///  意味着它只能在本合约（或继承合约）内被调用。
    function revealDivisionInfo(uint256 valuation, uint256 limitValue)
        internal
        nonReveal
        returns (uint256 errInfo)
    {
        if (stateProcess != 2) {
            // 不是评估值阶段
            if (stateProcess < 2) {
                return 3;
            } else {
                return 4;
            }
        }

        bool bRevealAll = true;
        for (uint256 i = 0; i < info.length; i++) {
            if (!mapReveal[info[i].coOwner]) {
                // 注意，如果该MAP结构中没有对应的值，说明也没有正确公开披露
                //  只要有一个未披露价格，则未披露完成；
                bRevealAll = false;
            }
            if (info[i].coOwner == msg.sender) {
                // 可以通过 `blindedValue` = keccak256(valuation, limitValue, address) 设置一个加密评价值。
                if (
                    mapBlindedValue[msg.sender] ==
                    keccak256(
                        abi.encodePacked(valuation, limitValue, msg.sender)
                    )
                ) {
                    //判断是否正确披露价格
                    info[i].valuation = valuation; //初始化设置，如果没有正确公开披露出价，则以该数值为准
                    info[i].resDivision = 0; //分配结果值;
                    info[i].onlyOwner = false; //最终权利所有人
                    mapReveal[msg.sender]     = true;  // 正确公开披露价格
                    // 注意，这里不需要退出处理；继续循环查看是否披露完毕
                } else {
                    // 没有正确披露价格，错误返回；
                    return 6;
                }
            }
        }

        if (bRevealAll) {
            // 所有人都披露价格完毕，自动进入分配阶段；
            stateProcess = 3;
            emit RerealEnd(); // 公开披露结束

            Division(); // 根据分配价格结果转移对应的数字资产；
        }

        return 0; //退出gongkai
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

        stateProcess = 4; // 分配结束
        emit DivisionEnd(); //
        return 0;
    }

    // 返回一个结构体的函数
    function getDivisionInfo() public view returns (infoDivision[] memory) {
        return info;
    }
}
