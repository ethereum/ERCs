// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./ISettlement.sol";
import {IAIProcess} from "../../process/interfaces/IAIProcess.sol";

/**
 * @title Storage for Settlement
 * @notice For future upgrades, do not change SettlementStorageV1. Create a new
 * contract which implements SettlementStorageV1
 */
abstract contract SettlementStorageV1 is ISettlement {
    address payable public queryAddress;
    address payable public inferenceAddress;
    address payable public trainingAddress;
    IAIProcess public override query;
    IAIProcess public override inference;
    IAIProcess public override training;
    UserMap userMap;
}
