// SPDX-License-Identifier: Apache License 2.0
 
pragma solidity ^0.8.20;
 

struct infoDivision {
    address coOwner;    // 共同权利人
    uint256 valuation; //评估值;此处都是明文，加密属于应用逻辑
    uint256 resDivision; //分配结果值;
    uint256 weight;  //  比例权重；默认为1 
    bool    onlyOwner; //最终权利所有人
}
 
library superFairDivision {
    // 此处不使用全局变量，是为了兼容map接口参数,
    //不带分配权重
    function supperDivisionNoWeight(infoDivision[] storage info)
        public
        returns (address)
    {
        // 低gas费用，可能会发生溢出问题；如果发生溢出，请使用supperDivision_estimate；
        uint256 len = info.length;

        //分配计划需要至少两个参与人。
        require(
            len >= 2,
            "The division requires a minimum of two participants."
        );

        uint256 maxValue = info[0].valuation;
        uint256 maxIndex = 0;
        uint256 sum = 0; // 累加值

        for (uint256 i = 0; i < len; i++) {
            // 累加所有评估值
            sum += info[i].valuation;
            // 寻找第一个是最大的估价值
            if (info[i].valuation > maxValue) {
                maxValue = info[i].valuation;
                maxIndex = i;
            }
        }

        uint256 diffValue = len * maxValue - sum;
        uint256 supperValue = diffValue / (len * len);

        uint256 needPayValue = 0;

        for (uint256 i = 0; i < len; i++) {
            //修改分配结果值：
            info[i].resDivision = supperValue + info[i].valuation / len;
            info[i].onlyOwner = false;
            needPayValue += info[i].resDivision;
        }

        // 出价最高的人是最终权利人，需要支付其他人的费用；
        //  (info[maxIndex].valuation*(len -1)) /len 是理论上的支付费用。
        info[maxIndex].resDivision =
            (info[maxIndex].valuation * (len - 1)) /
            len -
            supperValue;
        info[maxIndex].onlyOwner = true;

        if (needPayValue > info[maxIndex].resDivision) {
            //理论上，needPayValue 应该小于 info[maxIndex].resDivision
            if ((needPayValue - 2) < info[maxIndex].resDivision) {
                // 计算存在偏差,适当修正下,最多不超过1个；
                info[maxIndex].resDivision = needPayValue;
            } else {
                // 计算出现错误，需要进行逻辑检查
                require(false, "needPayValue >  resDivision");
            }
        } else {
            if ((needPayValue + 2 * len) < info[maxIndex].resDivision) {
                // 适当修正下数据
                info[maxIndex].resDivision = needPayValue + len;
            }
        }
        return (info[maxIndex].coOwner);
    }

   // 带权重的分配
  function supperDivision(infoDivision[] storage info)
        public
        returns (address)
    {
        // 低gas费用，可能会发生溢出问题；如果发生溢出，请使用supperDivision_estimate；
        uint256 len = info.length;

        //分配计划需要至少两个参与人。
        require(
            len >= 2,
            "The division requires a minimum of two participants."
        );

        uint256 maxValue = info[0].valuation;
        uint256 maxIndex = 0;
        uint256 WeightAll = 0;

        for (uint256 i = 0; i < len; i++) {
            // 累加所有评估值
            WeightAll += info[i].weight;
            // 寻找第一个是最大的估价值
            if (info[i].valuation > maxValue) {
                maxValue = info[i].valuation;
                maxIndex = i;
            }
        }

        uint256 sum = 0; // 累加值
        for (uint256 i = 0; i < len; i++) {
            // 累加所有差值
            sum += (maxValue-info[i].valuation)*info[i].weight;
        }

        uint256 supperValue = sum / (WeightAll * WeightAll);

        uint256 needPayValue = 0;

        for (uint256 i = 0; i < len; i++) {
            //修改分配结果值：
            info[i].resDivision = (supperValue + info[i].valuation / len)*info[i].weight;
            info[i].onlyOwner = false;
            needPayValue += info[i].resDivision;
        }

        // 出价最高的人是最终权利人，需要支付其他人的费用；
        //  (info[maxIndex].valuation*(len -1)) /len 是理论上的支付费用。
        info[maxIndex].resDivision = needPayValue;
        info[maxIndex].onlyOwner = true; 
        
        return (info[maxIndex].coOwner);
    }

    function supperDivision_estimate(infoDivision[] memory info)
        public
        pure
        returns (address)
    {
        // 进行一定的防溢出处理；
        return (info[0].coOwner);
    }
}
