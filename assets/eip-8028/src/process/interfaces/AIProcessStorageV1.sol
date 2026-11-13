// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./IAIProcess.sol";
import {ISettlement} from "../../settlement/interfaces/ISettlement.sol";

/**
 * @title Storage for AIProcess
 * @notice For future upgrades, do not change AIProcessV1. Create a new
 * contract which implements AIProcessV1
 */
abstract contract AIProcessStorageV1 is IAIProcess {
    EnumerableSet.AddressSet internal _nodeList;
    EnumerableSet.AddressSet internal _activeNodeList;
    mapping(address nodeAddress => Node node) internal _nodes;

    ISettlement public override settlement;
    AccountMap accountMap;
    uint256 public lockTime;
}
