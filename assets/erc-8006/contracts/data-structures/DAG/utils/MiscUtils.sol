// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { DAG, DAGNode as Node } from "../types/Types.sol";

function isEdgeExists(Node storage node, uint256 _childNodeId) view returns (bool isEdge) {
    isEdge = node.edges[_childNodeId];
}

function isNodeExists(DAG storage self, uint256 _nodeId) view returns (bool exists) {
    exists = self.nodes[_nodeId].id != 0;
}

function reverseList(uint256[] memory list) pure returns (uint256[] memory reversedList) {
    if (list.length == 0) return reversedList;

    uint256 left = 0;
    uint256 right = list.length - 1;

    while (left < right) {
        uint256 temp = list[left];
        list[left] = list[right];
        list[right] = temp;

        left++;
        right--;
    }

    reversedList = list;
}

function toUint(bytes32 value) pure returns (uint256 result) {
    result = uint256(value);
}
