// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { NodeInitData } from "./Types.sol";
import { NodeConfig } from "./UtilTypes.sol";

function exractNodesConfig(
    NodeInitData[] calldata nodes
) pure returns (NodeConfig[] memory result) {
    result = new NodeConfig[](nodes.length);

    for (uint256 i = 0; i < nodes.length; i++) {
        // extract parent node-id
        NodeInitData calldata parent = nodes[i];
        result[i] = NodeConfig({ node: parent.id, childNodes: new bytes32[](0) });

        uint256 childCount = parent.substitutedExecArgs.length;

        if (childCount == 0) continue;

        // extract child-ids
        bytes32[] memory childIds = new bytes32[](childCount);
        for (uint256 j = 0; j < childCount; j++) {
            childIds[j] = parent.substitutedExecArgs[j].supplierNodeId;
        }

        result[i].childNodes = childIds;
    }

    return result;
}
