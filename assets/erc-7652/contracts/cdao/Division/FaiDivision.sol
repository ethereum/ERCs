// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

struct infoFairDivision {
    address coOwner; // 共同权利人
    uint256 resDivision; //分配结果值;
    uint256 weight; //  比例权重
}

/// 当所有参与人认知一致的时候，按照股份公平分配
library FairDivision {
    // 此处不使用全局变量，是为了兼容map接口参数,

    // 带权重的分配
    function Division(
        uint256 value,
        uint256 target,
        infoFairDivision[] storage info
    ) public  returns (bool) {
        // 低gas费用，可能会发生溢出问题；如果发生溢出，请使用supperDivision_estimate；
        uint256 len = info.length;
        uint256 WeightAll = 0;

        for (uint256 i = 0; i < len; i++) {
            // 累加所有值
            WeightAll += info[i].weight;
        }

        require(
            target == WeightAll,
            "The sum of weight values does not equal the target value."
        );

        for (uint256 i = 0; i < len; i++) {
            // 累加所有差值
            info[i].resDivision = ((value * info[i].weight) / WeightAll);
        }
        return true;
    }

    /// 用浮点数进行估算,需要自己定义数据结构类型

    function supperDivision_estimate(infoFairDivision[] storage info)
        public
        view returns (bool)
    {
        // 进行一定的防溢出处理；'
        uint256 len = info.length;
        uint256 WeightAll = 0;

        for (uint256 i = 0; i < len; i++) {
            // 累加所有值
            WeightAll += info[i].weight;
        }

        return true;
    }
}
